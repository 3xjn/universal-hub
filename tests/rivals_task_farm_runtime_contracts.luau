local Runtime = require("../games/rivals/tasks/TaskFarmRuntime")
local function signal()
    local callbacks = {}
    local s = {}
    function s:Connect(fn)
        table.insert(callbacks, fn)
        local c = { connected = true }
        function c:Disconnect()
            if not self.connected then
                return
            end
            self.connected = false
            for i, v in ipairs(callbacks) do
                if v == fn then
                    table.remove(callbacks, i)
                    break
                end
            end
        end
        return c
    end
    function s:Fire()
        for _, fn in ipairs(table.clone(callbacks)) do
            fn()
        end
    end
    function s:count()
        return #callbacks
    end
    return s
end
local signals, records = {}, { { Name = "Beginner7", Progress = 0, Completed = false } }
local data = {
    Get = function(_, key)
        if key == "Tasks" then
            return records
        elseif key == "Wins" then
            return 0
        end
    end,
    GetDataChangedSignal = function(_, key)
        signals[key] = signals[key] or signal()
        return signals[key]
    end,
}
local fighterSignal, duelSignal = signal(), signal()
local fighter = {
    Data = { IsInDuel = false, IsInShootingRange = false },
    Get = function(self, k)
        return self.Data[k]
    end,
    GetDataChangedSignal = function()
        return fighterSignal
    end,
}
local duel = {
    Data = { Status = "Waiting" },
    Get = function(self, k)
        return self.Data[k]
    end,
    GetDataChangedSignal = function()
        return duelSignal
    end,
}
local queued, timers, activity = {}, {}, {}
local leaveCalls = 0
local queueResults = { "Retry", "Success", "Success" }
local runtime = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = {
            Beginner7 = { Title = "Play a duel", Goal = 1 },
        },
    },
    playerDataController = data,
    matchmakingController = {
        QueueInto = function(_, q)
            table.insert(queued, q)
            return table.remove(queueResults, 1)
        end,
        TryLeaveQueue = function()
            leaveCalls += 1
        end,
    },
    fighterController = { LocalFighter = fighter },
    duelController = {
        GetDuel = function()
            return duel
        end,
    },
    constants = { BEGINNER_QUEUE_NAME = "beginner", BEGINNER_QUEUE_WINS = 5 },
    delay = function(_, fn)
        table.insert(timers, fn)
    end,
    maxQueueAttempts = 2,
    onActivityChanged = function(active)
        table.insert(activity, active)
    end,
})
assert(#queued == 1 and queued[1] == "beginner" and #timers == 1)
timers[1]()
assert(#queued == 2, "one failed request retries through the public controller boundary")
assert(
    #timers == 1 and runtime:status().state == "queued",
    "a successful queue response must stop retrying"
)
runtime:pause("test")
local stale = timers[1]
stale()
assert(
    #queued == 2 and leaveCalls == 1,
    "pausing must cancel only the queue accepted by task farming"
)
runtime:resume()
assert(#queued == 3, "resuming after cancellation must request a fresh queue")
fighter.Data.IsInDuel = true
duel.Data.Status = "RoundStarted"
fighterSignal:Fire()
assert(runtime:isCombatActive())
assert(activity[#activity] == true, "RoundStarted must wake Adapter frame ownership")
runtime:stop()
assert(not runtime:isCombatActive() and runtime:status().state == "stopped")
assert(leaveCalls == 2, "stopping must cancel an accepted task-owned queue")
assert(activity[#activity] == false, "stop must publish combat deactivation")
assert(signals.Tasks:count() == 0 and signals.BeginnerTasksCompleted:count() == 0)

fighter.Data.IsInDuel = false
fighter.Data.IsInShootingRange = true
local rangeLeaves, rangeQueues = 0, 0
local rangeRuntime = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = { Beginner7 = { Title = "Play a duel", Goal = 1 } },
    },
    playerDataController = data,
    matchmakingController = {
        QueueInto = function()
            rangeQueues += 1
            return "Success"
        end,
    },
    fighterController = { LocalFighter = fighter },
    duelController = { GetDuel = function() return nil end },
    leaveRange = function()
        rangeLeaves += 1
        return true
    end,
})
assert(
    rangeLeaves == 1 and rangeQueues == 0 and rangeRuntime:status().state == "range-leaving",
    "a PvP task must leave the shooting range before it queues"
)
fighter.Data.IsInShootingRange = false
fighterSignal:Fire()
assert(rangeQueues == 1, "queueing must begin after native range-exit confirmation")
rangeRuntime:stop()

fighter.Data.IsInShootingRange = true
local yieldingLeaves = 0
local yieldingRangeRuntime = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = { Beginner7 = { Title = "Play a duel", Goal = 1 } },
    },
    playerDataController = data,
    matchmakingController = { QueueInto = function() error("range exit must finish first") end },
    fighterController = { LocalFighter = fighter },
    duelController = { GetDuel = function() return nil end },
    paused = true,
    leaveRange = function()
        yieldingLeaves += 1
        if yieldingLeaves == 1 then
            coroutine.yield()
        end
        return true
    end,
})
local yieldingResume = coroutine.create(function()
    yieldingRangeRuntime:resume()
end)
assert(coroutine.resume(yieldingResume))
assert(yieldingRangeRuntime.rangeExitPending == true, "native range exit may yield")
yieldingRangeRuntime:pause("user")
assert(coroutine.resume(yieldingResume))
assert(
    yieldingRangeRuntime:status().paused
        and yieldingRangeRuntime:status().state == "paused"
        and yieldingRangeRuntime.rangeExitRequested == false,
    "a stale yielding range exit must not overwrite pause state"
)
yieldingRangeRuntime:resume()
assert(
    yieldingLeaves == 2 and yieldingRangeRuntime:status().state == "range-leaving",
    "resume must retry an interrupted range exit"
)
yieldingRangeRuntime:stop()
fighter.Data.IsInShootingRange = false

local unknownQueues, unknownLeaves = 0, 0
local unknownRuntime = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = { Beginner7 = { Title = "Play a duel", Goal = 1 } },
    },
    playerDataController = data,
    matchmakingController = {
        QueueInto = function()
            unknownQueues += 1
            return "Success"
        end,
    },
    fighterController = { LocalFighter = {} },
    duelController = { GetDuel = function() return nil end },
    leaveRange = function()
        unknownLeaves += 1
        return true
    end,
})
assert(
    unknownRuntime:status().state == "native-waiting"
        and unknownQueues == 0
        and unknownLeaves == 0,
    "unknown fighter and range state must not manufacture a queue-ready state"
)
unknownRuntime:stop()

