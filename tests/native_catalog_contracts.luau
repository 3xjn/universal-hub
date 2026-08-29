local roblox = require("@lune/roblox")
Enum = roblox.Enum
Color3 = roblox.Color3

local Catalog = require("../ui/presentation/Catalog")
local Presentation = require("../games/rivals/Presentation")

local settings = {
    aimAssistStrength = 60,
    aimSmoothness = 0,
    headshotRate = 100,
    missRate = 0,
    silentAim = false,
    shotAim = false,
    humanAim = false,
    triggerBot = false,
    alwaysScoped = false,
    skipDeflect = false,
    autoDeflect = false,
    rapidFire = false,
    fireRate = 200,
    flickProjectiles = false,
    quickReload = false,
    meleeReach = false,
    meleeReachScale = 200,
    triggerDelay = 0,
    cameraFov = 58,
    cameraFullScreenAim = false,
    cameraTargetMode = "radius",
    fov = 58,
    minimumFov = 40,
    maximumFov = 500,
    fullScreenAim = false,
    shotFov = 96,
    shotFullScreenAim = true,
    shotTargetMode = "fullscreen",
    teleportBehind = false,
    boxes = true,
    chams = true,
    chamsExcludeAccessories = false,
    chamsPerPart = false,
    names = true,
    health = true,
    weapon = true,
    showEnemies = true,
    showTeammates = false,
    worldRenderer = "limn",
    espOutlineColor = "",
    espFillColor = "",
    espNameColor = "",
    espWeaponColor = "",
    espHealthLowColor = "",
    espHealthHighColor = "",
    espFillAlpha = -1,
}
local state = { menuVisible = true, settings = settings }
local writes = {}
local store = {}
function store:Get()
    return state
end
function store:Patch(patch)
    for key, value in pairs(patch) do
        state[key] = value
    end
end

local catalog = Catalog.new({
    store = store,
    capabilities = {
        "silentAim",
        "shotAim",
        "target360",
        "humanAim",
        "triggerBot",
        "triggerDelay",
        "rapidFire",
        "fireRate",
        "flickProjectiles",
        "quickReload",
        "meleeReach",
        "meleeReachScale",
        "skipDeflect",
        "autoDeflect",
        "alwaysScoped",
        "aimSmoothness",
        "aimAssistStrength",
        "headshotRate",
        "missRate",
        "boxes",
        "chams",
        "chamsExcludeAccessories",
        "chamsPerPart",
        "names",
        "health",
        "weapon",
        "worldRenderer",
        "showEnemies",
        "showTeammates",
        "teleportBehind",
    },
    setSetting = function(id, value)
        settings[id] = value
    end,
    setOption = function(id, value, persist)
        settings[id] = value
        if id == "shotAim" and value then
            settings.silentAim = false
            settings.humanAim = false
        elseif id == "silentAim" and value then
            settings.shotAim = false
        end
        table.insert(writes, { id, value, persist })
    end,
    setRate = function(id, value, persist)
        settings[id] = value
        table.insert(writes, { id, value, persist })
    end,
    setFov = function(value)
        settings[settings.shotAim and "shotFov" or "cameraFov"] = value
    end,
    getPreviewKey = function()
        return "preview-key"
    end,
    getPreviewSubject = function()
        return { marker = "preview-subject" }
    end,
})
Presentation.mount(catalog)
local ephemeralSettings = Catalog.collectEphemeralSettings(Presentation)
assert(ephemeralSettings.teleportBehind == true, "Rage settings must be inferred as ephemeral")
assert(ephemeralSettings.rapidFire == true and ephemeralSettings.fireRate == true)
assert(ephemeralSettings.triggerBot == nil, "Non-Rage settings must remain persistent")
local model = catalog:model(state)
local combat = model.pages[1]
assert(combat.id == "Combat")
local expected = { "aimMode", "targeting", "response", "trigger" }
for index, id in ipairs(expected) do
    assert(combat.sections[index].id == id, "RIVALS Combat hierarchy changed at " .. index)
