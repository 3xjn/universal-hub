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

local oh = environment.oh
assert(
    oh
        and oh.drawing
        and oh.targeting
        and type(oh.drawing.createSurface) == "function"
        and type(oh.targeting.nearestPlayer) == "function",
    "Universal Hub requires the Hydroxide core to be loaded first"
)

local drawingControls = assert(oh.load, "Universal Hub requires Hydroxide helper loading")("controls")

local previous = environment.UniversalHubSession
if previous and type(previous.stop) == "function" then
    previous:stop()
end

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Store = import("modules/Store")
local Config = import("modules/Config")
local InputCapture = import("modules/InputCapture")
local MenuToggle = import("modules/MenuToggle")
local Registry = import("modules/Registry")
local Session = import("modules/Session")
local Overlay = import("modules/Overlay")
local Counterblox = import("games/Counterblox")
local Town = import("games/Town")
local Rivals = import("games/rivals/Adapter")
local RivalsTargeting = import("games/rivals/Targeting")
local RivalsProjectileAim = import("games/rivals/ProjectileAim")
local RivalsShotPresentation = import("games/rivals/ShotPresentation")
local RivalsScopedAccuracy = import("games/rivals/ScopedAccuracy")
local RivalsWeaponPolicy = import("games/rivals/WeaponPolicy")
local RivalsEffects = import("games/rivals/Effects")
local RivalsMovement = import("games/rivals/Movement")
local RivalsCombatState = import("games/rivals/CombatState")

local registry = Registry.new()
registry:Register(Counterblox)
registry:Register(Town)
registry:Register(Rivals)

local adapterDefinition = registry:Resolve({
    gameId = game.GameId,
    placeId = game.PlaceId,
})
assert(
    adapterDefinition,
    ("Universal Hub does not support game %s / place %s"):format(tostring(game.GameId), tostring(game.PlaceId))
)

local defaultSettings = {
    aimSmoothness = 0,
    autoPickup = false,
    bhop = false,
    boxes = true,
    bombTimer = true,
    chams = true,
    fov = 180,
    fovCircle = true,
    fullScreenAim = false,
    gloveColorOverride = false,
    gloveOverride = false,
    headshotRate = 0,
    health = true,
    humanAim = false,
    knifeAura = false,
    maximumFov = 500,
    microStep = false,
    minimumFov = 40,
    missRate = 0,
    names = true,
    noFlash = false,
    noRecoil = false,
    noSmoke = false,
    noSpread = false,
    noWeaponSlow = false,
    rapidFire = false,
    alwaysScoped = false,
    shotAim = false,
    silentAim = false,
    skinOverrides = {},
    spinBot = false,
    triggerBot = false,
    utilityEsp = true,
    wallbang = false,
    weapon = true,
}
local configPath = configuration.ConfigPath or ("universal-hub/configs/%s.json"):format(adapterDefinition.id)
local configStore = Config.new({
    decode = function(source)
        return HttpService:JSONDecode(source)
    end,
    encode = function(value)
        return HttpService:JSONEncode(value)
    end,
    isFile = type(isfile) == "function" and isfile or nil,
    path = configPath,
    readFile = type(readfile) == "function" and readfile or nil,
    writeFile = type(writefile) == "function" and writefile or nil,
})
local settings = configStore:load(defaultSettings)
local hasPersistedConfig = type(isfile) == "function" and isfile(configPath)
if not hasPersistedConfig then
    for name, value in pairs(environment.UniversalHubSettings or {}) do
        if settings[name] ~= nil then
            settings[name] = value
        end
    end
end

local store = Store.new({
    activeWeapon = nil,
    activeWeaponKind = nil,
    cosmeticWeapon = nil,
    cosmetics = {
        maximumWear = 1,
        minimumWear = 0,
        skin = "Stock",
        skinCount = 1,
        skinIndex = 1,
        statTrak = false,
        supportsStatTrak = false,
        wear = 0,
        weapon = nil,
    },
    cosmeticMode = "weapon",
    cosmeticsOpen = false,
    error = nil,
    menuVisible = true,
    observations = {},
    plotCopy = {
        active = false,
        phase = "Ready",
        progress = 0,
    },
    bombObservation = {
        visible = false,
    },
    utilityObservations = {},
    gloves = {
        maximumWear = 1,
        minimumWear = 0,
        skin = "Game equipped",
        skinCount = 1,
        skinIndex = 0,
        wear = 0,
        weapon = "Gloves",
    },
    settings = settings,
    status = ("Loading %s"):format(adapterDefinition.label),
})
environment.UniversalHubSettings = store:Get().settings

local session
local overlay
local adapter
local inputCapture = InputCapture.new({
    releaseMouseOnDisable = adapterDefinition.id == "town",
})
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

local adapterCapabilities = type(adapterDefinition.capabilitiesFor) == "function"
        and adapterDefinition.capabilitiesFor({
            fireTouchInterestAvailable = type(environment.firetouchinterest) == "function",
            gameId = game.GameId,
            placeId = game.PlaceId,
        })
    or adapterDefinition.capabilities
