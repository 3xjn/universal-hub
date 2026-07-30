local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Canonical = importDependency("games/town/Canonical", "./Canonical")

local ExecutionPlan = {}

local DEFAULT_BATCH_SIZE = 128
local DEFAULT_CLONE_REQUEST_SIZE = 513
local EXECUTION_CHUNK_SIZE = 64

local OPERATION_DEFINITIONS = {
    { key = "resize", operation = "SyncResize", phase = "Shaping geometry" },
    { key = "color", operation = "SyncColor", phase = "Painting colors" },
    { key = "material", operation = "SyncMaterial", phase = "Applying materials" },
    { key = "surface", operation = "SyncSurface", phase = "Finishing surfaces" },
    { entry = "mesh", key = "meshCreate", operation = "CreateMeshes", phase = "Creating mesh details" },
    { entry = "mesh", key = "meshSync", operation = "SyncMesh", phase = "Applying mesh details" },
    { entry = "textures", key = "textureCreate", operation = "CreateTextures", phase = "Creating textures" },
    { entry = "textures", key = "textureSync", operation = "SyncTexture", phase = "Applying textures" },
    { entry = "lights", key = "lightCreate", operation = "CreateLights", phase = "Creating lights" },
    { entry = "lights", key = "lightSync", operation = "SyncLighting", phase = "Configuring lights" },
    { key = "collision", operation = "SyncCollision", phase = "Setting collisions" },
    { key = "anchor", operation = "SyncAnchor", phase = "Securing parts" },
}

local function hasOperation(record, key)
    for _, operation in ipairs(record.operations or {}) do
        if operation == key then
            return true
        end
    end
    return false
end

local function eachRecord(checkpoint, jobId, chunks, visit)
    for _, metadata in ipairs(chunks) do
        local chunk = checkpoint:readPlanChunk(jobId, metadata)
        for _, record in ipairs(chunk.records) do
            visit(record)
        end
    end
end

local function stagingCFrame(jobId, record)
    local digest = Canonical.sha256Bytes(Canonical.encode({
        jobId = jobId,
        planId = record.id,
        purpose = "create-ownership",
    }))
    local result = {}
    for index, value in ipairs(record.cframe) do
        result[index] = value
    end
    for axis = 1, 3 do
        local value = tonumber(digest:sub((axis - 1) * 8 + 1, axis * 8), 16)
        local sign = value % 2 == 0 and 1 or -1
        local magnitude = 0.01 + ((value % 1000000) / 1000000) * 0.04
        result[axis] += sign * magnitude
    end
    return result
end

