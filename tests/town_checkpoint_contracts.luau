local serde = require("@lune/serde")
local Canonical = require("../games/town/Canonical")
local CheckpointStore = require("../games/town/CheckpointStore")

local function deepCopy(value)
    return serde.decode("json", serde.encode("json", value))
end

local function newFileSystem()
    local files = {}
    local directories = {}
    return {
        directories = directories,
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
        makeFolder = function(path)
            directories[path] = true
        end,
        readFile = function(path)
            assert(files[path] ~= nil, "missing fake file " .. path)
            return files[path]
        end,
        writeFile = function(path, contents)
            files[path] = contents
        end,
    }
end

local function context()
    return {
        destination = {
            baselineFingerprint = "destination-fingerprint",
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
            fingerprint = "source-fingerprint",
            ownerName = "Source",
            ownerUserId = 222,
            plotName = "SourceBuildArea",
            plotPath = "Plots.SourceBuildArea.Build",
        },
    }
end

local function state(now)
    return {
        adapterId = "town",
        authorization = {
            state = "awaiting_confirmation",
        },
        context = context(),
        generation = 1,
        job = {
            createdAt = now,
            id = "job-1",
            lastUpdatedAt = now,
            state = "awaiting_confirmation",
        },
        plan = {
            chunkCount = 1,
            chunks = {},
            fingerprint = "plan-fingerprint",
            supported = 1,
            totalWeight = 1,
        },
        planVersion = 1,
        progress = {
            confirmedWeight = 0,
            lastConfirmedSequence = 0,
        },
        schemaVersion = 1,
    }
end

local function attachExecution(store, fixture, jobId)
    local metadata = assert(store:writeJobChunk(jobId, "execution", 1, {
        index = 1,
        jobId = jobId,
        kind = "execution",
        records = {
            {
                operation = "SyncResize",
                phase = "Shaping geometry",
                planIds = { "part-1" },
                sequence = 1,
            },
        },
    }))
    fixture.execution = {
        batchCount = 1,
        chunkCount = 1,
        chunks = { metadata },
        operationCounts = { SyncResize = 1 },
        phaseCounts = { ["Shaping geometry"] = 1 },
        planHash = fixture.plan.fingerprint,
        strategy = "town-stream-v1",
        totalWeight = 1,
    }
    fixture.execution.hash = Canonical.checksum({
        batchCount = fixture.execution.batchCount,
        chunks = fixture.execution.chunks,
        operationCounts = fixture.execution.operationCounts,
        phaseCounts = fixture.execution.phaseCounts,
        planHash = fixture.execution.planHash,
        strategy = fixture.execution.strategy,
        totalWeight = fixture.execution.totalWeight,
    })
end

local function newStore(now)
    local fs = newFileSystem()
    local store = CheckpointStore.new({
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
            return now
        end,
        planVersion = 1,
        readFile = fs.readFile,
        root = "universal-hub/private/town-copy",
        schemaVersion = 1,
        userId = 111,
        writeFile = fs.writeFile,
    })
    return store, fs
end

local unavailable = CheckpointStore.new({
    root = "private",
    userId = 111,
})
assert(unavailable.available == false)
assert(unavailable.publicError == "Persistent recovery is unavailable in this executor")

local now = 1000000
local store, fs = newStore(now)
assert(store.available)
assert(store.root == "universal-hub/private/town-copy/111")
assert(store:beginStaging("job-1", context()))

local chunkMetadata = assert(store:writePlanChunk("job-1", 1, {
    jobId = "job-1",
    index = 1,
    records = {
        { id = "part-1", type = "Normal" },
    },
}))
assert(chunkMetadata.file == "jobs/job-1/plan-00001.json")
assert(chunkMetadata.checksum:match("^sha256%-c14n%-v1:"))

local initial = state(now)
initial.plan.chunks = { chunkMetadata }
attachExecution(store, initial, "job-1")
assert(store:commitInitial(initial))
assert(fs.files[store.root .. "/state.a.json"] ~= nil)
assert(store:verifyPlan("job-1", initial.plan.chunks, 1))
assert(not store:verifyPlan("job-1", {}, 0), "An empty plan must never validate")

local loaded = store:load(context())
assert(loaded.status == "ready")
assert(loaded.state.generation == 1)
assert(loaded.state.job.state == "awaiting_confirmation")

local advanced = assert(store:advance(function(nextState)
    nextState.authorization.state = "copy_authorized"
    nextState.job.state = "copy_authorized"
end))
assert(advanced.generation == 2)
assert(fs.files[store.root .. "/state.b.json"] ~= nil)

