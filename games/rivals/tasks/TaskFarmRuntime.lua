local TaskPolicy = require("./TaskPolicy")

local TaskFarmRuntime = {}
TaskFarmRuntime.__index = TaskFarmRuntime

local function read(replica, key)
    if type(replica) ~= "table" then
        return nil
    end
    if type(replica.Get) == "function" then
        local ok, result = pcall(replica.Get, replica, key)
        if ok then
            return result
        end
    end
    if type(replica.Data) == "table" then
        return replica.Data[key]
    end
    return replica[key]
end

local function connect(connections, signal, callback)
    if signal and type(signal.Connect) == "function" then
        local ok, connection = pcall(signal.Connect, signal, callback)
        if ok and connection then
            table.insert(connections, connection)
            return connection
        end
    end
    return nil
end

local function changedSignal(replica, key)
    if type(replica) ~= "table" then
        return nil
    end
    for _, method in ipairs({
        "GetDataChangedSignal",
        "GetChangedSignal",
        "GetPropertyChangedSignal",
    }) do
        if type(replica[method]) == "function" then
            local ok, result = pcall(replica[method], replica, key)
            if ok and result then
                return result
            end
        end
    end
    return replica.Changed
end

function TaskFarmRuntime.new(options)
    assert(options and options.taskLibrary, "Task farm requires TaskLibrary")
    assert(options.playerDataController, "Task farm requires PlayerDataController")
    assert(options.matchmakingController, "Task farm requires MatchmakingController")
    local defaultDelay = task and task.delay or nil
    local self = setmetatable({
        taskLibrary = options.taskLibrary,
        playerDataController = options.playerDataController,
        matchmakingController = options.matchmakingController,
        duelController = options.duelController,
        fighterController = options.fighterController,
        localPlayer = options.localPlayer,
        constants = options.constants or options.CONSTANTS or {},
        context = options.context or {},
        delay = options.delay or options.schedule or defaultDelay,
        cancelDelay = options.cancelDelay or (task and task.cancel or nil),
        retryHandles = {},
        retryDelay = options.retryDelay or options.retrySeconds or 10,
        maxQueueAttempts = options.maxQueueAttempts or options.maxQueueRetries or 3,
        onActivityChanged = options.onActivityChanged,
        onStatusChanged = options.onStatusChanged,
        onManualDuel = options.onManualDuel,
        leaveRange = options.leaveRange,
        rangeExitPending = false,
        rangeExitRequested = false,
        practiceDriver = options.practiceDriver,
        lastCombatActive = false,
        queueAccepted = false,
        queuedTaskName = nil,
        wasInDuel = false,
        connections = {},
        contextConnections = {},
        generation = 0,
        attempts = 0,
        stopped = false,
        paused = options.paused == true,
        pauseReason = options.paused == true and "user" or nil,
        currentTask = nil,
        state = "idle",
    }, TaskFarmRuntime)

    if self.practiceDriver and type(self.practiceDriver.setChanged) == "function" then
        self.practiceDriver:setChanged(function()
            self:_notifyActivity()
        end)
    end
    local function onNativeChange()
        self:_reconcile(false)
    end
    local groups = options.taskLibrary.TASKS_DATA_NAMES
        or {
            "Tasks",
            "BonusTasks",
            "EventTasks",
            "SpecialChallenges",
            "LimitedTasks",
        }
    for _, group in ipairs(groups) do
        if type(options.playerDataController.GetDataChangedSignal) == "function" then
            local ok, signal = pcall(
                options.playerDataController.GetDataChangedSignal,
                options.playerDataController,
                group
            )
            if ok then
                connect(self.connections, signal, onNativeChange)
            end
        end
    end
    if type(options.playerDataController.GetDataChangedSignal) == "function" then
        local ok, signal = pcall(
            options.playerDataController.GetDataChangedSignal,
            options.playerDataController,
            "BeginnerTasksCompleted"
        )
        if ok then
            connect(self.connections, signal, onNativeChange)
        end
    end
    local fighter = self:_fighter()
    connect(self.connections, changedSignal(fighter, "IsInDuel"), onNativeChange)
    connect(self.connections, changedSignal(fighter, "IsInShootingRange"), onNativeChange)
    if options.fighterController then
        connect(self.connections, options.fighterController.LocalFighterChanged, onNativeChange)
    end
    connect(
        self.connections,
        changedSignal(options.matchmakingController, "MatchmadeGameOver"),
        onNativeChange
    )
    connect(self.connections, options.matchmakingController.MatchmadeDuelEnded, onNativeChange)
    if options.duelController then
        connect(self.connections, options.duelController.DuelChanged, onNativeChange)
        connect(self.connections, options.duelController.LocalDuelChanged, onNativeChange)
    end
    self:_bindDuel()
    self:_reconcile(false)
    return self