end
assert(combat.sections[1].controls[1].kind == "segmented")
assert(combat.sections[1].controls[1].value == "off")
local targetMode = combat.sections[2].controls[1]
assert(targetMode.emphasis == "prominent" and targetMode.value == "radius")
assert(#targetMode.options == 3 and targetMode.options[3].value == "360")
assert(combat.sections[2].controls[2].id == "fov")
assert(combat.sections[3].controls[1].emphasis == "row")
local triggerIds = {}
for _, control in ipairs(combat.sections[4].controls) do
    triggerIds[control.id] = control
end
assert(triggerIds.rapidFire == nil, "Rapid Fire must not remain under Trigger Bot")
assert(triggerIds.quickReload and triggerIds.quickReload.label == "Quick Reload")
assert(triggerIds.meleeReach and triggerIds.meleeReach.label == "Melee Reach")
assert(triggerIds.meleeReachScale == nil, "Reach must wait until Melee Reach is on")
assert(triggerIds.triggerDelay == nil, "Delay must wait until Trigger Bot is on")
local rageControls = model.pages[2].sections[1].controls
assert(rageControls[1].id == "teleportBehind" and rageControls[2].id == "rapidFire")
assert(rageControls[2].label == "Rapid Fire")
settings.triggerBot = true
model = catalog:model(state)
local triggerControls = model.pages[1].sections[4].controls
assert(triggerControls[1].id == "triggerBot")
assert(triggerControls[2].id == "triggerDelay" and triggerControls[2].emphasis == "nested")
assert(triggerControls[2].parent == "triggerBot" and triggerControls[2].unit == "ms")
assert(triggerControls[2].min == 0 and triggerControls[2].max == 250)
triggerIds = {}
for _, control in ipairs(triggerControls) do
    triggerIds[control.id] = control
end
model.onValueChange("triggerDelay", 40, true)
assert(settings.triggerDelay == 40)
model.onValueChange("quickReload", true, true)
assert(settings.quickReload == true)
model.onValueChange("meleeReach", true, true)
model = catalog:model(state)
triggerIds = {}
for _, control in ipairs(model.pages[1].sections[4].controls) do
    triggerIds[control.id] = control
end
assert(triggerIds.meleeReachScale and triggerIds.meleeReachScale.parent == "meleeReach")
assert(triggerIds.meleeReachScale.min == 100 and triggerIds.meleeReachScale.max == 300)
assert(triggerIds.meleeReachScale.step == 5 and triggerIds.meleeReachScale.unit == "%")
model.onValueChange("meleeReachScale", 275, true)
assert(settings.meleeReachScale == 275)
model.onValueChange("rapidFire", true, true)
assert(writes[#writes][1] == "rapidFire" and writes[#writes][3] == false)
model = catalog:model(state)
rageControls = {}
for _, control in ipairs(model.pages[2].sections[1].controls) do
    rageControls[control.id] = control
end
assert(rageControls.fireRate and rageControls.fireRate.parent == "rapidFire")
assert(rageControls.fireRate.min == 100 and rageControls.fireRate.max == 1000)
assert(rageControls.fireRate.step == 5 and rageControls.fireRate.unit == "%")
model.onValueChange("fireRate", 250, true)
assert(settings.fireRate == 250 and writes[#writes][3] == false)

local writeCount = #writes
model.onValueChange("aimMode", "camera", true)
assert(writes[writeCount + 1][1] == "shotAim" and writes[writeCount + 1][2] == false)
assert(writes[writeCount + 2][1] == "silentAim" and writes[writeCount + 2][2] == true)
model = catalog:model(state)
assert(model.pages[1].sections[1].controls[1].value == "camera")
assert(#model.pages[1].sections[1].controls == 3)
assert(model.pages[1].sections[1].controls[2].id == "humanAim")
assert(model.pages[1].sections[1].controls[3].id == "flickProjectiles")
model.onValueChange("flickProjectiles", true, true)
assert(settings.flickProjectiles == true)
assert(model.pages[1].sections[4].id == "trigger")
assert(model.pages[1].sections[2].controls[2].value == 58)
model.onValueChange("fov", 72, true)
model.onValueChange("fullScreenAim", "360", true)
assert(settings.cameraFov == 72 and settings.cameraFullScreenAim == true)
assert(settings.cameraTargetMode == "360")
model = catalog:model(state)
assert(#model.pages[1].sections[2].controls == 1)
assert(model.pages[1].sections[2].controls[1].value == "360")

model.onValueChange("humanAim", true, true)
assert(settings.humanAim == true)
model.onValueChange("aimMode", "silent", true)
assert(settings.silentAim == false and settings.shotAim == true)
assert(settings.humanAim == false)
model = catalog:model(state)
assert(model.pages[1].sections[1].controls[1].value == "silent")
assert(#model.pages[1].sections[2].controls == 1)
assert(model.pages[1].sections[2].controls[1].value == "fullscreen")
assert(#model.pages[1].sections == 4)
assert(#model.pages[1].sections[1].controls == 1)
assert(model.pages[1].sections[4].id == "trigger")

model.onValueChange("aimMode", "camera", true)
assert(settings.humanAim == true)
model = catalog:model(state)
assert(model.pages[1].sections[1].controls[1].value == "camera")
assert(model.pages[1].sections[1].controls[2].id == "humanAim")
assert(model.pages[1].sections[1].controls[2].value == true)
assert(model.pages[1].sections[1].controls[3].id == "aimAssistStrength")
assert(model.pages[1].sections[1].controls[3].parent == "humanAim")
assert(model.pages[1].sections[1].controls[3].value == 60)
assert(model.pages[1].sections[1].controls[4].id == "flickProjectiles")
model.onValueChange("aimAssistStrength", 85, true)
assert(settings.aimAssistStrength == 85 and writes[#writes][3] == true)
assert(model.pages[1].sections[2].controls[1].value == "360")

local visuals
for _, page in ipairs(model.pages) do
    if page.id == "Visuals" then
        visuals = page
        break
    end
end
assert(visuals and visuals.layout == "toggle-grid")
assert(
    visuals.views[1].id == "preview"
        and visuals.views[1].label == "Preview"
        and visuals.views[2].id == "colors"
        and visuals.views[2].label == "ESP Colors",
    "Preview pages with a palette must publish their available views"
)
assert(visuals.preview.kind == "character" and visuals.preview.key == "preview-key")
assert(visuals.preview.resolve().marker == "preview-subject")
assert(visuals.preview.worldRenderer == "limn" and visuals.preview.chams == true)
assert(#visuals.preview.palette.relationships == 2)
local enemyPalette = visuals.preview.palette.relationships[1]
local teammatePalette = visuals.preview.palette.relationships[2]
assert(enemyPalette.id == "enemy" and teammatePalette.id == "teammate")
assert(#enemyPalette.targets == 6 and enemyPalette.fillAlpha == 0.18)
model.onValueChange("espColor:enemy:outline", "#123456", true)
model.onValueChange("espAlpha:enemy", 0.73, true)
assert(settings.espEnemyOutlineColor == "#123456" and settings.espEnemyFillAlpha == 0.73)
model = catalog:model(state)
for _, page in ipairs(model.pages) do
    if page.id == "Visuals" then
        visuals = page
        break
    end
end
enemyPalette = visuals.preview.palette.relationships[1]
assert(enemyPalette.targets[1].color == Color3.fromRGB(18, 52, 86))
assert(enemyPalette.fillAlpha == 0.73)
local rendererSection
local visualSection
for _, section in ipairs(visuals.sections) do
    if section.treatment == "style" then
        rendererSection = section
    elseif section.treatment == "grid" then
        visualSection = section
    end
end
assert(rendererSection and rendererSection.label == "ESP")
assert(rendererSection.treatment == "style", "ESP renderer selection must use style treatment")
assert(rendererSection.controls[1].label == "Style" and rendererSection.controls[1].value == "limn")
assert(
    visualSection and visualSection.treatment == "grid",
    "Visual toggle section must use grid treatment"
)
assert(#visualSection.controls == 7, "Native-only Chams options must stay hidden in Classic mode")
local classicControls = {}
for _, control in ipairs(visualSection.controls) do
    classicControls[control.id] = control
end
assert(
    classicControls.showEnemies.placement == "audience"
        and classicControls.showEnemies.parent == nil
        and classicControls.showTeammates.placement == "audience"
        and classicControls.showTeammates.parent == nil,
    "Audience controls must not emit a fake parent"
)
model.onValueChange("worldRenderer", "native", true)
assert(settings.worldRenderer == "native", "Renderer selection must preserve its string setting")
model = catalog:model(state)
for _, page in ipairs(model.pages) do
    if page.id == "Visuals" then
        visuals = page
        break
    end
end
for _, section in ipairs(visuals.sections) do
    if section.treatment == "grid" then
        visualSection = section
        break
    end
end
assert(visuals.preview.worldRenderer == "native")
assert(#visualSection.controls == 9, "Native Chams sub-options must appear only in Native mode")
local nativeControls = {}
for _, control in ipairs(visualSection.controls) do
    nativeControls[control.id] = control
end
assert(
    nativeControls.chamsExcludeAccessories.placement == "details"
        and nativeControls.chamsExcludeAccessories.parent == "chams"
        and nativeControls.chamsPerPart.placement == "details"
        and nativeControls.chamsPerPart.parent == "chams",
    "Chams child options must retain their real toggle parent"
)
model.onValueChange("teleportBehind", true, true)
assert(
    settings.teleportBehind == true
        and writes[#writes][1] == "teleportBehind"
        and writes[#writes][3] == false,
    "Rage toggles must update live with persistence disabled"
)
model.onValueChange("triggerBot", false, true)
assert(
    settings.triggerBot == false
        and writes[#writes][1] == "triggerBot"
        and writes[#writes][3] == true,
    "Non-Rage toggles must continue to persist"
)

local genericState = {
    menuVisible = true,
    settings = { fills = true, fillOutline = false, menuKey = "RightShift" },
}
local genericStore = {}
function genericStore:Get()
    return genericState
end
function genericStore:Patch() end
local genericCatalog = Catalog.new({
    store = genericStore,
    capabilities = { "fills", "fillOutline" },
    setOption = function() end,
    setRate = function() end,
    setFov = function() end,
})
genericCatalog:page("Visuals", { layout = "toggle-grid" })
genericCatalog:section("Visuals", "esp", "ESP", 70)
genericCatalog:option("esp", 1, "fills", "Fills")
genericCatalog:option("esp", 2, "fillOutline", "Fill Outline", {
    parent = "fills",
    placement = "details",
    visibility = "when-parent",
})
local genericModel = genericCatalog:model(genericState)
local genericVisuals
for _, page in ipairs(genericModel.pages) do
    if page.id == "Visuals" then
        genericVisuals = page
        break
    end
end
assert(
    genericVisuals.sections[1].id == "esp"
        and genericVisuals.sections[1].treatment == "grid"
        and genericVisuals.sections[1].controls[1].id == "fills"
        and genericVisuals.sections[1].controls[1].placement == "grid"
        and genericVisuals.sections[1].controls[2].id == "fillOutline"
        and genericVisuals.sections[1].controls[2].parent == "fills"
        and genericVisuals.sections[1].controls[2].placement == "details",
    "Toggle-grid layout must be driven by treatment and placement, not fixed ids"
)

local cosmeticState = {
    menuVisible = true,
    settings = { boxes = false, menuKey = "RightShift" },
    cosmetics = {
        minimumWear = 0,
        maximumWear = 1,
        skin = "Fade",
        skinLabel = "Fade",
        wear = 0.2,
        weapon = "Karambit",
        statTrak = true,
        supportsStatTrak = true,
    },
    gloves = {
        minimumWear = 0,
        maximumWear = 1,
        skin = "Vice",
        wear = 0.1,
        weapon = "Sports Gloves",
    },
}
local cosmeticStore = {}
function cosmeticStore:Get()
    return cosmeticState
end
function cosmeticStore:Patch() end
local cosmeticCatalog = Catalog.new({
    store = cosmeticStore,
    capabilities = { "boxes" },
    setOption = function() end,
    setRate = function() end,
    setFov = function() end,
    getWeaponPreviewKey = function()
        return "weapon-preview-key"
    end,
    getWeaponPreviewSubject = function()
        return { marker = "weapon-preview" }
    end,
})
cosmeticCatalog:page("Visuals", { layout = "toggle-grid" })
cosmeticCatalog:section("Visuals", "visuals", "VISUALS", 70)
cosmeticCatalog:option("visuals", 1, "boxes", "Hitboxes")
cosmeticCatalog:cosmetics()
local cosmeticModel = cosmeticCatalog:model(cosmeticState)
local cosmeticVisuals
for _, page in ipairs(cosmeticModel.pages) do
    assert(page.id ~= "Tools", "Cosmetics must not create a Tools tab")
    if page.id == "Visuals" then
        cosmeticVisuals = page
    end
end
assert(cosmeticVisuals and cosmeticVisuals.sections[2].id == "skin-changer")
assert(cosmeticVisuals.sections[3].id == "glove-changer")
local viewer = cosmeticVisuals.sections[2].controls[1]
assert(viewer.kind == "model-viewer" and viewer.key == "weapon-preview-key")
assert(viewer.resolve().marker == "weapon-preview")

local orderedCatalog = Catalog.new({
    store = cosmeticStore,
    capabilities = { "antiHit", "boxes" },
    setOption = function() end,
    setRate = function() end,
    setFov = function() end,
})
orderedCatalog:page("Tools", { order = 1 })
orderedCatalog:page("Visuals", { order = 2 })
orderedCatalog:section("Tools", "orderedTools", "TOOLS", 70)
orderedCatalog:option("orderedTools", 1, "antiHit", "Anti Hit")
orderedCatalog:section("Visuals", "orderedVisuals", "VISUALS", 70)
orderedCatalog:option("orderedVisuals", 1, "boxes", "Boxes")
local orderedModel = orderedCatalog:model(cosmeticState)
assert(
    orderedModel.pages[1].id == "Tools" and orderedModel.pages[2].id == "Visuals",
    "Page metadata must support game-specific tab ordering"
)

print("native-catalog-contracts-ok")