local raceRuntime
local raceLeaves = 0
local raceSignals = {}
local raceData = {
    Get = function(_, key)
        if key == "Tasks" then
            return records
        end
    end,
    GetDataChangedSignal = function(_, key)
        raceSignals[key] = raceSignals[key] or signal()
        return raceSignals[key]
    end,
}
fighter.Data.IsInDuel = false
duel.Data.Status = "Waiting"
raceRuntime = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = {
            Beginner7 = { Title = "Play a duel", Goal = 1 },
        },
    },
    playerDataController = raceData,
    matchmakingController = {
        QueueInto = function()
            raceRuntime:pause("user")
            return "Success"
        end,
        TryLeaveQueue = function()
            raceLeaves += 1
        end,
    },
    fighterController = { LocalFighter = fighter },
    duelController = {
        GetDuel = function()
            return duel
        end,
    },
    paused = true,
})
raceRuntime:resume()
assert(
    raceRuntime:status().paused and raceRuntime:status().state == "paused" and raceLeaves == 1,
    "a pause racing a successful QueueInto must leave that newly accepted queue"
)
raceRuntime:stop()

local veteranQueue
fighter.Data.IsInDuel = false
local veteranSignals = {}
local veteranData = {
    Get = function(_, key)
        if key == "Tasks" then
            return records
        end
    end,
    GetStatistic = function(_, key)
        assert(key == "StatisticDuelsWon")
        return 10
    end,
    GetDataChangedSignal = function(_, key)
        veteranSignals[key] = veteranSignals[key] or signal()
        return veteranSignals[key]
    end,
}
local veteran = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = {
            Beginner7 = { Title = "Play a duel", Goal = 1 },
        },
    },
    playerDataController = veteranData,
    matchmakingController = {
        QueueInto = function(_, q)
            veteranQueue = q
            return "Success"
        end,
    },
    fighterController = { LocalFighter = fighter },
    duelController = {
        GetDuel = function()
            return nil
        end,
    },
    constants = { BEGINNER_QUEUE_NAME = "beginner", BEGINNER_QUEUE_WINS = 5 },
    paused = false,
})
assert(
    veteranQueue == "1v1" and veteran:status().state == "queued",
    "native duel-win statistics must route veterans to 1v1"
)
veteran:stop()

