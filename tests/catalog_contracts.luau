local fs = require("@lune/fs")
local Registry = require("../modules/Registry")
local Compatibility = require("../games/Compatibility")

local expectedCatalog = {
    "games/counterblox/Definition",
    "games/rivals/Definition",
    "games/town/Definition",
    "games/bloxstrike/Definition",
    "games/duelinggrounds/Definition",
}
local legacyIds = {
    counterblox = true,
    rivals = true,
    town = true,
}

local expectedDefaults = {
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
    fov = 180,
    fovCircle = true,
    fullScreenAim = false,
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

local expectedInitialState = {
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

local function deepEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not deepEqual(value, right[key]) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function assertDataOnly(value, path, seen)
    local valueType = type(value)
    assert(
        valueType == "nil"
            or valueType == "boolean"
            or valueType == "number"
            or valueType == "string"
            or valueType == "table",
        path .. " must contain only data"
    )
    if valueType ~= "table" then
        return
    end

    seen = seen or {}
    assert(not seen[value], path .. " must not contain cycles")
    seen[value] = true
    for key, child in pairs(value) do
        assertDataOnly(key, path .. " key", seen)
        assertDataOnly(child, path .. "." .. tostring(key), seen)
    end
    seen[value] = nil
end

local function assertDisjointTables(left, right, path, seen)
    if type(left) ~= "table" or type(right) ~= "table" then
        return
    end
    assert(left ~= right, path .. " must be deep-copied")
    seen = seen or {}
    if seen[left] then
        return
    end
    seen[left] = true
    for key, value in pairs(left) do
        assertDisjointTables(value, right[key], path .. "." .. tostring(key), seen)
    end
end

local Catalog = require("../games/Catalog")
assert(#Catalog >= #expectedCatalog, "Catalog must preserve the current games")
for index, path in ipairs(expectedCatalog) do
    assert(
        Catalog[index] == path,
        "Catalog order and current definition paths must remain explicit"
    )
end

local definitions = {}
local rawDefinitions = {}
for _, path in ipairs(Catalog) do
    local rawDefinition = require("../" .. path)
    assertDataOnly(rawDefinition, path)
    Registry.Validate(rawDefinition)
    local definition = Compatibility.Compose(rawDefinition)
    Registry.Validate(definition)
    assert(
        definition.factory == nil and definition.match == nil,
        path .. " must not contain runtime callbacks"
    )
    assert(type(definition.defaults) == "table", path .. " must compose defaults")
    assert(type(definition.initialState) == "table", path .. " must compose initial state")
    if legacyIds[definition.id] then
        local expected = expectedDefaults
        local expectedState = expectedInitialState
        if definition.id == "rivals" then
            expected = Compatibility.Defaults()
            expected.autoCounter = false
            expected.redLightSafety = false
            expected.taskAutomationPaused = true
            expected.taskAutomationEmergencyKey = "End"
            expected.infiniteJump = false
            expected.wallNoclip = false
            expected.teleportBehind = false
            expected.skipDeflect = false
            expected.autoDeflect = false
            expected.unlockAllSkins = false
            expected.unlockAllSkinsRestore = {}
            expected.triggerDelay = 0
            expectedState = Compatibility.InitialState()
        end
        assert(
            deepEqual(definition.defaults, expected),
            path .. " must preserve the existing config defaults"
        )
        assert(
            deepEqual(definition.initialState, expectedState),
            path .. " must preserve the selected-game initial state shape"
        )
    end
    assert(fs.isFile(path .. ".lua"), path .. " must resolve to a definition source")
    assert(fs.isFile(definition.module .. ".lua"), path .. " must resolve to its behavior module")
    assert(
        fs.isFile(definition.presentation .. ".lua"),
        path .. " must resolve to its presentation module"
    )
    assert(
        table.find(definition.sources, definition.module)
            and table.find(definition.sources, definition.presentation),
        path .. " must own its behavior and presentation sources"
    )
    if definition.composition then
        assert(
            fs.isFile(definition.composition .. ".lua")
                and table.find(definition.sources, definition.composition),
            path .. " must own its optional composition source"
        )
    end
    for _, source in ipairs(definition.sources) do
        assert(fs.isFile(source .. ".lua"), path .. " declares a missing source: " .. source)
    end

    local second = Compatibility.Compose(rawDefinition)
    assert(deepEqual(definition, second), path .. " must compose deterministically")
    assertDisjointTables(rawDefinition, definition, path .. " raw definition")
    assertDisjointTables(definition, second, path .. " composed definition")
    definition.defaults.skinOverrides.__catalogContract = true
    definition.initialState.cosmetics.skin = "Mutated"
    assert(
        second.defaults.skinOverrides.__catalogContract == nil
            and second.initialState.cosmetics.skin == "Stock",
        path .. " must isolate composed compatibility tables"
    )
    definition = second
    definitions[definition.id] = definition
    rawDefinitions[definition.id] = rawDefinition
end

for _, id in ipairs({ "counterblox", "rivals", "town" }) do
    local defaultsAreSparse = next(rawDefinitions[id].defaults) == nil
    local initialStateIsSparse = next(rawDefinitions[id].initialState) == nil
    if id == "rivals" then
        local count = 0
        for _ in pairs(rawDefinitions[id].defaults) do
            count += 1
        end
        defaultsAreSparse = count == 12
            and rawDefinitions[id].defaults.autoCounter == false
            and rawDefinitions[id].defaults.redLightSafety == false
            and rawDefinitions[id].defaults.taskAutomationPaused == true
            and rawDefinitions[id].defaults.taskAutomationEmergencyKey == "End"
            and rawDefinitions[id].defaults.infiniteJump == false
            and rawDefinitions[id].defaults.wallNoclip == false
            and rawDefinitions[id].defaults.teleportBehind == false
            and rawDefinitions[id].defaults.skipDeflect == false
            and rawDefinitions[id].defaults.autoDeflect == false
            and rawDefinitions[id].defaults.unlockAllSkins == false
            and type(rawDefinitions[id].defaults.unlockAllSkinsRestore) == "table"
            and next(rawDefinitions[id].defaults.unlockAllSkinsRestore) == nil
            and rawDefinitions[id].defaults.triggerDelay == 0
        initialStateIsSparse = next(rawDefinitions[id].initialState) == nil
    end
    assert(
        defaultsAreSparse and initialStateIsSparse,
        id .. " definition must contain only sparse compatibility additions"
    )
end
assert(definitions.counterblox.label == "Counterblox")
assert(definitions.counterblox.module == "games/Counterblox")
assert(definitions.counterblox.composition == "games/counterblox/Composition")
assert(deepEqual(definitions.counterblox.hydroxide, { "targeting" }))
assert(definitions.counterblox.features.cosmetics == nil)
assert(table.find(definitions.counterblox.features.capabilities, "wallbang"))

assert(definitions.bloxstrike.label == "Bloxstrike")
assert(definitions.bloxstrike.module == "games/Bloxstrike")
assert(definitions.bloxstrike.composition == "games/bloxstrike/Composition")
assert(deepEqual(definitions.bloxstrike.hydroxide, { "targeting" }))
assert(table.find(definitions.bloxstrike.features.capabilities, "wallbang"))

assert(definitions.rivals.label == "RIVALS")
assert(definitions.rivals.module == "games/rivals/Adapter")
assert(definitions.rivals.composition == nil)
assert(deepEqual(definitions.rivals.hydroxide, { "targeting" }))
assert(definitions.rivals.features.cosmetics == false)
assert(definitions.rivals.features.optionLabels.silentAim == "Camera Aim")
assert(deepEqual(definitions.rivals.features.exclusiveOptions.shotAim, { "silentAim", "humanAim" }))
assert(not table.find(definitions.rivals.features.capabilities, "wallbang"))

assert(definitions.town.label == "Town")
assert(definitions.town.module == "games/Town")
assert(definitions.town.composition == "games/town/Composition")
assert(deepEqual(definitions.town.hydroxide, {}))
assert(definitions.town.features.cosmetics == false)
assert(deepEqual(definitions.town.features.capabilities, { "plotCopy" }))

local registry = Registry.new()
for _, path in ipairs(Catalog) do
    registry:Register(Compatibility.Compose(require("../" .. path)))
end
assert(registry:Resolve({ gameId = 7633926880, placeId = 114234929420007 }).id == "bloxstrike")
assert(registry:Resolve({ gameId = 115797356, placeId = 301549746 }).id == "counterblox")
assert(registry:Resolve({ gameId = 6035872082, placeId = 17625359962 }).id == "rivals")
assert(registry:Resolve({ gameId = 6035872082, placeId = 133215910299950 }).id == "rivals")
assert(registry:Resolve({ gameId = 1718755273, placeId = 4991214437 }).id == "town")
assert(registry:Resolve({ gameId = 9051406594, placeId = 94217045453265 }).id == "duelinggrounds")

local counterCopy = Compatibility.Compose(rawDefinitions.counterblox)
local rivalsCopy = Compatibility.Compose(rawDefinitions.rivals)
counterCopy.defaults.skinOverrides.test = true
counterCopy.initialState.cosmetics.skin = "Mutated"
assert(
    rivalsCopy.defaults.skinOverrides.test == nil
        and rivalsCopy.initialState.cosmetics.skin == "Stock"
        and next(rawDefinitions.counterblox.defaults) == nil
        and next(rawDefinitions.counterblox.initialState) == nil,
    "Compatibility composition must deep-copy every shared and game-owned table"
)

for _, path in ipairs({
    "games/Counterblox.lua",
    "games/rivals/Adapter.lua",
    "games/Town.lua",
}) do
    local source = fs.readFile(path)
    assert(not source:find(".factory =", 1, true), path .. " must not expose registration metadata")
    assert(
        not source:find(".sources =", 1, true),
        path .. " must not expose source inventory metadata"
    )
end

print("catalog-contracts-ok")