fs.files[store.root .. "/state.b.json"] = "{partial"
local fallback = store:load(context())
assert(fallback.status == "ready")
assert(fallback.state.generation == 1, "A partial newest slot must fall back to the previous valid generation")

local conflictStore, conflictFs = newStore(now)
assert(conflictStore:beginStaging("job-1", context()))
local activeState = state(now)
local activeChunk = assert(conflictStore:writePlanChunk("job-1", 1, {
    jobId = "job-1",
    index = 1,
    records = { { id = "part-1" } },
}))
activeState.plan.chunks = { activeChunk }
activeState.plan.supported = 1
attachExecution(conflictStore, activeState, "job-1")
assert(conflictStore:commitInitial(activeState))
assert(conflictStore:advance(function(nextState)
    nextState.authorization.state = "copy_authorized"
    nextState.job.state = "paused"
end).generation == 2)
local activeBefore = conflictFs.files[conflictStore.stateB]
local mayStage, conflictMessage = conflictStore:beginStaging("job-2", context())
assert(mayStage == false and conflictMessage == "An unfinished Town copy already exists")
assert(conflictFs.files[conflictStore.stateB] == activeBefore)
assert(conflictStore:abortStaging("job-2"))
assert(conflictFs.files[conflictStore.stateA] ~= nil and conflictFs.files[conflictStore.stateB] ~= nil)
assert(conflictStore:load(context()).state.job.id == "job-1")

local traversalMetadata = {
    checksum = activeChunk.checksum,
    file = "../state.a.json",
    index = 1,
    jobId = "job-1",
    recordCount = 1,
}
assert(
    not conflictStore:verifyPlan("job-1", { traversalMetadata }, 1),
    "Checkpoint-controlled filenames must stay inside the private job directory"
)

local listingTraversalStore, listingTraversalFs = newStore(now)
local foreignListingPath = listingTraversalStore.root .. "/../foreign.txt"
listingTraversalFs.files[foreignListingPath] = "foreign"
listingTraversalStore:quarantine("orphan")
assert(
    listingTraversalFs.files[foreignListingPath] == "foreign",
    "REVIEW-P0-PRIVATE-CONTAINMENT: listFiles dot segments must never escape private storage"
)

local semanticStore, semanticFs = newStore(now)
assert(semanticStore:beginStaging("job-1", context()))
local semanticState = state(now)
local semanticChunk = assert(semanticStore:writePlanChunk("job-1", 1, {
    jobId = "job-1",
    index = 1,
    records = { { id = "part-1" } },
}))
semanticState.plan.chunks = { semanticChunk }
semanticState.plan.supported = 1
attachExecution(semanticStore, semanticState, "job-1")
assert(semanticStore:commitInitial(semanticState))
local invalidNewest = deepCopy(semanticState)
invalidNewest.generation = 9
invalidNewest.schemaVersion = 999
semanticStore:_writeVerified(semanticStore.stateB, invalidNewest)
local semanticFallback = semanticStore:load(context())
assert(
    semanticFallback.status == "ready" and semanticFallback.state.generation == 1,
    "A schema-invalid newest slot must fall back to the prior fully valid state"
)

local semanticCase = 0
local function assertSemanticFallback(label, mutate)
    semanticCase += 1
    local caseStore = newStore(now)
    local jobId = "semantic-" .. tostring(semanticCase)
    assert(caseStore:beginStaging(jobId, context()))
    local validState = state(now)
    validState.job.id = jobId
    local validChunk = assert(caseStore:writePlanChunk(jobId, 1, {
        jobId = jobId,
        index = 1,
        records = { { id = "part-1" } },
    }))
    validState.plan.chunks = { validChunk }
    attachExecution(caseStore, validState, jobId)
    assert(caseStore:commitInitial(validState))
    local invalidState = deepCopy(validState)
    invalidState.generation = 2
    invalidState.authorization.state = "copy_authorized"
    invalidState.job.state = "paused"
    mutate(invalidState)
    caseStore:_writeVerified(caseStore.stateB, invalidState)
    local recovered = caseStore:load(context())
    assert(
        recovered.status == "ready" and recovered.state.generation == 1,
        "REVIEW-P1-SEMANTIC-STATE: invalid newest slot must fall back: " .. label
    )
end