end

function TaskFarmRuntime:_fighter()
    if type(self.context.getFighter) == "function" then
        return self.context.getFighter()
    end
    return self.fighterController and self.fighterController.LocalFighter or nil
end

function TaskFarmRuntime:_duel()
    if type(self.context.getDuel) == "function" then
        return self.context.getDuel()
    end
    if self.duelController and type(self.duelController.GetDuel) == "function" then
        local ok, duel = pcall(self.duelController.GetDuel, self.duelController, self.localPlayer)
        if ok then
            return duel
        end
    end
    return nil
end

function TaskFarmRuntime:_bindDuel()
    for _, connection in ipairs(self.contextConnections) do
        if connection and type(connection.Disconnect) == "function" then
            connection:Disconnect()
        end
    end
    self.contextConnections = {}
    local duel = self:_duel()
    connect(self.contextConnections, changedSignal(duel, "Status"), function()
        self:_reconcile(false)
    end)
end

function TaskFarmRuntime:_inDuel()
    local value
    if type(self.context.isInDuel) == "function" then
        value = self.context.isInDuel()
    else
        value = read(self:_fighter(), "IsInDuel")
    end
    if type(value) == "boolean" then
        return value
    end
    return nil
end

function TaskFarmRuntime:_inRange()
    local value
    if type(self.context.isInRange) == "function" then
        value = self.context.isInRange()
    else
        value = read(self:_fighter(), "IsInShootingRange")
    end
    if type(value) == "boolean" then
        return value
    end
    return nil
end

function TaskFarmRuntime:_isMatchmadeDuel()
    if type(self.context.isMatchmadeDuel) == "function" then
        return self.context.isMatchmadeDuel(self:_duel()) == true
    end
    return self.queueAccepted or self:_isQueued()
end

function TaskFarmRuntime:_isQueued()
    if type(self.context.isQueued) == "function" then
        return self.context.isQueued() == true
    end
    if type(self.context.getQueueName) == "function" then
        return self.context.getQueueName() ~= nil
    end
    local controller = self.matchmakingController
    return read(controller, "IsQueued") == true
        or read(controller, "IsInQueue") == true
        or read(controller, "QueueName") ~= nil
        or read(controller, "QueuedFor") ~= nil
end

function TaskFarmRuntime:_wins()
    if type(self.context.getWins) == "function" then
        return self.context.getWins() or 0
    end
    if type(self.playerDataController.GetStatistic) == "function" then
        local ok, value = pcall(
            self.playerDataController.GetStatistic,
            self.playerDataController,
            "StatisticDuelsWon"
        )
        if ok and type(value) == "number" then
            return value
        end
    end
    for _, key in ipairs({ "Wins", "DuelWins", "TotalWins" }) do
        local value = read(self.playerDataController, key)
        if type(value) == "number" then
            return value
        end
    end
    for _, containerKey in ipairs({ "Stats", "Statistics", "PlayerStats" }) do
        local container = read(self.playerDataController, containerKey)
        if type(container) == "table" then
            for _, key in ipairs({ "Wins", "DuelWins", "TotalWins" }) do
                if type(container[key]) == "number" then
                    return container[key]
                end
            end
        end
    end
    return 0
end

function TaskFarmRuntime:_queueName()
    local cap = self.constants.BEGINNER_QUEUE_WINS
    local beginner = self.constants.BEGINNER_QUEUE_NAME
    if beginner and type(cap) == "number" and self:_wins() < cap then
        return beginner
    end
    return "1v1"
end

function TaskFarmRuntime:_cancelRetries()
    for handle, _ in pairs(self.retryHandles) do
        if type(self.cancelDelay) == "function" then
            pcall(self.cancelDelay, handle)
        elseif type(handle) == "table" and type(handle.Cancel) == "function" then
            pcall(handle.Cancel, handle)
        end
        self.retryHandles[handle] = nil
    end
end

