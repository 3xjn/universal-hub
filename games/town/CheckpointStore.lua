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

local CheckpointStore = {}
CheckpointStore.__index = CheckpointStore

local ACTIVE_RETENTION_SECONDS = 7 * 24 * 60 * 60
local QUARANTINE_RETENTION_SECONDS = 7 * 24 * 60 * 60
local PUBLIC_ERROR = "Persistent recovery is unavailable in this executor"
local QUARANTINE_MESSAGE = "Checkpoint unavailable; recovery data was quarantined"
local ACTIVE_JOB_MESSAGE = "An unfinished Town copy already exists"
local STATE_AUTHORIZATION = {
    awaiting_confirmation = "awaiting_confirmation",
    cancel_requested = "copy_authorized",
    cleanup_pending = "copy_authorized",
    completed = "copy_authorized",
    copy_authorized = "copy_authorized",
    copying = "copy_authorized",
    paused = "copy_authorized",
    reconciling = "copy_authorized",
    resuming = "copy_authorized",
    rollback = "copy_authorized",
    rollback_incomplete = "copy_authorized",
}
local OPERATIONS = {
    AddGroupMembers = true,
    AdoptOwnership = true,
    AdoptGroupOwnership = true,
    AdoptChildOwnership = true,
    Clone = true,
    CreateGroup = true,
    CreateLights = true,
    CreateMeshes = true,
    CreatePart = true,
    CreateTextures = true,
    Save = true,
    SetGroupName = true,
    SetPartNames = true,
    SyncAnchor = true,
    SyncCollision = true,
    SyncColor = true,
    SyncLighting = true,
    SyncMaterial = true,
    SyncMesh = true,
    SyncResize = true,
    SyncSurface = true,
    SyncTexture = true,
    Wire = true,
}
local DESTINATION_CONTEXT_KEYS = {
    "baselineFingerprint",
    "baselineInventory",
    "buildClassName",
    "buildIdentity",
    "buildName",
    "ownerName",
    "ownerUserId",
    "plotFrame",
    "plotName",
    "plotPath",
    "plotSize",
}
local SOURCE_CONTEXT_KEYS = {
    "fingerprint",
    "ownerName",
    "ownerUserId",
    "plotName",
    "plotPath",
}
local REQUIRED_FUNCTIONS = {
    "decode",
    "deleteFile",
    "encode",
    "isFile",
    "listFiles",
    "makeFolder",
    "readFile",
    "writeFile",
}

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[key] = copy(child)
    end
    return result
end

local function copyMutableState(state)
    local result = {}
    for key, value in pairs(state) do
        if key == "context"
            or key == "execution"
            or key == "manifest"
            or key == "plan"
            or key == "request"
        then
            result[key] = value
        else
            result[key] = copy(value)
        end
    end
    return result
end

local function withoutKey(value, omitted)
    local result = {}
    for key, child in pairs(value) do
        if key ~= omitted then
            result[key] = child
        end
    end
    return result
end

local function dirname(path)
    return path:match("^(.*)[/\\][^/\\]+$")
end

local function normalize(path)
    return tostring(path):gsub("\\", "/"):gsub("/+", "/"):gsub("/$", "")
end

local function hasUnsafePathSegments(path)
    if type(path) ~= "string" or path:find("\0", 1, true) then
        return true
    end
    for component in path:gsub("\\", "/"):gmatch("[^/]+") do
        if component == "." or component == ".." then
            return true
        end
    end
    return false
end

local function isSafeJobId(jobId)
    return type(jobId) == "string"
        and #jobId > 0
        and #jobId <= 128
        and jobId:match("^[%w_%-]+$") ~= nil
end

local function isInteger(value, minimum)
    return type(value) == "number"
        and value % 1 == 0
        and value >= (minimum or 0)
end

