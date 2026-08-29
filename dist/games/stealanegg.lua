return {
    buildId = [[610c86b0]],
    id = [[stealanegg]],
    sources = {
        ["games/stealanegg/Adapter.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local AntiHit = importDependency("games/stealanegg/features/AntiHit", "./features/AntiHit")
local AntiTrap = importDependency("games/stealanegg/features/AntiTrap", "./features/AntiTrap")
local AutoBlossom =
    importDependency("games/stealanegg/features/AutoBlossom", "./features/AutoBlossom")
local AutoFarm = importDependency("games/stealanegg/features/AutoFarm", "./features/AutoFarm")
local AutoOpenEggs =
    importDependency("games/stealanegg/features/AutoOpenEggs", "./features/AutoOpenEggs")
local HighlightEsp =
    importDependency("games/stealanegg/features/HighlightEsp", "./features/HighlightEsp")
local HitAura = importDependency("games/stealanegg/features/HitAura", "./features/HitAura")
local InstantPrompts =
    importDependency("games/stealanegg/features/InstantPrompts", "./features/InstantPrompts")
local LagSafeMovement =
    importDependency("games/stealanegg/features/LagSafeMovement", "./features/LagSafeMovement")
local ServerHop = importDependency("games/stealanegg/features/ServerHop", "./features/ServerHop")
local WalkNavigator =
    importDependency("games/stealanegg/features/WalkNavigator", "./features/WalkNavigator")

local Adapter = {}

function Adapter.new(context)
    assert(context and context.store, "Steal An Egg adapter requires a reactive store")

    local environment = type(getgenv) == "function" and getgenv() or _G
    if type(environment.UniversalHubRuntimeState) ~= "table" then
        environment.UniversalHubRuntimeState = {}
    end
    local runtimeState = environment.UniversalHubRuntimeState
    if type(runtimeState.stealanegg) ~= "table" then
        runtimeState.stealanegg = {}
    end
    local gameRuntime = runtimeState.stealanegg
    if type(gameRuntime.visitedServerIds) ~= "table" then
        gameRuntime.visitedServerIds = {}
    end
    local Workspace = context.workspace or workspace
    local LocalPlayer = context.localPlayer or context.players.LocalPlayer
    local CollectionService = game:GetService("CollectionService")
    local HttpService = game:GetService("HttpService")
    local PathfindingService = game:GetService("PathfindingService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")
    local TeleportService = game:GetService("TeleportService")
    local function readPing()
        local ok, value = pcall(function()
            return Stats.PerformanceStats.Ping:GetValue()
        end)
        if not ok or type(value) ~= "number" then
            ok, value = pcall(function()
                return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
            end)
        end
        if not ok or type(value) ~= "number" then
            ok, value = pcall(LocalPlayer.GetNetworkPing, LocalPlayer)
            value = ok and type(value) == "number" and value * 1000 or 0
        end
        return math.round(value)
    end
    local historySettingKey = "UniversalHubStealAnEggFarmHistory"
    if type(gameRuntime.farmHistory) ~= "table" then
        local loaded, history =
            pcall(TeleportService.GetTeleportSetting, TeleportService, historySettingKey)
        gameRuntime.farmHistory = loaded and type(history) == "table" and history
            or { active = false, eggs = {} }
    end
    if type(gameRuntime.farmHistory.eggs) ~= "table" then
        gameRuntime.farmHistory.eggs = {}
    end
    if type(gameRuntime.farmHistory.globalSpawns) ~= "table" then
        gameRuntime.farmHistory.globalSpawns = {}
    end
    local function persistFarmHistory()
        pcall(
            TeleportService.SetTeleportSetting,
            TeleportService,
            historySettingKey,
            gameRuntime.farmHistory
        )
    end
    local function isGlobalSpawnKnown(rarity)
        return gameRuntime.farmHistory.globalSpawns[rarity] == true
    end
    local function markGlobalSpawn(rarity)
        if
            (rarity == "Secret" or rarity == "Eternal")
            and gameRuntime.farmHistory.globalSpawns[rarity] ~= true
        then
            gameRuntime.farmHistory.globalSpawns[rarity] = true
            persistFarmHistory()
        end
    end
    local visitedSettingKey = "UniversalHubStealAnEggVisitedServers"
    if next(gameRuntime.visitedServerIds) == nil then
        local loaded, visited =
            pcall(TeleportService.GetTeleportSetting, TeleportService, visitedSettingKey)
        if loaded and type(visited) == "table" then
            for serverId in pairs(visited) do
                gameRuntime.visitedServerIds[serverId] = true
            end
        end
    end
    local function persistVisitedServers()
        pcall(
            TeleportService.SetTeleportSetting,
            TeleportService,
            visitedSettingKey,
            gameRuntime.visitedServerIds
        )
    end
    local AreaEggResetConfig = require(ReplicatedStorage.Directory.AreaEggResetCycle)
    local AreaEggResetTimeUtil = require(ReplicatedStorage.Library.Util.AreaEggResetTimeUtil)
    local Areas = require(ReplicatedStorage.Directory.Areas)
    local Assets = require(ReplicatedStorage.Directory.Assets)
    local Sakura = require(ReplicatedStorage.Directory.Sakura)
    local EggCmds = require(ReplicatedStorage.Library.Client.EggCmds)
    local GuardChasePolicy = require(ReplicatedStorage.Library.Modules.GuardAreas.GuardChasePolicy)
    local GuardEscapePrediction =
        require(ReplicatedStorage.Library.Modules.GuardAreas.GuardEscapePrediction)
    local Save = require(ReplicatedStorage.Library.Client.Save)
    local indexCategories = {}
    for _, area in pairs(Areas.Directory) do
        for _, drop in pairs(area.DropTable or {}) do
            local category = drop[1]
            local asset = Assets.Directory[category]
            if drop[2] > 0 and asset and asset.DontRoll ~= true then
                indexCategories[category] = true
            end
        end
    end
    local function isIndexed(category)
        local save = Save.Get()
        return save ~= nil and save.Index[category] == true
    end
    local function isIndexPending(category)
        for _, record in pairs(EggCmds.GetOwnerRuntimeRecords(LocalPlayer.UserId)) do
            if record.AssetCategory == category then
                return true
            end
        end
        return false
    end
    local function hasMissingIndex()
        for category in pairs(indexCategories) do
            if not isIndexed(category) and not isIndexPending(category) then
                return true
            end
        end
        return false
    end
    local function securedEggs()
        local eggs = {}
        for index, egg in ipairs(gameRuntime.farmHistory.eggs) do
            local color = egg.rarityColor
            table.insert(eggs, {
                area = egg.area,
                icon = egg.icon,
                name = egg.name,
                rarity = egg.rarity,
                rarityColor = type(color) == "table"
                        and Color3.new(color[1] or 0.7, color[2] or 0.7, color[3] or 0.7)
                    or Color3.fromRGB(177, 188, 199),
                secured = true,
                size = egg.size,
                state = "Secured",
                target = false,
                uid = ("secured-%d-%s"):format(index, tostring(egg.uid)),
            })
        end
        return eggs
    end
    local function recordSecuredEgg(record)
        local asset = Assets.Directory[record.AssetCategory]
        local rarity = asset and asset.Rarity
        local color = rarity and rarity.Color or Color3.fromRGB(177, 188, 199)
        table.insert(gameRuntime.farmHistory.eggs, 1, {
            area = record.AreaId or "Unknown",
            icon = asset and asset.Icon or "",
            name = asset and asset.DisplayName or record.AssetCategory,
            rarity = rarity and (rarity.DisplayName or rarity._id) or "Unknown",
            rarityColor = { color.R, color.G, color.B },
            size = tonumber(record.AssetScale) or 1,
            uid = record.Uid,
        })
        persistFarmHistory()
    end
    local Constants = require(ReplicatedStorage.Library.Globals.Constants)
    local Network = require(ReplicatedStorage.Library.Client.Network)
    local PlotCmds = require(ReplicatedStorage.Library.Client.PlotCmds)
    local SlotIdentity = require(ReplicatedStorage.Library.Util.AreaEggSlotIdentity)
    local stopped = false
    local navigator
    local antiHit = AntiHit.new({
        eggCmds = EggCmds,
        guardHitEndpoint = Constants.NETWORK_MAP.Guards.FOREST_HIT,
        localPlayer = LocalPlayer,
        logger = context.logger,
        network = Network,
        onRecovered = function()
            if navigator then
                navigator:resume()
            end
        end,
        ragdoll = require(ReplicatedStorage.Library.Modules.Ragdoll),
        runService = RunService,
        slotIdentity = SlotIdentity,
        workspace = Workspace,
    })
    local antiTrap = AntiTrap.new({
        collectionService = CollectionService,
        localPlayer = LocalPlayer,
    })
    local autoOpenEggs = AutoOpenEggs.new({
        eggCmds = EggCmds,
        isIndexed = isIndexed,
        localPlayer = LocalPlayer,
        plotCmds = PlotCmds,
        renderer = require(ReplicatedStorage.Library.Client.Eggs.PlacedEggRenderer),
        runService = RunService,
    })
    local highlightEsp = HighlightEsp.new({
        assets = Assets,
        collectionService = CollectionService,
        eggCmds = EggCmds,
        localPlayer = LocalPlayer,
        runService = RunService,
        trapIcon = require(ReplicatedStorage.Directory.Gears._Index.Other.Trap).Icon,
        workspace = Workspace,
    })
    local hitAura = HitAura.new({
        eggCmds = EggCmds,
        endpoint = Constants.NETWORK_MAP.Bat.ACTIVATE,
        localPlayer = LocalPlayer,
        network = Network,
        players = context.players,
        runService = RunService,
        workspace = Workspace,
    })
    local instantPrompts = InstantPrompts.new(Workspace)
    local guardConfigs = {}
    local guardModels = {}
    local objects = Workspace:FindFirstChild("__OBJECTS")
    local areas = objects and objects:FindFirstChild("Areas")
    local guardAreas = areas and areas:FindFirstChild("GuardAreas")
    local separationLine = areas and areas:FindFirstChild("SeparationLine")
    for areaId, config in pairs(require(ReplicatedStorage.Directory.Guards).Directory) do
        guardConfigs[areaId] = config
        local area = guardAreas and guardAreas:FindFirstChild(areaId)
        local guard = area and area:FindFirstChild("Guard")
        if guard and guard:IsA("Model") then
            guardModels[areaId] = guard
        end
    end
    local function nativeEscapePosition(record)
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local area = guardAreas and guardAreas:FindFirstChild(record.AreaId)
        local bounds = area and area:FindFirstChild("Bounds")
        if
            not root
            or not root:IsA("BasePart")
            or not bounds
            or not bounds:IsA("BasePart")
            or not separationLine
            or not separationLine:IsA("BasePart")
        then
            return nil
        end
        local direction = -separationLine.CFrame.LookVector
        local ok, distance = pcall(
            GuardEscapePrediction.ResolveExitDistance,
            bounds.CFrame,
            bounds.Size,
            root.Position,
            direction
        )
        return ok and root.Position + direction * (distance + 18) or nil
    end
    local function canOutrunGuard(areaId, playerSpeed)
        local config = guardConfigs[areaId]
        local guard = guardModels[areaId]
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local area = guardAreas and guardAreas:FindFirstChild(areaId)
        local bounds = area and area:FindFirstChild("Bounds")
        if
            not config
            or not guard
            or not guard.Parent
            or not root
            or not root:IsA("BasePart")
            or not bounds
            or not bounds:IsA("BasePart")
            or not separationLine
            or not separationLine:IsA("BasePart")
        then
            return nil
        end
        local direction = -separationLine.CFrame.LookVector
        local distanceOk, exitDistance = pcall(
            GuardEscapePrediction.ResolveExitDistance,
            bounds.CFrame,
            bounds.Size,
            root.Position,
            direction
        )
        if not distanceOk then
            return nil
        end
        local predictionOk, prediction = pcall(GuardEscapePrediction.Resolve, {
            BaseGuardWalkSpeed = config.WalkSpeed,
            ExitDirection = direction,
            ExitDistance = exitDistance,
            FlatRadius = config.FlatRadius,
            GuardStartPosition = guard:GetPivot().Position,
            HitDistance = config.HitDistance or 10,
            PlayerStartPosition = root.Position,
            PlayerWalkSpeed = playerSpeed,
        })
        if not predictionOk then
            return nil
        end
        if prediction.Outcome == "EscapedSafely" or prediction.CatchTime == nil then
            return true
        end
        return prediction.CatchTime - prediction.ExitTime >= readPing() / 1000
    end
    local function currentPing()
        for _, metric in ipairs(context.store:Get().footerMetrics or {}) do
            if metric.id == "ping" and type(metric.value) == "number" then
                return metric.value
            end
        end
        return 0
    end
    local lagSafeMovement = LagSafeMovement.new({
        canOutrun = canOutrunGuard,
        eggCmds = EggCmds,
        getPing = currentPing,
        guardConfigs = guardConfigs,
        guardModels = guardModels,
        localPlayer = LocalPlayer,
        onEscape = function()
            if navigator then
                navigator:resume()
            end
        end,
        runService = RunService,
        wakingDuration = GuardChasePolicy.GetWakingDuration(),
    })
    local resetPadding = AreaEggResetConfig.WallCountdownDelayAfterDayStartsSeconds
        + AreaEggResetConfig.WallCountdownSeconds
    local resetUntil = 0
    local now = Workspace:GetServerTimeNow()
    if Workspace:GetAttribute("Event_AdminAbuse") ~= true and AreaEggResetTimeUtil.IsNight(now) then
        resetUntil = AreaEggResetTimeUtil.GetNextResetAt(now) + resetPadding
    end
    local function resetSecondsRemaining()
        return math.max(0, resetUntil - Workspace:GetServerTimeNow())
    end
    local requestHttp = context.httpGet
        or function(url)
            local request = environment.request or environment.http_request
            if type(request) == "function" then
                local response = request({ Method = "GET", Url = url })
                assert(
                    type(response) == "table" and type(response.Body) == "string",
                    "HTTP request failed"
                )
                return response.Body
            end
            return game:HttpGet(url, true)
        end
    local serverHop = ServerHop.new({
        decode = function(source)
            return HttpService:JSONDecode(source)
        end,
        httpGet = requestHttp,
        jobId = context.jobId,
        localPlayer = LocalPlayer,
        logger = context.logger,
        maxPlayers = context.players.MaxPlayers,
        placeId = context.placeId,
        persistVisited = persistVisitedServers,
        teleportService = TeleportService,
        visitedServerIds = gameRuntime.visitedServerIds,
    })
    local resetConnection = EggCmds.AreaEggResetStartCountdown:Connect(function(payload)
        if type(payload) == "table" and type(payload.DayStartsAt) == "number" then
            resetUntil = math.max(resetUntil, payload.DayStartsAt + resetPadding)
        end
        table.clear(gameRuntime.visitedServerIds)
        gameRuntime.visitedServerIds[context.jobId] = true
        table.clear(gameRuntime.farmHistory.globalSpawns)
        persistVisitedServers()
        persistFarmHistory()
    end)
    local function treadmillBottom()
        local plot = PlotCmds.GetPlotData()
        local bottom = plot and plot.PlotFolder:FindFirstChild("TreadmillBottom")
        return bottom and bottom:IsA("BasePart") and bottom or nil
    end
    local function idleTreadmillPosition()
        local bottom = treadmillBottom()
        return bottom and bottom.Position or nil
    end
    local function isOnTreadmill()
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local bottom = treadmillBottom()
        if not root or not root:IsA("BasePart") or not bottom then
            return false
        end
        local position = bottom.CFrame:PointToObjectSpace(root.Position)
        return math.abs(position.X) <= bottom.Size.X * 0.5 + 2
            and math.abs(position.Z) <= bottom.Size.Z * 0.5 + 2
            and math.abs(position.Y) <= 8
    end
    navigator = WalkNavigator.new({
        blockedParts = { treadmillBottom() },
        localPlayer = LocalPlayer,
        pathfindingService = PathfindingService,
        runService = RunService,
        workspace = Workspace,
    })
    local autoFarm
    local autoBlossom
    local blossomSelected = false
    autoBlossom = AutoBlossom.new({
        batAttribute = Sakura.BatToolAttribute,
        canFarm = function()
            local save = Save.Get()
            return save ~= nil and save.Sakura ~= nil and save.Sakura.Unlocked == true
        end,
        collectionService = CollectionService,
        hitCooldown = Sakura.Bloom.HitCooldownSeconds,
        hitRange = Sakura.Bloom.HitRange,
        localPlayer = LocalPlayer,
        navigator = navigator,
        onWorkChanged = function(working)
            if not autoFarm then
                return
            end
            if working and autoFarm:hasPriorityTarget() then
                autoBlossom:setEnabled(false)
                autoFarm:setPaused(false)
                return
            end
            autoFarm:setPaused(working)
        end,
        treeTag = Sakura.TreeTag,
    })
    autoFarm = AutoFarm.new({
        assets = Assets,
        eggCmds = EggCmds,
        localPlayer = LocalPlayer,
        logger = context.logger,
        getEscapePosition = nativeEscapePosition,
        getIdlePosition = idleTreadmillPosition,
        getResetSeconds = resetSecondsRemaining,
        getSecuredEggs = securedEggs,
        hasMissingIndex = hasMissingIndex,
        isGlobalSpawnKnown = isGlobalSpawnKnown,
        isIndexed = isIndexed,
        isIndexPending = isIndexPending,
        isOnTreadmill = isOnTreadmill,
        leaveTreadmill = function()
            return Network.Invoke(Constants.NETWORK_MAP.Treadmills.REQUEST_UNEQUIP)
        end,
        markGlobalSpawn = markGlobalSpawn,
        navigator = navigator,
        onRareAvailable = function()
            autoBlossom:setEnabled(false)
            autoFarm:setPaused(false)
        end,
        onSecured = recordSecuredEgg,
        plotCmds = PlotCmds,
        players = context.players,
        publishStatus = function(model)
            if type(model) ~= "table" then
                context.store:Patch({ floatingMonitor = false })
                return
            end
            model.players = #context.players:GetPlayers()
            context.store:Patch({ floatingMonitor = model })
        end,
        serverHop = serverHop,
        shouldRunBlossom = function()
            if not blossomSelected or not autoBlossom:hasWork() then
                return false
            end
            autoBlossom:setEnabled(true)
            return true
        end,
        slotIdentity = SlotIdentity,
        workspace = Workspace,
    })
    local inventoryUids = {}
    for uid in pairs((Save.Get() and Save.Get().Inventory) or {}) do
        inventoryUids[uid] = true
    end
    local equipBestQueued = false
    local inventoryConnection = Save.GetStatChangedSignal("Inventory"):Connect(function()
        local nextUids = {}
        local added = false
        for uid in pairs((Save.Get() and Save.Get().Inventory) or {}) do
            nextUids[uid] = true
            added = added or inventoryUids[uid] ~= true
        end
        inventoryUids = nextUids
        if not added or equipBestQueued or stopped then
            return
        end
        equipBestQueued = true
        task.defer(function()
            if not stopped then
                pcall(Network.Invoke, Constants.NETWORK_MAP.Backpack.EQUIP_BEST)
            end
            equipBestQueued = false
        end)
    end)
    local unsubscribePing = context.subscribeFooterMetric("ping", {
        kind = "latency",
        label = "Ping",
    }, readPing)
    local function apply(state)
        local farming = state.settings.autoFarm == true
        blossomSelected = farming and state.settings.autoBlossom == true
        if gameRuntime.farmHistory.active ~= farming then
            if farming then
                table.clear(gameRuntime.farmHistory.eggs)
                table.clear(gameRuntime.farmHistory.globalSpawns)
            end
            gameRuntime.farmHistory.active = farming
            persistFarmHistory()
        end
        antiHit:setEnabled(state.settings.antiHit == true or farming)
        antiTrap:setEnabled(state.settings.antiTrap == true or farming)
        autoOpenEggs:setCompleteIndex(farming and state.settings.autoFarmIndex == true)
        autoOpenEggs:setEnabled(
            state.settings.autoOpenEggs == true
                or (farming and state.settings.autoFarmIndex == true)
        )
        highlightEsp:setAntiTrapEnabled(state.settings.antiTrap == true or farming)
        highlightEsp:setMinimumRarity(state.settings.eggEspMinimumRarity)
        highlightEsp:setMinimumSize(state.settings.eggEspMinimumSize)
        highlightEsp:setEggsEnabled(state.settings.eggEsp == true)
        highlightEsp:setTrapsEnabled(state.settings.trapEsp == true)
        hitAura:setIgnoreFriends(not farming and state.settings.hitAuraIgnoreFriends == true)
        hitAura:setEnabled(state.settings.hitAura == true or farming)
        instantPrompts:setEnabled(state.settings.instantPrompts == true)
        lagSafeMovement:setPingThreshold(state.settings.serverHopMaxPing)
        lagSafeMovement:setEnabled(
            (state.settings.antiHit == true or farming) and state.settings.lagSafeMovement == true
        )
        autoFarm:setIdleTreadmill(state.settings.idleTreadmill)
        autoFarm:setTargetRarities(state.settings.autoFarmEternal, state.settings.autoFarmSecret)
        autoFarm:setCompleteIndex(state.settings.autoFarmIndex)
        autoFarm:setServerHopping(state.settings.autoFarmServerHopping)
        autoFarm:setTargetPopulation(state.settings.serverHopTargetPopulation)
        autoFarm:setMaxPing(state.settings.serverHopMaxPing)
        autoFarm:setEnabled(farming)
        autoBlossom:setEnabled(blossomSelected and not autoFarm:hasPriorityTarget())
        if state.settings.serverHop == true then
            context.store:Patch({
                settings = {
                    serverHop = false,
                    serverHopAttempts = 0,
                    serverHopPingGuard = true,
                },
            })
            context.settingsChanged(context.store:Get().settings)
            serverHop:run(
                state.settings.serverHopMaxPing,
                nil,
                nil,
                state.settings.serverHopTargetPopulation
            )
        end
    end
    local unsubscribe = context.store:Subscribe(apply, false)
    local function stop()
        if stopped then
            return
        end
        stopped = true
        pcall(unsubscribe)
        pcall(unsubscribePing)
        pcall(resetConnection.Disconnect, resetConnection)
        pcall(inventoryConnection.Disconnect, inventoryConnection)
        pcall(antiHit.stop, antiHit)
        pcall(antiTrap.stop, antiTrap)
        pcall(autoBlossom.stop, autoBlossom)
        pcall(autoFarm.stop, autoFarm)
        pcall(autoOpenEggs.stop, autoOpenEggs)
        pcall(highlightEsp.stop, highlightEsp)
        pcall(hitAura.stop, hitAura)
        pcall(instantPrompts.stop, instantPrompts)
        pcall(lagSafeMovement.stop, lagSafeMovement)
        pcall(navigator.stop, navigator)
        pcall(serverHop.stop, serverHop)
    end
    local applied, applyError = pcall(apply, context.store:Get())
    if not applied then
        stop()
        error(applyError, 0)
    end
    task.delay(10, function()
        local settings = context.store:Get().settings
        local ping = readPing()
        if stopped then
            return
        end
        if settings.serverHopPingGuard == true then
            if ping <= settings.serverHopMaxPing then
                context.store:Patch({
                    settings = { serverHopAttempts = 0, serverHopPingGuard = false },
                })
                context.settingsChanged(context.store:Get().settings)
                return
            end
            context.store:Patch({
                notification = {
                    action = "serverHop",
                    confirmLabel = "Try Another",
                    position = "bottom-right",
                    text = ("This server settled at %.0f ms, above your %d ms limit. Hop again?"):format(
                        ping,
                        settings.serverHopMaxPing
                    ),
                    title = "High Server Ping",
                    tone = "warning",
                },
                settings = { serverHopAttempts = 0, serverHopPingGuard = false },
            })
            context.settingsChanged(context.store:Get().settings)
            return
        end
        local latestSettings = context.store:Get().settings
        if
            latestSettings.lagSafeMovement ~= true
            and latestSettings.autoFarm ~= true
            and gameRuntime.lagSafePromptServer ~= context.jobId
            and ping > latestSettings.serverHopMaxPing
        then
            gameRuntime.lagSafePromptServer = context.jobId
            context.store:Patch({
                notification = {
                    action = "lagSafeMovement",
                    confirmLabel = "Enable",
                    position = "bottom-right",
                    text = ("Ping is %.0f ms. Use safer movement while carrying eggs near fast bosses?"):format(
                        ping
                    ),
                    title = "High Ping Detected",
                    tone = "warning",
                },
            })
        end
    end)

    return {
        stop = stop,
    }
end

return Adapter
]],
        ["games/stealanegg/Presentation.lua"] = [[local Presentation = {}

function Presentation.mount(host)
    local maxPlayers = 8
    pcall(function()
        maxPlayers = math.max(1, game:GetService("Players").MaxPlayers)
    end)
    if type(host.page) == "function" then
        host:page("Tools", { order = 1 })
        host:page("Visuals", { order = 2 })
    end

    host:section("Tools", "survival", "SURVIVAL", 70)
    host:option("survival", 1, "antiHit", "Anti Hit")
    host:option("survival", 2, "lagSafeMovement", "High Ping Mode", "antiHit")
    host:option("survival", 3, "antiTrap", "Anti Trap")

    host:section("Tools", "combat", "COMBAT", 70)
    host:option("combat", 1, "hitAura", "Hit Aura")
    host:option("combat", 2, "hitAuraIgnoreFriends", "Ignore Friends", "hitAura")

    host:section("Tools", "eggs", "EGGS", 70)
    host:option("eggs", 1, "autoFarm", "Auto Farm")
    host:option("eggs", 2, "autoFarmEternal", "Eternal Eggs", "autoFarm")
    host:option("eggs", 3, "autoFarmSecret", "Secret Eggs", "autoFarm")
    host:option("eggs", 4, "autoBlossom", "Auto Blossom", "autoFarm")
    host:option("eggs", 5, "autoFarmIndex", "Complete Index", "autoFarm")
    host:option("eggs", 6, "autoFarmServerHopping", "Rare Server Hopping", "autoFarm")
    host:option("eggs", 7, "idleTreadmill", "Treadmill", "autoFarm")
    host:option("eggs", 8, "autoOpenEggs", "Auto Open Eggs")

    host:section("Tools", "server", "SERVER", 70)
    host:slider("server", "serverHopMaxPing", "Maximum Ping", {
        min = 50,
        max = 300,
        step = 10,
        unit = "ms",
    })
    host:slider("server", "serverHopTargetPopulation", "Population Preference", {
        min = 0,
        max = math.max(0, maxPlayers - 1),
        step = 1,
        unit = " players",
    })
    host:section("Tools", "serverHop", "SERVER HOP", 70)
    if type(host.button) == "function" then
        host:button("serverHop", "serverHop", "Hop to Best Connection", {
            confirm = "Leave this server and hop to the best available connection?",
            variant = "primary",
        })
    end

    host:section("Tools", "prompts", "PROMPTS", 70)
    host:option("prompts", 1, "instantPrompts", "Instant Prompts")

    host:section("Visuals", "eggRadar", "EGG RADAR", 70, false, 1, { renderEmpty = true })
    host:section("Visuals", "highlights", "HIGHLIGHTS", 70, false, 2, { treatment = "grid" })
    host:option("highlights", 1, "eggRadar", "Egg Radar")
    host:option("highlights", 2, "eggEsp", "Eggs")
    host:option("highlights", 3, "trapEsp", "Traps")
    host:section("Visuals", "eggFilters", "EGG FILTERS", 70)
    if type(host.slider) == "function" then
        host:slider("eggFilters", "eggEspMinimumRarity", "Min Rarity", {
            min = 1,
            max = 10,
            step = 1,
            parent = "eggEsp",
        })
        host:slider("eggFilters", "eggEspMinimumSize", "Min Size", {
            min = 0.5,
            max = 3,
            step = 0.1,
            unit = "x",
            parent = "eggEsp",
        })
    end
end

return Presentation
]],
        ["games/stealanegg/features/AntiHit.lua"] = [[local AntiHit = {}
AntiHit.__index = AntiHit

local RECLAIM_SECONDS = 6
local KNOCKBACK_SUPPRESSION_SECONDS = 0.35

local function disconnectAll(connections)
    for _, connection in ipairs(connections) do
        pcall(connection.Disconnect, connection)
    end
    table.clear(connections)
end

function AntiHit.new(options)
    assert(options and options.localPlayer and options.workspace and options.runService)
    assert(options.ragdoll and options.eggCmds and options.slotIdentity)
    return setmetatable({
        guardHitEndpoint = options.guardHitEndpoint,
        localPlayer = options.localPlayer,
        logger = options.logger,
        network = options.network,
        onRecovered = options.onRecovered,
        workspace = options.workspace,
        runService = options.runService,
        ragdoll = options.ragdoll,
        eggCmds = options.eggCmds,
        slotIdentity = options.slotIdentity,
        spawn = options.spawn or task.spawn,
        wait = options.wait or task.wait,
        connections = {},
        characterConnections = {},
        enabled = false,
        claimToken = 0,
        suppressKnockbackUntil = -math.huge,
    }, AntiHit)
end

function AntiHit:_log(level, message, fields)
    local logger = self.logger
    local write = logger and logger[level]
    if type(write) == "function" then
        write(logger, "stealanegg.antiHit", message, fields)
    end
end

function AntiHit:_now()
    return self.workspace:GetServerTimeNow()
end

function AntiHit:_syncCarried()
    self.carriedUid = nil
    for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
        if record.State == "Carried" and record.CarrierUserId == self.localPlayer.UserId then
            self.carriedUid = record.Uid
            return
        end
    end
end

function AntiHit:_slotKey(uid)
    if not self.slotIdentity.IsFirstAreaUid(uid) then
        return nil
    end
    local record = self.eggCmds.GetAreaEggRecord(uid)
    return record and self.slotIdentity.BuildSlotKey(record.AreaId, record.NestId) or nil
end

function AntiHit:_requestReclaim(uid)
    local slotKey = self:_slotKey(uid)
    local succeeded, carried = pcall(self.eggCmds.RequestCarryAreaEgg, uid, slotKey)
    if not succeeded then
        return false, "request-error:" .. tostring(carried)
    end
    if carried ~= true then
        return false, "request-rejected"
    end
    self.carriedUid = uid
    self.reclaimUid = nil
    self.claimToken += 1
    self.reclaimMoving = nil
    return true
end

function AntiHit:_tryReclaim(uid)
    local record = self.eggCmds.GetAreaEggRecord(uid)
    if not record then
        return false, "missing-record"
    end
    if record.State ~= "Dropped" and record.State ~= "Slot" then
        return false, "state-" .. tostring(record.State)
    end
    local character = self.localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if
        root
        and humanoid
        and typeof(record.BottomCFrame) == "CFrame"
        and (root.Position - record.BottomCFrame.Position).Magnitude > 9
    then
        self.reclaimMoving = true
        humanoid:MoveTo(record.BottomCFrame.Position)
        return false, "moving-to-drop"
    end
    return self:_requestReclaim(uid)
end

function AntiHit:_reclaim(uid)
    self.reclaimUid = uid
    self.claimToken += 1
    local token = self.claimToken
    local record = self.eggCmds.GetAreaEggRecord(uid)
    local reclaimed, reason
    if record and (record.State == "Dropped" or record.State == "Slot") then
        reclaimed, reason = self:_tryReclaim(uid)
    else
        reclaimed, reason = self:_requestReclaim(uid)
    end
    if reclaimed then
        self:_log("info", "reclaim immediate", { uid = uid })
        return
    end
    self:_log("info", "reclaim queued", { reason = reason, uid = uid })
    self.spawn(function()
        local deadline = self:_now() + RECLAIM_SECONDS
        local attempts = 0
        local lastReason = reason
        while self.enabled and token == self.claimToken and self:_now() <= deadline do
            attempts += 1
            reclaimed, lastReason = self:_tryReclaim(uid)
            if reclaimed then
                self:_log("info", "reclaim succeeded", { attempts = attempts, uid = uid })
                return
            end
            self.wait(0.1)
        end
        if token == self.claimToken then
            self.reclaimUid = nil
            self:_log("warn", "reclaim expired", {
                attempts = attempts,
                reason = lastReason,
                uid = uid,
            })
        end
    end)
end

function AntiHit:_onEggRecord(record)
    if self.enabled and self.reclaimUid and record and record.Uid == self.reclaimUid then
        if self:_tryReclaim(record.Uid) then
            self:_log("info", "reclaim succeeded", { source = "record-update", uid = record.Uid })
        end
    end
end

function AntiHit:_cancelVelocity()
    local character = self.localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local movement = humanoid and humanoid.MoveDirection * humanoid.WalkSpeed or Vector3.zero
    root.AssemblyLinearVelocity = Vector3.new(movement.X, 0, movement.Z)
    root.AssemblyAngularVelocity = Vector3.zero
end

function AntiHit:_recover()
    local character = self.localPlayer.Character
    if not character then
        return
    end
    pcall(self.ragdoll.ClearClientRagdoll, character)
    self:_cancelVelocity()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.PlatformStand = false
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
    if type(self.onRecovered) == "function" then
        pcall(self.onRecovered)
    end
end

function AntiHit:_onHit()
    if not self.enabled then
        return
    end
    self.suppressKnockbackUntil = self:_now() + KNOCKBACK_SUPPRESSION_SECONDS
    self:_log("info", "hit detected", {
        carriedUid = self.carriedUid,
        ragdollEnd = self.localPlayer:GetAttribute("RagdollEndTime"),
    })
    self:_recover()
end

function AntiHit:_onCarryState(state)
    if state.IsCarrying then
        self:_log("info", "carry acquired", { uid = state.Uid })
        self.carriedUid = state.Uid
        self.intentionalDropUid = nil
        self.reclaimUid = nil
        self.claimToken += 1
        return
    end

    local uid = state.Uid or self.carriedUid or self.reclaimUid
    self:_log("info", "carry lost", {
        intentional = uid == self.intentionalDropUid,
        uid = uid,
    })
    self.carriedUid = nil
    if uid == self.intentionalDropUid then
        self.intentionalDropUid = nil
        self.reclaimUid = nil
        self.claimToken += 1
        return
    end
    if uid then
        self:_reclaim(uid)
    end
end

function AntiHit:_bindGuardHit()
    local network = self.network
    local original = network and network.Fire
    if type(original) ~= "function" or self.guardHitEndpoint == nil then
        return
    end
    self.originalNetworkFire = original
    self.networkFire = function(endpoint, ...)
        if endpoint == self.guardHitEndpoint then
            self:_log("info", "guard hit blocked", { carriedUid = self.carriedUid })
            self:_onHit()
            return nil
        end
        return original(endpoint, ...)
    end
    network.Fire = self.networkFire
end

function AntiHit:_unbindGuardHit()
    if self.network and self.network.Fire == self.networkFire then
        self.network.Fire = self.originalNetworkFire
    end
    self.networkFire = nil
    self.originalNetworkFire = nil
end

function AntiHit:_bindDropRequest()
    local original = self.eggCmds.RequestDropAreaEgg
    if type(original) ~= "function" then
        return
    end
    self.originalDropRequest = original
    self.dropRequest = function(...)
        local uid = self.carriedUid
        self.intentionalDropUid = uid
        self.reclaimUid = nil
        self.claimToken += 1
        local results = table.pack(original(...))
        if results[1] ~= true and self.intentionalDropUid == uid then
            self.intentionalDropUid = nil
        end
        return table.unpack(results, 1, results.n)
    end
    self.eggCmds.RequestDropAreaEgg = self.dropRequest
end

function AntiHit:_unbindDropRequest()
    if self.eggCmds.RequestDropAreaEgg == self.dropRequest then
        self.eggCmds.RequestDropAreaEgg = self.originalDropRequest
    end
    self.dropRequest = nil
    self.originalDropRequest = nil
end

function AntiHit:_bindCharacter(character)
    disconnectAll(self.characterConnections)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end
    table.insert(
        self.characterConnections,
        humanoid.StateChanged:Connect(function(_, state)
            if state == Enum.HumanoidStateType.Physics then
                self:_onHit()
            end
        end)
    )
end

function AntiHit:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    self:_log("info", enabled and "enabled" or "disabled")

    if enabled then
        self:_syncCarried()
        self:_bindGuardHit()
        self:_bindDropRequest()
        table.insert(
            self.connections,
            self.runService.PostSimulation:Connect(function()
                if self:_now() <= self.suppressKnockbackUntil then
                    self:_cancelVelocity()
                end
            end)
        )
        table.insert(
            self.connections,
            self.eggCmds.AreaEggCarryStateChanged:Connect(function(state)
                if self.enabled then
                    self:_onCarryState(state)
                end
            end)
        )
        table.insert(
            self.connections,
            self.eggCmds.AreaEggUpdated:Connect(function(record)
                self:_onEggRecord(record)
            end)
        )
        table.insert(
            self.connections,
            self.localPlayer:GetAttributeChangedSignal("RagdollEndTime"):Connect(function()
                if (self.localPlayer:GetAttribute("RagdollEndTime") or 0) > self:_now() then
                    self:_onHit()
                end
            end)
        )
        table.insert(
            self.connections,
            self.localPlayer.CharacterAdded:Connect(function(character)
                self:_bindCharacter(character)
            end)
        )
        self:_bindCharacter(self.localPlayer.Character)
        return
    end

    self.claimToken += 1
    if self.reclaimMoving then
        local character = self.localPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if root and humanoid then
            humanoid:MoveTo(root.Position)
        end
        self.reclaimMoving = nil
    end
    self:_unbindGuardHit()
    self:_unbindDropRequest()
    disconnectAll(self.connections)
    disconnectAll(self.characterConnections)
    self.carriedUid = nil
    self.intentionalDropUid = nil
    self.reclaimUid = nil
    self.suppressKnockbackUntil = -math.huge
end

function AntiHit:stop()
    self:setEnabled(false)
end

return AntiHit
]],
        ["games/stealanegg/features/AntiTrap.lua"] = [[local AntiTrap = {}
AntiTrap.__index = AntiTrap

function AntiTrap.new(options)
    assert(options and options.collectionService and options.localPlayer)
    return setmetatable({
        collectionService = options.collectionService,
        localPlayer = options.localPlayer,
        connections = {},
        touched = {},
        enabled = false,
    }, AntiTrap)
end

function AntiTrap:_neutralize(trap)
    local function neutralize(instance)
        if instance:IsA("BasePart") and self.touched[instance] == nil then
            self.touched[instance] = instance.CanTouch
            instance.CanTouch = false
        end
    end
    neutralize(trap)
    for _, instance in ipairs(trap:GetDescendants()) do
        neutralize(instance)
    end
end

function AntiTrap:_bindCharacter(character)
    if self.characterConnection then
        self.characterConnection:Disconnect()
    end
    local function clear()
        if self.enabled and character:GetAttribute("IsTrapped") == true then
            character:SetAttribute("IsTrapped", false)
        end
    end
    self.characterConnection = character:GetAttributeChangedSignal("IsTrapped"):Connect(clear)
    clear()
end

function AntiTrap:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    if enabled then
        for _, trap in ipairs(self.collectionService:GetTagged("PlacedTrap")) do
            self:_neutralize(trap)
        end
        table.insert(
            self.connections,
            self.collectionService:GetInstanceAddedSignal("PlacedTrap"):Connect(function(trap)
                self:_neutralize(trap)
            end)
        )
        table.insert(
            self.connections,
            self.localPlayer.CharacterAdded:Connect(function(character)
                self:_bindCharacter(character)
            end)
        )
        if self.localPlayer.Character then
            self:_bindCharacter(self.localPlayer.Character)
        end
        return
    end

    for _, connection in ipairs(self.connections) do
        pcall(connection.Disconnect, connection)
    end
    table.clear(self.connections)
    if self.characterConnection then
        pcall(self.characterConnection.Disconnect, self.characterConnection)
        self.characterConnection = nil
    end
    for part, canTouch in pairs(self.touched) do
        if part.Parent then
            pcall(function()
                part.CanTouch = canTouch
            end)
        end
    end
    table.clear(self.touched)
end

function AntiTrap:stop()
    self:setEnabled(false)
end

return AntiTrap
]],
        ["games/stealanegg/features/AutoBlossom.lua"] = [[local AutoBlossom = {}
AutoBlossom.__index = AutoBlossom

function AutoBlossom.new(options)
    assert(options and options.collectionService and options.localPlayer and options.navigator)
    local self = setmetatable({
        batAttribute = options.batAttribute or "IsBat",
        canFarm = options.canFarm or function()
            return true
        end,
        collectionService = options.collectionService,
        hitCooldown = tonumber(options.hitCooldown) or 0.6,
        hitRange = tonumber(options.hitRange) or 10,
        localPlayer = options.localPlayer,
        navigator = options.navigator,
        onWorkChanged = options.onWorkChanged,
        spawn = options.spawn or task.spawn,
        treeTag = options.treeTag or "SakuraBloomTree",
        wait = options.wait or task.wait,
        enabled = false,
        running = false,
        working = false,
        token = 0,
    }, AutoBlossom)
    if type(self.collectionService.GetInstanceAddedSignal) == "function" then
        self.treeAddedConnection = self.collectionService
            :GetInstanceAddedSignal(self.treeTag)
            :Connect(function()
                if self.enabled then
                    self:_startRun()
                end
            end)
    end
    return self
end

function AutoBlossom:_active(token)
    return self.enabled and self.token == token
end

function AutoBlossom:_root()
    local character = self.localPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

function AutoBlossom:_nearestTree()
    local root = self:_root()
    if not root then
        return nil
    end
    local nearest
    local nearestDistance = math.huge
    for _, tree in ipairs(self.collectionService:GetTagged(self.treeTag)) do
        if tree.Parent and tree:IsA("Model") and tree.Name ~= "SakuraTreeFalling" then
            local distance = (root.Position - tree:GetPivot().Position).Magnitude
            if distance < nearestDistance then
                nearest = tree
                nearestDistance = distance
            end
        end
    end
    return nearest
end

function AutoBlossom:hasWork()
    return self.canFarm() and self:_nearestTree() ~= nil
end

function AutoBlossom:_setWorking(working)
    working = working == true
    if self.working == working then
        return
    end
    self.working = working
    if type(self.onWorkChanged) == "function" then
        self.onWorkChanged(working)
    end
end

function AutoBlossom:_equipBat()
    local character = self.localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end
    local equipped = character:FindFirstChildOfClass("Tool")
    if equipped and equipped:GetAttribute(self.batAttribute) == true then
        return true
    end
    local backpack = self.localPlayer:FindFirstChildOfClass("Backpack")
    for _, tool in ipairs(backpack and backpack:GetChildren() or {}) do
        if tool:GetAttribute(self.batAttribute) == true then
            humanoid:EquipTool(tool)
            return true
        end
    end
    return false
end

function AutoBlossom:_run(token)
    while self:_active(token) do
        if not self.canFarm() then
            self:_setWorking(false)
            return
        end
        local tree = self:_nearestTree()
        if not tree then
            self:_setWorking(false)
            return
        end
        self:_setWorking(true)
        if not self:_active(token) then
            return
        end
        self:_equipBat()
        local radius = tonumber(tree:GetAttribute("Radius")) or 0
        self.navigator:walkTo(tree:GetPivot().Position, function()
            return self:_active(token) and tree.Parent ~= nil
        end, math.max(1, radius + self.hitRange - 1))
        if self:_active(token) then
            self.wait(self.hitCooldown)
        end
    end
    self:_setWorking(false)
end

function AutoBlossom:_startRun()
    if self.running or not self.enabled then
        return
    end
    self.running = true
    local token = self.token
    self.spawn(function()
        local ok = pcall(self._run, self, token)
        self.running = false
        if not ok then
            self:_setWorking(false)
        end
    end)
end

function AutoBlossom:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        if enabled then
            self:_startRun()
        end
        return
    end
    self.enabled = enabled
    self.token += 1
    if enabled then
        self:_startRun()
    else
        self:_setWorking(false)
    end
end

function AutoBlossom:stop()
    self:setEnabled(false)
    if self.treeAddedConnection then
        pcall(self.treeAddedConnection.Disconnect, self.treeAddedConnection)
        self.treeAddedConnection = nil
    end
end

return AutoBlossom
]],
        ["games/stealanegg/features/AutoFarm.lua"] = [[local AutoFarm = {}
AutoFarm.__index = AutoFarm

local function rootPosition(localPlayer)
    local character = localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and root:IsA("BasePart") and root.Position or nil
end

local function isCarried(record)
    return record.State == "Carried" or record.State == "Claimed"
end

function AutoFarm.new(options)
    assert(options and options.assets and options.eggCmds and options.localPlayer)
    assert(options.navigator and options.plotCmds and options.serverHop and options.slotIdentity)
    local self = setmetatable({
        assets = options.assets,
        eggCmds = options.eggCmds,
        localPlayer = options.localPlayer,
        logger = options.logger,
        navigator = options.navigator,
        defer = options.defer or task.defer,
        getEscapePosition = options.getEscapePosition or function()
            return nil
        end,
        getIdlePosition = options.getIdlePosition or function()
            return nil
        end,
        getResetSeconds = options.getResetSeconds or function()
            return 0
        end,
        getSecuredEggs = options.getSecuredEggs or function()
            return {}
        end,
        hasMissingIndex = options.hasMissingIndex or function()
            return false
        end,
        isGlobalSpawnKnown = options.isGlobalSpawnKnown or function()
            return false
        end,
        isIndexed = options.isIndexed or function()
            return true
        end,
        isIndexPending = options.isIndexPending or function()
            return false
        end,
        isOnTreadmill = options.isOnTreadmill or function()
            return false
        end,
        leaveTreadmill = options.leaveTreadmill or function() end,
        markGlobalSpawn = options.markGlobalSpawn or function() end,
        onRareAvailable = options.onRareAvailable,
        onSecured = options.onSecured,
        shouldRunBlossom = options.shouldRunBlossom or function()
            return false
        end,
        plotCmds = options.plotCmds,
        players = options.players,
        publishStatus = options.publishStatus,
        serverHop = options.serverHop,
        serverHopping = true,
        slotIdentity = options.slotIdentity,
        spawn = options.spawn or task.spawn,
        wait = options.wait or task.wait,
        workspace = options.workspace or workspace,
        completeIndex = false,
        enabled = false,
        idleTreadmill = true,
        onTreadmill = false,
        paused = false,
        targetRarities = { Eternal = true, Secret = true },
        targetPopulation = 6,
        maxPing = 120,
        token = 0,
        claimed = false,
    }, AutoFarm)
    self.claimConnection = self.eggCmds.AreaEggClaimed:Connect(function(feedback)
        if feedback and feedback.AssetCategory == self.claimCategory then
            self.claimed = true
        end
    end)
    if self.eggCmds.AreaEggUpdated then
        self.eggUpdateConnection = self.eggCmds.AreaEggUpdated:Connect(function(record)
            if type(record) == "table" then
                local _, rarityName = self:_rarity(record)
                if self:_isRarityTarget(rarityName) then
                    self.markGlobalSpawn(rarityName)
                    if
                        type(self.onRareAvailable) == "function"
                        and (
                            record.State == "Slot"
                            or record.State == "Dropped"
                            or (
                                isCarried(record)
                                and record.CarrierUserId ~= self.localPlayer.UserId
                            )
                        )
                    then
                        pcall(self.onRareAvailable, record)
                    end
                end
            end
            if not self.enabled then
                self:_publish("Farm off", "Enable Auto Farm to pursue a target.")
            elseif self.waitingForEggUpdate == self.token then
                self.waitingForEggUpdate = nil
                self:_startRun()
            end
        end)
    end
    return self
end

function AutoFarm:_log(level, message, fields)
    local write = self.logger and self.logger[level]
    if type(write) == "function" then
        write(self.logger, "stealanegg.autoFarm", message, fields)
    end
end

function AutoFarm:_publish(stage, detail, targetUid)
    if type(self.publishStatus) ~= "function" then
        return
    end
    local eggs = {}
    local targets = 0
    local snapshot = self.eggCmds.GetAreaEggSnapshot()
    for _, record in ipairs(snapshot.Records) do
        local rarityNumber, rarityName = self:_rarity(record)
        local asset = self.assets.Directory[record.AssetCategory]
        local available = record.State == "Slot"
            or record.State == "Dropped"
            or (isCarried(record) and record.CarrierUserId ~= self.localPlayer.UserId)
        local indexTarget = self:_isIndexTarget(record)
        if available and (self:_isRarityTarget(rarityName) or indexTarget) then
            targets += 1
        end
        table.insert(eggs, {
            uid = record.Uid,
            name = asset and asset.DisplayName or record.AssetCategory,
            icon = asset and asset.Icon or "",
            rarity = rarityName,
            rarityColor = asset and asset.Rarity and asset.Rarity.Color
                or Color3.fromRGB(177, 188, 199),
            rarityNumber = rarityNumber,
            area = record.AreaId or "Unknown",
            size = tonumber(record.AssetScale) or 1,
            state = record.State == "Claimed" and "Contested" or record.State,
            target = record.Uid == targetUid,
            eligible = available and (self:_isRarityTarget(rarityName) or indexTarget),
            reason = indexTarget and "Missing from Index" or rarityName .. " target",
        })
    end
    table.sort(eggs, function(left, right)
        if left.target ~= right.target then
            return left.target == true
        end
        if left.rarityNumber ~= right.rarityNumber then
            return left.rarityNumber > right.rarityNumber
        end
        return left.name < right.name
    end)
    for _, egg in ipairs(eggs) do
        egg.rarityNumber = nil
    end
    self.publishStatus({
        visible = self.enabled,
        stage = stage,
        detail = detail,
        targets = targets,
        eggs = eggs,
        securedEggs = self.getSecuredEggs(),
    })
end

function AutoFarm:_active(token)
    return self.enabled and not self.paused and token == self.token
end

function AutoFarm:_rarity(record)
    local asset = self.assets.Directory[record.AssetCategory]
    local rarity = asset and asset.Rarity
    return rarity and rarity.RarityNumber or 0,
        rarity and (rarity.DisplayName or rarity._id) or "Unknown"
end

function AutoFarm:_isRarityTarget(rarityName)
    return self.targetRarities[rarityName] == true
        or (rarityName == "Divine" and (self.targetRarities.Eternal or self.targetRarities.Secret))
end

function AutoFarm:_isIndexTarget(record)
    return self.completeIndex
        and not self.isIndexed(record.AssetCategory)
        and not self.isIndexPending(record.AssetCategory)
end

function AutoFarm:_carrierRoot(record)
    if not self.players or type(self.players.GetPlayerByUserId) ~= "function" then
        return nil
    end
    local player = self.players:GetPlayerByUserId(record.CarrierUserId)
    local character = player and player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and root:IsA("BasePart") and root or nil
end

function AutoFarm:_selectTarget(mode)
    local position = rootPosition(self.localPlayer)
    local best
    for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
        if
            record.State == "Slot"
            or record.State == "Dropped"
            or (isCarried(record) and record.CarrierUserId ~= self.localPlayer.UserId)
        then
            local rarityNumber, rarityName = self:_rarity(record)
            local indexTarget = mode ~= "rare" and self:_isIndexTarget(record)
            local rareTarget = mode ~= "index" and self:_isRarityTarget(rarityName)
            if rareTarget or indexTarget then
                if rareTarget then
                    self.markGlobalSpawn(rarityName)
                end
                local carrierRoot = isCarried(record) and self:_carrierRoot(record) or nil
                local bottomCFrame = record.BottomCFrame
                local targetPosition = carrierRoot and carrierRoot.Position
                    or (typeof(bottomCFrame) == "CFrame" and bottomCFrame.Position or nil)
                local distance = position
                        and targetPosition
                        and (position - targetPosition).Magnitude
                    or math.huge
                if
                    targetPosition
                    and (
                        not best
                        or (rareTarget and not best.rareTarget)
                        or (
                            rareTarget == best.rareTarget
                            and (
                                (indexTarget and not best.indexTarget)
                                or (
                                    indexTarget == best.indexTarget
                                    and (
                                        rarityNumber > best.rarityNumber
                                        or (rarityNumber == best.rarityNumber and distance < best.distance)
                                        or (
                                            rarityNumber == best.rarityNumber
                                            and distance == best.distance
                                            and record.Uid < best.record.Uid
                                        )
                                    )
                                )
                            )
                        )
                    )
                then
                    best = {
                        distance = distance,
                        indexTarget = indexTarget,
                        rareTarget = rareTarget,
                        rarityName = rarityName,
                        rarityNumber = rarityNumber,
                        record = record,
                    }
                end
            end
        end
    end
    return best
end

function AutoFarm:_selectCarried()
    for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
        if isCarried(record) and record.CarrierUserId == self.localPlayer.UserId then
            local rarityNumber, rarityName = self:_rarity(record)
            return {
                distance = 0,
                rarityName = rarityName,
                rarityNumber = rarityNumber,
                record = record,
            }
        end
    end
    return nil
end

function AutoFarm:hasPriorityTarget()
    return self:_selectCarried() ~= nil or self:_selectTarget("rare") ~= nil
end

function AutoFarm:_pursueCarrier(record, token)
    local deadline = self.workspace:GetServerTimeNow() + 30
    while self:_active(token) and self.workspace:GetServerTimeNow() <= deadline do
        local current = self.eggCmds.GetAreaEggRecord(record.Uid)
        if not current then
            return nil, "egg-removed"
        end
        if current.CarrierUserId == self.localPlayer.UserId or not isCarried(current) then
            return current
        end
        local carrierRoot = self:_carrierRoot(current)
        if not carrierRoot then
            return nil, "carrier-unavailable"
        end
        self:_publish(
            "Contesting carrier",
            "Staying close so Hit Aura can force a drop, then taking the egg.",
            current.Uid
        )
        self.navigator:walkTo(carrierRoot.Position, function()
            local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
            return self:_active(token)
                and latest ~= nil
                and isCarried(latest)
                and latest.CarrierUserId ~= self.localPlayer.UserId
        end, 12)
        self.wait(0.1)
    end
    return nil, self:_active(token) and "pursuit-timeout" or "cancelled"
end

function AutoFarm:_slotKey(record)
    if self.slotIdentity.IsFirstAreaUid(record.Uid) then
        return self.slotIdentity.BuildSlotKey(record.AreaId, record.NestId)
    end
    return nil
end

function AutoFarm:_claim(record, token)
    local deadline = self.workspace:GetServerTimeNow() + 5
    repeat
        local current = self.eggCmds.GetAreaEggRecord(record.Uid)
        if not current then
            return false, "egg-removed"
        end
        if current.State == "Carried" and current.CarrierUserId == self.localPlayer.UserId then
            return true
        end
        if current.State == "Slot" or current.State == "Dropped" then
            local position = rootPosition(self.localPlayer)
            if not position or (position - current.BottomCFrame.Position).Magnitude > 10 then
                return false, "egg-moved"
            end
            local escapePosition = self.getEscapePosition(current)
            if typeof(escapePosition) == "Vector3" then
                self.defer(function()
                    if self:_active(token) then
                        self.navigator:headToward(escapePosition)
                    end
                end)
            end
            local ok, carried, carryReason =
                pcall(self.eggCmds.RequestCarryAreaEgg, current.Uid, self:_slotKey(current))
            if ok and carried == true then
                return true
            end
            if ok and carryReason == "Get closer to the egg" then
                self.navigator:moveToDirect(current.BottomCFrame.Position, function()
                    local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
                    return self:_active(token)
                        and latest ~= nil
                        and (latest.State == "Slot" or latest.State == "Dropped")
                end, 1)
            end
        end
        self.wait(0.25)
    until not self:_active(token) or self.workspace:GetServerTimeNow() > deadline
    return false, self:_active(token) and "claim-timeout" or "cancelled"
end

function AutoFarm:_homePosition()
    local respawn = self.plotCmds.GetRespawnPointCFrame()
    if typeof(respawn) ~= "CFrame" then
        local plot = self.plotCmds.GetPlotData()
        respawn = plot and plot.RespawnPointCFrame or nil
    end
    local objects = type(self.workspace.FindFirstChild) == "function"
            and self.workspace:FindFirstChild("__OBJECTS")
        or nil
    local areas = objects and objects:FindFirstChild("Areas")
    local line = areas and areas:FindFirstChild("SeparationLine")
    if typeof(respawn) == "CFrame" and line and line:IsA("BasePart") then
        local offset = Vector3.new(
            respawn.Position.X - line.Position.X,
            0,
            respawn.Position.Z - line.Position.Z
        )
        if offset.Magnitude > 0 then
            return Vector3.new(line.Position.X, respawn.Position.Y, line.Position.Z)
                + offset.Unit * 18
        end
    end
    return typeof(respawn) == "CFrame" and respawn.Position or nil
end

function AutoFarm:_leaveTreadmill()
    if not self.onTreadmill and not self.isOnTreadmill() then
        return
    end
    self.onTreadmill = false
    pcall(self.leaveTreadmill)
    if type(self.navigator.jump) == "function" then
        self.navigator:jump()
        self.wait(0.1)
    end
end

function AutoFarm:_idleOnTreadmill(token)
    if not self.idleTreadmill or self.onTreadmill or self:_selectCarried() then
        return
    end
    local position = self.getIdlePosition()
    if typeof(position) ~= "Vector3" then
        return
    end
    self:_publish("Training while idle", "No farm action is ready. Walking onto your treadmill.")
    if type(self.navigator.jump) == "function" then
        self.navigator:jump()
    end
    local reached = self.navigator:moveToDirect(position, function()
        return self:_active(token) and self:_selectCarried() == nil
    end, 4)
    self.onTreadmill = reached == true
end

function AutoFarm:_waitForClaim(uid, token)
    local deadline = self.workspace:GetServerTimeNow() + 10
    while self:_active(token) and self.workspace:GetServerTimeNow() <= deadline do
        if self.eggCmds.GetAreaEggRecord(uid) == nil then
            return true
        end
        self.wait(0.1)
    end
    return false
end

function AutoFarm:_waitForReset(token)
    local remaining = math.max(0, tonumber(self.getResetSeconds()) or 0)
    if remaining > 0 then
        self:_idleOnTreadmill(token)
    end
    while self:_active(token) and remaining > 0 do
        self:_publish(
            "Reset in progress",
            ("Eggs are refreshing globally. Waiting %d seconds before scanning or hopping."):format(
                math.ceil(remaining)
            )
        )
        self.wait(math.min(1, remaining))
        remaining = math.max(0, tonumber(self.getResetSeconds()) or 0)
    end
    return self:_active(token)
end

function AutoFarm:_hop(token)
    if self:_selectCarried() or self:_selectTarget("rare") then
        self:_startRun()
        return
    end
    if self.shouldRunBlossom() then
        return
    end
    if self:_selectTarget("index") then
        self:_startRun()
        return
    end
    if (tonumber(self.getResetSeconds()) or 0) > 0 then
        self.spawn(function()
            self:_run(token)
        end)
        return
    end
    local indexTargetsRemain = self.completeIndex and self.hasMissingIndex()
    local rareSpawnKnown = (self.targetRarities.Eternal and self.isGlobalSpawnKnown("Eternal"))
        or (self.targetRarities.Secret and self.isGlobalSpawnKnown("Secret"))
    if not indexTargetsRemain and not rareSpawnKnown then
        self:_idleOnTreadmill(token)
        self.waitingForEggUpdate = token
        self:_publish(
            "Waiting for global spawn",
            "No selected global egg spawn has been observed yet. Staying in this server."
        )
        return
    end
    local mayHop = rareSpawnKnown and self.serverHopping
    if not mayHop then
        self:_idleOnTreadmill(token)
        self.waitingForEggUpdate = token
        self:_publish(
            "Waiting for targets",
            "No selected egg is available here. Waiting for the server egg state to change."
        )
        return
    end
    self.serverHop:run(self.maxPing, function(succeeded)
        if succeeded or not self:_active(token) then
            return
        end
        self:_publish(
            "Waiting to retry",
            "No eligible server answered yet. Trying again in 5 seconds."
        )
        self.spawn(function()
            self.wait(5)
            if self:_active(token) then
                self:_run(token)
            end
        end)
    end, function()
        return self:_active(token) and (tonumber(self.getResetSeconds()) or 0) <= 0
    end, self.targetPopulation)
end

function AutoFarm:_run(token)
    if not self:_active(token) or not self:_waitForReset(token) then
        return
    end
    pcall(self.eggCmds.RequestAreaEggSnapshot)
    self:_publish("Scanning server", "Checking every egg against your selected priorities.")
    local target = self:_selectCarried()
    local alreadyCarried = target ~= nil
    if not target then
        target = self:_selectTarget("rare")
    end
    if not target and self.shouldRunBlossom() then
        self:_publish(
            "Auto Blossom",
            "No Divine, Eternal, or Secret egg is ready. Farming Great Bloom before Index eggs."
        )
        return
    end
    if not target then
        target = self:_selectTarget("index")
    end
    if not target then
        self:_log("info", "no matching egg; hopping", {
            eternal = self.targetRarities.Eternal,
            secret = self.targetRarities.Secret,
        })
        self:_publish(
            "Finding another server",
            "No selected rarity spawned here. Requesting another server."
        )
        self:_hop(token)
        return
    end

    self:_leaveTreadmill()
    local record = target.record
    self.claimCategory = record.AssetCategory
    if not alreadyCarried and isCarried(record) then
        local pursued, pursuitReason = self:_pursueCarrier(record, token)
        if not pursued then
            self:_log("warn", "carrier pursuit ended", {
                reason = pursuitReason,
                uid = record.Uid,
            })
            if self:_active(token) then
                self:_hop(token)
            end
            return
        end
        record = pursued
        alreadyCarried = record.CarrierUserId == self.localPlayer.UserId
    end
    if not alreadyCarried then
        self:_log("info", "target selected", {
            area = record.AreaId,
            category = record.AssetCategory,
            rarity = target.rarityName,
            uid = record.Uid,
        })
        self:_publish(
            "Walking to target",
            ("%s %s · %s"):format(target.rarityName, record.AssetCategory, record.AreaId),
            record.Uid
        )
        local function targetAvailable()
            local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
            return self:_active(token)
                and latest ~= nil
                and (latest.State == "Slot" or latest.State == "Dropped")
        end
        local reached, reason =
            self.navigator:walkTo(record.BottomCFrame.Position, targetAvailable, 2)
        if not reached and reason == "timeout" and targetAvailable() then
            reached, reason =
                self.navigator:moveToDirect(record.BottomCFrame.Position, targetAvailable, 2)
        end
        if not reached then
            local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
            if
                self:_active(token)
                and (latest == nil or (latest.State ~= "Slot" and latest.State ~= "Dropped"))
            then
                self:_startRun()
                return
            end
            self:_log("warn", "target walk failed", { reason = reason, uid = record.Uid })
            self:_publish(
                "Rebuilding route",
                "The target path was blocked. Retrying inside this server.",
                record.Uid
            )
            self.wait(1)
            if self:_active(token) then
                self:_startRun()
            end
            return
        end

        self:_publish(
            "Claiming egg",
            "In pickup range. Waiting for the server to confirm carry.",
            record.Uid
        )
        local carried, carryReason = self:_claim(record, token)
        if not carried then
            self:_log("warn", "claim failed", { reason = carryReason, uid = record.Uid })
            if self:_active(token) then
                self:_hop(token)
            end
            return
        end
    end

    self:_publish(
        "Returning with egg",
        "Walking to the safe boundary and avoiding the treadmill.",
        record.Uid
    )
    local secured = false
    local escaped = false
    while self:_active(token) and not secured do
        local crossedEscape = false
        local escape = not escaped and self.getEscapePosition(record) or nil
        local home = escape or self:_homePosition()
        if home then
            self.claimed = false
            local navigate = escape and self.navigator.moveToDirect or self.navigator.walkTo
            local returned, returnReason = navigate(self.navigator, home, function()
                local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
                return self:_active(token)
                    and not self.claimed
                    and latest ~= nil
                    and latest.State == "Carried"
                    and latest.CarrierUserId == self.localPlayer.UserId
            end, 8)
            if returned and escape then
                escaped = true
                crossedEscape = true
            elseif returned or self.claimed then
                secured = self:_waitForClaim(record.Uid, token)
            else
                local latest = self.eggCmds.GetAreaEggRecord(record.Uid)
                if not latest then
                    secured = true
                elseif latest.State == "Slot" or latest.State == "Dropped" then
                    self:_publish(
                        "Recovering egg",
                        "The boss interrupted the return. Reclaiming the same egg immediately.",
                        record.Uid
                    )
                    self:_startRun()
                    return
                elseif
                    latest.State ~= "Carried"
                    or latest.CarrierUserId ~= self.localPlayer.UserId
                then
                    self.waitingForEggUpdate = token
                    self:_publish(
                        "Tracking boss",
                        "Waiting for the same egg to leave the boss, then reclaiming it.",
                        record.Uid
                    )
                    return
                else
                    self:_log("warn", "return walk failed", {
                        reason = returnReason,
                        uid = record.Uid,
                    })
                    self:_publish(
                        "Retrying return",
                        "The route stalled. Rebuilding the safe path without dropping the egg.",
                        record.Uid
                    )
                end
            end
        else
            self:_log("warn", "home unavailable; retrying", { uid = record.Uid })
            self:_publish(
                "Waiting for base",
                "Base data is still loading. The carried egg stays prioritized.",
                record.Uid
            )
        end
        if not secured and not crossedEscape then
            self.wait(2)
        end
    end
    if not secured then
        return
    end

    self:_log("info", "egg secured; rescanning", { uid = record.Uid })
    if type(self.onSecured) == "function" then
        pcall(self.onSecured, record)
    end
    self:_publish("Egg secured", "Deposit confirmed. Checking this server for another target.")
    self.wait(1)
    if self:_active(token) then
        self:_startRun()
    end
end

function AutoFarm:_startRun()
    local token = self.token
    self.spawn(function()
        local ok, err = pcall(self._run, self, token)
        if not ok then
            self:_log("error", "run failed", { error = err })
        end
    end)
end

function AutoFarm:setPaused(paused)
    paused = paused == true
    if self.paused == paused then
        return
    end
    self.paused = paused
    self.token += 1
    self.waitingForEggUpdate = nil
    if paused then
        self:_leaveTreadmill()
        self:_publish(
            "Auto Blossom",
            "Rare eggs are clear. Great Bloom has priority before Index farming."
        )
    elseif self.enabled then
        self:_startRun()
    end
end

function AutoFarm:setCompleteIndex(enabled)
    enabled = enabled == true
    if self.completeIndex == enabled then
        return
    end
    self.completeIndex = enabled
    if self.enabled then
        self.token += 1
        self:_startRun()
    end
end

function AutoFarm:setTargetRarities(eternal, secret)
    eternal = eternal == true
    secret = secret == true
    if self.targetRarities.Eternal == eternal and self.targetRarities.Secret == secret then
        return
    end
    self.targetRarities.Eternal = eternal
    self.targetRarities.Secret = secret
    if self.enabled then
        self.token += 1
        self:_startRun()
    end
end

function AutoFarm:setTargetPopulation(value)
    self.targetPopulation = math.max(0, tonumber(value) or 6)
end

function AutoFarm:setIdleTreadmill(enabled)
    enabled = enabled == true
    if self.idleTreadmill == enabled then
        return
    end
    self.idleTreadmill = enabled
    if not enabled then
        self:_leaveTreadmill()
    end
    if self.enabled then
        self.token += 1
        self.waitingForEggUpdate = nil
        self:_startRun()
    end
end

function AutoFarm:setServerHopping(enabled)
    enabled = enabled == true
    if self.serverHopping == enabled then
        return
    end
    self.serverHopping = enabled
    if self.enabled then
        self.token += 1
        self.waitingForEggUpdate = nil
        self:_startRun()
    end
end

function AutoFarm:setMaxPing(value)
    self.maxPing = math.max(1, tonumber(value) or 120)
end

function AutoFarm:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    if not enabled then
        self.paused = false
    end
    self.token += 1
    self.waitingForEggUpdate = nil
    if not enabled then
        self:_leaveTreadmill()
    end
    self:_log("info", enabled and "enabled" or "disabled")
    if enabled then
        self:_publish("Starting", "Reading the current server and preparing the farm.")
        self:_startRun()
    elseif type(self.publishStatus) == "function" then
        self.publishStatus(false)
    end
end

function AutoFarm:stop()
    self.enabled = false
    self.paused = false
    self.token += 1
    self:_leaveTreadmill()
    if type(self.publishStatus) == "function" then
        self.publishStatus(false)
    end
    if self.claimConnection then
        pcall(self.claimConnection.Disconnect, self.claimConnection)
        self.claimConnection = nil
    end
    if self.eggUpdateConnection then
        pcall(self.eggUpdateConnection.Disconnect, self.eggUpdateConnection)
        self.eggUpdateConnection = nil
    end
end

return AutoFarm
]],
        ["games/stealanegg/features/AutoOpenEggs.lua"] = [[local AutoOpenEggs = {}
AutoOpenEggs.__index = AutoOpenEggs

local SCAN_INTERVAL = 0.25

function AutoOpenEggs.new(options)
    assert(
        options
            and options.eggCmds
            and options.renderer
            and options.localPlayer
            and options.runService
    )
    return setmetatable({
        eggCmds = options.eggCmds,
        renderer = options.renderer,
        localPlayer = options.localPlayer,
        plotCmds = options.plotCmds,
        runService = options.runService,
        isIndexed = options.isIndexed or function()
            return true
        end,
        spawn = options.spawn or task.spawn,
        opening = {},
        placing = {},
        completeIndex = false,
        elapsed = 0,
        enabled = false,
    }, AutoOpenEggs)
end

local function category(record)
    return record.Item and record.Item.Category or record.AssetCategory
end

function AutoOpenEggs:_findPlacement(records)
    local plot = self.plotCmds and self.plotCmds.GetPlotData()
    if not plot then
        return nil
    end
    local occupied = {}
    for _, record in pairs(records) do
        local placement = record.Placement
        if placement and typeof(placement.LocalCFrame) == "CFrame" then
            table.insert(occupied, placement.LocalCFrame.Position)
        end
    end
    local half = plot.PetArea.Size * 0.5
    for x = -half.X + 5, half.X - 5, 10 do
        for z = -half.Z + 5, half.Z - 5, 10 do
            local world = plot.PetArea.CFrame:PointToWorldSpace(Vector3.new(x, half.Y, z))
            local localCFrame = plot.CenterPoint.CFrame:ToObjectSpace(CFrame.new(world))
            local clear = true
            for _, position in ipairs(occupied) do
                if (position - localCFrame.Position).Magnitude < 8 then
                    clear = false
                    break
                end
            end
            if clear then
                return localCFrame
            end
        end
    end
    return nil
end

function AutoOpenEggs:_scan()
    local records = self.eggCmds.GetOwnerRuntimeRecords(self.localPlayer.UserId)
    for uid in pairs(self.opening) do
        if not records[uid] or not self.eggCmds.IsLocalEggReady(uid) then
            self.opening[uid] = nil
        end
    end
    for uid in pairs(self.placing) do
        if not records[uid] or records[uid].Placement then
            self.placing[uid] = nil
        end
    end
    if self.completeIndex then
        local placementUid
        for uid, record in pairs(records) do
            local assetCategory = category(record)
            if not record.Placement and not self.placing[uid] and assetCategory then
                placementUid = placementUid or uid
                if not self.isIndexed(assetCategory) then
                    placementUid = uid
                    break
                end
            end
        end
        if placementUid then
            local placement = self:_findPlacement(records)
            if placement then
                self.placing[placementUid] = true
                self.spawn(function()
                    if not self.enabled or not self.completeIndex then
                        return
                    end
                    local placed = self.eggCmds.RequestPlaceEgg(placementUid, placement)
                    if placed then
                        if type(self.renderer.Refresh) == "function" then
                            self.renderer.Refresh()
                        end
                    else
                        self.placing[placementUid] = nil
                    end
                end)
            end
        end
    end
    for uid, record in pairs(records) do
        if record.Placement and self.eggCmds.IsLocalEggReady(uid) and not self.opening[uid] then
            self.opening[uid] = true
            self.spawn(function()
                if not self.enabled then
                    return
                end
                if not self.renderer.ActivateLocalEgg(uid) then
                    self.opening[uid] = nil
                end
            end)
        end
    end
end

function AutoOpenEggs:setCompleteIndex(enabled)
    self.completeIndex = enabled == true
    if self.enabled then
        self:_scan()
    end
end

function AutoOpenEggs:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    if enabled then
        self:_scan()
        self.connection = self.runService.Heartbeat:Connect(function(deltaTime)
            self.elapsed += deltaTime
            if self.elapsed >= SCAN_INTERVAL then
                self.elapsed = 0
                self:_scan()
            end
        end)
        return
    end
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
    table.clear(self.opening)
    table.clear(self.placing)
    self.elapsed = 0
end

function AutoOpenEggs:stop()
    self:setEnabled(false)
end

return AutoOpenEggs
]],
        ["games/stealanegg/features/HighlightEsp.lua"] = [[local HighlightEsp = {}
HighlightEsp.__index = HighlightEsp

local function updateLabelMap(labels, cameraPosition)
    for _, entry in pairs(labels) do
        local adornee = entry.billboard.Adornee
        if adornee and adornee.Parent then
            local distance = (cameraPosition - adornee.Position).Magnitude
            local proximityBoost = math.clamp((180 - distance) / 15, 0, 12)
            local textSize = math.clamp(entry.baseSize + proximityBoost, 16, 30)
            entry.label.TextSize = textSize
            if entry.icon then
                local iconSize = textSize + 2
                entry.icon.Size = UDim2.fromOffset(iconSize, iconSize)
                entry.label.Position = UDim2.fromOffset(iconSize + 6, 0)
                entry.label.Size = UDim2.new(1, -(iconSize + 6), 1, 0)
            end
        end
    end
end

function HighlightEsp.new(options)
    assert(
        options
            and options.assets
            and options.collectionService
            and options.eggCmds
            and options.localPlayer
            and options.runService
            and options.workspace
    )
    local self = setmetatable({
        assets = options.assets,
        collectionService = options.collectionService,
        eggCmds = options.eggCmds,
        localPlayer = options.localPlayer,
        runService = options.runService,
        workspace = options.workspace,
        createHighlight = options.createHighlight or function()
            return Instance.new("Highlight")
        end,
        createLabel = options.createLabel or function(target)
            local adornee = target:IsA("BasePart") and target
                or target.PrimaryPart
                or target:FindFirstChildWhichIsA("BasePart", true)
            if not adornee then
                return nil
            end
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "UniversalHubEspLabel"
            billboard.Adornee = adornee
            billboard.AlwaysOnTop = true
            billboard.MaxDistance = 600
            billboard.Size = UDim2.fromOffset(220, 64)
            billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
            billboard.Parent = target
            local label = Instance.new("TextLabel")
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.GothamBold
            label.Position = UDim2.fromOffset(28, 0)
            label.Size = UDim2.new(1, -28, 1, 0)
            label.TextScaled = false
            label.TextSize = 14
            label.TextStrokeTransparency = 0.25
            label.TextWrapped = true
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Parent = billboard
            local icon = Instance.new("ImageLabel")
            icon.BackgroundTransparency = 1
            icon.Position = UDim2.fromOffset(2, 4)
            icon.ScaleType = Enum.ScaleType.Fit
            icon.Size = UDim2.fromOffset(22, 22)
            icon.Parent = billboard
            return billboard, label, icon
        end,
        depthMode = options.depthMode or Enum.HighlightDepthMode.AlwaysOnTop,
        outlineColor = options.outlineColor or Color3.new(1, 1, 1),
        trapColor = options.trapColor or Color3.fromRGB(255, 70, 70),
        trapIcon = options.trapIcon,
        safeTrapColor = options.safeTrapColor or Color3.fromRGB(80, 220, 120),
        antiTrapEnabled = false,
        eggHighlights = {},
        eggLabels = {},
        trapHighlights = {},
        trapLabels = {},
        eggConnections = {},
        trapConnections = {},
        minimumRarity = 1,
        minimumSize = 0.5,
        labelElapsed = 0,
        eggsEnabled = false,
        trapsEnabled = false,
    }, HighlightEsp)
    self.heartbeatConnection = options.runService.Heartbeat:Connect(function(elapsed)
        self:_updateLabelSizes(elapsed)
    end)
    return self
end

function HighlightEsp:_updateLabelSizes(elapsed)
    self.labelElapsed += elapsed or 0
    if self.labelElapsed < 0.1 then
        return
    end
    self.labelElapsed = 0
    local camera = self.workspace.CurrentCamera
    if camera then
        local cameraPosition = camera.CFrame.Position
        updateLabelMap(self.eggLabels, cameraPosition)
        updateLabelMap(self.trapLabels, cameraPosition)
    end
end

function HighlightEsp:_destroy(map, key, labels)
    local highlight = map[key]
    map[key] = nil
    if highlight then
        pcall(highlight.Destroy, highlight)
    end
    local entry = labels and labels[key]
    if entry then
        labels[key] = nil
        pcall(entry.billboard.Destroy, entry.billboard)
    end
end

function HighlightEsp:_highlight(map, key, target, color, name)
    local highlight = map[key]
    if not highlight then
        highlight = self.createHighlight()
        highlight.Name = name
        highlight.DepthMode = self.depthMode
        highlight.FillTransparency = 0.55
        highlight.OutlineTransparency = 0
        highlight.OutlineColor = self.outlineColor
        highlight.Adornee = target
        highlight.Parent = target
        map[key] = highlight
    end
    highlight.FillColor = color
end

function HighlightEsp:_label(map, key, target, text, color, textSize, iconImage)
    local entry = map[key]
    if not entry then
        local billboard, label, icon = self.createLabel(target)
        if not billboard then
            return
        end
        entry = { billboard = billboard, label = label, icon = icon }
        map[key] = entry
    end
    if entry.icon then
        entry.icon.Image = iconImage or ""
        entry.icon.Visible = iconImage ~= nil
    end
    entry.baseSize = textSize or 14
    entry.label.Text = text
    entry.label.TextColor3 = color
    entry.label.TextSize = math.max(entry.baseSize, 16)
end

function HighlightEsp:_refreshEgg(uid)
    if not self.eggsEnabled then
        self:_destroy(self.eggHighlights, uid, self.eggLabels)
        return
    end
    local model = self.workspace:FindFirstChild(uid, true)
    local record = self.eggCmds.GetAreaEggRecord(uid)
    local asset = record and self.assets.Directory[record.AssetCategory]
    local rarity = asset and asset.Rarity
    if
        not model
        or not rarity
        or (rarity.RarityNumber or 0) < self.minimumRarity
        or (record.AssetScale or 0) < self.minimumSize
    then
        self:_destroy(self.eggHighlights, uid, self.eggLabels)
        return
    end
    self:_highlight(self.eggHighlights, uid, model, rarity.Color, "UniversalHubEggHighlight")
    self:_label(
        self.eggLabels,
        uid,
        model,
        ("%s\n%s • %.1fx"):format(
            tostring(record.AssetCategory),
            tostring(rarity.DisplayName or rarity._id or "Egg"),
            record.AssetScale
        ),
        rarity.Color,
        math.clamp(12 + record.AssetScale * 3, 14, 22),
        asset.Egg and asset.Egg.Icon or asset.Icon
    )
end

function HighlightEsp:_refreshEggs()
    local present = {}
    for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
        present[record.Uid] = true
        self:_refreshEgg(record.Uid)
    end
    for uid in pairs(self.eggHighlights) do
        if not present[uid] then
            self:_destroy(self.eggHighlights, uid, self.eggLabels)
        end
    end
end

function HighlightEsp:setEggsEnabled(enabled)
    enabled = enabled == true
    if self.eggsEnabled == enabled then
        return
    end
    self.eggsEnabled = enabled
    if enabled then
        table.insert(
            self.eggConnections,
            self.workspace.DescendantAdded:Connect(function(instance)
                if self.eggCmds.GetAreaEggRecord(instance.Name) then
                    self:_refreshEgg(instance.Name)
                end
            end)
        )
        table.insert(
            self.eggConnections,
            self.workspace.DescendantRemoving:Connect(function(instance)
                local highlight = self.eggHighlights[instance.Name]
                if highlight and highlight.Adornee == instance then
                    self:_destroy(self.eggHighlights, instance.Name, self.eggLabels)
                end
            end)
        )
        table.insert(
            self.eggConnections,
            self.eggCmds.AreaEggUpdated:Connect(function(record)
                self:_refreshEgg(record.Uid)
            end)
        )
        self:_refreshEggs()
        return
    end
    for _, connection in ipairs(self.eggConnections) do
        pcall(connection.Disconnect, connection)
    end
    table.clear(self.eggConnections)
    for uid in pairs(self.eggHighlights) do
        self:_destroy(self.eggHighlights, uid, self.eggLabels)
    end
end

function HighlightEsp:setMinimumRarity(value)
    value = math.clamp(tonumber(value) or 1, 1, 10)
    if self.minimumRarity ~= value then
        self.minimumRarity = value
        self:_refreshEggs()
    end
end

function HighlightEsp:setMinimumSize(value)
    value = math.clamp(tonumber(value) or 0.5, 0.5, 3)
    if self.minimumSize ~= value then
        self.minimumSize = value
        self:_refreshEggs()
    end
end

function HighlightEsp:_refreshTrap(trap)
    if self.trapsEnabled then
        local owner = trap:GetAttribute("Owner")
        local color = (self.antiTrapEnabled or owner == self.localPlayer.Name)
                and self.safeTrapColor
            or self.trapColor
        self:_highlight(self.trapHighlights, trap, trap, color, "UniversalHubTrapHighlight")
        self:_label(
            self.trapLabels,
            trap,
            trap,
            owner and ("Trap\n%s"):format(tostring(owner)) or "Trap",
            color,
            nil,
            self.trapIcon
        )
    else
        self:_destroy(self.trapHighlights, trap, self.trapLabels)
    end
end

function HighlightEsp:setAntiTrapEnabled(enabled)
    enabled = enabled == true
    if self.antiTrapEnabled ~= enabled then
        self.antiTrapEnabled = enabled
        for _, trap in ipairs(self.collectionService:GetTagged("PlacedTrap")) do
            self:_refreshTrap(trap)
        end
    end
end

function HighlightEsp:setTrapsEnabled(enabled)
    enabled = enabled == true
    if self.trapsEnabled == enabled then
        return
    end
    self.trapsEnabled = enabled
    if enabled then
        for _, trap in ipairs(self.collectionService:GetTagged("PlacedTrap")) do
            self:_refreshTrap(trap)
        end
        table.insert(
            self.trapConnections,
            self.collectionService:GetInstanceAddedSignal("PlacedTrap"):Connect(function(trap)
                self:_refreshTrap(trap)
            end)
        )
        table.insert(
            self.trapConnections,
            self.collectionService:GetInstanceRemovedSignal("PlacedTrap"):Connect(function(trap)
                self:_destroy(self.trapHighlights, trap, self.trapLabels)
            end)
        )
        return
    end
    for _, connection in ipairs(self.trapConnections) do
        pcall(connection.Disconnect, connection)
    end
    table.clear(self.trapConnections)
    for trap in pairs(self.trapHighlights) do
        self:_destroy(self.trapHighlights, trap, self.trapLabels)
    end
end

function HighlightEsp:stop()
    self:setEggsEnabled(false)
    self:setTrapsEnabled(false)
    if self.heartbeatConnection then
        pcall(self.heartbeatConnection.Disconnect, self.heartbeatConnection)
        self.heartbeatConnection = nil
    end
end

return HighlightEsp
]],
        ["games/stealanegg/features/HitAura.lua"] = [[local HitAura = {}
HitAura.__index = HitAura

local COOLDOWN = 0.6
local RANGE = 17

function HitAura.new(options)
    assert(options and options.eggCmds and options.localPlayer and options.network)
    assert(options.players and options.runService and options.workspace and options.endpoint)
    return setmetatable({
        eggCmds = options.eggCmds,
        endpoint = options.endpoint,
        localPlayer = options.localPlayer,
        network = options.network,
        players = options.players,
        runService = options.runService,
        workspace = options.workspace,
        enabled = false,
        friendCache = {},
        ignoreFriends = true,
        lastHitAt = -math.huge,
        sequence = 0,
    }, HitAura)
end

function HitAura:_equippedBat()
    local character = self.localPlayer.Character
    if not character then
        return nil
    end
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") and child:GetAttribute("IsBat") == true then
            return child
        end
    end
    return nil
end

function HitAura:_isFriend(player)
    local cached = self.friendCache[player.UserId]
    if cached == nil then
        local succeeded, result =
            pcall(self.localPlayer.IsFriendsWith, self.localPlayer, player.UserId)
        cached = not succeeded or result == true
        self.friendCache[player.UserId] = cached
    end
    return cached
end

function HitAura:_target()
    local carriers = {}
    for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
        if record.State == "Carried" and record.CarrierUserId then
            carriers[record.CarrierUserId] = true
        end
    end
    local character = self.localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return nil
    end
    local closest
    local closestDistance = RANGE
    for _, player in ipairs(self.players:GetPlayers()) do
        if player ~= self.localPlayer and carriers[player.UserId] then
            local targetCharacter = player.Character
            local targetRoot = targetCharacter
                and targetCharacter:FindFirstChild("HumanoidRootPart")
            local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
            local distance = targetRoot and (targetRoot.Position - root.Position).Magnitude
                or math.huge
            if humanoid and humanoid.Health > 0 and distance <= closestDistance then
                if not self.ignoreFriends or not self:_isFriend(player) then
                    closest = player
                    closestDistance = distance
                end
            end
        end
    end
    return closest
end

function HitAura:_step()
    if not self.enabled or not self:_equippedBat() then
        return
    end
    local now = self.workspace:GetServerTimeNow()
    if now - self.lastHitAt < COOLDOWN then
        return
    end
    local target = self:_target()
    if not target then
        return
    end
    self.lastHitAt = now
    self.sequence += 1
    local traceId = ("%s:%s:%s"):format(
        self.localPlayer.UserId,
        self.sequence,
        math.floor(now * 1000)
    )
    self.network.Fire(self.endpoint, target, traceId)
end

function HitAura:setIgnoreFriends(enabled)
    self.ignoreFriends = enabled == true
end

function HitAura:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    if enabled then
        self.connection = self.runService.Heartbeat:Connect(function()
            self:_step()
        end)
        return
    end
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
end

function HitAura:stop()
    self:setEnabled(false)
end

return HitAura
]],
        ["games/stealanegg/features/InstantPrompts.lua"] = [[local InstantPrompts = {}
InstantPrompts.__index = InstantPrompts

function InstantPrompts.new(root)
    assert(root, "Instant Prompts requires a root instance")
    return setmetatable({
        root = root,
        entries = {},
        enabled = false,
    }, InstantPrompts)
end

function InstantPrompts:_apply(instance)
    if not self.enabled or not instance:IsA("ProximityPrompt") then
        return
    end

    local entry = self.entries[instance]
    if not entry then
        entry = {
            original = instance.HoldDuration,
        }
        self.entries[instance] = entry
        entry.connection = instance:GetPropertyChangedSignal("HoldDuration"):Connect(function()
            if not self.enabled or instance.HoldDuration == 0 then
                return
            end
            entry.original = instance.HoldDuration
            instance.HoldDuration = 0
        end)
    end
    instance.HoldDuration = 0
end

function InstantPrompts:_forget(instance)
    local entry = self.entries[instance]
    if not entry then
        return
    end
    pcall(entry.connection.Disconnect, entry.connection)
    self.entries[instance] = nil
end

function InstantPrompts:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled

    if enabled then
        for _, instance in ipairs(self.root:GetDescendants()) do
            self:_apply(instance)
        end
        self.addedConnection = self.root.DescendantAdded:Connect(function(instance)
            self:_apply(instance)
        end)
        self.removingConnection = self.root.DescendantRemoving:Connect(function(instance)
            self:_forget(instance)
        end)
        return
    end

    local addedConnection = self.addedConnection
    local removingConnection = self.removingConnection
    self.addedConnection = nil
    self.removingConnection = nil
    if addedConnection then
        pcall(addedConnection.Disconnect, addedConnection)
    end
    if removingConnection then
        pcall(removingConnection.Disconnect, removingConnection)
    end
    for prompt, entry in pairs(self.entries) do
        pcall(entry.connection.Disconnect, entry.connection)
        if prompt.Parent then
            pcall(function()
                prompt.HoldDuration = entry.original
            end)
        end
    end
    table.clear(self.entries)
end

function InstantPrompts:stop()
    self:setEnabled(false)
end

return InstantPrompts
]],
        ["games/stealanegg/features/LagSafeMovement.lua"] = [[local LagSafeMovement = {}
LagSafeMovement.__index = LagSafeMovement

function LagSafeMovement.new(options)
    assert(options and options.eggCmds and options.localPlayer and options.runService)
    return setmetatable({
        eggCmds = options.eggCmds,
        enabled = false,
        clock = options.clock or os.clock,
        factor = 0.65,
        canOutrun = options.canOutrun or function()
            return nil
        end,
        getPing = options.getPing or function()
            return math.huge
        end,
        guardConfigs = assert(options.guardConfigs),
        guardModels = options.guardModels or {},
        hitIntervals = {},
        localPlayer = options.localPlayer,
        onEscape = options.onEscape,
        pingThreshold = options.pingThreshold or 170,
        reclaimDistance = options.reclaimDistance or 9,
        runService = options.runService,
        wakingDuration = options.wakingDuration or 0.63,
    }, LagSafeMovement)
end

function LagSafeMovement:_humanoid()
    local character = self.localPlayer.Character
    return character and character:FindFirstChildOfClass("Humanoid") or nil
end

function LagSafeMovement:_restore()
    if self.humanoid and self.humanoid.Parent and self.humanoid.WalkSpeed == self.appliedSpeed then
        self.humanoid.WalkSpeed = self.baseSpeed
    end
    self.humanoid = nil
    self.baseSpeed = nil
    self.appliedSpeed = nil
end

function LagSafeMovement:_resetEncounter()
    self.phase = nil
    self.phaseArea = nil
    self.wakingStartedAt = nil
end

function LagSafeMovement:_beginEscape()
    if self.phase ~= "escape" and type(self.onEscape) == "function" then
        pcall(self.onEscape)
    end
    self.phase = "escape"
end

function LagSafeMovement:_shouldBait(humanoid, areaId, config)
    if not self.carrying or type(config) ~= "table" then
        return false
    end
    local guardSpeed = tonumber(config.WalkSpeed)
    local flatRadius = tonumber(config.FlatRadius)
    local hitDistance = tonumber(config.HitDistance) or 10
    if not guardSpeed or not flatRadius then
        self:_resetEncounter()
        return false
    end
    local ping = tonumber(self.getPing()) or 0
    if ping < self.pingThreshold then
        self:_resetEncounter()
        return false
    end
    local playerSpeed = humanoid == self.humanoid and self.baseSpeed or humanoid.WalkSpeed
    local guard = self.guardModels[areaId]
    local character = self.localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not guard or not guard.Parent or not root or not root:IsA("BasePart") then
        self:_resetEncounter()
        return false
    end
    local offset = guard:GetPivot().Position - root.Position
    local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
    if distance > flatRadius * 7 then
        self:_resetEncounter()
        return false
    end
    if type(playerSpeed) ~= "number" or self.canOutrun(areaId, playerSpeed) ~= false then
        self:_resetEncounter()
        return false
    end
    if self.phaseArea ~= areaId then
        self.phaseArea = areaId
        self.phase = "bait"
    end
    local slowedSpeed = playerSpeed * self.factor
    local releaseDistance = hitDistance + math.max(0, guardSpeed - slowedSpeed) * (ping / 1000)
    local guardState = guard:GetAttribute("GuardState")
    if guardState == "RetrievingEgg" then
        self:_beginEscape()
        return false
    elseif guardState == "Sleeping" then
        self.wakingStartedAt = nil
        self.phase = "bait"
        return true
    elseif guardState == "Waking" then
        self.wakingStartedAt = self.wakingStartedAt or self.clock()
        if
            self.clock() - self.wakingStartedAt
            >= math.max(0, self.wakingDuration - (ping * 2) / 1000)
        then
            self:_beginEscape()
            return false
        end
        self.phase = "bait"
        return true
    elseif guardState == "Chasing" then
        self.wakingStartedAt = nil
        if self.phase == "escape" then
            return false
        end
        local interval = self.hitIntervals[areaId]
        local elapsed = self.carryStartedAt and self.clock() - self.carryStartedAt
        if interval and elapsed then
            local lead = math.min(ping / 1000, self.reclaimDistance / math.max(playerSpeed, 1))
            if
                elapsed >= math.max(0, interval - lead)
                and elapsed <= interval + math.max(0.1, lead * 0.5)
            then
                self:_beginEscape()
                return false
            end
            self.phase = "bait"
            return true
        elseif distance <= releaseDistance then
            self:_beginEscape()
            return false
        end
        self.phase = "bait"
        return true
    end
    if self.phase == "escape" then
        return false
    end
    if distance <= releaseDistance then
        self:_beginEscape()
        return false
    end
    return true
end

function LagSafeMovement:setPingThreshold(value)
    self.pingThreshold = math.max(1, tonumber(value) or 170)
end

function LagSafeMovement:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    if enabled then
        self.carrying = false
        for _, record in ipairs(self.eggCmds.GetAreaEggSnapshot().Records) do
            if record.State == "Carried" and record.CarrierUserId == self.localPlayer.UserId then
                self.carrying = true
                self.carryUid = record.Uid
                self.carryStartedAt = self.clock()
                break
            end
        end
        self.carryConnection = self.eggCmds.AreaEggCarryStateChanged:Connect(function(state)
            if state.IsCarrying == true then
                if self.carryUid and state.Uid and state.Uid ~= self.carryUid then
                    self:_resetEncounter()
                end
                self.carryUid = state.Uid or self.carryUid
                self.carrying = true
                self.carryStartedAt = self.clock()
            else
                local guard = self.phaseArea and self.guardModels[self.phaseArea]
                if
                    self.carryStartedAt
                    and guard
                    and guard:GetAttribute("GuardState") == "RetrievingEgg"
                then
                    local interval = self.clock() - self.carryStartedAt
                    if interval > 0 and interval < 5 then
                        self.hitIntervals[self.phaseArea] = interval
                    end
                end
                self.carrying = false
                self.carryStartedAt = nil
                if self.phaseArea then
                    self.phase = "bait"
                end
            end
        end)
        self.connection = self.runService.Heartbeat:Connect(function()
            local humanoid = self:_humanoid()
            if not humanoid then
                return
            end
            local areaId = self.localPlayer:GetAttribute("AreaId")
            local config = self.guardConfigs[areaId]
            if not self:_shouldBait(humanoid, areaId, config) then
                self:_restore()
                return
            end
            if humanoid ~= self.humanoid or humanoid.WalkSpeed ~= self.appliedSpeed then
                self.humanoid = humanoid
                self.baseSpeed = humanoid.WalkSpeed
            end
            self.appliedSpeed = self.baseSpeed * self.factor
            humanoid.WalkSpeed = self.appliedSpeed
        end)
    else
        if self.carryConnection then
            self.carryConnection:Disconnect()
            self.carryConnection = nil
        end
        if self.connection then
            self.connection:Disconnect()
            self.connection = nil
        end
        self.carrying = false
        self.carryStartedAt = nil
        self.carryUid = nil
        self:_resetEncounter()
        self:_restore()
    end
end

function LagSafeMovement:stop()
    self:setEnabled(false)
end

return LagSafeMovement
]],
        ["games/stealanegg/features/ServerHop.lua"] = [[local ServerHop = {}
ServerHop.__index = ServerHop

function ServerHop.new(options)
    assert(options and options.httpGet and options.decode and options.teleportService)
    assert(options.localPlayer and options.placeId and options.jobId)
    local visitedServerIds = options.visitedServerIds or {}
    visitedServerIds[options.jobId] = true
    if options.persistVisited then
        options.persistVisited()
    end
    local self = setmetatable({
        decode = options.decode,
        httpGet = options.httpGet,
        jobId = options.jobId,
        localPlayer = options.localPlayer,
        logger = options.logger,
        maxPlayers = math.max(1, tonumber(options.maxPlayers) or 100),
        placeId = options.placeId,
        persistVisited = options.persistVisited,
        spawn = options.spawn or task.spawn,
        teleportService = options.teleportService,
        visitedServerIds = visitedServerIds,
        requestSerial = 0,
        running = false,
        stopped = false,
    }, ServerHop)
    local failedSignal = options.teleportService.TeleportInitFailed
    if failedSignal and type(failedSignal.Connect) == "function" then
        self.teleportFailedConnection = failedSignal:Connect(function(player, result, message)
            if player ~= self.localPlayer or not self.pendingTeleport then
                return
            end
            local pending = self.pendingTeleport
            self.pendingTeleport = nil
            self:_log("warn", "destination rejected; trying another", {
                error = message,
                result = tostring(result),
                serverId = pending.serverId,
            })
            if pending.completed then
                pending.completed(false, message or tostring(result))
            end
        end)
    end
    return self
end

function ServerHop:_log(level, message, fields)
    local write = self.logger and self.logger[level]
    if type(write) == "function" then
        write(self.logger, "stealanegg.serverHop", message, fields)
    end
end

function ServerHop:run(maxPing, completed, isActive, targetPopulation)
    if self.running or self.stopped then
        if completed then
            completed(false, self.stopped and "stopped" or "busy")
        end
        return
    end
    self.running = true
    self.spawn(function()
        local ok, result = pcall(function()
            self.requestSerial += 1
            targetPopulation = math.clamp(tonumber(targetPopulation) or 6, 0, self.maxPlayers - 1)
            local desiredPlaying = targetPopulation
            local sortOrder = targetPopulation >= 4 and "Desc" or "Asc"
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100&excludeFullGames=true&_=%s-%d"):format(
                self.placeId,
                sortOrder,
                self.jobId,
                self.requestSerial
            )
            local response = self.decode(self.httpGet(url))
            local best
            for _, server in ipairs(response.data or {}) do
                if
                    server.id ~= self.jobId
                    and self.visitedServerIds[server.id] ~= true
                    and server.playing < server.maxPlayers
                    and type(server.ping) == "number"
                    and server.ping <= maxPing
                    and (
                        not best
                        or server.ping < best.ping
                        or (
                            server.ping == best.ping
                            and math.abs(server.playing - desiredPlaying)
                                < math.abs(best.playing - desiredPlaying)
                        )
                    )
                then
                    best = server
                end
            end
            assert(best, ("No available server found below %d ms"):format(maxPing))
            self:_log("info", "teleporting", {
                ping = best.ping,
                players = best.playing,
                serverId = best.id,
            })
            assert(not self.stopped and (not isActive or isActive()), "Server hop cancelled")
            self.pendingTeleport = {
                completed = completed,
                serverId = best.id,
            }
            self.teleportService:TeleportToPlaceInstance(self.placeId, best.id, self.localPlayer)
            self.visitedServerIds[best.id] = true
            if self.persistVisited then
                self.persistVisited()
            end
        end)
        self.running = false
        if not ok then
            self.pendingTeleport = nil
            self:_log("error", "failed", { error = result })
        end
        if completed then
            completed(ok, result)
        end
    end)
end

function ServerHop:stop()
    self.stopped = true
    self.pendingTeleport = nil
    if self.teleportFailedConnection then
        pcall(self.teleportFailedConnection.Disconnect, self.teleportFailedConnection)
        self.teleportFailedConnection = nil
    end
end

return ServerHop
]],
        ["games/stealanegg/features/WalkNavigator.lua"] = [[local WalkNavigator = {}
WalkNavigator.__index = WalkNavigator

local function flatDistance(from, to)
    local delta = from - to
    return math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
end

local function characterParts(localPlayer)
    local character = localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and root and root:IsA("BasePart") then
        return humanoid, root
    end
    return nil, nil
end

function WalkNavigator.new(options)
    assert(options and options.localPlayer and options.runService)
    local self = setmetatable({
        localPlayer = options.localPlayer,
        modifiers = {},
        pathCosts = {},
        pathfindingService = options.pathfindingService,
        runService = options.runService,
        workspace = options.workspace or workspace,
        stopped = false,
    }, WalkNavigator)
    for _, part in ipairs(options.blockedParts or {}) do
        if part and part.Parent and part:IsA("BasePart") then
            local modifier = Instance.new("PathfindingModifier")
            modifier.Label = "UniversalHubTreadmill"
            modifier.PassThrough = false
            modifier.Parent = part
            table.insert(self.modifiers, modifier)
            self.pathCosts[modifier.Label] = 1000000
        end
    end
    return self
end

function WalkNavigator:_waitForCharacter(isActive)
    local deadline = self.workspace:GetServerTimeNow() + 12
    while not self.stopped and isActive() and self.workspace:GetServerTimeNow() <= deadline do
        local humanoid, root = characterParts(self.localPlayer)
        if humanoid and root then
            return humanoid, root
        end
        self.runService.Heartbeat:Wait()
    end
    return nil, nil
end

function WalkNavigator:_walkPoint(position, isActive, tolerance)
    local humanoid, root = self:_waitForCharacter(isActive)
    if not humanoid then
        return false, "character-unavailable"
    end
    self.movementId = (self.movementId or 0) + 1
    local movementId = self.movementId
    self.activeHumanoid = humanoid
    self.activePosition = position
    local function finish(reached, reason)
        if self.movementId == movementId then
            self.activeHumanoid = nil
            self.activePosition = nil
        end
        return reached, reason
    end
    local deadline = self.workspace:GetServerTimeNow()
        + math.max(10, flatDistance(root.Position, position) / 6)
    local nextMove = -math.huge
    while not self.stopped and isActive() and self.workspace:GetServerTimeNow() <= deadline do
        humanoid, root = characterParts(self.localPlayer)
        if not humanoid or not root then
            return finish(false, "character-lost")
        end
        self.activeHumanoid = humanoid
        if flatDistance(root.Position, position) <= tolerance then
            return finish(true)
        end
        local now = self.workspace:GetServerTimeNow()
        if now >= nextMove then
            humanoid:MoveTo(position)
            nextMove = now + 1.5
        end
        self.runService.Heartbeat:Wait()
    end
    local cancelled = self.stopped or not isActive()
    if cancelled then
        humanoid, root = characterParts(self.localPlayer)
        if humanoid and root then
            humanoid:MoveTo(root.Position)
        end
    end
    return finish(false, cancelled and "cancelled" or "timeout")
end

function WalkNavigator:_waypoints(startPosition, destination)
    if not self.pathfindingService then
        return nil
    end
    local path = self.pathfindingService:CreatePath({
        AgentCanJump = true,
        AgentRadius = 2,
        AgentHeight = 5,
        Costs = self.pathCosts,
        WaypointSpacing = 12,
    })
    local ok = pcall(path.ComputeAsync, path, startPosition, destination)
    if not ok or path.Status ~= Enum.PathStatus.Success then
        return nil
    end
    return path:GetWaypoints()
end

function WalkNavigator:walkTo(destination, isActive, tolerance)
    assert(typeof(destination) == "Vector3", "WalkNavigator destination must be a Vector3")
    isActive = isActive or function()
        return true
    end
    tolerance = tolerance or 7
    local _, root = self:_waitForCharacter(isActive)
    if not root then
        return false, "character-unavailable"
    end
    local waypoints = self:_waypoints(root.Position, destination)
    if waypoints then
        for index, waypoint in ipairs(waypoints) do
            if index > 1 then
                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    local humanoid = characterParts(self.localPlayer)
                    if humanoid then
                        humanoid.Jump = true
                    end
                end
                local reached, reason = self:_walkPoint(waypoint.Position, isActive, tolerance)
                if not reached then
                    return false, reason
                end
            end
        end
    end
    return self:_walkPoint(destination, isActive, tolerance)
end

function WalkNavigator:moveToDirect(destination, isActive, tolerance)
    assert(typeof(destination) == "Vector3", "WalkNavigator destination must be a Vector3")
    return self:_walkPoint(destination, isActive or function()
        return true
    end, tolerance or 4)
end

function WalkNavigator:headToward(destination)
    assert(typeof(destination) == "Vector3", "WalkNavigator destination must be a Vector3")
    local humanoid = characterParts(self.localPlayer)
    if not humanoid then
        return false
    end
    self.movementId = (self.movementId or 0) + 1
    self.activeHumanoid = humanoid
    self.activePosition = destination
    return pcall(humanoid.MoveTo, humanoid, destination)
end

function WalkNavigator:resume()
    local humanoid = self.activeHumanoid
    local position = self.activePosition
    if not humanoid or typeof(position) ~= "Vector3" then
        return false
    end
    return pcall(humanoid.MoveTo, humanoid, position)
end

function WalkNavigator:jump()
    local humanoid = characterParts(self.localPlayer)
    if not humanoid then
        return false
    end
    humanoid.Jump = true
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    return true
end

function WalkNavigator:stop()
    self.stopped = true
    self.movementId = (self.movementId or 0) + 1
    self.activeHumanoid = nil
    self.activePosition = nil
    local humanoid, root = characterParts(self.localPlayer)
    if humanoid and root then
        humanoid:MoveTo(root.Position)
    end
    for _, modifier in ipairs(self.modifiers) do
        pcall(modifier.Destroy, modifier)
    end
    table.clear(self.modifiers)
end

return WalkNavigator
]],
    },
}