assertSemanticFallback("state enum", function(candidate)
    candidate.job.state = "unknown"
end)
assertSemanticFallback("authorization pairing", function(candidate)
    candidate.authorization.state = "awaiting_confirmation"
end)
assertSemanticFallback("progress bounds", function(candidate)
    candidate.progress.lastConfirmedSequence = 2
end)
assertSemanticFallback("pending id", function(candidate)
    candidate.progress.pendingBatch = {
        id = "foreign:resize:1",
        operation = "SyncResize",
        planIds = { "part-1" },
        sequence = 1,
    }
end)
assertSemanticFallback("pending operation allowlist", function(candidate)
    candidate.progress.pendingBatch = {
        id = candidate.job.id .. ":evil:1",
        operation = "InvokeAnything",
        planIds = { "part-1" },
        sequence = 1,
    }
end)
assertSemanticFallback("pending remainder allowlist", function(candidate)
    candidate.progress.pendingBatch = {
        id = candidate.job.id .. ":ownership:1",
        nextPending = {
            operation = "InvokeAnything",
            planIds = { "part-1" },
        },
        operation = "AdoptOwnership",
        planIds = { "part-1" },
        sequence = 1,
    }
end)
assertSemanticFallback("pending adoption identity", function(candidate)
    candidate.progress.pendingAdoption = {
        batchId = "foreign:clone:1",
        count = 2,
        planIds = { "part-1" },
        sequence = 1,
    }
end)
assertSemanticFallback("execution hash", function(candidate)
    candidate.execution.hash = "sha256-c14n-v1:wrong"
end)
assertSemanticFallback("operation counts", function(candidate)
    candidate.execution.operationCounts.SyncResize = 2
end)
assertSemanticFallback("cleanup invariants", function(candidate)
    candidate.cleanup = {
        cursorSequence = 0,
        lastConfirmedSequence = 0,
        removedCount = 2,
    }
end)
assertSemanticFallback("completion eligibility", function(candidate)
    candidate.job.state = "completed"
end)

local monotonicStore = newStore(now)
assert(monotonicStore:beginStaging("monotonic-job", context()))
local monotonicState = state(now)
monotonicState.job.id = "monotonic-job"
local monotonicChunk = assert(monotonicStore:writePlanChunk("monotonic-job", 1, {
    jobId = "monotonic-job",
    index = 1,
    records = { { id = "part-1" } },
}))
monotonicState.plan.chunks = { monotonicChunk }
attachExecution(monotonicStore, monotonicState, "monotonic-job")
monotonicState.authorization.state = "copy_authorized"
monotonicState.job.state = "paused"
monotonicState.progress.confirmedWeight = 1
monotonicState.progress.lastConfirmedSequence = 1
assert(monotonicStore:commitInitial(monotonicState))
local regressedState = deepCopy(monotonicState)
regressedState.generation = 2
regressedState.progress.confirmedWeight = 0
regressedState.progress.lastConfirmedSequence = 0
monotonicStore:_writeVerified(monotonicStore.stateB, regressedState)
local monotonicFallback = monotonicStore:load(context())
assert(
    monotonicFallback.status == "ready" and monotonicFallback.state.generation == 1,
    "REVIEW-P1-SEQUENCE-MONOTONIC: a newer slot may not regress confirmed progress"
)

local foreignSlotStore, foreignSlotFs = newStore(now)
assert(foreignSlotStore:beginStaging("job-1", context()))
local firstState = state(now)
local firstChunk = assert(foreignSlotStore:writePlanChunk("job-1", 1, {
    jobId = "job-1",
    index = 1,
    records = { { id = "part-1" } },
}))
firstState.plan.chunks = { firstChunk }
attachExecution(foreignSlotStore, firstState, "job-1")
assert(foreignSlotStore:commitInitial(firstState))
local foreignState = state(now)
foreignState.generation = 9
foreignState.job.id = "job-foreign"
local foreignChunk = assert(foreignSlotStore:writePlanChunk("job-foreign", 1, {
    jobId = "job-foreign",
    index = 1,
    records = { { id = "foreign-part" } },
}))
foreignState.plan.chunks = { foreignChunk }
attachExecution(foreignSlotStore, foreignState, "job-foreign")
foreignSlotStore:_writeVerified(foreignSlotStore.stateB, foreignState)
local stateABefore = foreignSlotFs.files[foreignSlotStore.stateA]
local stateBBefore = foreignSlotFs.files[foreignSlotStore.stateB]
local deletedForeign, foreignDeleteError = foreignSlotStore:deleteJob("job-foreign")
assert(
    not deletedForeign and foreignDeleteError == "No valid Town checkpoint is available",
    "Different jobs in the two active slots must fail closed before cleanup"
)
assert(foreignSlotFs.files[foreignSlotStore.stateA] == stateABefore)
assert(foreignSlotFs.files[foreignSlotStore.stateB] == stateBBefore)

