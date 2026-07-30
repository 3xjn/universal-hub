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

local CopyPlan = {}

local DEFAULT_CHUNK_SIZE = 256
local DEFAULT_CLONE_REQUEST_SIZE = 513
local DEFAULT_PREFERRED_BATCH_SIZE = 128

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

local function batchCount(count, size)
    return count > 0 and math.ceil(count / size) or 0
end

local function cloneCallCount(count, requestSize)
    if count <= 1 then
        return 0
    end
    local created = 1
    local calls = 0
    while created < count do
        created += math.min(count - created, created, requestSize)
        calls += 1
    end
    return calls
end

local function eachPart(source, emit)
    if type(source.iterParts) == "function" then
        source.iterParts(emit)
        return
    end
    for _, record in ipairs(source.parts or {}) do
        emit(record)
    end
end

local function increment(map, key, amount)
    map[key] = (map[key] or 0) + (amount or 1)
end

function CopyPlan.cloneCallCount(count, requestSize)
    return cloneCallCount(count, requestSize or DEFAULT_CLONE_REQUEST_SIZE)
end

function CopyPlan.fingerprint(value)
    return Canonical.checksum(value)
end

function CopyPlan.estimateWork(summary, preferredBatchSize)
    preferredBatchSize = preferredBatchSize or DEFAULT_PREFERRED_BATCH_SIZE
    local phases = {}
    local phaseOrder = {}
    local remoteCalls = summary.seeds + summary.cloneCalls
    for phase, records in pairs(summary.phaseCounts) do
        local batches = batchCount(records, preferredBatchSize)
        phases[phase] = {
            batches = batches,
            records = records,
        }
        table.insert(phaseOrder, phase)
        remoteCalls += batches
    end
    table.sort(phaseOrder)
    remoteCalls += summary.groups
    remoteCalls += summary.groupNames or 0
    if summary.copyWiring then
        remoteCalls += 1
    end
    if summary.save then
        remoteCalls += 1
    end
    return {
        cloneCalls = summary.cloneCalls,
        groups = summary.groups,
        groupNames = summary.groupNames or 0,
        phaseOrder = phaseOrder,
        phases = phases,
        remoteCalls = remoteCalls,
        seeds = summary.seeds,
        terminal = {
            save = summary.save == true,
            wiring = summary.copyWiring == true,
        },
    }
end

function CopyPlan.compile(source, options)
    assert(type(source) == "table", "CopyPlan requires a source")
    options = options or {}
    assert(options.maxParts == nil, "CopyPlan does not accept maxParts")
    assert(options.limit == nil, "CopyPlan does not accept limit")

    local chunkSize = options.chunkSize or DEFAULT_CHUNK_SIZE
    local cloneRequestSize = options.cloneRequestSize or DEFAULT_CLONE_REQUEST_SIZE
    local preferredBatchSize = options.preferredBatchSize or DEFAULT_PREFERRED_BATCH_SIZE
    assert(chunkSize >= 1 and chunkSize % 1 == 0, "CopyPlan chunkSize must be a positive integer")
    assert(
        cloneRequestSize >= 1 and cloneRequestSize % 1 == 0,
        "CopyPlan cloneRequestSize must be a positive integer"
    )
    assert(
        preferredBatchSize >= 1 and preferredBatchSize % 1 == 0,
        "CopyPlan preferredBatchSize must be a positive integer"
    )

    local buffer = {}
    local chunkChecksums = {}
    local chunks = options.retainChunks and {} or nil
    local peakBuffer = 0
    local phaseCounts = {}
    local supportedClasses = {}
    local typeCounts = {}
    local supported = 0
    local markerBearing = 0

    local function flush()
        if #buffer == 0 then
            return
        end
        local chunk = {
            index = #chunkChecksums + 1,
            records = buffer,
        }
        local checksum = Canonical.checksum(chunk)
        table.insert(chunkChecksums, checksum)
        if chunks then
            table.insert(chunks, copy(chunk))
        end
        if options.onChunk then
            options.onChunk(copy(chunk), checksum)
        end
        buffer = {}
    end

    eachPart(source, function(record)
        assert(type(record) == "table" and type(record.id) == "string", "CopyPlan parts require stable ids")
        assert(type(record.className) == "string", "CopyPlan parts require className")
        assert(type(record.type) == "string", "CopyPlan parts require Town part type")
        supported += 1
        if record.markerBearing == true then
            markerBearing += 1
        end
        increment(supportedClasses, record.className)
        increment(typeCounts, record.type)
        local operations = record.operations or { "resize" }
        for _, operation in ipairs(operations) do
            assert(type(operation) == "string", "CopyPlan operation names must be strings")
            increment(phaseCounts, operation)
        end
        table.insert(buffer, copy(record))
        peakBuffer = math.max(peakBuffer, #buffer)
        if #buffer == chunkSize then
            flush()
        end
    end)
    flush()

    local seeds = 0
    local cloneCalls = 0
    for _, count in pairs(typeCounts) do
        seeds += 1
        cloneCalls += cloneCallCount(count, cloneRequestSize)
    end

    local groups = source.groupCount or #(source.groups or {})
    local groupNames = 0
    for _, group in ipairs(source.groups or {}) do
        if group.name and group.name ~= "Model" then
            groupNames += 1
        end
    end
    local work = CopyPlan.estimateWork({
        cloneCalls = cloneCalls,
        copyWiring = source.copyWiring == true,
        groups = groups,
        groupNames = groupNames,
        phaseCounts = phaseCounts,
        save = source.save ~= false,
        seeds = seeds,
    }, preferredBatchSize)

    local plan = {
        baseParts = source.baseParts or supported + (source.unsupported or 0),
        chunkChecksums = chunkChecksums,
        chunks = chunks,
        context = copy(source.context or {}),
        groups = groups,
        markerBearing = markerBearing,
        peakBuffer = peakBuffer,
        requestSizing = {
            clone = cloneRequestSize,
            preferredBatch = preferredBatchSize,
            provenApiLimits = false,
        },
        schemaVersion = 1,
        supported = supported,
        supportedClasses = supportedClasses,
        typeCounts = typeCounts,
        totalDescendants = source.totalDescendants
            or supported + (source.unsupported or 0),
        unsupported = source.unsupported or 0,
        unsupportedClasses = copy(source.unsupportedClasses or {}),
        work = work,
    }
    plan.fingerprint = Canonical.checksum({
        baseParts = plan.baseParts,
        chunkChecksums = chunkChecksums,
        context = plan.context,
        groups = source.groups or {},
        markerBearing = markerBearing,
        requestSizing = plan.requestSizing,
        supported = supported,
        supportedClasses = supportedClasses,
        typeCounts = typeCounts,
        totalDescendants = plan.totalDescendants,
        unsupported = plan.unsupported,
        unsupportedClasses = plan.unsupportedClasses,
        work = work,
    })
    return plan
end

function CopyPlan.iterChunks(plan)
    local index = 0
    return function()
        index += 1
        return plan.chunks and plan.chunks[index] or nil
    end
end

return CopyPlan