function TaskFarmRuntime:_scheduleRetry(generation)
    if type(self.delay) ~= "function" or self.attempts >= self.maxQueueAttempts then
        return
    end
    local token = { active = true }
    local handle
    local function retry()
        token.active = false
        if handle ~= nil then
            self.retryHandles[handle] = nil
        end
        if self.stopped or self.paused or generation ~= self.generation then
            return
        end
        self:_reconcile(true)
    end
    handle = self.delay(self.retryDelay, retry)
    if token.active and handle ~= nil then
        self.retryHandles[handle] = true
    end
end

function TaskFarmRuntime:_tryLeaveQueue()
    local leaveQueue = self.context.leaveQueue or self.matchmakingController.TryLeaveQueue
    if type(leaveQueue) == "function" then
        pcall(leaveQueue, self.matchmakingController)
    end
end

function TaskFarmRuntime:_cancelOwnedQueue()
    if not self.queueAccepted then
        return
    end
    self.queueAccepted = false
    self.queuedTaskName = nil
    self:_tryLeaveQueue()
end

function TaskFarmRuntime:_requestQueue(generation)
    if self.stopped or self.paused or generation ~= self.generation then
        return
    end
    if self.attempts >= self.maxQueueAttempts then
        self.state = "retry-exhausted"
        return
    end
    self.attempts += 1
    self.state = "queueing"
    -- This is deliberately the sole state-changing boundary in the runtime.
    local ok, result =
        pcall(self.matchmakingController.QueueInto, self.matchmakingController, self:_queueName())
    local accepted = ok and (result == true or result == "Success")
    if self.stopped or self.paused or generation ~= self.generation then
        if accepted then
            self:_tryLeaveQueue()
        end
        return
    end
    if accepted then
        self.queueAccepted = true
        self.queuedTaskName = self.currentTask and self.currentTask.name or nil
        self.state = "queued"
        return
    end
    self:_scheduleRetry(generation)
end

function TaskFarmRuntime:_notifyActivity()
    local status = self:status()
    if type(self.onStatusChanged) == "function" then
        pcall(self.onStatusChanged, status)
    end
    local active = self:isCombatActive() == true
    if active == self.lastCombatActive then
        return
    end
    self.lastCombatActive = active
    if type(self.onActivityChanged) == "function" then
        pcall(self.onActivityChanged, active, status)
    end
end

