local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}
local root = configuration.LocalRoot or "universal-hub/local"
local cache = {}

local function import(path)
    if cache[path] ~= nil then
        return cache[path]
    end

    local result
    if configuration.Import then
        result = configuration.Import(path)
    else
        local source = readfile(root .. "/" .. path .. ".lua")
        local chunk, compileError = loadstring(source, path .. ".lua")
        result = assert(chunk, compileError)()
    end
    cache[path] = result
    return result
end

local function copyData(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[copyData(key)] = copyData(child)
    end
    return copy
end

local function extend(target, additions)
    for key, value in pairs(additions or {}) do
        assert(target[key] == nil, "Composition must not replace shared context: " .. tostring(key))
        target[key] = value
    end
    return target
end

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Store = import("modules/Store")
local Config = import("modules/Config")
local Changelog = import("modules/Changelog")
local WhatsNew = import("ui/WhatsNew")
local InputCapture = import("modules/InputCapture")
local MenuToggle = import("modules/MenuToggle")
local Registry = import("modules/Registry")
local Logger = import("modules/Logger")
local Session = import("modules/Session")
local DrawingRenderer = import("ui/esp/DrawingRenderer")
local VisualPolicy = import("ui/esp/VisualPolicy")
local HighlightRenderer = import("ui/esp/HighlightRenderer")
local WorldRenderer = import("ui/esp/WorldRenderer")
local HubMenu = import("ui/Menu")
local HubView = import("modules/HubView")
local PresentationCatalog = import("ui/presentation/Catalog")
local PresentationHost = import("ui/PresentationHost")
local PresentationRuntime = import("ui/presentation/Runtime")
local StandardPanels = import("ui/presentation/StandardPanels")
local CosmeticsPanel = import("ui/presentation/CosmeticsPanel")
local Compatibility = import("games/Compatibility")
local Catalog = import("games/Catalog")

local previousLogger = environment.UniversalHubLogger
if type(previousLogger) == "table" and type(previousLogger.close) == "function" then
    pcall(previousLogger.close, previousLogger, { reason = "reexecution" })
end
local logger = Logger.new({
    appendFile = type(appendfile) == "function" and appendfile or nil,
    archiveName = function()
        return "session-" .. tostring(DateTime.now().UnixTimestampMillis)
    end,
    isFile = type(isfile) == "function" and isfile or nil,
    makeFolder = type(makefolder) == "function" and makefolder or nil,
    readFile = type(readfile) == "function" and readfile or nil,
    writeFile = type(writefile) == "function" and writefile or nil,
})
environment.UniversalHubLogger = logger
logger:info("bootstrap", "initializing", {
    gameId = game.GameId,
    jobId = game.JobId,
    placeId = game.PlaceId,
})
local bootTiming = configuration.BootTiming
if type(bootTiming) == "table" then
    local function seconds(value)
        return type(value) == "number" and ("%.3f"):format(value) or nil
    end
    logger:info("bootstrap", "loader timing", {
        fetchCount = bootTiming.fetchCount,
        fetchSeconds = seconds(bootTiming.fetchSeconds),
        hydroxideSeconds = seconds(bootTiming.hydroxideSeconds),
        inventorySeconds = seconds(bootTiming.inventorySeconds),
        limnSeconds = seconds(bootTiming.limnSeconds),
        menuCompileSeconds = seconds(bootTiming.menuCompileSeconds),
        menuExecuteSeconds = seconds(bootTiming.menuExecuteSeconds),
        menuSeconds = seconds(bootTiming.menuSeconds),
        mode = bootTiming.mode,
        preInitSeconds = seconds(bootTiming.preInitSeconds),
        slowestFetch = bootTiming.slowestFetch,
        slowestFetchSeconds = seconds(bootTiming.slowestFetchSeconds),
    })
end

local registry = Registry.new()
for _, definitionPath in ipairs(Catalog) do
    registry:Register(Compatibility.Compose(import(definitionPath)))
end

local adapterDefinition = registry:Resolve({
    gameId = game.GameId,
    placeId = game.PlaceId,
})
assert(
    adapterDefinition,
    ("Universal Hub does not support game %s / place %s"):format(
        tostring(game.GameId),
        tostring(game.PlaceId)
    )
)
logger:info("bootstrap", "game selected", {
    adapter = adapterDefinition.id,
    label = adapterDefinition.label,
})
local adapterModule = import(adapterDefinition.module)
assert(
    type(adapterModule) == "table" and type(adapterModule.new) == "function",
    "Invalid game adapter module"
)
local presentation = import(adapterDefinition.presentation)
local features = adapterDefinition.features
local compositionModule
local compositionDependencies = {}
if adapterDefinition.composition then
    compositionModule = import(adapterDefinition.composition)
    assert(
        type(compositionModule) == "table" and type(compositionModule.bind) == "function",
        "Invalid game composition module"
    )
    local declaredSources = {}
    for _, path in ipairs(adapterDefinition.sources) do
        declaredSources[path] = true
    end
    local dependencyNames = {}
    for name, path in pairs(compositionModule.dependencies or {}) do
        assert(
            type(name) == "string" and name ~= "",
            "Composition dependency names must be strings"
        )
        assert(
            type(path) == "string" and declaredSources[path],
            "Composition dependency must be declared by the selected definition"
        )
        table.insert(dependencyNames, name)
    end
    table.sort(dependencyNames)
    for _, name in ipairs(dependencyNames) do
        compositionDependencies[name] = import(compositionModule.dependencies[name])
    end
end

local Limn = assert(configuration.Limn, "Universal Hub loader must stage Limn before init")
assert(type(Limn) == "table" and type(Limn.new) == "function", "Universal Hub requires Limn")
local Helpers = assert(
    configuration.HydroxideHelpers,
    "Universal Hub loader must stage Hydroxide Helpers before init"
)
local hydroxideImport = assert(
    configuration.HydroxideImport,
    "Universal Hub loader must stage a Hydroxide importer before init"
)
assert(
    type(Helpers) == "table" and type(Helpers.load) == "function",
    "Universal Hub requires Hydroxide Helpers.load"
)
local helpers = Helpers.load({
    import = hydroxideImport,
    modules = adapterDefinition.hydroxide or {},
})
for _, name in ipairs(adapterDefinition.hydroxide or {}) do
    assert(type(helpers[name]) == "table", "Missing Hydroxide helper module: " .. tostring(name))
end

Session.stopPrevious(environment)
local drawingRuntime = Limn.new({
    Drawing = Drawing,
    DrawingImmediate = DrawingImmediate,
    Vector2 = Vector2,
    Input = {
        MapPosition = function(position)
            local topLeftInset = GuiService:GetGuiInset()
            return position + topLeftInset
        end,
        -- The visible menu intentionally sinks pointer input before Limn receives it.
        Processed = "allow",
    },
})
configuration.Limn = nil
configuration.HydroxideHelpers = nil
configuration.HydroxideImport = nil

local configPath = configuration.ConfigPath
    or ("universal-hub/configs/%s.json"):format(adapterDefinition.id)
local ephemeralSettings = PresentationCatalog.collectEphemeralSettings(presentation)
local configStore = Config.new({
    decode = function(source)
        return HttpService:JSONDecode(source)
    end,
    encode = function(value)
        return HttpService:JSONEncode(value)
    end,
    isFile = type(isfile) == "function" and isfile or nil,
    omittedKeys = ephemeralSettings,
    path = configPath,
    readFile = type(readfile) == "function" and readfile or nil,
    writeFile = type(writefile) == "function" and writefile or nil,
})
local configDefaults = copyData(adapterDefinition.defaults)
local settings = configStore:load(configDefaults)
local hasPersistedConfig = type(isfile) == "function" and isfile(configPath)
if not hasPersistedConfig then
    for name, value in pairs(environment.UniversalHubSettings or {}) do
        if settings[name] ~= nil and not ephemeralSettings[name] then
            settings[name] = value
        end
    end
end
local taskAutomationWasNormalized = configuration.TeleportBootstrap ~= true
    and settings.taskAutomationEnabled == true
if taskAutomationWasNormalized then
    settings.taskAutomationEnabled = false
end

local session
local overlay
local adapter
local store
local pendingAdapterOptions = {}
local function setAdapterOption(name, enabled, persist)
    if session then
        session:setOption(name, enabled, persist)
        return true
    end
    table.insert(pendingAdapterOptions, {
        name = name,
        enabled = enabled,
        persist = persist,
    })
    return false
end
local function noAfterAdapter(_adapter) end
local composition = {
    adapter = {},
    afterAdapter = noAfterAdapter,
    inputCapture = {
        releaseMouseOnDisable = false,
    },
    overlay = {},
}
if compositionModule then
    composition = compositionModule.bind({
        config = function(name, fallback)
            local value = configuration[name]
            return value == nil and fallback or value
        end,
        decode = function(source)
            return HttpService:JSONDecode(source)
        end,
        encode = function(value)
            return HttpService:JSONEncode(value)
        end,
        files = {
            delete = type(delfile) == "function" and delfile or nil,
            isFile = type(isfile) == "function" and isfile or nil,
            list = type(listfiles) == "function" and listfiles or nil,
            makeFolder = type(makefolder) == "function" and makefolder or nil,
            read = type(readfile) == "function" and readfile or nil,
            write = type(writefile) == "function" and writefile or nil,
        },
        getAdapter = function()
            return adapter
        end,
        getStore = function()
            return store
        end,
        spawn = task.spawn,
        userId = LocalPlayer.UserId,
    }, compositionDependencies)
    assert(type(composition) == "table", "Game composition must return a table")
    assert(
        composition.adapter == nil or type(composition.adapter) == "table",
        "Game composition adapter context must be a table"
    )
    assert(
        composition.inputCapture == nil or type(composition.inputCapture) == "table",
        "Game composition input context must be a table"
    )
    assert(
        composition.overlay == nil or type(composition.overlay) == "table",
        "Game composition overlay context must be a table"
    )
    assert(
        composition.afterAdapter == nil or type(composition.afterAdapter) == "function",
        "Game composition afterAdapter must be a function"
    )
    composition.adapter = composition.adapter or {}
    composition.afterAdapter = composition.afterAdapter or noAfterAdapter
    composition.inputCapture = composition.inputCapture or {}
    composition.overlay = composition.overlay or {}
end

local startupCleanups = {}
local function ownStartup(cleanup)
    table.insert(startupCleanups, cleanup)
end
local function failStartup(message)
    logger:error("bootstrap", "startup failed", { error = message })
    for index = #startupCleanups, 1, -1 do
        pcall(startupCleanups[index])
    end
    table.clear(startupCleanups)
    logger:close({ reason = "startup-failed" })
    if environment.UniversalHubLogger == logger then
        environment.UniversalHubLogger = nil
    end
    error(message, 0)
end

local initialState = copyData(adapterDefinition.initialState)
initialState.settings = settings
initialState.status = ("Loading %s"):format(adapterDefinition.label)
if settings.taskAutomationEnabled == true then
    initialState.menuVisible = false
end
store = Store.new(initialState)
ownStartup(function()
    store:Destroy()
end)
environment.UniversalHubSettings = store:Get().settings
local footerSubscriptions = {}
local footerElapsed = 1
local footerConnection = RunService.Heartbeat:Connect(function(deltaTime)
    footerElapsed += deltaTime
    if footerElapsed < 1 then
        return
    end
    footerElapsed = 0
    local metrics = {}
    for id, subscription in pairs(footerSubscriptions) do
        local ok, value = pcall(subscription.read)
        if ok then
            table.insert(metrics, {
                id = id,
                kind = subscription.kind,
                label = subscription.label,
                value = value,
            })
        end
    end
    store:Patch({ footerMetrics = metrics })
end)
local function subscribeFooterMetric(id, spec, read)
    footerSubscriptions[id] = { kind = spec.kind, label = spec.label, read = read }
    return function()
        footerSubscriptions[id] = nil
    end
end
ownStartup(function()
    footerConnection:Disconnect()
end)

local inputCaptureCreated, inputCaptureResult = pcall(InputCapture.new, {
    releaseMouseOnDisable = composition.inputCapture.releaseMouseOnDisable == true,
})
if not inputCaptureCreated then
    failStartup(inputCaptureResult)
end
local inputCapture = inputCaptureResult
ownStartup(function()
    inputCapture:Destroy()
end)
local thirdPersonState

local function setInputCaptured(captured)
    inputCapture:SetEnabled(captured)
end

local function setThirdPerson(enabled)
    if enabled then
        if not thirdPersonState then
            thirdPersonState = {
                cameraMode = LocalPlayer.CameraMode,
                maximumZoom = LocalPlayer.CameraMaxZoomDistance,
                minimumZoom = LocalPlayer.CameraMinZoomDistance,
            }
        end
        LocalPlayer.CameraMode = Enum.CameraMode.Classic
        LocalPlayer.CameraMaxZoomDistance = 12
        LocalPlayer.CameraMinZoomDistance = 8
    elseif thirdPersonState then
        LocalPlayer.CameraMode = thirdPersonState.cameraMode
        LocalPlayer.CameraMaxZoomDistance = thirdPersonState.maximumZoom
        LocalPlayer.CameraMinZoomDistance = thirdPersonState.minimumZoom
        thirdPersonState = nil
    end
end

local adapterCapabilityContext = {
    fireTouchInterestAvailable = type(environment.firetouchinterest) == "function",
    getConnectionsAvailable = type(getconnections) == "function",
    getNamecallMethodAvailable = type(getnamecallmethod) == "function",
    hookFunctionAvailable = type(hookfunction) == "function",
    hookMetaMethodAvailable = type(hookmetamethod) == "function",
    restoreFunctionAvailable = type(restorefunction) == "function",
    gameId = game.GameId,
    placeId = game.PlaceId,
}
if type(adapterModule.capabilityContext) == "function" then
    local succeeded, nativeContext = pcall(adapterModule.capabilityContext)
    if succeeded and type(nativeContext) == "table" then
        extend(adapterCapabilityContext, nativeContext)
    end
end
local adapterCapabilities = type(adapterModule.capabilitiesFor) == "function"
        and adapterModule.capabilitiesFor(adapterCapabilityContext, features.capabilities)
    or features.capabilities
adapterCapabilities = copyData(adapterCapabilities)
local function customAsset(path)
    if type(getcustomasset) ~= "function" or type(isfile) ~= "function" or not isfile(path) then
        return nil
    end
    local succeeded, asset = pcall(getcustomasset, path)
    return succeeded and asset or nil
end
local brandIcon = customAsset(root .. "/assets/brand/universal-hub.png")
local gameIcon = ("rbxthumb://type=GameIcon&id=%d&w=150&h=150"):format(game.GameId)
local enemyAudienceIcon = customAsset(root .. "/assets/icons/enemies.png")
local allyAudienceIcon = customAsset(root .. "/assets/icons/allies.png")
local alphaCheckerboard = customAsset(root .. "/assets/ui/alpha-checkerboard.png")
local pageIcons = {}
for page, file in pairs({
    Combat = "combat.png",
    Rage = "rage.png",
    Movement = "movement.png",
    Visuals = "visuals.png",
    Tools = "tools.png",
    Settings = "settings.png",
}) do
    pageIcons[page] = customAsset(root .. "/assets/icons/" .. file)
end

local uiParent = (function()
    local success, parent = pcall(function()
        if type(gethui) == "function" then
            return gethui()
        end
        return game:GetService("CoreGui")
    end)
    return success and parent or nil
end)()

local overlayContext = {
    capabilities = adapterCapabilities,
    highlightsSupported = table.find(adapterCapabilities, "worldRenderer") ~= nil,
    visualPolicy = VisualPolicy,
    catalog = PresentationCatalog,
    cosmetics = features.cosmetics,
    prismMenu = assert(
        configuration.Menu,
        "Universal Hub loader must stage the compiled Prism menu"
    ),
    worldOnly = true,
    gameLabel = adapterDefinition.label,
    getCamera = function()
        return Workspace.CurrentCamera
    end,
    uiParent = uiParent,
    guiParent = uiParent,
    players = Players,
    localPlayer = LocalPlayer,
    runService = RunService,
    brandIcon = brandIcon,
    gameIcon = gameIcon,
    enemyAudienceIcon = enemyAudienceIcon,
    allyAudienceIcon = allyAudienceIcon,
    alphaCheckerboard = alphaCheckerboard,
    optionLabels = features.optionLabels,
    pageIcons = pageIcons,
    presentation = presentation,
    presentationHost = PresentationHost,
    presentationParts = {
        cosmetics = CosmeticsPanel,
        standard = StandardPanels,
    },
    presentationRuntime = PresentationRuntime,
    inputService = UserInputService,
    limn = drawingRuntime,
    setFov = function(value, persist)
        local current = session
        if not current then
            return
        end
        local settings = current.store:Get().settings
        local name = settings.shotAim == true and "shotFov" or "cameraFov"
        local clamped = math.clamp(value, settings.minimumFov, settings.maximumFov)
        current:patchSettings({ fov = clamped, [name] = clamped }, persist)
    end,
    setCosmeticsOpen = function(open)
        local current = session
        if not current then
            return
        end
        current:setCosmeticsOpen(open)
    end,
    setCosmeticMode = function(mode)
        local current = session
        if not current then
            return
        end
        current:setCosmeticMode(mode)
    end,
    setInputCaptured = setInputCaptured,
    menuEnabled = false,
    setMenuKey = function(value)
        local current = session
        if not current then
            return
        end
        current:setMenuKey(value)
    end,
    setMenuVisible = function(visible)
        local current = session
        if not current then
            return
        end
        current:setMenuVisible(visible)
    end,
    setSetting = function(name, value, persist)
        local current = session
        if not current then
            return
        end
        current:setSetting(name, value, persist)
    end,
    setOption = function(name, enabled, persist)
        local current = session
        if not current then
            return
        end
        current:setOption(name, enabled, persist)
        if enabled and features.exclusiveOptions then
            for _, excluded in ipairs(features.exclusiveOptions[name] or {}) do
                current:setOption(excluded, false, persist)
            end
        end
    end,
    setRate = function(name, value, persist)
        local current = session
        if not current then
            return
        end
        current:setRate(name, value, persist)
    end,
    store = store,
}
extend(overlayContext, composition.overlay)
local worldCreated, worldResult = pcall(function()
    local drawingWorld = DrawingRenderer.new(overlayContext)
    local highlightsCreated, highlightWorld = pcall(HighlightRenderer.new, overlayContext)
    if not highlightsCreated then
        drawingWorld:destroy()
        error(highlightWorld, 0)
    end
    return WorldRenderer.new(overlayContext, drawingWorld, highlightWorld)
end)
if not worldCreated then
    failStartup(worldResult)
end
local worldOverlay = worldResult
overlayContext.optionSupport = worldOverlay.optionSupport
local menuCreated, menuResult = pcall(HubMenu.new, overlayContext)
if not menuCreated then
    worldOverlay:destroy()
    failStartup(menuResult)
end
overlay = HubView.new(worldOverlay, menuResult)
ownStartup(function()
    overlay:destroy()
end)

local adapterContext = {
    aimClick = mouse2click,
    aimPress = mouse2press,
    aimRelease = mouse2release,
    click = mouse1click,
    contextActionService = ContextActionService,
    fireTouchInterest = type(environment.firetouchinterest) == "function"
            and environment.firetouchinterest
        or nil,
    press = mouse1press,
    release = mouse1release,
    gcObjects = function()
        return getgc(true)
    end,
    getConnections = getconnections,
    getNamecallMethod = getnamecallmethod,
    hookFunction = hookfunction,
    hookMetaMethod = hookmetamethod,
    isInputCaptured = function()
        return inputCapture:IsEnabled()
    end,
    isFireHeld = function()
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end,
    isJumpHeld = function()
        return UserInputService:IsKeyDown(Enum.KeyCode.Space)
    end,
    keyPress = type(keypress) == "function" and keypress or nil,
    keyRelease = type(keyrelease) == "function" and keyrelease or nil,
    fireSignal = type(firesignal) == "function" and firesignal or nil,
    movementDirection = function()
        local horizontal = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
            - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
        local forward = (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
            - (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
        if horizontal == 0 and forward == 0 then
            return Vector3.new(0, 0, 0)
        end

        local camera = Workspace.CurrentCamera
        if not camera then
            return Vector3.new(0, 0, 0)
        end
        local look = camera.CFrame.LookVector
        local right = camera.CFrame.RightVector
        local direction = Vector3.new(right.X, 0, right.Z) * horizontal
            + Vector3.new(look.X, 0, look.Z) * forward
        return direction.Magnitude > 1 and direction.Unit or direction
    end,
    limn = drawingRuntime,
    logger = logger,
    capabilities = adapterCapabilities,
    oh = helpers,
    render = function(observations, mousePosition, utilityObservations)
        overlay:render(observations, mousePosition, utilityObservations)
    end,
    restoreFunction = restorefunction,
    settingsChanged = function(updatedSettings)
        configStore:save(updatedSettings)
    end,
    subscribeFooterMetric = subscribeFooterMetric,
    setThirdPerson = setThirdPerson,
    gameId = game.GameId,
    generateGuid = function()
        return HttpService:GenerateGUID(false)
    end,
    localPlayer = LocalPlayer,
    jobId = game.JobId,
    newCClosure = newcclosure,
    now = os.time,
    placeId = game.PlaceId,
    players = Players,
    store = store,
    setOption = setAdapterOption,
    teleportBootstrap = configuration.TeleportBootstrap == true,
    wait = task.wait,
    workspace = Workspace,
}
extend(adapterContext, composition.adapter)
local created, result = pcall(adapterModule.new, adapterContext)
if not created then
    failStartup(result)
end
adapter = result
if type(worldOverlay.setPolicy) == "function" then
    worldOverlay:setPolicy(adapter.worldPolicy or {
        isPlayerEligible = adapter.isOpponent,
    })
end
ownStartup(function()
    if type(adapter.stop) == "function" then
        adapter:stop()
    end
end)
if composition.afterAdapter then
    composition.afterAdapter(adapter)
end

local sessionCreated, sessionResult = pcall(Session.new, {
    adapter = adapter,
    environment = environment,
    inputCapture = inputCapture,
    logger = logger,
    overlay = overlay,
    settingsChanged = function(updatedSettings)
        configStore:save(updatedSettings)
    end,
    store = store,
})
if not sessionCreated then
    failStartup(sessionResult)
end
session = sessionResult
for _, request in ipairs(pendingAdapterOptions) do
    session:setOption(request.name, request.enabled, request.persist)
end
table.clear(pendingAdapterOptions)
if taskAutomationWasNormalized then
    session:setOption("taskAutomationEnabled", false, true)
end
overlay.menu:setEnabled(true)
table.clear(startupCleanups)
local finalized, finalError = pcall(function()
    session.adapterId = adapterDefinition.id
    session.game = adapterDefinition.label
    session.registry = registry
    session.state = store:Get()
    session.store = store
    local menuToggleConnection = UserInputService.InputBegan:Connect(
        function(input, gameProcessedEvent)
            local bindingSettled = os.clock() - (session.menuKeyChangedAt or -math.huge) > 0.2
            if
                bindingSettled
                and MenuToggle.shouldToggle(
                    input,
                    gameProcessedEvent,
                    UserInputService,
                    store:Get().settings.menuKey
                )
            then
                session:toggleMenu()
            end
        end
    )
    session:Add(function()
        menuToggleConnection:Disconnect()
    end)

    local readyStatus = ("%s ready"):format(adapterDefinition.label)
    store:Patch({ status = readyStatus })
    if type(bootTiming) == "table" and type(bootTiming.startedAt) == "number" then
        bootTiming.totalSeconds = os.clock() - bootTiming.startedAt
    end
    logger:info("bootstrap", "ready", {
        adapter = adapterDefinition.id,
        totalSeconds = type(bootTiming) == "table" and bootTiming.totalSeconds or nil,
    })
    print("[Universal Hub]", readyStatus)

    local lastUsedStore = Config.new({
        decode = function(source)
            return HttpService:JSONDecode(source)
        end,
        encode = function(value)
            return HttpService:JSONEncode(value)
        end,
        isFile = type(isfile) == "function" and isfile or nil,
        path = configuration.LastUsedVersionPath or WhatsNew.DEFAULT_PATH,
        readFile = type(readfile) == "function" and readfile or nil,
        writeFile = type(writefile) == "function" and writefile or nil,
    })
    local remoteUrls = {}
    if type(configuration.SourceBaseUrl) == "string" and configuration.SourceBaseUrl ~= "" then
        table.insert(remoteUrls, configuration.SourceBaseUrl .. "changelog.json")
    end
    table.insert(remoteUrls, WhatsNew.PAGES_CHANGELOG_URL)
    local changelogCatalog = Changelog.load({
        decode = function(source)
            return HttpService:JSONDecode(source)
        end,
        source = configuration.ChangelogSource,
        localPath = root .. "/changelog.json",
        isFile = type(isfile) == "function" and isfile or nil,
        readFile = type(readfile) == "function" and readfile or nil,
        remoteUrls = remoteUrls,
        httpGet = type(game.HttpGet) == "function" and function(url)
            return game:HttpGet(url, true)
        end or nil,
    })
    local notice = WhatsNew.evaluate({
        catalog = changelogCatalog,
        lastUsed = lastUsedStore:load(WhatsNew.defaults()),
    })
    local function hideNotice()
        store:Patch({
            whatsNew = {
                visible = false,
            },
        })
    end
    overlayContext.whatsNewDismiss = hideNotice
    overlayContext.whatsNewDontShowAgain = function()
        if notice.current then
            lastUsedStore:save(WhatsNew.acknowledge(notice.current, true))
        end
        hideNotice()
    end
    overlayContext.whatsNewAcknowledge = function()
        if notice.current then
            lastUsedStore:save(WhatsNew.acknowledge(notice.current))
        end
        hideNotice()
    end
    overlayContext.whatsNewViewAll = function()
        store:Patch({
            whatsNew = {
                showingAll = true,
            },
        })
    end
    local function replaceWhatsNew(snapshot)
        store:Patch({
            whatsNew = false,
        })
        store:Patch({
            whatsNew = snapshot,
        })
    end
    replaceWhatsNew(WhatsNew.snapshot(notice))
    session:Add(hideNotice)

    local function fingerprint(path)
        if type(readfile) ~= "function" then
            return ""
        end
        local ok, source = pcall(readfile, path)
        if not ok or type(source) ~= "string" then
            return ""
        end
        return tostring(#source)
            .. ":"
            .. string.sub(source, 1, 48)
            .. ":"
            .. string.sub(source, -48)
    end

    local function forget(path)
        cache[path] = nil
        if type(configuration.Forget) == "function" then
            configuration.Forget(path)
        end
    end

    local function reloadChangelog()
        changelogCatalog = Changelog.load({
            decode = function(source)
                return HttpService:JSONDecode(source)
            end,
            source = configuration.HotReload == true and nil or configuration.ChangelogSource,
            localPath = root .. "/changelog.json",
            isFile = type(isfile) == "function" and isfile or nil,
            readFile = type(readfile) == "function" and readfile or nil,
            remoteUrls = remoteUrls,
            httpGet = type(game.HttpGet) == "function" and function(url)
                return game:HttpGet(url, true)
            end or nil,
        })
        notice = WhatsNew.evaluate({
            catalog = changelogCatalog,
            lastUsed = lastUsedStore:load(WhatsNew.defaults()),
        })
        replaceWhatsNew(WhatsNew.snapshot(notice))
    end

    local function restageCompiledMenu()
        if type(configuration.ReloadMenu) ~= "function" then
            return true
        end
        local ok, nextMenu = pcall(configuration.ReloadMenu)
        if not ok then
            warn("[Universal Hub] Compiled menu reload failed:", nextMenu)
            return false
        end
        if type(nextMenu) ~= "table" or type(nextMenu.mountUniversalHubMenu) ~= "function" then
            warn("[Universal Hub] Compiled menu reload returned an invalid artifact")
            return false
        end
        configuration.Menu = nextMenu
        overlayContext.prismMenu = nextMenu
        return true
    end

    local function reloadUi(options)
        local restageMenu = options == nil
            or (type(options) == "table" and options.restageMenu == true)
        if restageMenu then
            restageCompiledMenu()
        end
        forget("modules/Changelog")
        forget("ui/Menu")
        forget("ui/WhatsNew")
        forget("ui/presentation/Catalog")
        Changelog = import("modules/Changelog")
        WhatsNew = import("ui/WhatsNew")
        PresentationCatalog = import("ui/presentation/Catalog")
        HubMenu = import("ui/Menu")
        overlayContext.catalog = PresentationCatalog
        local remounted, nextMenu = pcall(HubMenu.new, overlayContext)
        if not remounted then
            warn("[Universal Hub] UI reload failed:", nextMenu)
            return false
        end
        overlay:setMenu(nextMenu)
        nextMenu:setEnabled(true)
        reloadChangelog()
        print("[Universal Hub] UI reloaded")
        return true
    end

    session.reloadUi = reloadUi
    if configuration.HotReload == true and type(readfile) == "function" then
        local watched = {
            root .. "/ui/Menu.lua",
            root .. "/ui/WhatsNew.lua",
            root .. "/ui/presentation/Catalog.lua",
            root .. "/changelog.json",
        }
        local menuStampPath = configuration.MenuStampPath
        if type(menuStampPath) == "string" and menuStampPath ~= "" then
            table.insert(watched, menuStampPath)
        end
        local last = {}
        for _, path in ipairs(watched) do
            last[path] = fingerprint(path)
        end
        local elapsed = 0
        local connection = RunService.Heartbeat:Connect(function(dt)
            elapsed += dt
            if elapsed < 0.4 then
                return
            end
            elapsed = 0
            local dirty = false
            local restageMenu = false
            for _, path in ipairs(watched) do
                local nextHash = fingerprint(path)
                if nextHash ~= last[path] then
                    last[path] = nextHash
                    dirty = true
                    if path == menuStampPath then
                        restageMenu = true
                    end
                end
            end
            if dirty then
                pcall(reloadUi, { restageMenu = restageMenu })
            end
        end)
        session:Add(function()
            connection:Disconnect()
        end)
    end
end)
if not finalized then
    session:stop()
    error(finalError, 0)
end
return session