function ExecutionPlan.compile(checkpoint, jobId, planChunks, plan, options)
    options = options or {}
    local batchSize = options.preferredBatchSize or DEFAULT_BATCH_SIZE
    local cloneSize = options.cloneRequestSize or DEFAULT_CLONE_REQUEST_SIZE
    local chunkMetadata = {}
    local buffer = {}
    local batchCount = 0
    local maximumBufferedRecords = 0
    local operationCounts = {}
    local phaseCounts = {}

    local function flushExecution()
        if #buffer == 0 then
            return
        end
        local index = #chunkMetadata + 1
        table.insert(chunkMetadata, checkpoint:writeJobChunk(jobId, "execution", index, {
            index = index,
            jobId = jobId,
            kind = "execution",
            records = buffer,
        }))
        buffer = {}
    end

    local function emit(batch)
        batchCount += 1
        operationCounts[batch.operation] = (operationCounts[batch.operation] or 0) + 1
        phaseCounts[batch.phase] = (phaseCounts[batch.phase] or 0) + 1
        batch.sequence = batchCount
        batch.weight = batch.weight or 1
        table.insert(buffer, batch)
        maximumBufferedRecords = math.max(maximumBufferedRecords, #buffer)
        if #buffer == EXECUTION_CHUNK_SIZE then
            flushExecution()
        end
    end

    local types = {}
    local operationStates = {}
    for _, definition in ipairs(OPERATION_DEFINITIONS) do
        table.insert(operationStates, {
            definition = definition,
            entries = {},
            planIds = {},
        })
    end

    local function flushOperation(state)
        if #state.planIds == 0 then
            return
        end
        local definition = state.definition
        local batch = {
            operation = definition.operation,
            phase = definition.phase,
            planIds = state.planIds,
        }
        if #state.entries > 0 then
            batch.entries = state.entries
        end
        emit(batch)
        state.planIds = {}
        state.entries = {}
    end

    local function appendOperation(state, record)
        local definition = state.definition
        if not hasOperation(record, definition.key) then
            return
        end
        if definition.entry == "textures" or definition.entry == "lights" then
            for index, item in ipairs(record[definition.entry] or {}) do
                if definition.entry ~= "lights" or item.enabled then
                    table.insert(state.entries, { index = index, partId = record.id })
                    if #state.planIds == 0 or state.planIds[#state.planIds] ~= record.id then
                        table.insert(state.planIds, record.id)
                    end
                    if #state.entries == batchSize then
                        flushOperation(state)
                    end
                end
            end
        else
            table.insert(state.planIds, record.id)
            if definition.entry then
                table.insert(state.entries, { index = 1, partId = record.id })
            end
            if #state.planIds == batchSize then
                flushOperation(state)
            end
        end
    end

    local function flushClones(typeState)
        if #typeState.pending == 0 then
            return
        end
        local sourceIds = {}
        for index = 1, #typeState.pending do
            table.insert(sourceIds, typeState.sources[index])
        end
        emit({
            operation = "Clone",
            ownershipRequired = true,
            phase = "Creating parts",
            planIds = typeState.pending,
            sourceIds = sourceIds,
            townType = typeState.name,
        })
        for _, id in ipairs(typeState.pending) do
            if #typeState.sources < cloneSize then
                table.insert(typeState.sources, id)
            end
        end
        typeState.created += #typeState.pending
        typeState.pending = {}
    end

    eachRecord(checkpoint, jobId, planChunks, function(record)
        local typeState = types[record.type]
        if not typeState then
            typeState = {
                created = 1,
                name = record.type,
                pending = {},
                sources = { record.id },
            }
            types[record.type] = typeState
            emit({
                creationCFrame = stagingCFrame(jobId, record),
                operation = "CreatePart",
                ownershipRequired = true,
                phase = "Creating parts",
                planIds = { record.id },
                townType = record.type,
            })
        else
            table.insert(typeState.pending, record.id)
            if #typeState.pending == math.min(typeState.created, cloneSize) then
                flushClones(typeState)
            end
        end
    end)
    for _, typeState in pairs(types) do
        flushClones(typeState)
    end
    eachRecord(checkpoint, jobId, planChunks, function(record)
        for _, operationState in ipairs(operationStates) do
            appendOperation(operationState, record)
        end
    end)
    for _, operationState in ipairs(operationStates) do
        flushOperation(operationState)
    end
    local nameState = {
        definition = {
            key = "name",
            operation = "SetPartNames",
            phase = "Restoring part names",
        },
        entries = {},
        planIds = {},
    }
    eachRecord(checkpoint, jobId, planChunks, function(record)
        appendOperation(nameState, record)
    end)
    flushOperation(nameState)

    local function emitGroup(group)
        local memberCount = 0
        local membershipChecksums = {}
        local fingerprintBuffer = {}
        local function flushFingerprint()
            if #fingerprintBuffer > 0 then
                table.insert(membershipChecksums, Canonical.checksum(fingerprintBuffer))
                fingerprintBuffer = {}
            end
        end
        local function fingerprintMember(kind, id)
            memberCount += 1
            table.insert(fingerprintBuffer, {
                id = id,
                kind = kind,
            })
            if #fingerprintBuffer == batchSize then
                flushFingerprint()
            end
        end
        if group.iterMembers then
            group.iterMembers(fingerprintMember)
        else
            for _, id in ipairs(group.partIds or {}) do
                fingerprintMember("part", id)
            end
            for _, id in ipairs(group.modelIds or {}) do
                fingerprintMember("model", id)
            end
        end
        flushFingerprint()
        local groupFingerprint = Canonical.checksum({
            chunks = membershipChecksums,
            id = group.id,
            memberCount = memberCount,
            name = group.name,
        })
        local memberBuffer = {}
        local created = false
        local function flushMembers()
            if #memberBuffer == 0 and created then
                return
            end
            emit({
                groupFingerprint = groupFingerprint,
                groupId = group.id,
                groupName = group.name,
                memberCount = memberCount,
                memberIds = memberBuffer,
                operation = created and "AddGroupMembers" or "CreateGroup",
                ownershipRequired = not created,
                phase = "Building groups",
            })
            created = true
            memberBuffer = {}
        end
        local function appendMember(kind, id)
            table.insert(memberBuffer, {
                id = id,
                kind = kind,
            })
            if #memberBuffer == batchSize then
                flushMembers()
            end
        end
        if group.iterMembers then
            group.iterMembers(appendMember)
        else
            for _, id in ipairs(group.partIds or {}) do
                appendMember("part", id)
            end
            for _, id in ipairs(group.modelIds or {}) do
                appendMember("model", id)
            end
        end
        flushMembers()
        if group.name ~= "Model" then
            emit({
                groupFingerprint = groupFingerprint,
                groupId = group.id,
                groupName = group.name,
                memberCount = memberCount,
                operation = "SetGroupName",
                phase = "Naming groups",
            })
        end
    end
    if options.iterGroups then
        options.iterGroups(emitGroup)
    else
        for _, group in ipairs(plan.groups or {}) do
            emitGroup(group)
        end
    end
    if options.copyWiring then
        emit({
            operation = "Wire",
            phase = "Compiling wiring",
            wiringFingerprint = options.wiringFingerprint,
        })
    end
    emit({
        operation = "Save",
        phase = "Saving copy",
        priorSaveIdentity = options.priorSaveIdentity,
        saveName = options.saveName,
    })
    flushExecution()

    local result = {
        batchCount = batchCount,
        chunkCount = #chunkMetadata,
        chunks = chunkMetadata,
        maximumBufferedRecords = maximumBufferedRecords,
        operationCounts = operationCounts,
        phaseCounts = phaseCounts,
        planHash = plan.fingerprint,
        strategy = "town-stream-v1",
        totalWeight = batchCount,
    }
    result.hash = Canonical.checksum({
        batchCount = result.batchCount,
        chunks = result.chunks,
        operationCounts = result.operationCounts,
        phaseCounts = result.phaseCounts,
        planHash = result.planHash,
        strategy = result.strategy,
        totalWeight = result.totalWeight,
    })
    return result
end

return ExecutionPlan
