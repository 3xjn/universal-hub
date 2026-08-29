local Compatibility = {}

local DEFAULTS = {
    aimSmoothness = 0,
    autoPickup = false,
    bhop = false,
    boxes = true,
    bombTimer = true,
    chams = true,
    chamsExcludeAccessories = false,
    chamsPerPart = false,
    cameraFov = 180,
    cameraFullScreenAim = false,
    cameraTargetMode = "radius",
    fov = 180,
    fovCircle = true,
    -- Legacy shared palette remains for config migration; relationship-specific
    -- values take precedence when customized.
    espFillAlpha = -1,
    espFillColor = "",
    espHealthHighColor = "",
    espHealthLowColor = "",
    espNameColor = "",
    espOutlineColor = "",
    espWeaponColor = "",
    espEnemyOutlineColor = "",
    espEnemyFillColor = "",
    espEnemyFillAlpha = -1,
    espEnemyNameColor = "",
    espEnemyWeaponColor = "",
    espEnemyHealthLowColor = "",
    espEnemyHealthHighColor = "",
    espTeammateOutlineColor = "",
    espTeammateFillColor = "",
    espTeammateFillAlpha = -1,
    espTeammateNameColor = "",
    espTeammateWeaponColor = "",
    espTeammateHealthLowColor = "",
    espTeammateHealthHighColor = "",
    fullScreenAim = false,
    gloveColorOverride = false,
    gloveOverride = false,
    headshotRate = 0,
    health = true,
    humanAim = false,
    knifeAura = false,
    maximumFov = 500,
    menuKey = "RightShift",
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
    shotFov = 180,
    shotFullScreenAim = false,
    shotTargetMode = "radius",
    shotAim = false,
    showEnemies = true,
    showTeammates = false,
    silentAim = false,
    skinOverrides = {},
    spinBot = false,
    triggerBot = false,
    utilityEsp = true,
    wallbang = false,
    weapon = true,
    worldRenderer = "limn",
}

local INITIAL_STATE = {
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
        confirmedProgress = 0,
        context = "",
        phase = "Ready",
        state = "idle",
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
}

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local function merge(base, additions)
    local result = copy(base)
    for key, value in pairs(additions or {}) do
        if type(value) == "table" and type(result[key]) == "table" then
            result[key] = merge(result[key], value)
        else
            result[key] = copy(value)
        end
    end
    return result
end

function Compatibility.Compose(definition)
    assert(type(definition) == "table", "Compatibility composition requires a game definition")
    local result = copy(definition)
    result.defaults = merge(DEFAULTS, definition.defaults)
    result.initialState = merge(INITIAL_STATE, definition.initialState)
    return result
end

function Compatibility.Defaults()
    return copy(DEFAULTS)
end

function Compatibility.InitialState()
    return copy(INITIAL_STATE)
end

return Compatibility