fighter.Data.IsInDuel = true
duel.Data.Status = "GameOver"
local requeueName
local requeueSignals = {}
local requeueData = {
    Get = function(_, key)
        if key == "Tasks" then
            return records
        end
    end,
    GetDataChangedSignal = function(_, key)
        requeueSignals[key] = requeueSignals[key] or signal()
        return requeueSignals[key]
    end,
}
local gameOverRuntime = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = {
            Beginner7 = { Title = "Play a duel", Goal = 1 },
        },
    },
    playerDataController = requeueData,
    matchmakingController = {
        QueueInto = function(_, name)
            requeueName = name
            return "Success"
        end,
    },
    fighterController = { LocalFighter = fighter },
    duelController = {
        GetDuel = function()
            return duel
        end,
    },
    context = {
        isMatchmadeDuel = function()
            return true
        end,
    },
    constants = { BEGINNER_QUEUE_NAME = "beginner", BEGINNER_QUEUE_WINS = 5 },
})
assert(
    requeueName == "beginner" and gameOverRuntime:status().state == "queued",
    "GameOver must requeue incomplete PvP work through MatchmakingController"
)
gameOverRuntime:stop()

fighter.Data.IsInShootingRange = nil
duel.Data.Status = "RoundStarted"
local nilRangeCombat = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = { Beginner7 = { Title = "Play a duel", Goal = 1 } },
    },
    playerDataController = requeueData,
    matchmakingController = { QueueInto = function() error("active combat must not queue") end },
    fighterController = { LocalFighter = fighter },
    duelController = { GetDuel = function() return duel end },
    context = { isMatchmadeDuel = function() return true end },
})
assert(
    nilRangeCombat:status().state == "combat",
    "an unavailable range flag must not disable an active duel"
)
nilRangeCombat:stop()

local fallbackRequeue
local gameOverFallback = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = { Beginner7 = { Title = "Play a duel", Goal = 1 } },
    },
    playerDataController = requeueData,
    matchmakingController = {
        IsMatchmadeDuelOver = function() return true end,
        QueueInto = function(_, name)
            fallbackRequeue = name
            return "Success"
        end,
    },
    fighterController = { LocalFighter = fighter },
    duelController = { GetDuel = function() return nil end },
    context = { isMatchmadeDuel = function() return true end },
    constants = { BEGINNER_QUEUE_NAME = "beginner", BEGINNER_QUEUE_WINS = 5 },
})
assert(
    fallbackRequeue == "beginner" and gameOverFallback:status().state == "queued",
    "native matchmade GameOver evidence must requeue even after the duel replica disappears"
)
gameOverFallback:stop()

local transitionEnded = signal()
local transitionDuel = duel
local transitionOver = false
local transitionRequeue
fighter.Data.IsInDuel = true
duel.Data.Status = "RoundStarted"
local gameOverTransition = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = { Beginner7 = { Title = "Play a duel", Goal = 1 } },
    },
    playerDataController = requeueData,
    matchmakingController = {
        MatchmadeDuelEnded = transitionEnded,
        IsMatchmadeDuelOver = function()
            return transitionOver
        end,
        QueueInto = function(_, name)
            transitionRequeue = name
            return "Success"
        end,
    },
    fighterController = { LocalFighter = fighter },
    duelController = {
        GetDuel = function()
            return transitionDuel
        end,
    },
    context = { isMatchmadeDuel = function() return true end },
    constants = { BEGINNER_QUEUE_NAME = "beginner", BEGINNER_QUEUE_WINS = 5 },
})
assert(gameOverTransition:status().state == "combat")
transitionDuel = nil
transitionOver = true
transitionEnded:Fire()
assert(
    transitionRequeue == "beginner" and gameOverTransition:status().state == "queued",
    "native matchmade end signal must wake requeue when the duel replica disappears"
)
gameOverTransition:stop()
fighter.Data.IsInShootingRange = false