overlay = Overlay.new({
    capabilities = adapterCapabilities,
    cosmetics = adapterDefinition.cosmetics,
    cycleGlove = function(direction)
        adapter:cycleGlove(direction)
    end,
    drawing = oh.drawing,
    drawingControls = drawingControls,
    gameLabel = adapterDefinition.label,
    getCamera = function()
        return Workspace.CurrentCamera
    end,
    listPlotOwners = function()
        if adapter and type(adapter.listPlotOwners) == "function" then
            return adapter:listPlotOwners()
        end
        return {}
    end,
    copyPlot = function(ownerName, saveName)
        if not adapter or type(adapter.copyPlot) ~= "function" then
            return false, "Plot copying is not ready"
        end
        task.spawn(function()
            adapter:copyPlot(ownerName, saveName)
        end)
        return true
    end,
    reportPlotCopyError = function(message)
        store:Patch({
            error = message,
            status = message,
        })
    end,
    uiParent = (function()
        local success, parent = pcall(function()
            if type(gethui) == "function" then
                return gethui()
            end
            return game:GetService("CoreGui")
        end)
        return success and parent or nil
    end)(),
    optionLabels = adapterDefinition.optionLabels,
    setFov = function(value)
        session:setFov(value)
    end,
    setCosmeticsOpen = function(open)
        session:setCosmeticsOpen(open)
    end,
    setCosmeticMode = function(mode)
        session:setCosmeticMode(mode)
    end,
    setInputCaptured = setInputCaptured,
    setMenuVisible = function(visible)
        session:setMenuVisible(visible)
    end,
    setOption = function(name, enabled)
        session:setOption(name, enabled)
        if enabled and adapterDefinition.exclusiveOptions then
            for _, excluded in ipairs(
                adapterDefinition.exclusiveOptions[name] or {}
            ) do
                session:setOption(excluded, false)
            end
        end
    end,
    setRate = function(name, value)
        session:setRate(name, value)
    end,
    cycleSkin = function(direction)
        adapter:cycleSkin(direction)
    end,
    cycleCosmeticWeapon = function(direction)
        adapter:cycleCosmeticWeapon(direction)
    end,
    resetSkin = function()
        adapter:resetSkin()
    end,
    resetGlove = function()
        adapter:resetGlove()
    end,
    setGloveWear = function(alpha)
        adapter:setGloveWear(alpha)
    end,
    setGloveColor = function(color)
        adapter:setGloveColor(color)
    end,
    setWear = function(alpha)
        adapter:setWear(alpha)
    end,
    toggleStatTrak = function()
        adapter:toggleStatTrak()
    end,
    store = store,
})

local created, result = pcall(adapterDefinition.new, {
    aimClick = mouse2click,
    aimPress = mouse2press,
    aimRelease = mouse2release,
    click = mouse1click,
    fireTouchInterest = type(environment.firetouchinterest) == "function"
            and environment.firetouchinterest
        or nil,
    press = mouse1press,
    release = mouse1release,
    gcObjects = function()
        return getgc(true)
    end,
    getLoadedModules = type(environment.getloadedmodules) == "function"
            and environment.getloadedmodules
        or nil,
    hookFunction = hookfunction,
    isInputCaptured = function()
        return inputCapture:IsEnabled()
    end,
    isFireHeld = function()
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end,
    isJumpHeld = function()
        return UserInputService:IsKeyDown(Enum.KeyCode.Space)
    end,
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
    oh = oh,
    render = function(observations, mousePosition, utilityObservations)
        overlay:render(observations, mousePosition, utilityObservations)
    end,
    restoreFunction = restorefunction,
    settingsChanged = function(updatedSettings)
        configStore:save(updatedSettings)
    end,
    setThirdPerson = setThirdPerson,
    rivalsTargeting = RivalsTargeting,
    projectileAim = RivalsProjectileAim,
    shotPresentation = RivalsShotPresentation,
    alwaysScoped = RivalsScopedAccuracy,
    weaponPolicy = RivalsWeaponPolicy,
    effects = RivalsEffects,
    movement = RivalsMovement,
    combatState = RivalsCombatState,
    store = store,
})
if not created then
    overlay:destroy()
    store:Destroy()
    error(result, 0)
end
adapter = result

session = Session.new({
    adapter = adapter,
    environment = environment,
    overlay = overlay,
    settingsChanged = function(updatedSettings)
        configStore:save(updatedSettings)
    end,
    store = store,
})
session.adapterId = adapterDefinition.id
session.game = adapterDefinition.label
session.registry = registry
session.state = store:Get()
session.store = store
local menuToggleConnection = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if MenuToggle.shouldToggle(input, gameProcessedEvent, UserInputService) then
        session:toggleMenu()
    end
end)
session:Add(function()
    menuToggleConnection:Disconnect()
end)
session:Add(function()
    inputCapture:Destroy()
end)

oh.Resources = oh.Resources or {}
table.insert(oh.Resources, session)
local readyStatus = ("%s ready"):format(adapterDefinition.label)
store:Patch({ status = readyStatus })
print("[Universal Hub]", readyStatus)
return session
