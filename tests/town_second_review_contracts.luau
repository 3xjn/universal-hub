local serde = require("@lune/serde")
local CheckpointStore = require("../games/town/CheckpointStore")
local CopyEngine = require("../games/town/CopyEngine")
local ExecutionPlan = require("../games/town/ExecutionPlan")

local function newFileSystem()
    local files = {}
    return {
        files = files,
        deleteFile = function(path)
            files[path] = nil
        end,
        isFile = function(path)
            return files[path] ~= nil
        end,
        listFiles = function(root)
            local result = {}
            for path in pairs(files) do
                if path:sub(1, #root + 1) == root .. "/" then
                    table.insert(result, path)
                end
            end
            table.sort(result)
            return result
        end,
        makeFolder = function() end,
        readFile = function(path)
            return assert(files[path], "missing fake file " .. path)
        end,
        writeFile = function(path, source)
            files[path] = source
        end,
    }
end

local function exactContext()
    return {
        destination = {
            baselineFingerprint = "baseline",
            baselineInventory = {
                baseParts = 0,
                descendants = 0,
                fingerprint = "empty",
            },
            buildClassName = "Model",
            buildIdentity = "Plots.LocalBuildArea.Build|Model",
            buildName = "Build",
            ownerName = "Local",
            ownerUserId = 111,
            plotFrame = { 1, 2, 3 },
            plotName = "LocalBuildArea",
            plotPath = "Plots.LocalBuildArea.Build",
            plotSize = { 4, 5, 6 },
        },
        gameId = 1718755273,
        localUserId = 111,
        placeId = 4991214437,
        source = {
            fingerprint = "source",
            ownerName = "Source",
            ownerUserId = 222,
            plotName = "SourceBuildArea",
            plotPath = "Plots.SourceBuildArea.Build",
        },
    }
end

local fs = newFileSystem()
local checkpoint = CheckpointStore.new({
    adapterId = "town",
    decode = function(source)
        return serde.decode("json", source)
    end,
    deleteFile = fs.deleteFile,
    encode = function(value)
        return serde.encode("json", value)
    end,
    isFile = fs.isFile,
    listFiles = fs.listFiles,
    makeFolder = fs.makeFolder,
    now = function()
        return 1000
    end,
    planVersion = 1,
    readFile = fs.readFile,
    root = "private/town",
    schemaVersion = 1,
    userId = 111,
    writeFile = fs.writeFile,
})

local missingBuildContext = exactContext()
missingBuildContext.destination.buildIdentity = nil
assert(
    checkpoint:_compatible(exactContext(), missingBuildContext) == false,
    "REVIEW-P1-DESTINATION-EXACT: missing Build identity must fail closed"
)
local missingSourceContext = exactContext()
missingSourceContext.source = nil
assert(
    checkpoint:_compatible(exactContext(), missingSourceContext) == false,
    "REVIEW-P1-SOURCE-EXACT: missing source identity must fail closed"
)

local planRecords = {}
for index = 1, 300 do
    table.insert(planRecords, {
        className = "Part",
        cframe = { index, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
        id = ("part-%04d"):format(index),
        operations = { "resize" },
        type = "Normal",
    })
end
local executionChunks = {}
local executionCheckpoint = {
    readPlanChunk = function()
        return { records = planRecords }
    end,
    writeJobChunk = function(_, jobId, kind, index, chunk)
        table.insert(executionChunks, chunk.records)
        return {
            byteLength = 1,
            checksum = "checksum-" .. index,
            file = ("jobs/%s/%s-%05d.json"):format(jobId, kind, index),
            index = index,
            jobId = jobId,
            kind = kind,
            recordCount = #chunk.records,
        }
    end,
}
local groupParts = {}
for index = 1, 300 do
    table.insert(groupParts, ("part-%04d"):format(index))
end
local execution = ExecutionPlan.compile(
    executionCheckpoint,
    "job-execution",
    { { index = 1 } },
    { groups = 1 },
    {
        cloneRequestSize = 513,
        iterGroups = function(emit)
            emit({
                id = "model-root",
                modelIds = {},
                name = "Root",
                partIds = groupParts,
            })
        end,
        preferredBatchSize = 128,
        saveName = "Copy",
    }
)
local flattened = {}
for _, chunk in ipairs(executionChunks) do
    for _, batch in ipairs(chunk) do
        table.insert(flattened, batch)
    end
end
for _, batch in ipairs(flattened) do
    assert(
        batch.operation ~= "SetOwnership",
        "REVIEW-P1-CREATE-OWNERSHIP: creation and durable ownership must be one logical batch"
    )
    if batch.operation == "CreateGroup" or batch.operation == "AddGroupMembers" then
        local members = batch.memberIds or {}
        assert(
            #members <= 128,
            "REVIEW-P1-GROUP-BOUNDED: group membership batches must stay scheduler-bounded"
        )
    end
end
assert(type(execution.hash) == "string", "REVIEW-P1-EXECUTION-HASH: execution plans require a durable hash")
assert(
    type(execution.phaseCounts) == "table",
    "REVIEW-P1-PROGRESS-O1: persisted phase counters are required for O(1) views"
)

local readCount = 0
local batches = {}
for index = 1, 1000 do
    batches[index] = {
        operation = "SyncResize",
        phase = "Shaping geometry",
        sequence = index,
    }
end
local viewEngine = CopyEngine.new({
    checkpoint = {
        available = true,
    },
})
viewEngine.state = {
    execution = {
        batchCount = #batches,
        batches = batches,
        operationCounts = { SyncResize = #batches },
        phaseCounts = { ["Shaping geometry"] = #batches },
    },
    job = {
        id = "job-view",
        state = "copying",
    },
    plan = {
        supported = 1000,
        totalWeight = 1000,
    },
    progress = {
        confirmedWeight = 10,
        lastConfirmedSequence = 10,
        phaseConfirmed = { ["Shaping geometry"] = 10 },
        remainingOperationCounts = { SyncResize = 990 },
        timing = {},
    },
}
local originalBatchAt = viewEngine._batchAt
viewEngine._batchAt = function(self, sequence)
    readCount += 1
    return originalBatchAt(self, sequence)
end
viewEngine:_view()
assert(readCount == 0, "REVIEW-P1-PROGRESS-O1: rendering progress must not scan the whole execution plan")

local cancelState = {
    authorization = { state = "copy_authorized" },
    execution = {
        batchCount = 1,
        batches = {
            {
                operation = "Save",
                sequence = 1,
            },
        },
    },
    generation = 1,
    job = {
        id = "job-terminal",
        state = "copying",
    },
    plan = {
        supported = 1,
        totalWeight = 1,
    },
    progress = {
        confirmedWeight = 0,
        lastConfirmedSequence = 0,
        pendingBatch = {
            id = "job-terminal:save:1",
            operation = "Save",
            sequence = 1,
        },
        timing = {},
    },
}
local terminalCheckpoint = {
    advance = function(_, mutate)
        mutate(cancelState)
        return cancelState
    end,
    available = true,
}
local terminalEngine = CopyEngine.new({
    checkpoint = terminalCheckpoint,
})
terminalEngine.state = cancelState
local cancelled = terminalEngine:requestCancel()
assert(
    cancelled == false and terminalEngine.cancelRequested == false,
    "REVIEW-P1-TERMINAL-CANCEL: pending Save/Wire must be reconcile-only, never discardably paused"
)

print("town-second-review-contracts-ok")