local orphanStore, orphanFs = newStore(now)
assert(orphanStore:writePlanChunk("orphan-job", 1, {
    jobId = "orphan-job",
    index = 1,
    records = { { id = "orphan" } },
}))
local orphaned = orphanStore:load()
assert(orphaned.status == "quarantined" and orphaned.reason == "orphan")
assert(#orphanFs.listFiles(orphanStore.root) > 0)

local mismatch = store:load({
    destination = context().destination,
    gameId = 1718755273,
    localUserId = 999,
    placeId = 4991214437,
    source = context().source,
})
assert(mismatch.status == "incompatible")
assert(not mismatch.message:find(store.root, 1, true))
assert(not mismatch.message:find("source-fingerprint", 1, true))

local staleStore, staleFs = newStore(now + 8 * 24 * 60 * 60)
assert(staleStore:beginStaging("job-1", context()))
local staleState = state(now)
local staleChunk = assert(staleStore:writePlanChunk("job-1", 1, {
    jobId = "job-1",
    index = 1,
    records = { { id = "part-1" } },
}))
staleState.plan.chunks = { staleChunk }
attachExecution(staleStore, staleState, "job-1")
assert(staleStore:commitInitial(staleState))
local stale = staleStore:load(context())
assert(stale.status == "quarantined")
assert(stale.reason == "stale")
assert(stale.message == "Checkpoint unavailable; recovery data was quarantined")
assert(staleFs.files[staleStore.root .. "/state.a.json"] == nil)
local quarantinedFiles = staleFs.listFiles(staleStore.root)
assert(#quarantinedFiles > 0, "Fresh quarantine data must remain private and recoverable")
staleStore:prune(now + 16 * 24 * 60 * 60)
assert(
    #staleFs.listFiles(staleStore.root) == 0,
    "Quarantine data must be deleted after its additional seven-day retention"
)

local corruptStore, corruptFs = newStore(now)
corruptFs.files[corruptStore.root .. "/state.a.json"] = "{bad-a"
corruptFs.files[corruptStore.root .. "/state.b.json"] = "{bad-b"
local corrupt = corruptStore:load(context())
assert(corrupt.status == "quarantined")
assert(corrupt.reason == "corrupt")
assert(not corrupt.message:find("{bad", 1, true))

local versionStore = newStore(now)
local versionState = state(now)
assert(versionStore:beginStaging("job-1", context()))
local versionChunk = assert(versionStore:writePlanChunk("job-1", 1, {
    jobId = "job-1",
    index = 1,
    records = { { id = "part-1" } },
}))
versionState.plan.chunks = { versionChunk }
attachExecution(versionStore, versionState, "job-1")
assert(versionStore:commitInitial(versionState))
versionState.schemaVersion = 2
versionStore:_writeVerified(versionStore.stateA, versionState)
local incompatibleVersion = versionStore:load(context())
assert(incompatibleVersion.status == "quarantined")
assert(incompatibleVersion.reason == "version")

local deleteStore, deleteFs = newStore(now)
assert(deleteStore:beginStaging("job-1", context()))
local deleteState = state(now)
local deleteChunk = assert(deleteStore:writePlanChunk("job-1", 1, {
    jobId = "job-1",
    index = 1,
    records = { { id = "part-1" } },
}))
deleteState.plan.chunks = { deleteChunk }
attachExecution(deleteStore, deleteState, "job-1")
assert(deleteStore:commitInitial(deleteState))
assert(deleteStore:deleteJob("job-1"))
assert(#deleteFs.listFiles(deleteStore.root) == 0)

local completionStore, completionFs = newStore(now)
assert(completionStore:beginStaging("job-1", context()))
local completionState = state(now)
local completionChunk = assert(completionStore:writePlanChunk("job-1", 1, {
    jobId = "job-1",
    index = 1,
    records = { { id = "part-1" } },
}))
completionState.plan.chunks = { completionChunk }
attachExecution(completionStore, completionState, "job-1")
assert(completionStore:commitInitial(completionState))
completionStore:advance(function(nextState)
    nextState.authorization.state = "copy_authorized"
    nextState.job.state = "cleanup_pending"
    nextState.progress.confirmedWeight = 1
    nextState.progress.lastConfirmedSequence = 1
end)
completionFs.files[completionStore.root .. "/" .. completionChunk.file] = nil
local completionRecovery = completionStore:load(context())
assert(completionRecovery.status == "ready")
assert(completionRecovery.state.job.state == "cleanup_pending")

local serializedState = fs.files[store.root .. "/state.a.json"]
for _, secretWord in ipairs({ "credential", "cookie", "token", "volt" }) do
    assert(
        not serializedState:lower():find(secretWord, 1, true),
        "Checkpoint state must not retain credentials or unrelated secrets"
    )
end

print("town-checkpoint-contracts-ok")
