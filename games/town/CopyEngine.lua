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

local CopyPlan = importDependency("games/town/CopyPlan", "./CopyPlan")

local CopyEngine = {}
CopyEngine.__index = CopyEngine

local FORWARD_RESUME_STATES = {
    copy_authorized = true,
    copying = true,
    paused = true,
    reconciling = true,
    resuming = true,
}
local TERMINAL_OPERATIONS = {
    Save = true,
    Wire = true,
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

local function totalWeight(batches)
    local total = 0
    for _, batch in ipairs(batches or {}) do
        total += batch.weight or 1
    end
    return total
end

local function appliedPrefix(batch, remainder)
    local remaining = {}
    for _, id in ipairs(remainder and remainder.planIds or {}) do
        remaining[id] = true
    end
    local applied = {}
    for _, id in ipairs(batch.planIds or {}) do
        if not remaining[id] then
            table.insert(applied, id)
        end
    end
    return applied
end

function CopyEngine.new(context)
    context = context or {}
    return setmetatable({
        afterAuthorization = context.afterAuthorization,
        afterCleanupConfirmation = context.afterCleanupConfirmation,
        afterPartialAdoption = context.afterPartialAdoption,
        afterReplacement = context.afterReplacement,
        afterRemote = context.afterRemote,
        applyBatch = context.applyBatch,
        beforeRemote = context.beforeRemote,
        cancelRequested = false,
        checkpoint = context.checkpoint,
        clock = context.clock or os.clock,
        captureError = context.captureError,
        generateGuid = context.generateGuid or function()
            return ("%d-%d"):format(os.time(), math.random(1, 1000000000))
        end,
        now = context.now or os.time,
        publish = context.publish or function() end,
        reconcileBatch = context.reconcileBatch,
        reconcileCleanup = context.reconcileCleanup,
        releaseBatchState = context.releaseBatchState,
        removeBatch = context.removeBatch,
        nextCleanupBatch = context.nextCleanupBatch or context.cleanupBatches,
        state = nil,
        executionCache = nil,
        stopped = false,
        validateContext = context.validateContext,
        waitForCooling = context.waitForCooling or function()
            return true
        end,
    }, CopyEngine)
end

function CopyEngine:_batchCount()
    local execution = self.state and self.state.execution or {}
    return execution.batchCount or #(execution.batches or {})
end

function CopyEngine:_batchAt(sequence)
    local execution = self.state and self.state.execution or {}
    if execution.batches then
        return execution.batches[sequence]
    end
    local offset = 0
    for _, metadata in ipairs(execution.chunks or {}) do
        local final = offset + metadata.recordCount
        if sequence <= final then
            if not self.executionCache or self.executionCache.index ~= metadata.index then
                self.executionCache = self.checkpoint:readJobChunk(
                    self.state.job.id,
                    "execution",
                    metadata
                )
            end
            return self.executionCache.records[sequence - offset]
        end
        offset = final
    end
    return nil
end

function CopyEngine:getBatch(sequence)
    local batch = self:_batchAt(sequence)
    return batch and copy(batch) or nil
end

function CopyEngine:_view(overrides)
    local state = self.state or {}
    local job = state.job or {}
    local progress = state.progress or {}
    local plan = state.plan or {}
    local jobState = overrides and overrides.state or job.state or "idle"
    local phase = overrides and overrides.phase or jobState
    local execution = state.execution or {}
    local phaseCompleted = progress.phaseConfirmed
            and progress.phaseConfirmed[phase]
        or 0
    local phaseTotal = execution.phaseCounts and execution.phaseCounts[phase] or 0
    local estimatedRemaining = 0
    local estimateKnown = false
    for operation, count in pairs(progress.remainingOperationCounts or {}) do
        local timing = progress.timing and progress.timing[operation]
        if timing and timing.ewma then
            estimatedRemaining += timing.ewma * count
            estimateKnown = true
        end
    end
    local view = {
        active = jobState == "copying"
            or jobState == "copy_authorized"
            or jobState == "reconciling"
            or jobState == "resuming"
            or jobState == "rollback",
        cancelAvailable = jobState == "awaiting_confirmation"
            or (jobState == "copying" and progress.terminalStarted ~= true),
        confirmedProgress = plan.totalWeight and plan.totalWeight > 0
                and (progress.confirmedWeight or 0) / plan.totalWeight
            or 0,
        context = overrides and overrides.context or nil,
        discardAvailable = jobState == "paused",
        error = overrides and overrides.error or nil,
        etaRange = estimateKnown and {
            maximum = math.ceil(estimatedRemaining * 1.25),
            minimum = math.max(0, math.floor(estimatedRemaining * 0.8)),
        } or nil,
        phase = phase,
        phaseCompleted = phaseCompleted,
        phaseTotal = phaseTotal,
        baseParts = plan.baseParts,
        markerBearing = plan.markerBearing,
        planBytes = plan.bytes,
        possiblyAppliedBatch = progress.pendingBatch and progress.pendingBatch.id or nil,
        localCleanupAvailable = jobState == "cleanup_pending",
        resumeAvailable = FORWARD_RESUME_STATES[jobState] == true,
        retryCleanupAvailable = jobState == "rollback"
            or jobState == "rollback_incomplete",
        startAvailable = jobState == "awaiting_confirmation",
        state = jobState,
        supported = plan.supported,
        totalDescendants = plan.totalDescendants,
        unsupported = plan.unsupported,
        work = copy(plan.work),
    }
    if overrides then
        for key, value in pairs(overrides) do
            view[key] = value
        end
    end
    return view
end

function CopyEngine:_publish(overrides)
    local view = self:_view(overrides)
    self.publish(view)
    return view
end

function CopyEngine:preflight(request)
    request = request or {}
    if not self.checkpoint or self.checkpoint.available ~= true then
        local message = self.checkpoint and self.checkpoint.publicError
            or "Persistent recovery is unavailable in this executor"
        self:_publish({
            error = message,
            phase = "Copy blocked",
            state = "error",
        })
        return false, message
    end
    assert(request.source, "Copy preflight requires a source")

    local jobId = self.generateGuid()
    local mayStage, stagingMessage = self.checkpoint:beginStaging(jobId, request.source.context)
    if not mayStage then
        local message = stagingMessage or "Persistent copy plan could not be secured"
        self:_publish({
            error = message,
            phase = "Copy blocked",
            state = "error",
        })
        return false, message
    end
    local chunkMetadata = {}
    local compiled, plan = pcall(CopyPlan.compile, request.source, {
        cloneRequestSize = request.cloneRequestSize,
        onChunk = function(chunk)
            table.insert(
                chunkMetadata,
                self.checkpoint:writePlanChunk(jobId, chunk.index, {
                    index = chunk.index,
                    jobId = jobId,
                    records = chunk.records,
                })
            )
        end,
        preferredBatchSize = request.preferredBatchSize,
    })
    if not compiled then
        pcall(function()
            self.checkpoint:abortStaging(jobId)
        end)
        local message = "Persistent copy plan could not be secured"
        self:_publish({
            error = message,
            phase = "Copy blocked",
            state = "error",
        })
        return false, message
    end
    local batches = copy(request.batches or {})
    local operationCounts = {}
    local phaseCounts = {}
    for _, batch in ipairs(batches) do
        local operation = batch.operation or "unknown"
        local phase = batch.phase or operation
        operationCounts[operation] = (operationCounts[operation] or 0) + 1
        phaseCounts[phase] = (phaseCounts[phase] or 0) + 1
    end
    local execution = {
        batchCount = #batches,
        batches = batches,
        operationCounts = operationCounts,
        phaseCounts = phaseCounts,
    }
    local weight = totalWeight(batches)
    if request.compileExecution then
        local executionCompiled, compiledExecution = pcall(
            request.compileExecution,
            jobId,
            copy(chunkMetadata),
            copy(plan)
        )
        if not executionCompiled
            or type(compiledExecution) ~= "table"
            or type(compiledExecution.chunks) ~= "table"
            or not compiledExecution.batchCount
        then
            self.checkpoint:abortStaging(jobId)
            local message = "Persistent execution plan could not be secured"
            self:_publish({
                error = message,
                phase = "Copy blocked",
                state = "error",
            })
            return false, message
        end
        execution = compiledExecution
        weight = compiledExecution.totalWeight or compiledExecution.batchCount
        plan.work.remoteCalls = compiledExecution.batchCount
        plan.work.operationCalls = copy(compiledExecution.operationCounts or {})
    end
    local planBytes = 0
    for _, metadata in ipairs(chunkMetadata) do
        planBytes += metadata.bytes or 0
    end
    local now = self.now()
    local persistedContext = copy(plan.context)
    persistedContext.source = persistedContext.source or {}
    persistedContext.source.fingerprint =
        persistedContext.source.fingerprint or plan.fingerprint
    local initial = {
        adapterId = "town",
        authorization = {
            state = "awaiting_confirmation",
        },
        context = persistedContext,
        execution = execution,
        generation = 1,
        job = {
            createdAt = now,
            id = jobId,
            lastUpdatedAt = now,
            originJobId = request.originJobId or "",
            state = "awaiting_confirmation",
        },
        plan = {
            baseParts = plan.baseParts,
            bytes = planBytes,
            chunkCount = #chunkMetadata,
            chunks = chunkMetadata,
            fingerprint = plan.fingerprint,
            groups = plan.groups,
            markerBearing = plan.markerBearing,
            supported = plan.supported,
            totalDescendants = plan.totalDescendants,
            totalWeight = weight,
            unsupported = plan.unsupported,
            work = plan.work,
        },
        planVersion = 1,
        progress = {
            confirmedWeight = 0,
            lastConfirmedSequence = 0,
            phaseConfirmed = {},
            remainingOperationCounts = copy(execution.operationCounts or {}),
            timing = {},
        },
        request = {
            copyWiring = request.copyWiring == true,
            saveName = request.saveName or "",
        },
        schemaVersion = 1,
    }

    local committed, stateOrMessage = self.checkpoint:commitInitial(initial)
    local verified = committed
        and self.checkpoint:verifyPlan(jobId, chunkMetadata, plan.supported)
    if not committed or not verified then
        if committed then
            self.checkpoint:deleteJob(jobId)
        else
            self.checkpoint:abortStaging(jobId)
        end
        local message = type(stateOrMessage) == "string"
                and stateOrMessage
            or "Persistent copy plan verification failed"
        self:_publish({
            error = message,
            phase = "Copy blocked",
            state = "error",
        })
        return false, message
    end
    self.state = stateOrMessage
    local confidence = request.estimateConfidence or "uncalibrated"
    local eta = request.etaRange
        or (confidence == "uncalibrated" and "ETA uncalibrated")
        or "ETA unavailable"
    return self:_publish({
        cancelAvailable = true,
        confidence = confidence,
        context = ("%d supported · %d unsupported · %d planned calls · %d plan bytes · %s"):format(
            plan.supported,
            plan.unsupported,
            plan.work.remoteCalls,
            planBytes,
            eta
        ),
        phase = "Plan secured",
        startAvailable = true,
        state = "awaiting_confirmation",
    })
end

function CopyEngine:_pause(phase)
    if not self.state or not self.checkpoint or not self.checkpoint.available then
        return false
    end
    self.state = self.checkpoint:advance(function(state)
        state.job.state = "paused"
    end)
    self:_publish({
        context = phase or "Confirmed work is safe to resume",
        phase = "Copy paused",
        state = "paused",
    })
    return true
end

function CopyEngine:_terminalPending()
    local progress = self.state and self.state.progress or {}
    local pending = progress.pendingBatch
    return progress.terminalStarted == true
        or (pending and TERMINAL_OPERATIONS[pending.operation] == true)
end

function CopyEngine:_durableError(message)
    local terminal = self:_terminalPending()
    self.state = self.checkpoint:advance(function(state)
        state.job.error = message
        state.job.state = terminal and "reconciling" or "paused"
    end)
    self:_publish({
        context = terminal
                and "Irreversible terminal work will be reconciled before any retry"
            or "Confirmed work and the pending intent remain safe for recovery",
        error = message,
        discardAvailable = false,
        phase = terminal and "Recovery required" or "Copy paused",
        state = terminal and "reconciling" or "paused",
    })
    return false, message
end

function CopyEngine:_confirmBatch(batch, sequence, duration)
    self.state = self.checkpoint:advance(function(state)
        state.job.state = "copying"
        state.progress.confirmedWeight += batch.confirmWeight or batch.weight or 1
        state.progress.lastConfirmedBatchId = batch.id
        state.progress.lastConfirmedSequence = sequence
        state.progress.pendingBatch = nil
        state.progress.pendingAdoption = nil
        state.progress.phaseConfirmed = state.progress.phaseConfirmed or {}
        local phase = batch.phase or batch.operation
        state.progress.phaseConfirmed[phase] =
            (state.progress.phaseConfirmed[phase] or 0) + 1
        state.progress.remainingOperationCounts =
            state.progress.remainingOperationCounts or {}
        local operation = batch.originalOperation or batch.operation
        state.progress.remainingOperationCounts[operation] = math.max(
            0,
            (state.progress.remainingOperationCounts[operation] or 1) - 1
        )
        if duration then
            operation = operation or "unknown"
            local timing = state.progress.timing[operation] or {
                count = 0,
                samples = {},
            }
            timing.count += 1
            timing.ewma = timing.ewma and (timing.ewma * 0.8 + duration * 0.2) or duration
            table.insert(timing.samples, duration)
            if #timing.samples > 20 then
                table.remove(timing.samples, 1)
            end
            local ordered = copy(timing.samples)
            table.sort(ordered)
            timing.p90 = ordered[math.max(1, math.ceil(#ordered * 0.9))]
            state.progress.timing[operation] = timing
        end
    end)
    local estimated = self:_view().etaRange
    local etaText = estimated
            and (" · ETA %d-%d sec"):format(estimated.minimum, estimated.maximum)
        or ""
    self:_publish({
        context = ("Batch %d/%d%s"):format(
            sequence,
            self:_batchCount(),
            etaText
        ),
        phase = batch.phase or batch.operation or "Copying",
        state = "copying",
    })
end

function CopyEngine:_reconcile(batch, applied, recovering)
    local succeeded, result = pcall(function()
        return self.reconcileBatch
                and self.reconcileBatch(batch, applied, recovering == true)
            or (applied == true and "confirmed" or "not_applied")
    end)
    if not succeeded then
        return "ambiguous"
    end
    if type(result) == "table" then
        return result.status, result.remainder, result.appliedPlanIds
    end
    return result
end

function CopyEngine:_reconcileCleanup(batch, applied, recovering)
    local succeeded, result = pcall(function()
        return self.reconcileCleanup
                and self.reconcileCleanup(batch, applied, recovering == true)
            or (applied ~= false and "confirmed" or "not_applied")
    end)
    if not succeeded then
        return "ambiguous"
    end
    return result
end

function CopyEngine:_persistPartial(batch, remainder, sequence, appliedPlanIds)
    local adopted = appliedPlanIds or appliedPrefix(batch, remainder)
    assert(#adopted > 0, "Partial reconciliation did not identify an applied prefix")
    self.state = self.checkpoint:advance(function(state)
        state.progress.pendingAdoption = {
            batchId = batch.id,
            count = #adopted,
            planIds = copy(adopted),
            sequence = sequence,
        }
    end)
    if self.afterPartialAdoption then
        self.afterPartialAdoption(copy(self.state.progress.pendingAdoption))
    end
    remainder.id = remainder.id or (tostring(batch.id) .. ":remainder")
    remainder.sequence = sequence
    remainder.confirmWeight = batch.confirmWeight or batch.weight or 1
    self.state = self.checkpoint:advance(function(state)
        state.progress.pendingBatch = copy(remainder)
        state.progress.pendingAdoption = nil
    end)
end

function CopyEngine:_persistReplacement(batch, replacement, sequence)
    replacement.id = replacement.id or (tostring(batch.id) .. ":ownership")
    replacement.sequence = sequence
    replacement.confirmWeight = batch.confirmWeight or batch.weight or 1
    replacement.originalOperation = batch.originalOperation or batch.operation
    self.state = self.checkpoint:advance(function(state)
        state.progress.pendingBatch = copy(replacement)
        state.progress.pendingAdoption = nil
    end)
    if self.afterReplacement then
        self.afterReplacement(copy(self.state.progress.pendingBatch))
    end
end

function CopyEngine:_applyPending(batch, sequence)
    local terminal = TERMINAL_OPERATIONS[batch.operation] == true
    if self.validateContext then
        local valid, message = self.validateContext(copy(self.state), copy(batch))
        if valid ~= true then
            return self:_durableError(message or "Town destination context changed")
        end
    end
    if not self.waitForCooling(function()
        return (self.cancelRequested and not terminal) or self.stopped
    end) then
        if terminal then
            return self:_durableError("Terminal Town work stopped before reconciliation")
        end
        return self:_pause("Stopped while waiting for Town cooling")
    end
    if (self.cancelRequested and not terminal) or self.stopped then
        if terminal then
            return self:_durableError("Terminal Town work stopped before reconciliation")
        end
        return self:_pause("Stopped before the pending remote")
    end
    if self.beforeRemote then
        local scheduled = pcall(self.beforeRemote, copy(batch))
        if not scheduled then
            return self:_durableError("Town command scheduling failed")
        end
    end
    if (self.cancelRequested and not terminal) or self.stopped then
        if terminal then
            return self:_durableError("Terminal Town work stopped before reconciliation")
        end
        return self:_pause("Stopped before the pending remote")
    end

    assert(type(self.applyBatch) == "function", "CopyEngine requires applyBatch for mutation")
    local startedAt = self.clock()
    local succeeded, applied = pcall(self.applyBatch, batch)
    if not succeeded and self.captureError then
        self.captureError(tostring(applied))
    end
    local duration = math.max(0, self.clock() - startedAt)
    if succeeded and self.afterRemote then
        self.afterRemote(copy(batch), applied)
    end
    local reconciliation, remainder, appliedPlanIds = self:_reconcile(
        batch,
        succeeded and applied or nil,
        not succeeded
    )
    local function release()
        if self.releaseBatchState then
            self.releaseBatchState()
        end
    end
    if reconciliation == "confirmed" then
        if batch.nextPending then
            release()
            self:_persistReplacement(batch, batch.nextPending, sequence)
            return self:_applyPending(batch.nextPending, sequence)
        end
        release()
        self:_confirmBatch(batch, sequence, duration)
        return true
    elseif reconciliation == "ownership_pending" and type(remainder) == "table" then
        release()
        self:_persistReplacement(batch, remainder, sequence)
        return self:_applyPending(remainder, sequence)
    elseif reconciliation == "partially_applied" and type(remainder) == "table" then
        release()
        self:_persistPartial(batch, remainder, sequence, appliedPlanIds)
        return self:_applyPending(remainder, sequence)
    elseif reconciliation == "not_applied" then
        release()
        return self:_durableError(
            succeeded and "Town copy batch was not confirmed" or "Town copy remote failed"
        )
    end
    release()
    return self:_durableError("Town copy state is ambiguous; no remote was replayed")
end

function CopyEngine:_run()
    local startSequence = (self.state.progress.lastConfirmedSequence or 0) + 1
    for sequence = startSequence, self:_batchCount() do
        local batch = copy(self:_batchAt(sequence))
        local phaseId = tostring(batch.phase or batch.operation or "batch")
            :lower()
            :gsub("[^%w]+", "_")
            :gsub("^_+", "")
            :gsub("_+$", "")
        batch.id = batch.id
            or ("%s:%s:%06d"):format(self.state.job.id, phaseId, sequence)
        batch.sequence = sequence

        if self.cancelRequested or self.stopped then
            return self:_pause("Stopped before the next remote")
        end

        self.state = self.checkpoint:advance(function(state)
            state.job.state = "copying"
            state.progress.pendingBatch = copy(batch)
            if TERMINAL_OPERATIONS[batch.operation] then
                state.progress.terminalStarted = true
            end
        end)

        local continued, message = self:_applyPending(batch, sequence)
        if not continued then
            return false, message
        end

        if (self.cancelRequested or self.stopped)
            and not self.state.progress.terminalStarted
        then
            return self:_pause("Stopped after confirming the current batch")
        end
    end

    self.state = self.checkpoint:advance(function(state)
        state.job.state = "completed"
    end)
    self.state = self.checkpoint:advance(function(state)
        state.job.state = "cleanup_pending"
    end)
    local deleted, deleteError = self.checkpoint:deleteJob(self.state.job.id)
    if not deleted then
        self:_publish({
            context = deleteError,
            phase = "Copy complete; local recovery cleanup pending",
            state = "cleanup_pending",
        })
        return false, deleteError
    end
    local supported = self.state.plan.supported
    self.state = nil
    self.executionCache = nil
    self:_publish({
        confirmedProgress = 1,
        context = ("%d supported parts confirmed"):format(supported),
        localCleanupAvailable = false,
        phase = "Copy complete",
        state = "completed",
    })
    return true
end

function CopyEngine:resume()
    assert(self.state, "No Town checkpoint is loaded")
    assert(
        FORWARD_RESUME_STATES[self.state.job.state] == true,
        "Town checkpoint is not eligible for forward resume"
    )
    self.cancelRequested = false
    self.stopped = false
    self.state = self.checkpoint:advance(function(state)
        state.job.state = "resuming"
    end)
    self:_publish({
        context = "Checking the last durable batch",
        phase = "Resuming copy",
        state = "resuming",
    })

    local pending = self.state.progress.pendingBatch
    if pending then
        self:_publish({
            context = pending.id,
            phase = "Checking previous work",
            state = "reconciling",
        })
        local reconciliation, remainder, appliedPlanIds = self:_reconcile(pending, nil, true)
        if reconciliation == "confirmed" then
            if pending.nextPending then
                self:_persistReplacement(pending, pending.nextPending, pending.sequence)
                local continued, message = self:_applyPending(
                    self.state.progress.pendingBatch,
                    pending.sequence
                )
                if not continued then
                    return false, message
                end
            else
                self:_confirmBatch(pending, pending.sequence)
            end
        elseif reconciliation == "not_applied" then
            local continued, message = self:_applyPending(pending, pending.sequence)
            if not continued then
                return false, message
            end
        elseif reconciliation == "partially_applied" and type(remainder) == "table" then
            self:_persistPartial(pending, remainder, pending.sequence, appliedPlanIds)
            local continued, message = self:_applyPending(remainder, pending.sequence)
            if not continued then
                return false, message
            end
        elseif reconciliation == "ownership_pending" and type(remainder) == "table" then
            self:_persistReplacement(pending, remainder, pending.sequence)
            local continued, message = self:_applyPending(remainder, pending.sequence)
            if not continued then
                return false, message
            end
        else
            if self:_terminalPending() then
                return self:_durableError("Pending terminal batch could not be reconciled safely")
            end
            self.state = self.checkpoint:advance(function(state)
                state.job.state = "paused"
                state.job.error = "Pending batch could not be reconciled safely"
            end)
            self:_publish({
                context = "Destination state is ambiguous; no remote was replayed",
                error = "Pending batch could not be reconciled safely",
                phase = "Recovery required",
                state = "paused",
            })
            return false, "Pending batch could not be reconciled safely"
        end
    end
    return self:_run()
end

function CopyEngine:confirmStart()
    assert(self.state and self.state.job.state == "awaiting_confirmation", "Copy is not awaiting confirmation")
    self.state = self.checkpoint:advance(function(state)
        state.authorization.confirmedAt = self.now()
        state.authorization.state = "copy_authorized"
        state.job.state = "copy_authorized"
    end)
    self:_publish({
        cancelAvailable = false,
        context = "Start confirmed; waiting for the first safe batch",
        phase = "Starting copy",
        startAvailable = false,
        state = "copy_authorized",
    })
    if self.afterAuthorization then
        self.afterAuthorization(copy(self.state))
    end
    return self:_run()
end

function CopyEngine:inspectRecovery(liveContext)
    if not self.checkpoint or self.checkpoint.available ~= true then
        return self:_publish({
            active = false,
            error = self.checkpoint and self.checkpoint.publicError,
            phase = "Copy blocked",
            state = "error",
        })
    end
    local loaded = self.checkpoint:load(liveContext)
    if loaded.status ~= "ready" then
        return self:_publish({
            active = false,
            context = loaded.message,
            error = loaded.status ~= "empty" and loaded.message or nil,
            phase = loaded.status == "empty" and "Ready" or "Copy blocked",
            state = loaded.status == "empty" and "idle" or "error",
        })
    end
    self.state = loaded.state
    local savedState = self.state.job.state
    if savedState == "awaiting_confirmation" then
        return self:_publish({
            active = false,
            cancelAvailable = true,
            context = "Verified plan is waiting for Start copy",
            phase = "Plan secured",
            startAvailable = true,
            state = "awaiting_confirmation",
        })
    end
    if savedState == "rollback" or savedState == "rollback_incomplete" then
        return self:_publish({
            active = false,
            context = "Plan-owned cleanup can be retried",
            discardAvailable = false,
            phase = savedState == "rollback" and "Cleaning copied parts" or "Recovery required",
            resumeAvailable = false,
            retryCleanupAvailable = true,
            state = savedState,
        })
    end
    if savedState == "completed" or savedState == "cleanup_pending" then
        return self:_publish({
            active = false,
            context = "The finished build is preserved; only local recovery data needs cleanup",
            discardAvailable = false,
            localCleanupAvailable = true,
            phase = "Copy complete; local recovery cleanup pending",
            resumeAvailable = false,
            state = savedState,
        })
    end
    if not FORWARD_RESUME_STATES[savedState] then
        return self:_publish({
            active = false,
            error = "Town recovery state is not eligible for resume",
            phase = "Recovery required",
            resumeAvailable = false,
            state = savedState,
        })
    end
    return self:_publish({
        active = false,
        context = "A compatible authorized copy can be resumed or discarded",
        phase = "Copy paused",
        state = savedState,
    })
end

function CopyEngine:requestCancel()
    if not self.state then
        return false
    end
    if self.state.job.state == "awaiting_confirmation" then
        local deleted, message = self.checkpoint:deleteJob(self.state.job.id)
        if not deleted then
            return false, message
        end
        self.state = nil
        self:_publish({
            phase = "Ready",
            state = "idle",
        })
        return true
    end
    if self:_terminalPending() then
        self:_publish({
            cancelAvailable = false,
            context = "Terminal save or wiring work must be reconciled before another action",
            discardAvailable = false,
            phase = "Recovery required",
            state = self.state.job.state,
        })
        return false
    end
    self.cancelRequested = true
    self:_publish({
        context = "Finishing the current batch safely",
        phase = "Cancel requested",
        state = "cancel_requested",
    })
    return true
end

function CopyEngine:_rollbackIncomplete(message)
    self.state = self.checkpoint:advance(function(state)
        state.cleanup = state.cleanup or {}
        state.job.state = "rollback_incomplete"
        state.job.error = message
    end)
    self:_publish({
        context = message,
        error = message,
        phase = "Recovery required",
        retryCleanupAvailable = true,
        state = "rollback_incomplete",
    })
    return false, message
end

function CopyEngine:discard()
    assert(self.state, "No Town checkpoint is loaded")
    assert(
        self.state.job.state ~= "completed" and self.state.job.state ~= "cleanup_pending",
        "Completed Town copies allow local checkpoint cleanup only"
    )
    assert(
        not self.state.progress.terminalStarted,
        "Terminal Town work must be reconciled and cannot be discarded"
    )
    self.cancelRequested = false
    local progress = self.state.progress or {}
    local pending = progress.pendingBatch
    if pending and (
        pending.operation == "CreatePart"
        or pending.operation == "Clone"
        or pending.operation == "AdoptOwnership"
        or pending.operation == "CreateGroup"
        or pending.operation == "AdoptGroupOwnership"
    ) then
        local reconciliation, remainder, appliedPlanIds = self:_reconcile(pending, nil, true)
        if reconciliation == "confirmed" then
            self.state = self.checkpoint:advance(function(state)
                if pending.operation == "CreateGroup"
                    or pending.operation == "AdoptGroupOwnership"
                then
                    state.progress.pendingGroupArtifact = {
                        groupFingerprint = pending.groupFingerprint,
                        groupId = pending.groupId,
                        sequence = pending.sequence,
                    }
                else
                    state.progress.pendingAdoption = {
                        batchId = pending.id,
                        count = #(pending.planIds or {}),
                        planIds = copy(pending.planIds or {}),
                        sequence = pending.sequence,
                    }
                end
                state.progress.pendingBatch = nil
            end)
        elseif reconciliation == "partially_applied" and type(remainder) == "table" then
            self:_persistPartial(pending, remainder, pending.sequence, appliedPlanIds)
        elseif reconciliation == "ownership_pending" and type(remainder) == "table" then
            self.state = self.checkpoint:advance(function(state)
                if remainder.operation == "AdoptGroupOwnership" then
                    state.progress.pendingGroupArtifact = {
                        groupFingerprint = remainder.groupFingerprint,
                        groupId = remainder.groupId,
                        raw = true,
                        sequence = pending.sequence,
                    }
                else
                    state.progress.pendingRawCreation = copy(remainder)
                    state.progress.pendingRawCreation.nextPending = nil
                end
                state.progress.pendingBatch = nil
            end)
        elseif reconciliation == "not_applied" then
            self.state = self.checkpoint:advance(function(state)
                state.progress.pendingBatch = nil
            end)
        elseif reconciliation ~= "not_applied" then
            return self:_rollbackIncomplete(
                "Pending created parts cannot be attributed safely for cleanup"
            )
        end
        progress = self.state.progress or {}
    end
    local hasMutation = (progress.lastConfirmedSequence or 0) > 0
        or progress.pendingBatch ~= nil
        or progress.pendingAdoption ~= nil
        or progress.pendingRawCreation ~= nil
        or progress.pendingGroupArtifact ~= nil
    if not hasMutation then
        local deleted, message = self.checkpoint:deleteJob(self.state.job.id)
        if not deleted then
            return self:_rollbackIncomplete(message or "Checkpoint cleanup is incomplete")
        end
        self.state = nil
        self:_publish({
            phase = "Ready",
            state = "idle",
        })
        return true
    end

    if type(self.nextCleanupBatch) ~= "function"
        or type(self.removeBatch) ~= "function"
    then
        return self:_rollbackIncomplete("Cleanup cannot identify all plan-owned destination items")
    end

    self.state = self.checkpoint:advance(function(state)
        state.cleanup = state.cleanup or {
            cursorSequence = state.progress.lastConfirmedSequence or 0,
            lastConfirmedSequence = 0,
            removedCount = 0,
        }
        state.cleanup.cursorSequence =
            state.cleanup.cursorSequence or state.progress.lastConfirmedSequence or 0
        state.cleanup.lastConfirmedSequence = state.cleanup.lastConfirmedSequence or 0
        state.cleanup.removedCount = state.cleanup.removedCount or 0
        state.job.state = "rollback"
    end)

    local cleanupPending = self.state.cleanup.pendingBatch
    if cleanupPending then
        local recovery = self:_reconcileCleanup(cleanupPending, nil, true)
        if recovery == "confirmed" then
            self.state = self.checkpoint:advance(function(state)
                state.cleanup.lastConfirmedSequence += 1
                state.cleanup.removedCount += cleanupPending.itemCount
                    or #(cleanupPending.planIds or {})
                state.cleanup.cursorSequence =
                    cleanupPending.nextCursor or state.cleanup.cursorSequence
                state.cleanup.cursorItemOffset =
                    cleanupPending.nextOffset or state.cleanup.cursorItemOffset
                if cleanupPending.clearsPendingAdoption then
                    state.cleanup.pendingAdoptionRemoved = true
                end
                if cleanupPending.clearsPendingRawCreation then
                    state.cleanup.pendingRawCreationRemoved = true
                end
                if cleanupPending.clearsPendingGroup then
                    state.cleanup.pendingGroupRemoved = true
                end
                state.cleanup.pendingBatch = nil
            end)
            if self.afterCleanupConfirmation then
                self.afterCleanupConfirmation(copy(cleanupPending))
            end
        elseif recovery ~= "not_applied" then
            return self:_rollbackIncomplete("Cleanup pending batch is ambiguous")
        end
    end

    self:_publish({
        context = ("%d plan-owned items removed"):format(self.state.cleanup.removedCount),
        phase = "Cleaning copied parts",
        state = "rollback",
    })

    while true do
        local identified, nextBatch = pcall(self.nextCleanupBatch, copy(self.state))
        if not identified then
            return self:_rollbackIncomplete("Cleanup cannot identify all plan-owned destination items")
        end
        if nextBatch == nil then
            break
        end
        if type(nextBatch) == "table"
            and nextBatch.operation == nil
            and type(nextBatch[1]) == "table"
        then
            nextBatch = nextBatch[(self.state.cleanup.lastConfirmedSequence or 0) + 1]
            if nextBatch == nil then
                break
            end
        end
        if type(nextBatch) ~= "table" then
            return self:_rollbackIncomplete("Cleanup cannot identify all plan-owned destination items")
        end
        local batch = copy(nextBatch)
        batch.id = batch.id
            or ("%s:remove:%06d"):format(
                self.state.job.id,
                (self.state.cleanup.lastConfirmedSequence or 0) + 1
            )
        batch.sequence = (self.state.cleanup.lastConfirmedSequence or 0) + 1
        self.state = self.checkpoint:advance(function(state)
            state.cleanup.pendingBatch = copy(batch)
            state.job.state = "rollback"
        end)

        if self.cancelRequested or self.stopped then
            return self:_rollbackIncomplete("Cleanup stopped before the next Remove")
        end
        local cooled = self.waitForCooling(function()
            return self.cancelRequested or self.stopped
        end)
        if not cooled then
            return self:_rollbackIncomplete("Cleanup stopped while waiting for Town cooling")
        end
        if self.cancelRequested or self.stopped then
            return self:_rollbackIncomplete("Cleanup stopped before the next Remove")
        end
        local succeeded, applied = pcall(self.removeBatch, batch)
        local reconciliation = self:_reconcileCleanup(
            batch,
            succeeded and applied or nil,
            not succeeded
        )
        if reconciliation ~= "confirmed" then
            return self:_rollbackIncomplete(
                succeeded and "Cleanup batch was not confirmed"
                    or "Cleanup remote result is ambiguous"
            )
        end
        self.state = self.checkpoint:advance(function(state)
            state.cleanup.lastConfirmedSequence += 1
            state.cleanup.removedCount += batch.itemCount or #(batch.planIds or {})
            state.cleanup.cursorSequence =
                batch.nextCursor or state.cleanup.cursorSequence
            state.cleanup.cursorItemOffset =
                batch.nextOffset or state.cleanup.cursorItemOffset
            if batch.clearsPendingAdoption then
                state.cleanup.pendingAdoptionRemoved = true
            end
            if batch.clearsPendingRawCreation then
                state.cleanup.pendingRawCreationRemoved = true
            end
            if batch.clearsPendingGroup then
                state.cleanup.pendingGroupRemoved = true
            end
            state.cleanup.pendingBatch = nil
        end)
        if self.afterCleanupConfirmation then
            self.afterCleanupConfirmation(copy(batch))
        end
        self:_publish({
            context = ("%d plan-owned items removed"):format(
                self.state.cleanup.removedCount
            ),
            phase = "Cleaning copied parts",
            state = "rollback",
        })
    end

    local deleted, message = self.checkpoint:deleteJob(self.state.job.id)
    if not deleted then
        return self:_rollbackIncomplete(message or "Checkpoint cleanup is incomplete")
    end
    self.state = nil
    self:_publish({
        phase = "Ready",
        state = "idle",
    })
    return true
end

function CopyEngine:retryCleanup()
    assert(
        self.state
            and (self.state.job.state == "rollback"
                or self.state.job.state == "rollback_incomplete"),
        "Cleanup is not awaiting retry"
    )
    return self:discard()
end

function CopyEngine:cleanupLocalCheckpoint(allowIncomplete)
    local completed = self.state
        and (self.state.job.state == "completed"
            or self.state.job.state == "cleanup_pending")
    assert(
        self.state and (completed or allowIncomplete == true),
        "Local checkpoint cleanup is unavailable"
    )
    local deleted, message = self.checkpoint:deleteJob(self.state.job.id)
    if not deleted then
        return false, message or "Checkpoint cleanup is incomplete"
    end
    self.state = nil
    self:_publish({
        confirmedProgress = completed and 1 or 0,
        phase = completed and "Copy complete" or "Ready",
        state = completed and "completed" or "idle",
    })
    return true
end

function CopyEngine:stop()
    self.stopped = true
    if self.state and self.state.job.state ~= "awaiting_confirmation" then
        self.cancelRequested = true
    end
end

return CopyEngine