local manualPauseRequests = 0
local manualQueueCalls = 0
fighter.Data.IsInDuel = true
duel.Data.Status = "RoundStarted"
local manualSignals = {}
local manualData = {
    Get = function(_, key)
        if key == "Tasks" then
            return records
        end
    end,
    GetDataChangedSignal = function(_, key)
        manualSignals[key] = manualSignals[key] or signal()
        return manualSignals[key]
    end,
}
local manualRuntime = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = {
            Beginner7 = { Title = "Play a duel", Goal = 1 },
        },
    },
    playerDataController = manualData,
    matchmakingController = {
        QueueInto = function()
            manualQueueCalls += 1
            return "Success"
        end,
        Get = function(_, key)
            if key == "MatchmadeStatus" then
                return ""
            elseif key == "MatchmadeGameOver" then
                return false
            elseif key == "MatchmadeConnectedPlayers" then
                return {}
            end
        end,
    },
    fighterController = { LocalFighter = fighter },
    duelController = {
        GetDuel = function()
            return duel
        end,
    },
    context = {
        isMatchmadeDuel = function()
            return false
        end,
    },
    onManualDuel = function()
        manualPauseRequests += 1
    end,
})
assert(
    manualRuntime:status().paused and manualRuntime:status().reason == "manual-duel",
    "duel-pad and other lobby duels must pause task ownership"
)
assert(
    not manualRuntime:isCombatActive() and manualQueueCalls == 0 and manualPauseRequests == 1,
    "manual lobby duels must neither run combat automation nor enter matchmaking"
)
manualRuntime:resume()
assert(
    not manualRuntime:status().paused and manualRuntime:status().reason == nil,
    "user resume during a private duel must stick"
)
assert(
    manualPauseRequests == 1 and manualQueueCalls == 0,
    "unpausing a private duel must not re-pause or enter matchmaking"
)
fighterSignal:Fire()
assert(
    not manualRuntime:status().paused and manualPauseRequests == 1,
    "round or fighter updates must not re-pause after the user unpauses"
)
fighter.Data.IsInDuel = nil
fighterSignal:Fire()
assert(
    not manualRuntime:status().paused and manualRuntime:status().state == "native-waiting",
    "temporary unknown duel state must fail closed without forgetting the active duel"
)
fighter.Data.IsInDuel = true
fighterSignal:Fire()
assert(
    not manualRuntime:status().paused and manualPauseRequests == 1,
    "native state recovery inside the same manual duel must not auto-pause again"
)
duel.Data.Status = "GameOver"
duelSignal:Fire()
assert(
    not manualRuntime:status().paused and manualQueueCalls == 0,
    "unpausing a private duel must not start matchmaking on GameOver"
)
duel.Data.Status = "RoundStarted"
manualRuntime:pause("user")
assert(
    manualRuntime:status().paused and manualRuntime:status().reason == "user",
    "the user must still be able to pause again in a private duel"
)
manualRuntime:resume()
assert(
    not manualRuntime:status().paused and manualPauseRequests == 1,
    "a later manual resume must also stick in a private duel"
)
fighter.Data.IsInDuel = false
fighterSignal:Fire()
assert(
    not manualRuntime:status().paused,
    "leaving a private duel must not re-pause an unpaused farm"
)
fighter.Data.IsInDuel = true
fighterSignal:Fire()
assert(
    manualRuntime:status().paused
        and manualRuntime:status().reason == "manual-duel"
        and manualPauseRequests == 2,
    "entering a new private duel may auto-pause once"
)
manualRuntime:stop()
fighter.Data.IsInDuel = false

local practiceCalls = {}
local practice = {
    setChanged = function(self, callback)
        self.changed = callback
    end,
    setTask = function(self, task)
        self.task = task
        table.insert(practiceCalls, task and task.name or "clear")
    end,
    resume = function() end,
    pause = function(self)
        self.paused = true
    end,
    stop = function(self)
        self.stopped = true
    end,
    status = function(self)
        return { state = "target-combat" }
    end,
    isCombatActive = function()
        return true
    end,
}
local practiceSignals = {}
local practiceData = {
    Get = function(_, key)
        if key == "Tasks" then
            return { { Name = "Beginner2", Progress = 0, Completed = false } }
        end
    end,
    GetDataChangedSignal = function(_, key)
        practiceSignals[key] = practiceSignals[key] or signal()
        return practiceSignals[key]
    end,
}
fighter.Data.IsInShootingRange = true
local practiceRuntime = Runtime.new({
    taskLibrary = {
        TASKS_DATA_NAMES = { "Tasks" },
        Info = {
            Beginner2 = { Title = "Break targets", Goal = 5 },
        },
    },
    playerDataController = practiceData,
    matchmakingController = {
        QueueInto = function()
            error("practice tasks must not queue")
        end,
    },
    fighterController = { LocalFighter = fighter },
    duelController = {
        GetDuel = function()
            return nil
        end,
    },
    practiceDriver = practice,
})
assert(practiceCalls[1] == "Beginner2" and practiceRuntime:isCombatActive())
assert(
    practiceRuntime:status().state == "target-combat"
        and practiceRuntime:status().practice.state == "target-combat"
)
practiceRuntime:pause("test")
assert(practice.paused)
practiceRuntime:stop()
assert(practice.stopped)
print("rivals-task-farm-runtime-contracts-ok")