function TaskFarmRuntime:_reconcile(isRetry)
    if self.stopped then
        return
    end
    if not isRetry then
        self:_cancelRetries()
        self.generation += 1
        self.attempts = 0
        self:_bindDuel()
    end
    local generation = self.generation
    local previousTaskName = self.currentTask and self.currentTask.name or nil
    local tasks = TaskPolicy.snapshot(self.taskLibrary, self.playerDataController)
    self.currentTask = TaskPolicy.select(tasks)
    local currentTaskName = self.currentTask and self.currentTask.name or nil
    if currentTaskName ~= previousTaskName then
        self.queueAccepted = false
        self.queuedTaskName = nil
    end
    if self.practiceDriver and type(self.practiceDriver.setTask) == "function" then
        local practiceTask = self.currentTask
        if practiceTask and TaskPolicy.requiresCombat(practiceTask) then
            practiceTask = nil
        end
        self.practiceDriver:setTask(practiceTask)
        if self.paused and type(self.practiceDriver.pause) == "function" then
            self.practiceDriver:pause()
        elseif not self.paused and type(self.practiceDriver.resume) == "function" then
            self.practiceDriver:resume()
        end
    end
    local inDuel = self:_inDuel()
    local matchmadeDuel = self:_isMatchmadeDuel()
    -- Auto-pause only when entering a private/lobby duel. A later user resume,
    -- round-status change, or Adapter pause/resume sync must not re-pause.
    if inDuel and not matchmadeDuel and not self.wasInDuel then
        self.wasInDuel = true
        self:pause("manual-duel")
        if type(self.onManualDuel) == "function" then
            pcall(self.onManualDuel)
        end
        return
    end
    if self.wasInDuel and inDuel == false then
        self.queueAccepted = false
        self.queuedTaskName = nil
    end
    if inDuel ~= nil then
        self.wasInDuel = inDuel
    end
    local function finish(state)
        self.state = state
        self:_notifyActivity()
    end
    if self.paused then
        finish("paused")
        return
    end
    if not self.currentTask then
        finish("idle")
        return
    end
    if not TaskPolicy.requiresCombat(self.currentTask) then
        local practiceStatus = self.practiceDriver and self.practiceDriver:status() or nil
        finish(practiceStatus and practiceStatus.state or "practice-pending")
        return
    end
    if inDuel == nil then
        finish("native-waiting")
        return
    end
    local duelStatus = read(self:_duel(), "Status")
    if inDuel and matchmadeDuel and duelStatus == nil then
        local isOver = self.matchmakingController.IsMatchmadeDuelOver
        if type(isOver) == "function" then
            local succeeded, result = pcall(isOver, self.matchmakingController)
            if succeeded and result == true then
                duelStatus = "GameOver"
            end
        end
    end
    if inDuel and duelStatus == "GameOver" and matchmadeDuel then
        if self:_isQueued() or (self.queueAccepted and self.queuedTaskName == currentTaskName) then
            finish("queued")
            return
        end
        self:_requestQueue(generation)
        self:_notifyActivity()
        return
    end
    if inDuel then
        finish(self:isCombatActive() and "combat" or "duel-waiting")
        return
    end
    local inRange = self:_inRange()
    if inRange == nil then
        finish("native-waiting")
        return
    end
    if inRange then
        if
            not self.rangeExitPending
            and not self.rangeExitRequested
            and type(self.leaveRange) == "function"
        then
            self.rangeExitPending = true
            local succeeded, accepted = pcall(self.leaveRange)
            self.rangeExitPending = false
            if self.generation ~= generation or self.stopped or self.paused then
                if not self.stopped and not self.paused then
                    self:_reconcile(false)
                end
                return
            end
            self.rangeExitRequested = succeeded and accepted ~= false
        end
        finish(
            (self.rangeExitPending or self.rangeExitRequested) and "range-leaving"
                or "range-waiting"
        )
        return
    end
    self.rangeExitRequested = false
    if self:_isQueued() or (self.queueAccepted and self.queuedTaskName == currentTaskName) then
        finish("queued")
        return
    end
    self:_requestQueue(generation)
    self:_notifyActivity()
end

function TaskFarmRuntime:isCombatActive()
    if self.stopped or self.paused then
        return false
    end
    if
        self.practiceDriver
        and type(self.practiceDriver.isCombatActive) == "function"
        and self.practiceDriver:isCombatActive()
    then
        return true
    end
    if not TaskPolicy.requiresCombat(self.currentTask) or not self:_inDuel() then
        return false
    end
    if type(self.context.isRoundStarted) == "function" then
        return self.context.isRoundStarted(self:_duel()) == true
    end
    return read(self:_duel(), "Status") == "RoundStarted"
end

function TaskFarmRuntime:status()
    return {
        state = self.state,
        task = self.currentTask,
        paused = self.paused,
        reason = self.pauseReason,
        attempts = self.attempts,
        practice = self.practiceDriver and self.practiceDriver:status() or nil,
    }
end

function TaskFarmRuntime:setActivityChanged(callback)
    self.onActivityChanged = callback
end

function TaskFarmRuntime:setStatusChanged(callback)
    self.onStatusChanged = callback
end

function TaskFarmRuntime:pause(reason)
    if self.stopped then
        return
    end
    self:_cancelRetries()
    self.generation += 1
    self.paused = true
    self.pauseReason = reason or "paused"
    self.rangeExitRequested = false
    self.state = "paused"
    self:_cancelOwnedQueue()
    if self.practiceDriver and type(self.practiceDriver.pause) == "function" then
        self.practiceDriver:pause()
    end
    self:_notifyActivity()
end

function TaskFarmRuntime:resume()
    if self.stopped or not self.paused then
        return
    end
    self.paused = false
    self.pauseReason = nil
    self:_reconcile(false)
end

function TaskFarmRuntime:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:_cancelRetries()
    self.generation += 1
    self:_cancelOwnedQueue()
    self.state = "stopped"
    self.currentTask = nil
    if self.practiceDriver and type(self.practiceDriver.stop) == "function" then
        self.practiceDriver:stop()
    end
    self:_notifyActivity()
    for _, list in ipairs({ self.connections, self.contextConnections }) do
        for _, connection in ipairs(list) do
            if connection and type(connection.Disconnect) == "function" then
                connection:Disconnect()
            end
        end
        table.clear(list)
    end
end

return TaskFarmRuntime