local function same(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not same(value, right[key]) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function hasExactKeys(value, keys)
    if type(value) ~= "table" then
        return false
    end
    for _, key in ipairs(keys) do
        if value[key] == nil then
            return false
        end
    end
    return true
end

local function validPendingRemainder(pending)
    if pending == nil then
        return true
    end
    return type(pending) == "table"
        and type(pending.operation) == "string"
        and OPERATIONS[pending.operation] == true
        and (pending.originalOperation == nil
            or OPERATIONS[pending.originalOperation] == true)
        and type(pending.planIds or {}) == "table"
        and pending.nextPending == nil
end

local function validPendingBatch(jobId, pending, lastConfirmed, batchCount)
    if pending == nil then
        return true
    end
    return type(pending) == "table"
        and type(pending.id) == "string"
        and pending.id:sub(1, #jobId + 1) == jobId .. ":"
        and type(pending.operation) == "string"
        and OPERATIONS[pending.operation] == true
        and isInteger(pending.sequence, 1)
        and pending.sequence == lastConfirmed + 1
        and pending.sequence <= batchCount
        and type(pending.planIds or {}) == "table"
        and (pending.originalOperation == nil
            or OPERATIONS[pending.originalOperation] == true)
        and validPendingRemainder(pending.nextPending)
end

local function validStringList(values, minimum)
    if type(values) ~= "table" or #values < (minimum or 0) then
        return false
    end
    local seen = {}
    for index, value in ipairs(values) do
        if type(value) ~= "string" or value == "" or seen[value] then
            return false
        end
        seen[value] = true
        if values[index] ~= value then
            return false
        end
    end
    for key in pairs(values) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #values then
            return false
        end
    end
    return true
end

local function validRecoveryArtifacts(jobId, progress, lastConfirmed, batchCount)
    local adoption = progress.pendingAdoption
    if adoption ~= nil
        and (type(adoption) ~= "table"
            or type(adoption.batchId) ~= "string"
            or adoption.batchId:sub(1, #jobId + 1) ~= jobId .. ":"
            or not isInteger(adoption.count, 1)
            or not validStringList(adoption.planIds, 1)
            or adoption.count ~= #adoption.planIds
            or adoption.sequence ~= lastConfirmed + 1
            or adoption.sequence > batchCount)
    then
        return false
    end
    local raw = progress.pendingRawCreation
    if raw ~= nil
        and (not validPendingRemainder(raw)
            or not validStringList(raw.planIds, 1))
    then
        return false
    end
    local group = progress.pendingGroupArtifact
    if group ~= nil
        and (type(group) ~= "table"
            or type(group.groupId) ~= "string"
            or group.groupId == ""
            or type(group.groupFingerprint) ~= "string"
            or group.groupFingerprint == ""
            or not isInteger(group.sequence, 1)
            or group.sequence > batchCount)
    then
        return false
    end
    return true
end

local function countValues(values)
    local total = 0
    for _, value in pairs(values or {}) do
        if not isInteger(value, 0) then
            return nil
        end
        total += value
    end
    return total
end

local function executionHash(execution)
    return Canonical.checksum({
        batchCount = execution.batchCount,
        chunks = execution.chunks,
        operationCounts = execution.operationCounts,
        phaseCounts = execution.phaseCounts,
        planHash = execution.planHash,
        strategy = execution.strategy,
        totalWeight = execution.totalWeight,
    })
end

local function mapNeverDecreases(previous, newer)
    for key, previousValue in pairs(previous or {}) do
        local newerValue = newer and newer[key] or 0
        if type(previousValue) ~= "number"
            or type(newerValue) ~= "number"
            or newerValue < previousValue
        then
            return false
        end
    end
    return true
end

local function mapNeverIncreases(previous, newer)
    for key, previousValue in pairs(previous or {}) do
        local newerValue = newer and newer[key]
        if type(previousValue) ~= "number"
            or type(newerValue) ~= "number"
            or newerValue > previousValue
        then
            return false
        end
    end
    return true
end

local function coherentSuccessor(previous, newer)
    if newer.generation ~= previous.generation + 1 then
        return false
    end
    local previousProgress = previous.progress
    local newerProgress = newer.progress
    if newerProgress.lastConfirmedSequence < previousProgress.lastConfirmedSequence
        or newerProgress.confirmedWeight < previousProgress.confirmedWeight
        or not mapNeverDecreases(
            previousProgress.phaseConfirmed,
            newerProgress.phaseConfirmed
        )
        or not mapNeverIncreases(
            previousProgress.remainingOperationCounts,
            newerProgress.remainingOperationCounts
        )
        or (previousProgress.terminalStarted == true
            and newerProgress.terminalStarted ~= true)
    then
        return false
    end

    local previousCleanup = previous.cleanup
    local newerCleanup = newer.cleanup
    if previousCleanup ~= nil
        and (newerCleanup == nil
            or (newerCleanup.lastConfirmedSequence or 0)
                < (previousCleanup.lastConfirmedSequence or 0)
            or (newerCleanup.removedCount or 0)
                < (previousCleanup.removedCount or 0))
    then
        return false
    end

    local previousState = previous.job.state
    local newerState = newer.job.state
    if previousState == "rollback" or previousState == "rollback_incomplete" then
        return newerState == "rollback" or newerState == "rollback_incomplete"
    elseif previousState == "completed" then
        return newerState == "completed" or newerState == "cleanup_pending"
    elseif previousState == "cleanup_pending" then
        return newerState == "cleanup_pending"
    end
    return true
end

function CheckpointStore.new(options)
    options = options or {}
    local self = setmetatable({
        adapterId = options.adapterId or "town",
        available = true,
        checksum = options.checksum or Canonical.checksum,
        checksumAlgorithm = options.checksumAlgorithm or Canonical.algorithm,
        decode = options.decode,
        deleteFile = options.deleteFile,
        encode = options.encode,
        isFile = options.isFile,
        listFiles = options.listFiles,
        makeFolder = options.makeFolder,
        now = options.now or os.time,
        normalizePayload = options.normalizePayload ~= false,
        planVersion = options.planVersion or 1,
        publicError = nil,
        readFile = options.readFile,
        schemaVersion = options.schemaVersion or 1,
        userId = options.userId,
        verifiedJobs = {},
        writeFile = options.writeFile,
    }, CheckpointStore)

    if type(options.root) ~= "string"
        or options.root == ""
        or hasUnsafePathSegments(options.root)
        or options.userId == nil
    then
        self.available = false
    end
    for _, name in ipairs(REQUIRED_FUNCTIONS) do
        if type(self[name]) ~= "function" then
            self.available = false
        end
    end
    if not self.available then
        self.publicError = PUBLIC_ERROR
        self.root = type(options.root) == "string" and options.root or ""
        return self
    end

    self.root = options.root:gsub("[/\\]+$", "") .. "/" .. tostring(options.userId)
    self.jobsRoot = self.root .. "/jobs"
    self.stateA = self.root .. "/state.a.json"
    self.stateB = self.root .. "/state.b.json"
    self:_ensureFolder(self.root)
    self:_ensureFolder(self.jobsRoot)
    return self
end

function CheckpointStore:_ensureFolder(path)
    local current = ""
    for component in path:gmatch("[^/\\]+") do
        current = current == "" and component or (current .. "/" .. component)
        pcall(self.makeFolder, current)
    end
end

function CheckpointStore:_envelope(payload)
    return {
        checksum = self.checksum(payload),
        checksumAlgorithm = self.checksumAlgorithm,
        format = "uh-town-checkpoint",
        payload = payload,
    }
end

function CheckpointStore:_decodeEnvelope(source)
    local decoded = self.decode(source)
    assert(type(decoded) == "table", "Checkpoint envelope must be an object")
    assert(decoded.format == "uh-town-checkpoint", "Unknown checkpoint format")
    assert(decoded.checksumAlgorithm == self.checksumAlgorithm, "Unknown checkpoint checksum algorithm")
    assert(type(decoded.payload) == "table", "Checkpoint payload is missing")
    assert(self.checksum(decoded.payload) == decoded.checksum, "Checkpoint checksum mismatch")
    return decoded
end

function CheckpointStore:_readEnvelope(path)
    if not self.isFile(path) then
        return "missing"
    end
    local succeeded, result = pcall(function()
        return self:_decodeEnvelope(self.readFile(path))
    end)
    if not succeeded then
        return "corrupt", result
    end
    return "valid", result
end

function CheckpointStore:_writeVerified(path, payload)
    assert(self.available, PUBLIC_ERROR)
    local parent = dirname(path)
    if parent then
        self:_ensureFolder(parent)
    end
    local normalizedPayload = self.normalizePayload
            and self.decode(self.encode(payload))
        or payload
    local envelope = self:_envelope(normalizedPayload)
    local encoded = self.encode(envelope)
    self.writeFile(path, encoded)
    local decoded = self:_decodeEnvelope(self.readFile(path))
    assert(same(decoded.payload, normalizedPayload), "Checkpoint readback payload mismatch")
    return {
        byteLength = #encoded,
        bytes = #encoded,
        checksum = decoded.checksum,
    }
end

function CheckpointStore:_manifestPath(jobId)
    return self:_jobRoot(jobId) .. "/manifest.json"
end

function CheckpointStore:_writeState(path, state)
    local hydrated = state
    local manifest = hydrated.manifest
    if not manifest then
        local manifestPath = self:_manifestPath(hydrated.job.id)
        local metadata = self:_writeVerified(manifestPath, {
            executionChunks = hydrated.execution.chunks,
            executionHash = hydrated.execution.hash,
            jobId = hydrated.job.id,
            kind = "manifest",
            planChunks = hydrated.plan.chunks,
            planFingerprint = hydrated.plan.fingerprint,
        })
        metadata.file = self:_relative(manifestPath)
        metadata.jobId = hydrated.job.id
        metadata.kind = "manifest"
        manifest = metadata
        hydrated = copyMutableState(hydrated)
        hydrated.manifest = metadata
    end
    local compact = copyMutableState(hydrated)
    compact.plan = withoutKey(hydrated.plan, "chunks")
    compact.execution = withoutKey(hydrated.execution, "chunks")
    self:_writeVerified(path, compact)
    return hydrated
end

function CheckpointStore:_hydrateState(state)
    if state.plan and state.plan.chunks
        and state.execution and state.execution.chunks
    then
        return state
    end
    local manifest = state.manifest
    assert(type(manifest) == "table", "Checkpoint manifest is missing")
    assert(manifest.jobId == state.job.id and manifest.kind == "manifest", "Checkpoint manifest binding mismatch")
    local relative = ("jobs/%s/manifest.json"):format(state.job.id)
    assert(normalize(manifest.file) == relative, "Checkpoint manifest path mismatch")
    local path = self.root .. "/" .. relative
    assert(self.isFile(path), "Checkpoint manifest is unavailable")
    local source = self.readFile(path)
    assert(#source == manifest.byteLength, "Checkpoint manifest byte length mismatch")
    local status, envelope = self:_readEnvelope(path)
    assert(status == "valid" and envelope.checksum == manifest.checksum, "Checkpoint manifest checksum mismatch")
    local payload = envelope.payload
    assert(
        payload.kind == "manifest"
            and payload.jobId == state.job.id
            and payload.planFingerprint == state.plan.fingerprint
            and payload.executionHash == state.execution.hash,
        "Checkpoint manifest content mismatch"
    )
    local hydrated = copy(state)
    hydrated.plan.chunks = payload.planChunks
    hydrated.execution.chunks = payload.executionChunks
    return hydrated
end

function CheckpointStore:_readState(path)
    local status, envelope = self:_readEnvelope(path)
    if status ~= "valid" then
        return status, envelope
    end
    local succeeded, hydrated = pcall(self._hydrateState, self, envelope.payload)
    if not succeeded then
        return "corrupt", hydrated
    end
    envelope.payload = hydrated
    return "valid", envelope
end

function CheckpointStore:_jobRoot(jobId)
    assert(isSafeJobId(jobId), "Checkpoint job id is invalid")
    return self.jobsRoot .. "/" .. jobId
end

function CheckpointStore:_relative(path)
    assert(not hasUnsafePathSegments(path), "Checkpoint path contains unsafe segments")
    local root = normalize(self.root)
    local normalized = normalize(path)
    assert(normalized:sub(1, #root + 1) == root .. "/", "Checkpoint path escapes the private root")
    return normalized:sub(#root + 2)
end

function CheckpointStore:_filesUnder(root)
    local files = {}
    local visited = {}
    local privateRoot = normalize(self.root)
    local function visit(path, depth)
        if hasUnsafePathSegments(path) then
            return
        end
        local normalized = normalize(path)
        if visited[normalized] or depth > 8 then
            return
        end
        assert(
            normalized == privateRoot or normalized:sub(1, #privateRoot + 1) == privateRoot .. "/",
            "Checkpoint listing escaped the private root"
        )
        visited[normalized] = true
        local succeeded, entries = pcall(self.listFiles, path)
        if not succeeded or type(entries) ~= "table" then
            return
        end
        for _, entry in ipairs(entries) do
            local child = not hasUnsafePathSegments(entry) and normalize(entry) or nil
            if child and child:sub(1, #privateRoot + 1) == privateRoot .. "/" then
                if self.isFile(entry) then
                    files[child] = entry
                else
                    visit(entry, depth + 1)
                end
            end
        end
    end
    visit(root, 0)
    local result = {}
    for _, original in pairs(files) do
        table.insert(result, original)
    end
    table.sort(result)
    return result
end

function CheckpointStore:_validState(state, trustCachedChunks)
    if type(state) ~= "table" then
        return false, "corrupt"
    end
    if state.schemaVersion ~= self.schemaVersion
        or state.planVersion ~= self.planVersion
        or state.adapterId ~= self.adapterId
    then
        return false, "version"
    end
    local context = state.context
    if not isInteger(state.generation, 1)
        or type(context) ~= "table"
        or context.gameId == nil
        or context.placeId == nil
        or context.localUserId == nil
        or not hasExactKeys(context.destination, DESTINATION_CONTEXT_KEYS)
        or not hasExactKeys(context.source, SOURCE_CONTEXT_KEYS)
        or type(state.job) ~= "table"
        or not isSafeJobId(state.job.id)
        or STATE_AUTHORIZATION[state.job.state] == nil
        or type(state.job.lastUpdatedAt) ~= "number"
        or type(state.authorization) ~= "table"
        or state.authorization.state ~= STATE_AUTHORIZATION[state.job.state]
        or type(state.plan) ~= "table"
        or not isInteger(state.plan.supported, 1)
        or not isInteger(state.plan.chunkCount, 1)
        or type(state.plan.chunks) ~= "table"
        or #state.plan.chunks ~= state.plan.chunkCount
        or type(state.plan.fingerprint) ~= "string"
        or not isInteger(state.plan.totalWeight, 1)
        or type(state.execution) ~= "table"
        or not isInteger(state.execution.batchCount, 1)
        or not isInteger(state.execution.chunkCount, 1)
        or type(state.execution.chunks) ~= "table"
        or #state.execution.chunks ~= state.execution.chunkCount
        or type(state.execution.hash) ~= "string"
        or type(state.execution.operationCounts) ~= "table"
        or type(state.execution.phaseCounts) ~= "table"
        or state.execution.planHash ~= state.plan.fingerprint
        or state.execution.totalWeight ~= state.plan.totalWeight
        or countValues(state.execution.operationCounts) ~= state.execution.batchCount
        or countValues(state.execution.phaseCounts) ~= state.execution.batchCount
        or type(state.progress) ~= "table"
        or not isInteger(state.progress.lastConfirmedSequence, 0)
        or state.progress.lastConfirmedSequence > state.execution.batchCount
        or type(state.progress.confirmedWeight) ~= "number"
        or state.progress.confirmedWeight < 0
        or state.progress.confirmedWeight > state.plan.totalWeight
        or not validPendingBatch(
            state.job.id,
            state.progress.pendingBatch,
            state.progress.lastConfirmedSequence,
            state.execution.batchCount
        )
        or not validRecoveryArtifacts(
            state.job.id,
            state.progress,
            state.progress.lastConfirmedSequence,
            state.execution.batchCount
        )
    then
        return false, "corrupt"
    end
    local immutableKey = state.job.id
        .. "|"
        .. state.plan.fingerprint
        .. "|"
        .. state.execution.hash
    if not (trustCachedChunks and self.verifiedJobs[state.job.id] == immutableKey)
        and state.execution.hash ~= executionHash(state.execution)
    then
        return false, "corrupt"
    end
    local localCleanupOnly = state.job.state == "completed"
        or state.job.state == "cleanup_pending"
    if state.job.state == "awaiting_confirmation"
        and (state.progress.lastConfirmedSequence ~= 0
            or state.progress.confirmedWeight ~= 0
            or state.progress.pendingBatch ~= nil)
    then
        return false, "corrupt"
    end
    if state.progress.terminalStarted == true
        and (state.job.state == "paused"
            or state.job.state == "rollback"
            or state.job.state == "rollback_incomplete"
            or state.job.state == "cancel_requested")
    then
        return false, "corrupt"
    end
    for phase, confirmed in pairs(state.progress.phaseConfirmed or {}) do
        if not isInteger(confirmed, 0)
            or confirmed > (state.execution.phaseCounts[phase] or 0)
        then
            return false, "corrupt"
        end
    end
    for operation, remaining in pairs(state.progress.remainingOperationCounts or {}) do
        if not isInteger(remaining, 0)
            or remaining > (state.execution.operationCounts[operation] or 0)
        then
            return false, "corrupt"
        end
    end
    if localCleanupOnly
        and (state.progress.lastConfirmedSequence ~= state.execution.batchCount
            or state.progress.pendingBatch ~= nil
            or state.progress.confirmedWeight ~= state.plan.totalWeight)
    then
        return false, "corrupt"
    end
    local cleanup = state.cleanup
    if cleanup ~= nil then
        if type(cleanup) ~= "table"
            or not isInteger(cleanup.lastConfirmedSequence or 0, 0)
            or not isInteger(cleanup.removedCount or 0, 0)
            or cleanup.removedCount > state.plan.supported + (state.plan.groups or 0)
            or not isInteger(
                cleanup.cursorSequence or state.progress.lastConfirmedSequence,
                0
            )
            or (cleanup.cursorSequence or state.progress.lastConfirmedSequence)
                > state.progress.lastConfirmedSequence
        then
            return false, "corrupt"
        end
        local pendingCleanup = cleanup.pendingBatch
        if pendingCleanup ~= nil
            and (type(pendingCleanup) ~= "table"
                or pendingCleanup.operation ~= "Remove"
                or type(pendingCleanup.id) ~= "string"
                or pendingCleanup.id:sub(1, #state.job.id + 1) ~= state.job.id .. ":")
        then
            return false, "corrupt"
        end
    end
    if not localCleanupOnly
        and not (trustCachedChunks and self.verifiedJobs[state.job.id] == immutableKey)
    then
        if not self:verifyPlan(state.job.id, state.plan.chunks, state.plan.supported)
            or not self:verifyJobChunks(
                state.job.id,
                "execution",
                state.execution.chunks,
                state.execution.batchCount
            )
        then
            return false, "corrupt"
        end
        self.verifiedJobs[state.job.id] = immutableKey
    end
    return true
end

function CheckpointStore:_stateSlots(trustCachedChunks)
    local stateA, envelopeA = self:_readState(self.stateA)
    local stateB, envelopeB = self:_readState(self.stateB)
    local candidates = {}
    local validA, invalidReasonA
    if stateA == "valid" then
        validA, invalidReasonA = self:_validState(envelopeA.payload, trustCachedChunks)
    end
    if stateA == "valid" and validA then
        table.insert(candidates, {
            envelope = envelopeA,
            path = self.stateA,
        })
    elseif stateA == "valid" then
        stateA = invalidReasonA
    end
    local validB, invalidReasonB
    if stateB == "valid" then
        validB, invalidReasonB = self:_validState(envelopeB.payload, trustCachedChunks)
    end
    if stateB == "valid" and validB then
        table.insert(candidates, {
            envelope = envelopeB,
            path = self.stateB,
        })
    elseif stateB == "valid" then
        stateB = invalidReasonB
    end
    table.sort(candidates, function(left, right)
        return left.envelope.payload.generation > right.envelope.payload.generation
    end)
    if #candidates > 1
        and candidates[1].envelope.payload.job.id ~= candidates[2].envelope.payload.job.id
    then
        return nil, "corrupt", "corrupt", {}
    end
    if #candidates > 1 then
        local newer = candidates[1].envelope.payload
        local previous = candidates[2].envelope.payload
        if newer.generation == previous.generation then
            if not same(newer, previous) then
                return nil, "corrupt", "corrupt", {}
            end
        elseif not coherentSuccessor(previous, newer) then
            table.remove(candidates, 1)
        end
    end
    return candidates[1], stateA, stateB, candidates
end

function CheckpointStore:writeJobChunk(jobId, kind, index, chunk)
    assert(self.available, PUBLIC_ERROR)
    assert(isSafeJobId(jobId), "Plan chunks require a safe job id")
    assert(type(kind) == "string" and kind:match("^[a-z]+$"), "Job chunk kind is invalid")
    assert(isInteger(index, 1), "Plan chunk index must be positive")
    assert(type(chunk) == "table", "Plan chunk must be an object")
    assert(chunk.jobId == jobId, "Plan chunk job id mismatch")
    assert(chunk.kind == kind, "Job chunk kind mismatch")
    assert(chunk.index == index, "Plan chunk index mismatch")
    assert(type(chunk.records) == "table" and #chunk.records > 0, "Plan chunks cannot be empty")
    local path = ("%s/%s-%05d.json"):format(self:_jobRoot(jobId), kind, index)
    local metadata = self:_writeVerified(path, chunk)
    metadata.file = self:_relative(path)
    metadata.index = index
    metadata.jobId = jobId
    metadata.kind = kind
    metadata.recordCount = #chunk.records
    return metadata
end

function CheckpointStore:writePlanChunk(jobId, index, chunk)
    local payload = copy(chunk)
    payload.kind = "plan"
    return self:writeJobChunk(jobId, "plan", index, payload)
end

function CheckpointStore:stagePlan(job, chunkIterator)
    assert(type(job) == "table" and type(job.id) == "string", "Plan staging requires a job")
    local chunks = {}
    local index = 0
    if type(chunkIterator) == "function" then
        while true do
            local chunk = chunkIterator()
            if chunk == nil then
                break
            end
            index += 1
            table.insert(chunks, self:writePlanChunk(job.id, index, {
                index = index,
                jobId = job.id,
                records = chunk.records or chunk,
            }))
        end
    else
        for _, chunk in ipairs(chunkIterator or {}) do
            index += 1
            table.insert(chunks, self:writePlanChunk(job.id, index, {
                index = index,
                jobId = job.id,
                records = chunk.records or chunk,
            }))
        end
    end
    return chunks
end

function CheckpointStore:_chunkPath(jobId, kind, metadata, expectedIndex)
    if not isSafeJobId(jobId)
        or type(kind) ~= "string"
        or kind:match("^[a-z]+$") == nil
        or type(metadata) ~= "table"
        or metadata.jobId ~= jobId
        or metadata.kind ~= kind
        or metadata.index ~= expectedIndex
        or not isInteger(metadata.recordCount, 1)
        or not isInteger(metadata.byteLength, 1)
        or type(metadata.checksum) ~= "string"
    then
        return nil
    end
    local expectedRelative = ("jobs/%s/%s-%05d.json"):format(jobId, kind, expectedIndex)
    if normalize(metadata.file) ~= expectedRelative
        or metadata.file:find("..", 1, true)
        or metadata.file:sub(1, 1) == "/"
    then
        return nil
    end
    return self.root .. "/" .. expectedRelative
end

function CheckpointStore:verifyJobChunks(jobId, kind, chunks, expectedRecordCount)
    if not self.available then
        return false
    end
    if not isSafeJobId(jobId)
        or type(chunks) ~= "table"
        or #chunks == 0
        or not isInteger(expectedRecordCount, 1)
    then
        return false
    end
    local records = 0
    for index, metadata in ipairs(chunks) do
        local path = self:_chunkPath(jobId, kind, metadata, index)
        if not path or not self.isFile(path) then
            return false
        end
        local source = self.readFile(path)
        if #source ~= metadata.byteLength then
            return false
        end
        local status, envelope = self:_readEnvelope(path)
        local payload = status == "valid" and envelope.payload or nil
        if status ~= "valid"
            or envelope.checksum ~= metadata.checksum
            or type(payload) ~= "table"
            or payload.jobId ~= jobId
            or payload.kind ~= kind
            or payload.index ~= index
            or type(payload.records) ~= "table"
            or #payload.records ~= metadata.recordCount
            or #payload.records == 0
        then
            return false
        end
        records += metadata.recordCount
    end
    return records == expectedRecordCount
end

function CheckpointStore:verifyPlan(jobId, chunks, expectedRecordCount)
    return self:verifyJobChunks(jobId, "plan", chunks, expectedRecordCount)
end

function CheckpointStore:readJobChunk(jobId, kind, metadata)
    assert(self.available, PUBLIC_ERROR)
    local path = self:_chunkPath(jobId, kind, metadata, metadata and metadata.index)
    assert(path, "Plan chunk metadata is invalid")
    assert(#self.readFile(path) == metadata.byteLength, "Plan chunk byte length mismatch")
    local status, envelope = self:_readEnvelope(path)
    assert(status == "valid", "Plan chunk is unavailable")
    assert(envelope.checksum == metadata.checksum, "Plan chunk checksum mismatch")
    assert(
        envelope.payload.jobId == jobId
            and envelope.payload.kind == kind
            and envelope.payload.index == metadata.index
            and #envelope.payload.records == metadata.recordCount,
        "Plan chunk binding mismatch"
    )
    return copy(envelope.payload)
end

function CheckpointStore:readPlanChunk(jobId, metadata)
    return self:readJobChunk(jobId, "plan", metadata)
end

function CheckpointStore:beginStaging(jobId, liveContext)
    if not self.available then
        return false, PUBLIC_ERROR
    end
    if not isSafeJobId(jobId) then
        return false, "Town copy job identity is invalid"
    end
    local loaded = self:load(liveContext)
    if loaded.status == "ready" or loaded.status == "incompatible" then
        return false, ACTIVE_JOB_MESSAGE
    end
    if loaded.status ~= "empty" and loaded.status ~= "quarantined" then
        return false, loaded.message or "Town recovery state is unavailable"
    end
    local jobRoot = self:_jobRoot(jobId)
    if #self:_filesUnder(jobRoot) > 0 then
        self:_quarantinePaths(self:_filesUnder(jobRoot), "orphan")
    end
    local succeeded = pcall(function()
        self:_writeVerified(jobRoot .. "/staging.json", {
            context = copy(liveContext or {}),
            createdAt = self.now(),
            jobId = jobId,
        })
    end)
    if not succeeded then
        return false, PUBLIC_ERROR
    end
    return true
end

function CheckpointStore:abortStaging(jobId)
    if not self.available or not isSafeJobId(jobId) then
        return false, PUBLIC_ERROR
    end
    local current = self:_stateSlots()
    if current and current.envelope.payload.job.id == jobId then
        return false, "Active Town recovery cannot be removed as staging"
    end
    local jobRoot = self:_jobRoot(jobId)
    for _, path in ipairs(self:_filesUnder(jobRoot)) do
        self.deleteFile(path)
    end
    return #self:_filesUnder(jobRoot) == 0
end

function CheckpointStore:commitInitial(state)
    if not self.available then
        return false, PUBLIC_ERROR
    end
    local initial = copy(state)
    initial.generation = 1
    initial.job.lastUpdatedAt = initial.job.lastUpdatedAt or self.now()
    local succeeded, result = pcall(function()
        assert(isSafeJobId(initial.job and initial.job.id), "Town copy job identity is invalid")
        local existing, stateA, stateB = self:_stateSlots()
        assert(not existing and stateA == "missing" and stateB == "missing", ACTIVE_JOB_MESSAGE)
        local stagingPath = self:_jobRoot(initial.job.id) .. "/staging.json"
        assert(self.isFile(stagingPath), "Town copy staging marker is unavailable")
        assert(self:_validState(initial), "Initial Town checkpoint is invalid")
        return self:_writeState(self.stateA, initial)
    end)
    if not succeeded then
        local message = tostring(result)
        if message:find(ACTIVE_JOB_MESSAGE, 1, true) then
            return false, ACTIVE_JOB_MESSAGE
        end
        return false, PUBLIC_ERROR
    end
    local stagingPath = self:_jobRoot(initial.job.id) .. "/staging.json"
    if self.isFile(stagingPath) then
        self.deleteFile(stagingPath)
    end
    local hydrated = result
    self.currentState = copy(hydrated)
    self.currentPath = self.stateA
    return true, copy(hydrated)
end

function CheckpointStore:advance(mutator)
    assert(self.available, PUBLIC_ERROR)
    local current
    if self.currentState and self.currentPath then
        current = {
            envelope = {
                payload = self.currentState,
            },
            path = self.currentPath,
        }
    else
        current = self:_stateSlots(true)
    end
    assert(current, "No valid Town checkpoint is available")
    local nextState = copyMutableState(current.envelope.payload)
    mutator(nextState)
    assert(
        nextState.job
            and nextState.job.id == current.envelope.payload.job.id,
        "Town checkpoint identity cannot change"
    )
    nextState.generation = current.envelope.payload.generation + 1
    nextState.job.lastUpdatedAt = self.now()
    local valid = self:_validState(nextState, true)
    assert(valid, "Town checkpoint transition is semantically invalid")
    local target = current.path == self.stateA and self.stateB or self.stateA
    nextState = self:_writeState(target, nextState)
    self.currentState = nextState
    self.currentPath = target
    return copyMutableState(nextState)
end

function CheckpointStore:_compatible(saved, live)
    if type(saved) ~= "table"
        or type(live) ~= "table"
        or saved.gameId == nil
        or saved.placeId == nil
        or saved.localUserId == nil
        or live.gameId == nil
        or live.placeId == nil
        or live.localUserId == nil
        or not hasExactKeys(saved.destination, DESTINATION_CONTEXT_KEYS)
        or not hasExactKeys(live.destination, DESTINATION_CONTEXT_KEYS)
        or not hasExactKeys(saved.source, SOURCE_CONTEXT_KEYS)
        or not hasExactKeys(live.source, SOURCE_CONTEXT_KEYS)
    then
        return false
    end
    if saved.gameId ~= live.gameId
        or saved.placeId ~= live.placeId
        or saved.localUserId ~= live.localUserId
    then
        return false
    end

    local savedDestination = saved.destination
    local liveDestination = live.destination
    for _, key in ipairs(DESTINATION_CONTEXT_KEYS) do
        if not same(savedDestination[key], liveDestination[key]) then
            return false
        end
    end

    local savedSource = saved.source
    local liveSource = live.source
    for _, key in ipairs(SOURCE_CONTEXT_KEYS) do
        if not same(savedSource[key], liveSource[key]) then
            return false
        end
    end
    return true
end

function CheckpointStore:load(liveContext)
    if not self.available then
        return {
            message = PUBLIC_ERROR,
            status = "unavailable",
        }
    end

    local current, stateA, stateB = self:_stateSlots()
    if not current then
        if stateA == "version" or stateB == "version" then
            return self:quarantine("version")
        elseif stateA == "corrupt" or stateB == "corrupt" then
            return self:quarantine("corrupt")
        end
        if #self:_filesUnder(self.jobsRoot) > 0 then
            return self:quarantine("orphan")
        end
        return {
            status = "empty",
        }
    end

    local state = current.envelope.payload
    self.currentState = copy(state)
    self.currentPath = current.path
    if type(state.job) ~= "table"
        or type(state.job.lastUpdatedAt) ~= "number"
        or self.now() - state.job.lastUpdatedAt > ACTIVE_RETENTION_SECONDS
    then
        return self:quarantine("stale")
    end
    if liveContext and not self:_compatible(state.context or {}, liveContext) then
        return {
            message = "Checkpoint does not match the current Town source or destination",
            state = copy(state),
            status = "incompatible",
        }
    end
    return {
        state = copy(state),
        status = "ready",
    }
end

function CheckpointStore:_quarantinePaths(paths, reason)
    local safeReason = tostring(reason):gsub("[^%w_%-]", "_"):sub(1, 48)
    local quarantineRoot = ("%s/quarantine/%d-%s"):format(self.root, self.now(), safeReason)
    self:_ensureFolder(quarantineRoot)
    local index = 0
    for _, path in ipairs(paths) do
        if not normalize(path):find(normalize(self.root) .. "/quarantine/", 1, true)
            and self.isFile(path)
        then
            index += 1
            local source = self.readFile(path)
            local relative = self:_relative(path):gsub("[^%w_.%-]", "_")
            local destination = ("%s/%04d-%s"):format(quarantineRoot, index, relative)
            self.writeFile(destination, source)
            assert(self.readFile(destination) == source, "Checkpoint quarantine verification failed")
            self.deleteFile(path)
        end
    end
end

function CheckpointStore:quarantine(reason)
    if not self.available then
        return {
            message = PUBLIC_ERROR,
            reason = reason,
            status = "unavailable",
        }
    end
    self:_quarantinePaths(self:_filesUnder(self.root), reason)
    return {
        message = QUARANTINE_MESSAGE,
        reason = reason,
        status = "quarantined",
    }
end

function CheckpointStore:deleteJob(expectedJobId)
    if not self.available then
        return false, PUBLIC_ERROR
    end
    local current = self:_stateSlots()
    if not current then
        return false, "No valid Town checkpoint is available"
    end
    local state = current.envelope.payload
    local jobId = state.job.id
    if expectedJobId ~= nil and expectedJobId ~= jobId then
        return false, "Town checkpoint identity changed"
    end
    local paths = {}
    local statePaths = {}
    for _, statePath in ipairs({ self.stateA, self.stateB }) do
        local status, envelope = self:_readEnvelope(statePath)
        if status == "valid" then
            if not envelope.payload.job or envelope.payload.job.id ~= jobId then
                return false, "Checkpoint cleanup is blocked by unrelated recovery data"
            end
            table.insert(statePaths, statePath)
        elseif status == "corrupt" then
            return false, "Checkpoint cleanup is blocked by unreadable recovery data"
        end
    end
    for _, path in ipairs(self:_filesUnder(self:_jobRoot(jobId))) do
        table.insert(paths, path)
    end
    for _, statePath in ipairs(statePaths) do
        table.insert(paths, statePath)
    end
    for _, path in ipairs(paths) do
        if self.isFile(path) then
            self.deleteFile(path)
        end
    end
    for _, path in ipairs(paths) do
        if self.isFile(path) then
            return false, "Checkpoint cleanup is incomplete"
        end
    end
    self.verifiedJobs[jobId] = nil
    self.currentState = nil
    self.currentPath = nil
    return true
end

function CheckpointStore:prune(now)
    now = now or self.now()
    for _, path in ipairs(self:_filesUnder(self.root)) do
        local quarantinedAt = path:match("[/\\]quarantine[/\\](%d+)%-")
        if quarantinedAt
            and now - tonumber(quarantinedAt) > QUARANTINE_RETENTION_SECONDS
            and self.isFile(path)
        then
            self.deleteFile(path)
        end
    end
    local loaded = self:load()
    if loaded.status == "ready" then
        local activePrefix = normalize(self:_jobRoot(loaded.state.job.id)) .. "/"
        local orphans = {}
        for _, path in ipairs(self:_filesUnder(self.jobsRoot)) do
            if normalize(path):sub(1, #activePrefix) ~= activePrefix then
                table.insert(orphans, path)
            end
        end
        if #orphans > 0 then
            self:_quarantinePaths(orphans, "orphan")
        end
    end
    if loaded.status == "ready"
        and now - loaded.state.job.lastUpdatedAt > ACTIVE_RETENTION_SECONDS
    then
        return self:quarantine("stale")
    end
    return loaded
end

CheckpointStore.publicUnavailableError = PUBLIC_ERROR

return CheckpointStore
