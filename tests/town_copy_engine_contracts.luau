local CopyPlan = require("../games/town/CopyPlan")
local CopyEngine = require("../games/town/CopyEngine")

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[key] = deepCopy(child)
    end
    return result
end

local function fakeCheckpoint(events)
    local checkpoint = {
        available = true,
        chunks = {},
        deleted = false,
        state = nil,
    }
    function checkpoint:beginStaging(jobId)
        if self.state then
            return false, "An unfinished Town copy already exists"
        end
        self.stagingJobId = jobId
        table.insert(events, "checkpoint:staging:" .. jobId)
        return true
    end
    function checkpoint:abortStaging(jobId)
        assert(jobId == self.stagingJobId)
        self.stagingJobId = nil
        table.insert(events, "checkpoint:staging_aborted:" .. jobId)
        return true
    end
    function checkpoint:writePlanChunk(jobId, index, chunk)
        table.insert(events, ("checkpoint:chunk:%d"):format(index))
        self.chunks[index] = deepCopy(chunk)
        return {
            byteLength = 100,
            checksum = "chunk-" .. tostring(index),
            file = ("jobs/%s/plan-%05d.json"):format(jobId, index),
            index = index,
            jobId = jobId,
            recordCount = #chunk.records,
        }
    end
    function checkpoint:commitInitial(state)
        self.state = deepCopy(state)
        self.state.generation = 1
        table.insert(events, "checkpoint:awaiting_confirmation")
        return true, deepCopy(self.state)
    end
    function checkpoint:verifyPlan()
        return true
    end
    function checkpoint:advance(mutator)
        local nextState = deepCopy(self.state)
        mutator(nextState)
        nextState.generation += 1
        self.state = nextState
        if nextState.progress and nextState.progress.pendingBatch then
            table.insert(events, "checkpoint:pending:" .. nextState.progress.pendingBatch.id)
        elseif nextState.authorization and nextState.authorization.state == "copy_authorized"
            and (not events[#events] or events[#events] ~= "checkpoint:copy_authorized")
        then
            table.insert(events, "checkpoint:copy_authorized")
        elseif nextState.progress and nextState.progress.lastConfirmedBatchId then
            table.insert(events, "checkpoint:confirmed:" .. nextState.progress.lastConfirmedBatchId)
        end
        return deepCopy(nextState)
    end
    function checkpoint:load()
        if not self.state then
            return { status = "empty" }
        end
        return {
            state = deepCopy(self.state),
            status = "ready",
        }
    end
    function checkpoint:deleteJob(jobId)
        assert(not self.state or jobId == self.state.job.id)
        self.deleted = true
        self.state = nil
        table.insert(events, "checkpoint:deleted")
        return true
    end
    return checkpoint
end

local function sourceFixture(count)
    return {
        context = {
            destination = {
                baselineFingerprint = "destination",
                ownerUserId = 1,
                plotName = "LocalBuildArea",
            },
            gameId = 1718755273,
            localUserId = 1,
            placeId = 4991214437,
            source = {
                fingerprint = "source",
                ownerUserId = 2,
                plotName = "SourceBuildArea",
            },
        },
        iterParts = function(emit)
            for index = 1, count do
                emit({
                    className = "Part",
                    id = ("part-%05d"):format(index),
                    operations = { "resize" },
                    type = "Normal",
                })
            end
        end,
    }
end

local function indexOf(events, target)
    for index, event in ipairs(events) do
        if event == target then
            return index
        end
    end
    return math.huge
end

local events = {}
local remoteCalls = {}
local published = {}
local checkpoint = fakeCheckpoint(events)
local engine = CopyEngine.new({
    applyBatch = function(batch)
        table.insert(events, "remote:" .. batch.id)
        table.insert(remoteCalls, batch.id)
        return true
    end,
    checkpoint = checkpoint,
    generateGuid = function()
        return "job-1"
    end,
    now = function()
        return 100
    end,
    publish = function(state)
        table.insert(published, deepCopy(state))
        table.insert(events, "progress:" .. state.state)
    end,
    reconcileBatch = function()
        return "confirmed"
    end,
    waitForCooling = function()
        table.insert(events, "cooling")
        return true
    end,
})

local summary = assert(engine:preflight({
    batches = {
        { id = "create:000001", operation = "CreatePart", weight = 1 },
        { id = "resize:000002", operation = "SyncResize", weight = 1 },
    },
    saveName = "copy_Source",
    source = sourceFixture(2001),
}))
assert(summary.supported == 2001)
assert(engine.state.job.state == "awaiting_confirmation")
assert(engine.state.authorization.state == "awaiting_confirmation")
assert(#remoteCalls == 0, "Preflight must make zero mutating calls")
assert(published[#published].startAvailable == true)
assert(published[#published].cancelAvailable == true)
assert(published[#published].supported == 2001)
assert(published[#published].context:find("2001 supported", 1, true))
assert(published[#published].context:find("planned calls", 1, true))
assert(published[#published].context:find("plan bytes", 1, true))
assert(published[#published].context:find("ETA uncalibrated", 1, true))

local relaunched = CopyEngine.new({
    checkpoint = checkpoint,
    publish = function(state)
        table.insert(published, deepCopy(state))
    end,
})
local recovery = relaunched:inspectRecovery(sourceFixture(1).context)
assert(recovery.state == "awaiting_confirmation")
assert(recovery.startAvailable == true and recovery.cancelAvailable == true)
assert(#remoteCalls == 0, "Relaunch from awaiting confirmation must make zero mutating calls")

table.insert(events, "user:start_copy")
assert(engine:confirmStart())
assert(#remoteCalls == 2)
assert(indexOf(events, "checkpoint:awaiting_confirmation") < indexOf(events, "user:start_copy"))
assert(indexOf(events, "user:start_copy") < indexOf(events, "checkpoint:copy_authorized"))
assert(indexOf(events, "checkpoint:copy_authorized") < indexOf(events, "checkpoint:pending:create:000001"))
assert(indexOf(events, "checkpoint:pending:create:000001") < indexOf(events, "remote:create:000001"))
assert(indexOf(events, "cooling") < indexOf(events, "remote:create:000001"))
assert(checkpoint.deleted == true, "Completed jobs must delete their checkpoint")
local firstConfirmedView
for _, view in ipairs(published) do
    if view.state == "copying" and view.confirmedProgress == 0.5 then
        firstConfirmedView = view
        break
    end
end
assert(firstConfirmedView and firstConfirmedView.phaseCompleted == 1 and firstConfirmedView.phaseTotal == 1)

local cancelEvents = {}
local cancelCheckpoint = fakeCheckpoint(cancelEvents)
local cancelRemotes = 0
local cancelEngine = CopyEngine.new({
    applyBatch = function()
        cancelRemotes += 1
    end,
    checkpoint = cancelCheckpoint,
    generateGuid = function()
        return "job-cancel"
    end,
    publish = function() end,
})
assert(cancelEngine:preflight({
    batches = {
        { id = "create:000001", operation = "CreatePart", weight = 1 },
    },
    source = sourceFixture(2000),
}))
assert(cancelEngine:requestCancel())
assert(cancelCheckpoint.deleted)
assert(cancelRemotes == 0, "Cancel before Start copy must make zero mutating calls")

local unavailableRemotes = 0
local unavailableEngine = CopyEngine.new({
    applyBatch = function()
        unavailableRemotes += 1
    end,
    checkpoint = {
        available = false,
        publicError = "Persistent recovery is unavailable in this executor",
    },
    publish = function() end,
})
local unavailable, unavailableMessage = unavailableEngine:preflight({
    source = sourceFixture(2001),
})
assert(unavailable == false)
assert(unavailableMessage == "Persistent recovery is unavailable in this executor")
assert(unavailableRemotes == 0)

local stagingEvents = {}
local stagingCheckpoint = fakeCheckpoint(stagingEvents)
local stagingWrites = 0
function stagingCheckpoint:writePlanChunk(jobId, index, chunk)
    stagingWrites += 1
    if stagingWrites == 2 then
        error("private storage full")
    end
    return fakeCheckpoint(stagingEvents).writePlanChunk(self, jobId, index, chunk)
end
local stagingRemotes = 0
local stagingEngine = CopyEngine.new({
    applyBatch = function()
        stagingRemotes += 1
    end,
    checkpoint = stagingCheckpoint,
    generateGuid = function()
        return "job-staging-failure"
    end,
    publish = function() end,
})
local stagingSucceeded, stagingMessage = stagingEngine:preflight({
    batches = {
        { id = "create:000001", operation = "CreatePart", weight = 1 },
    },
    source = sourceFixture(2001),
})
assert(stagingSucceeded == false)
assert(stagingMessage == "Persistent copy plan could not be secured")
assert(stagingCheckpoint.deleted == false)
assert(stagingCheckpoint.stagingJobId == nil)
assert(stagingRemotes == 0, "A partial local staging failure must make zero mutating calls")

local authorizationCrashEvents = {}
local authorizationCrashCheckpoint = fakeCheckpoint(authorizationCrashEvents)
local authorizationCrashRemotes = 0
local authorizationCrash = CopyEngine.new({
    afterAuthorization = function()
        error("simulated crash after authorization")
    end,
    applyBatch = function()
        authorizationCrashRemotes += 1
        return true
    end,
    checkpoint = authorizationCrashCheckpoint,
    generateGuid = function()
        return "job-authorization-crash"
    end,
    publish = function() end,
    reconcileBatch = function()
        return "confirmed"
    end,
})
assert(authorizationCrash:preflight({
    batches = {
        { id = "create:000001", operation = "CreatePart", weight = 1 },
    },
    source = sourceFixture(2001),
}))
local authorizationStartSucceeded = pcall(function()
    authorizationCrash:confirmStart()
end)
assert(not authorizationStartSucceeded)
assert(authorizationCrashRemotes == 0)
assert(authorizationCrashCheckpoint.state.authorization.state == "copy_authorized")
assert(authorizationCrashCheckpoint.state.progress.pendingBatch == nil)

local authorizationResume = CopyEngine.new({
    applyBatch = function()
        authorizationCrashRemotes += 1
        return true
    end,
    checkpoint = authorizationCrashCheckpoint,
    publish = function() end,
    reconcileBatch = function()
        return "confirmed"
    end,
})
local authorizationRecovery = authorizationResume:inspectRecovery(sourceFixture(1).context)
assert(authorizationRecovery.state == "copy_authorized")
assert(authorizationRecovery.resumeAvailable and not authorizationRecovery.startAvailable)
assert(authorizationResume:resume())
assert(authorizationCrashRemotes == 1, "Resume after the pre-first-remote crash must issue one first call")

local remoteCrashEvents = {}
local remoteCrashCheckpoint = fakeCheckpoint(remoteCrashEvents)
local remoteCrashCalls = 0
local crashOnce = true
local remoteCrash = CopyEngine.new({
    afterRemote = function()
        if crashOnce then
            crashOnce = false
            error("simulated crash after remote")
        end
    end,
    applyBatch = function()
        remoteCrashCalls += 1
        return true
    end,
    checkpoint = remoteCrashCheckpoint,
    generateGuid = function()
        return "job-remote-crash"
    end,
    publish = function() end,
    reconcileBatch = function()
        return "confirmed"
    end,
})
assert(remoteCrash:preflight({
    batches = {
        { id = "clone:000001", operation = "Clone", planIds = { "part-1" }, weight = 1 },
    },
    source = sourceFixture(2001),
}))
local remoteStartSucceeded = pcall(function()
    remoteCrash:confirmStart()
end)
assert(not remoteStartSucceeded)
assert(remoteCrashCalls == 1)
assert(remoteCrashCheckpoint.state.progress.pendingBatch.id == "clone:000001")

local remoteResume = CopyEngine.new({
    applyBatch = function()
        remoteCrashCalls += 1
        return true
    end,
    checkpoint = remoteCrashCheckpoint,
    publish = function() end,
    reconcileBatch = function(batch, _, recovering)
        assert(recovering == true)
        assert(batch.id == "clone:000001")
        return "confirmed"
    end,
})
remoteResume:inspectRecovery(sourceFixture(1).context)
assert(remoteResume:resume())
assert(remoteCrashCalls == 1, "A confirmed possibly-applied Clone must be adopted, not replayed")

local saveCrashCheckpoint = fakeCheckpoint({})
local saveCrashCalls = 0
local saveCrash = CopyEngine.new({
    afterRemote = function()
        error("crash after save invoke")
    end,
    applyBatch = function()
        saveCrashCalls += 1
        return true
    end,
    checkpoint = saveCrashCheckpoint,
    generateGuid = function()
        return "job-save-crash"
    end,
    publish = function() end,
})
assert(saveCrash:preflight({
    batches = {
        {
            id = "save:000001",
            operation = "Save",
            priorSaveIdentity = {
                exists = true,
                fingerprint = "before",
                lastEdited = 10,
            },
            saveName = "copy_Source",
        },
    },
    source = sourceFixture(2001),
}))
assert(not pcall(function()
    saveCrash:confirmStart()
end))
assert(saveCrashCheckpoint.state.progress.pendingBatch.priorSaveIdentity.lastEdited == 10)

local saveRecovery = CopyEngine.new({
    applyBatch = function()
        saveCrashCalls += 1
        return true
    end,
    checkpoint = saveCrashCheckpoint,
    publish = function() end,
    reconcileBatch = function(batch, _, recovering)
        assert(recovering and batch.priorSaveIdentity.fingerprint == "before")
        return "ambiguous"
    end,
})
saveRecovery:inspectRecovery(sourceFixture(1).context)
local saveResumed, saveError = saveRecovery:resume()
assert(saveResumed == false and saveError == "Pending terminal batch could not be reconciled safely")
assert(saveCrashCalls == 1, "An ambiguous overwritten save must never be replayed")
assert(saveCrashCheckpoint.state.progress.pendingBatch.priorSaveIdentity.lastEdited == 10)
assert(
    saveCrashCheckpoint.state.job.state == "reconciling",
    "REVIEW-P1-TERMINAL-AMBIGUITY: an ambiguous Save must remain reconcile-only"
)

local partialEvents = {}
local partialCheckpoint = fakeCheckpoint(partialEvents)
local partialCalls = {}
local partialCrash = CopyEngine.new({
    afterRemote = function()
        error("simulated partial remote disconnect")
    end,
    applyBatch = function(batch)
        table.insert(partialCalls, deepCopy(batch.planIds))
        return true
    end,
    checkpoint = partialCheckpoint,
    generateGuid = function()
        return "job-partial"
    end,
    publish = function() end,
})
assert(partialCrash:preflight({
    batches = {
        {
            id = "clone:000001",
            operation = "Clone",
            planIds = { "part-1", "part-2", "part-3" },
            weight = 3,
        },
    },
    source = sourceFixture(2001),
}))
pcall(function()
    partialCrash:confirmStart()
end)
assert(#partialCalls == 1)

local partialResume = CopyEngine.new({
    applyBatch = function(batch)
        table.insert(partialCalls, deepCopy(batch.planIds))
        return true
    end,
    checkpoint = partialCheckpoint,
    publish = function() end,
    reconcileBatch = function(_, _, recovering)
        if recovering then
            return {
                remainder = {
                    id = "clone:000001:remainder",
                    operation = "Clone",
                    planIds = { "part-3" },
                    sequence = 1,
                    weight = 1,
                },
                status = "partially_applied",
            }
        end
        return "confirmed"
    end,
})
partialResume:inspectRecovery(sourceFixture(1).context)
assert(partialResume:resume())
assert(#partialCalls == 2)
assert(#partialCalls[2] == 1 and partialCalls[2][1] == "part-3")

local secondCrashCheckpoint = fakeCheckpoint({})
local secondCrashCalls = 0
local secondCrashInitial = CopyEngine.new({
    afterRemote = function()
        error("crash after partial Clone")
    end,
    applyBatch = function()
        secondCrashCalls += 1
        return true
    end,
    checkpoint = secondCrashCheckpoint,
    generateGuid = function()
        return "job-partial-second-crash"
    end,
    publish = function() end,
})
assert(secondCrashInitial:preflight({
    batches = {
        {
            id = "clone:000001",
            operation = "Clone",
            planIds = { "part-1", "part-2", "part-3" },
            weight = 3,
        },
    },
    source = sourceFixture(2001),
}))
assert(not pcall(function()
    secondCrashInitial:confirmStart()
end))

local crashAfterAdoption = CopyEngine.new({
    afterPartialAdoption = function()
        error("crash after durable prefix adoption")
    end,
    checkpoint = secondCrashCheckpoint,
    publish = function() end,
    reconcileBatch = function()
        return {
            appliedPlanIds = { "part-1", "part-2" },
            remainder = {
                operation = "Clone",
                planIds = { "part-3" },
                weight = 1,
            },
            status = "partially_applied",
        }
    end,
})
crashAfterAdoption:inspectRecovery(sourceFixture(1).context)
assert(not pcall(function()
    crashAfterAdoption:resume()
end))
assert(secondCrashCheckpoint.state.progress.pendingBatch.id == "clone:000001")
assert(secondCrashCheckpoint.state.progress.pendingAdoption.batchId == "clone:000001")
assert(secondCrashCheckpoint.state.progress.pendingAdoption.count == 2)

local afterSecondCrash = CopyEngine.new({
    applyBatch = function(batch)
        secondCrashCalls += 1
        assert(#batch.planIds == 1 and batch.planIds[1] == "part-3")
        return true
    end,
    checkpoint = secondCrashCheckpoint,
    publish = function() end,
    reconcileBatch = function(_, _, recovering)
        if recovering then
            assert(secondCrashCheckpoint.state.progress.pendingAdoption.count == 2)
            return {
                appliedPlanIds = { "part-1", "part-2" },
                remainder = {
                    operation = "Clone",
                    planIds = { "part-3" },
                    weight = 1,
                },
                status = "partially_applied",
            }
        end
        return "confirmed"
    end,
})
afterSecondCrash:inspectRecovery(sourceFixture(1).context)
assert(afterSecondCrash:resume())
assert(secondCrashCalls == 2, "A second crash after prefix adoption must not duplicate Clone outputs")

local adoptionChainCheckpoint = fakeCheckpoint({})
adoptionChainCheckpoint.state = {
    authorization = { state = "copy_authorized" },
    execution = {
        batches = {
            {
                operation = "Clone",
                planIds = { "part-1", "part-2", "part-3" },
            },
        },
    },
    generation = 1,
    job = { id = "job-adoption-chain", state = "paused" },
    plan = { supported = 3, totalWeight = 1 },
    progress = {
        confirmedWeight = 0,
        lastConfirmedSequence = 0,
        pendingBatch = {
            id = "job-adoption-chain:clone:1:ownership",
            nextPending = {
                operation = "Clone",
                planIds = { "part-3" },
                sourceIds = { "part-1" },
            },
            operation = "AdoptOwnership",
            originalOperation = "Clone",
            planIds = { "part-1", "part-2" },
            sequence = 1,
        },
        timing = {},
    },
}
local adoptionChainCalls = 0
local adoptionChain = CopyEngine.new({
    applyBatch = function(batch)
        adoptionChainCalls += 1
        assert(batch.operation == "Clone" and #batch.planIds == 1)
        return true
    end,
    checkpoint = adoptionChainCheckpoint,
    publish = function() end,
    reconcileBatch = function(batch, _, recovering)
        if recovering then
            assert(batch.operation == "AdoptOwnership")
            return "confirmed"
        end
        return "confirmed"
    end,
})
adoptionChain:inspectRecovery(sourceFixture(1).context)
assert(adoptionChain:resume())
assert(
    adoptionChainCalls == 1,
    "REVIEW-P1-ADOPTION-CHAIN: confirmed ownership must continue its durable Clone remainder"
)

local coolingEvents = {}
local coolingCheckpoint = fakeCheckpoint(coolingEvents)
local coolingRemotes = 0
local coolingEngine
coolingEngine = CopyEngine.new({
    applyBatch = function()
        coolingRemotes += 1
        return true
    end,
    checkpoint = coolingCheckpoint,
    generateGuid = function()
        return "job-cooling-cancel"
    end,
    publish = function() end,
    waitForCooling = function()
        coolingEngine:requestCancel()
        return false
    end,
})
assert(coolingEngine:preflight({
    batches = {
        { id = "create:000001", operation = "CreatePart", weight = 1 },
    },
    source = sourceFixture(2001),
}))
assert(coolingEngine:confirmStart())
assert(coolingRemotes == 0)
assert(coolingCheckpoint.state.job.state == "paused")
assert(coolingCheckpoint.state.progress.pendingBatch.id == "create:000001")

local pausedEvents = {}
local pausedCheckpoint = fakeCheckpoint(pausedEvents)
local pausedRemotes = 0
local pausedEngine
pausedEngine = CopyEngine.new({
    afterRemote = function()
        pausedEngine:requestCancel()
    end,
    applyBatch = function()
        pausedRemotes += 1
        return true
    end,
    checkpoint = pausedCheckpoint,
    generateGuid = function()
        return "job-paused"
    end,
    publish = function() end,
    reconcileBatch = function()
        return "confirmed"
    end,
})
assert(pausedEngine:preflight({
    batches = {
        { id = "create:000001", operation = "CreatePart", weight = 1 },
        { id = "resize:000002", operation = "SyncResize", weight = 1 },
    },
    source = sourceFixture(2001),
}))
assert(pausedEngine:confirmStart())
assert(pausedRemotes == 1)
assert(pausedCheckpoint.state.job.state == "paused")
assert(pausedCheckpoint.state.progress.lastConfirmedSequence == 1)

local removed = 0
local discardEngine = CopyEngine.new({
    checkpoint = pausedCheckpoint,
    cleanupBatches = function()
        return {
            { id = "remove:000001", operation = "Remove", weight = 1 },
        }
    end,
    publish = function() end,
    reconcileCleanup = function()
        return "confirmed"
    end,
    removeBatch = function()
        removed += 1
        return true
    end,
})
discardEngine:inspectRecovery(sourceFixture(1).context)
assert(discardEngine:discard())
assert(removed == 1)
assert(pausedCheckpoint.deleted)

local rollbackEvents = {}
local rollbackCheckpoint = fakeCheckpoint(rollbackEvents)
local rollbackEngine
rollbackEngine = CopyEngine.new({
    afterRemote = function()
        rollbackEngine:requestCancel()
    end,
    applyBatch = function()
        return true
    end,
    checkpoint = rollbackCheckpoint,
    generateGuid = function()
        return "job-rollback"
    end,
    publish = function() end,
    reconcileBatch = function()
        return "confirmed"
    end,
})
assert(rollbackEngine:preflight({
    batches = {
        { id = "create:000001", operation = "CreatePart", weight = 1 },
        { id = "resize:000002", operation = "SyncResize", weight = 1 },
    },
    source = sourceFixture(2001),
}))
rollbackEngine:confirmStart()

local cleanupSucceeds = false
local cleanupViews = {}
local rollbackRecovery = CopyEngine.new({
    checkpoint = rollbackCheckpoint,
    cleanupBatches = function()
        return {
            { id = "remove:000001", operation = "Remove", weight = 1 },
        }
    end,
    publish = function(view)
        table.insert(cleanupViews, deepCopy(view))
    end,
    reconcileCleanup = function(_, applied)
        return applied and "confirmed" or "not_applied"
    end,
    removeBatch = function()
        return cleanupSucceeds
    end,
})
rollbackRecovery:inspectRecovery(sourceFixture(1).context)
local discarded, discardError = rollbackRecovery:discard()
assert(discarded == false)
assert(discardError == "Cleanup batch was not confirmed")
assert(rollbackCheckpoint.state.job.state == "rollback_incomplete")
assert(rollbackCheckpoint.deleted == false)
assert(cleanupViews[#cleanupViews].retryCleanupAvailable == true)

cleanupSucceeds = true
assert(rollbackRecovery:retryCleanup())
assert(rollbackCheckpoint.deleted)

local cleanupEffectCheckpoint = fakeCheckpoint({})
cleanupEffectCheckpoint.state = {
    authorization = { state = "copy_authorized" },
    execution = { batches = {} },
    generation = 1,
    job = { id = "cleanup-effect", state = "paused" },
    plan = { supported = 1, totalWeight = 1 },
    progress = {
        confirmedWeight = 1,
        lastConfirmedSequence = 1,
        timing = {},
    },
}
local cleanupEffectCalls = 0
local cleanupEffectApplied = false
local cleanupEffectEngine = CopyEngine.new({
    checkpoint = cleanupEffectCheckpoint,
    nextCleanupBatch = function(state)
        if (state.cleanup.removedCount or 0) == 1 then
            return nil
        end
        return {
            itemCount = 1,
            operation = "Remove",
            planIds = { "part-1" },
        }
    end,
    publish = function() end,
    reconcileCleanup = function(_, _, recovering)
        assert(recovering == true)
        return cleanupEffectApplied and "confirmed" or "ambiguous"
    end,
    removeBatch = function()
        cleanupEffectCalls += 1
        cleanupEffectApplied = true
        error("disconnect after Remove took effect")
    end,
})
cleanupEffectEngine:inspectRecovery(sourceFixture(1).context)
assert(
    cleanupEffectEngine:discard(),
    "REVIEW-P1-CLEANUP-CRASH: an applied Remove must reconcile before any retry"
)
assert(cleanupEffectCalls == 1, "Cleanup reconciliation must prevent a duplicate Remove")

local rawArtifactCheckpoint = fakeCheckpoint({})
rawArtifactCheckpoint.state = {
    authorization = { state = "copy_authorized" },
    execution = { batches = {} },
    generation = 1,
    job = { id = "raw-artifact", state = "paused" },
    plan = { supported = 1, totalWeight = 1 },
    progress = {
        confirmedWeight = 0,
        lastConfirmedSequence = 0,
        pendingBatch = {
            id = "raw-artifact:create:1",
            operation = "CreatePart",
            planIds = { "part-1" },
            sequence = 1,
        },
        timing = {},
    },
}
local rawArtifactRemoves = 0
local rawArtifactEngine = CopyEngine.new({
    checkpoint = rawArtifactCheckpoint,
    nextCleanupBatch = function(state)
        if state.progress.pendingRawCreation and (state.cleanup.removedCount or 0) == 0 then
            assert(
                state.progress.pendingRawCreation.nextPending == nil,
                "REVIEW-P1-RAW-ARTIFACT: unapplied Clone remainder is not a created artifact"
            )
            return {
                clearsPendingRawCreation = true,
                itemCount = 1,
                operation = "Remove",
                planIds = { "part-1" },
            }
        end
        return nil
    end,
    publish = function() end,
    reconcileBatch = function()
        return {
            remainder = {
                nextPending = {
                    operation = "Clone",
                    planIds = { "part-2" },
                },
                operation = "AdoptOwnership",
                planIds = { "part-1" },
            },
            status = "ownership_pending",
        }
    end,
    reconcileCleanup = function()
        return "confirmed"
    end,
    removeBatch = function()
        rawArtifactRemoves += 1
        return true
    end,
})
rawArtifactEngine:inspectRecovery(sourceFixture(1).context)
assert(rawArtifactEngine:discard())
assert(
    rawArtifactRemoves == 1,
    "REVIEW-P1-RAW-ARTIFACT: discard must remove a durably attributed pre-confirmation creation"
)

local cleanupCrashCheckpoint = fakeCheckpoint({})
cleanupCrashCheckpoint.state = {
    authorization = { state = "copy_authorized" },
    execution = { batches = {} },
    generation = 1,
    job = { id = "cleanup-crash", state = "paused" },
    plan = { supported = 2, totalWeight = 1 },
    progress = {
        confirmedWeight = 1,
        lastConfirmedSequence = 1,
        timing = {},
    },
}
local cleanupCrashCalls = {}
local cleanupCrash = CopyEngine.new({
    afterCleanupConfirmation = function()
        error("crash after durable cleanup confirmation")
    end,
    checkpoint = cleanupCrashCheckpoint,
    nextCleanupBatch = function(state)
        assert((state.cleanup.removedCount or 0) == 0)
        return { operation = "Remove", planIds = { "part-1" } }
    end,
    publish = function() end,
    reconcileCleanup = function()
        return "confirmed"
    end,
    removeBatch = function(batch)
        table.insert(cleanupCrashCalls, batch.planIds[1])
        return true
    end,
})
cleanupCrash:inspectRecovery(sourceFixture(1).context)
assert(not pcall(function()
    cleanupCrash:discard()
end))
assert(cleanupCrashCheckpoint.state.job.state == "rollback")
assert(cleanupCrashCheckpoint.state.cleanup.removedCount == 1)
assert(cleanupCrashCheckpoint.state.cleanup.pendingBatch == nil)

local cleanupResume = CopyEngine.new({
    checkpoint = cleanupCrashCheckpoint,
    nextCleanupBatch = function(state)
        if state.cleanup.removedCount >= 2 then
            return nil
        end
        assert(state.cleanup.removedCount == 1)
        return { operation = "Remove", planIds = { "part-2" } }
    end,
    publish = function() end,
    reconcileCleanup = function()
        return "confirmed"
    end,
    removeBatch = function(batch)
        table.insert(cleanupCrashCalls, batch.planIds[1])
        return true
    end,
})
cleanupResume:inspectRecovery(sourceFixture(1).context)
assert(cleanupResume:retryCleanup())
assert(#cleanupCrashCalls == 2)
assert(cleanupCrashCalls[1] == "part-1" and cleanupCrashCalls[2] == "part-2")

local unloadEvents = {}
local unloadCheckpoint = fakeCheckpoint(unloadEvents)
local unloadRemotes = 0
local unloadEngine
unloadEngine = CopyEngine.new({
    applyBatch = function()
        unloadRemotes += 1
        return true
    end,
    beforeRemote = function()
        unloadEngine:stop()
    end,
    checkpoint = unloadCheckpoint,
    generateGuid = function()
        return "job-unload"
    end,
    publish = function() end,
})
assert(unloadEngine:preflight({
    batches = {
        { id = "create:000001", operation = "CreatePart", weight = 1 },
    },
    source = sourceFixture(2001),
}))
assert(unloadEngine:confirmStart())
assert(unloadRemotes == 0, "Unload before an invoke must not begin a new remote")
assert(unloadCheckpoint.state.job.state == "paused")

local awaitingUnloadEvents = {}
local awaitingUnloadCheckpoint = fakeCheckpoint(awaitingUnloadEvents)
local awaitingUnload = CopyEngine.new({
    checkpoint = awaitingUnloadCheckpoint,
    generateGuid = function()
        return "job-awaiting-unload"
    end,
    publish = function() end,
})
assert(awaitingUnload:preflight({
    batches = {},
    source = sourceFixture(2001),
}))
awaitingUnload:stop()
assert(awaitingUnloadCheckpoint.state.job.state == "awaiting_confirmation")
assert(awaitingUnloadCheckpoint.deleted == false)

local conflictEvents = {}
local conflictCheckpoint = fakeCheckpoint(conflictEvents)
conflictCheckpoint.state = {
    job = { id = "existing", state = "paused" },
}
local conflictChunks = 0
function conflictCheckpoint:beginStaging()
    return false, "An unfinished Town copy already exists"
end
function conflictCheckpoint:writePlanChunk()
    conflictChunks += 1
end
local conflictEngine = CopyEngine.new({
    checkpoint = conflictCheckpoint,
    generateGuid = function()
        return "new-job"
    end,
    publish = function() end,
})
local conflictStarted, conflictError = conflictEngine:preflight({
    source = sourceFixture(2001),
})
assert(conflictStarted == false and conflictError == "An unfinished Town copy already exists")
assert(conflictChunks == 0 and conflictCheckpoint.state.job.id == "existing")

local recoveryStates = {
    rollback = { retryCleanupAvailable = true, resumeAvailable = false },
    rollback_incomplete = { retryCleanupAvailable = true, resumeAvailable = false },
    cleanup_pending = { localCleanupAvailable = true, resumeAvailable = false },
    completed = { localCleanupAvailable = true, resumeAvailable = false },
}
for savedState, expected in pairs(recoveryStates) do
    local recoveryCheckpoint = fakeCheckpoint({})
    recoveryCheckpoint.state = {
        authorization = { state = "copy_authorized" },
        execution = { batches = {} },
        generation = 1,
        job = { id = "recovery-" .. savedState, state = savedState },
        plan = { supported = 1, totalWeight = 1 },
        progress = {
            confirmedWeight = 1,
            lastConfirmedSequence = 1,
            timing = {},
        },
    }
    local stateEngine = CopyEngine.new({
        checkpoint = recoveryCheckpoint,
        publish = function() end,
    })
    local stateView = stateEngine:inspectRecovery(sourceFixture(1).context)
    assert(stateView.state == savedState, "Recovery state must be preserved: " .. savedState)
    assert((stateView.resumeAvailable == true) == (expected.resumeAvailable == true))
    assert((stateView.retryCleanupAvailable == true) == (expected.retryCleanupAvailable == true))
    assert((stateView.localCleanupAvailable == true) == (expected.localCleanupAvailable == true))
    assert(not pcall(function()
        stateEngine:resume()
    end), "Non-forward recovery states must not resume: " .. savedState)
end

local failedRemoteCheckpoint = fakeCheckpoint({})
local failedRemoteEngine = CopyEngine.new({
    applyBatch = function()
        error("C:\\executor\\private\\source.lua: remote exploded")
    end,
    checkpoint = failedRemoteCheckpoint,
    generateGuid = function()
        return "job-remote-error"
    end,
    publish = function() end,
})
assert(failedRemoteEngine:preflight({
    batches = {
        { id = "create:000001", operation = "CreatePart", planIds = { "part-1" }, weight = 1 },
    },
    source = sourceFixture(2001),
}))
local remoteResult, remoteError = failedRemoteEngine:confirmStart()
assert(remoteResult == false and remoteError == "Town copy remote failed")
assert(failedRemoteCheckpoint.state.job.state == "paused")
assert(failedRemoteCheckpoint.state.progress.pendingBatch.id == "create:000001")
assert(failedRemoteCheckpoint.state.job.error == "Town copy remote failed")
assert(not failedRemoteCheckpoint.state.job.error:find("executor", 1, true))

local cleanupStopCheckpoint = fakeCheckpoint({})
cleanupStopCheckpoint.state = {
    authorization = { state = "copy_authorized" },
    cleanup = { lastConfirmedSequence = 0 },
    execution = { batches = {} },
    generation = 1,
    job = { id = "cleanup-stop", state = "rollback_incomplete" },
    plan = { supported = 1, totalWeight = 1 },
    progress = {
        confirmedWeight = 1,
        confirmedCreatedIds = { "part-1" },
        lastConfirmedSequence = 1,
        timing = {},
    },
}
local cleanupStopCalls = 0
local cleanupStopEngine
cleanupStopEngine = CopyEngine.new({
    checkpoint = cleanupStopCheckpoint,
    cleanupBatches = function()
        return {
            { id = "remove:000001", operation = "Remove", planIds = { "part-1" } },
        }
    end,
    publish = function() end,
    reconcileCleanup = function()
        return "confirmed"
    end,
    removeBatch = function()
        cleanupStopCalls += 1
        return true
    end,
    waitForCooling = function(cancelled)
        cleanupStopEngine:stop()
        assert(cancelled(), "Cleanup cooling must observe unload/cancel")
        return false
    end,
})
cleanupStopEngine:inspectRecovery(sourceFixture(1).context)
local cleanupStopped = cleanupStopEngine:retryCleanup()
assert(cleanupStopped == false)
assert(cleanupStopCalls == 0, "Unload during cleanup cooling must prevent a new Remove")
assert(cleanupStopCheckpoint.state.job.state == "rollback_incomplete")

print("town-copy-engine-contracts-ok")
