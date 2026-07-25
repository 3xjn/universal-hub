local roblox = require("@lune/roblox")
Color3 = roblox.Color3
Enum = roblox.Enum
UDim = roblox.UDim
UDim2 = roblox.UDim2
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
Drawing = {
    Fonts = {
        Plex = 2,
    },
}

local Store = require("../modules/Store")
local Overlay = require("../modules/Overlay")

local nodes = {}
local destroyed = false
local surface = {}

function surface:create(kind, properties)
    local node = {
        callbacks = {},
        Kind = kind,
    }
    for key, value in pairs(properties) do
        node[key] = value
    end
    function node:on(eventName, callback)
        self.callbacks[eventName] = callback
    end
    table.insert(nodes, node)
    return node
end

function surface:destroy()
    destroyed = true
end

local utilityPaintCallback
function surface:paint(zIndex, callback)
    assert(zIndex == 68, "Utility zone mesh must stay behind its marker and label")
    utilityPaintCallback = callback
    return {
        Disconnect = function() end,
    }
end

local store = Store.new({
    activeWeapon = "AWP",
    cosmetics = {
        maximumWear = 0.15,
        minimumWear = 0,
        skin = "Nebula_PATTERN_11",
        skinLabel = "Nebula (Pattern 11)",
        skinCount = 8,
        skinIndex = 2,
        statTrak = true,
        supportsStatTrak = true,
        wear = 0.1,
        weapon = "AK-47",
    },
    cosmeticMode = "weapon",
    cosmeticsOpen = false,
    gloves = {
        maximumWear = 0.8,
        minimumWear = 0.1,
        skin = "Crimson Weave",
        skinCount = 42,
        skinIndex = 8,
        wear = 0.25,
        weapon = "Driver Gloves",
    },
    menuVisible = true,
    settings = {
        aimSmoothness = 35,
        bombTimer = true,
        boxes = true,
        chams = true,
        fov = 180,
        fovCircle = true,
        fullScreenAim = false,
        gloveColorOverride = false,
        headshotRate = 50,
        health = true,
        humanAim = false,
        bhop = false,
        knifeAura = false,
        maximumFov = 500,
        microStep = false,
        minimumFov = 40,
        missRate = 10,
        names = true,
        noFlash = false,
        noRecoil = false,
        noSmoke = false,
        noSpread = false,
        noWeaponSlow = false,
        rapidFire = false,
        silentAim = false,
        spinBot = false,
        triggerBot = false,
        utilityEsp = true,
        wallbang = false,
        weapon = true,
    },
    status = "Ready",
})
local optionChanges = {}
local fovChanges = {}
local rateChanges = {}
local captures = {}
local menuVisibilityChanges = {}
local cosmeticsVisibilityChanges = {}
local cosmeticActions = {}
local cosmeticWeaponChanges = {}
local guiInstances = {}
local function createInstance(className)
    local instance = {
        ClassName = className,
        Destroyed = false,
    }
    function instance:Destroy()
        self.Destroyed = true
    end
    table.insert(guiInstances, instance)
    return instance
end
local overlay = Overlay.new({
    capabilities = {
        "aimSmoothness",
        "bhop",
        "bombTimer",
        "boxes",
        "chams",
        "headshotRate",
        "health",
        "knifeAura",
        "microStep",
        "missRate",
        "names",
        "noFlash",
        "noRecoil",
        "noSmoke",
        "noSpread",
        "noWeaponSlow",
        "rapidFire",
        "silentAim",
        "spinBot",
        "triggerBot",
        "utilityEsp",
        "wallbang",
        "weapon",
    },
    cycleGlove = function(direction)
        table.insert(cosmeticActions, { action = "cycleGlove", value = direction })
    end,
    cycleSkin = function(direction)
        table.insert(cosmeticActions, { action = "cycle", value = direction })
    end,
    cycleCosmeticWeapon = function(direction)
        table.insert(cosmeticWeaponChanges, direction)
    end,
    createInstance = createInstance,
    drawing = {
        createSurface = function()
            return surface
        end,
        supports = function()
            return true
        end,
    },
    gameLabel = "Test Game",
    getCamera = function()
        return {
            ViewportSize = Vector2.new(1280, 720),
        }
    end,
    optionLabels = {
        silentAim = "Camera Aim",
    },
    uiParent = {},
    setFov = function(value)
        table.insert(fovChanges, value)
    end,
    setCosmeticsOpen = function(value)
        table.insert(cosmeticsVisibilityChanges, value)
    end,
    setInputCaptured = function(value)
        table.insert(captures, value)
    end,
    setMenuVisible = function(value)
        table.insert(menuVisibilityChanges, value)
    end,
    setRate = function(name, value)
        table.insert(rateChanges, { name = name, value = value })
    end,
    setOption = function(name, value)
        table.insert(optionChanges, { name = name, value = value })
    end,
    resetSkin = function()
        table.insert(cosmeticActions, { action = "reset" })
    end,
    resetGlove = function()
        table.insert(cosmeticActions, { action = "resetGlove" })
    end,
    setCosmeticMode = function(mode)
        table.insert(cosmeticActions, { action = "mode", value = mode })
    end,
    setGloveWear = function(value)
        table.insert(cosmeticActions, { action = "gloveWear", value = value })
    end,
    setGloveColor = function(value)
        table.insert(cosmeticActions, { action = "gloveColor", value = value })
    end,
    setWear = function(value)
        table.insert(cosmeticActions, { action = "wear", value = value })
    end,
    store = store,
    toggleStatTrak = function()
        table.insert(cosmeticActions, { action = "statTrak" })
    end,
})

assert(captures[1] == true, "A visible Drawing menu must immediately release and own the cursor")
assert(overlay.controls.title.Text == "Universal Hub · Test Game")
assert(overlay.controls.options.silentAim.label.Text == "Camera Aim")
overlay.controls.options.silentAim.row.callbacks.click()
assert(optionChanges[1].name == "silentAim" and optionChanges[1].value == true)
assert(overlay.controls.sections.rage.label.Text == "RAGE")
assert(overlay.controls.sections.melee.label.Text == "MELEE")
assert(overlay.controls.sections.movement.label.Text == "MOVEMENT")
assert(overlay.controls.sections.visuals.label.Text == "VISUALS")
assert(overlay.controls.options.wallbang.label.Text == "Wallbang")
assert(overlay.controls.options.wallbang.marker ~= nil)
assert(overlay.controls.options.microStep.label.Text == "Micro Step")
assert(overlay.controls.options.microStep.marker ~= nil)
assert(overlay.controls.options.noFlash.label.Text == "No Flash")
assert(overlay.controls.options.noSmoke.label.Text == "No Smoke")
assert(overlay.controls.options.noWeaponSlow.label.Text == "No Weapon Slow")
assert(overlay.controls.options.rapidFire.label.Text == "Rapid Fire")
assert(overlay.controls.options.boxes.label.Text == "Hitboxes")
assert(overlay.controls.options.chams.label.Text == "Chams")
assert(overlay.controls.rates.aimSmoothness.label.Text == "Aim Smoothness")
assert(overlay.controls.rates.headshotRate.label.Text == "Headshot Rate")
assert(overlay.controls.rates.missRate.label.Text == "Miss Rate")
assert(overlay.controls.rates.headshotRate.value.Text == "50%")
assert(overlay.controls.rates.missRate.value.Text == "10%")
assert(overlay.controls.rates.aimSmoothness.value.Text == "35%")
local bombAdornee = {}
store:Patch({
    bombObservation = {
        adornee = bombAdornee,
        presentation = {
            alwaysOnTop = true,
            height = 30,
            textSize = 13,
            visible = true,
            width = 92,
        },
        remaining = 37.4,
        visible = true,
    },
})
assert(overlay.worldGui.billboard.Enabled and overlay.worldGui.billboard.Adornee == bombAdornee)
assert(
    overlay.worldGui.title.Text == "BOMB"
        and overlay.worldGui.timer.Text == "37.4s"
        and overlay.worldGui.accent.BackgroundColor3 == Color3.fromRGB(98, 214, 173),
    "Bomb telemetry must use the Hub's split-label panel and accent treatment instead of a raw debug badge"
)
local collapsedPanelHeight = overlay.controls.panel.Size.Y
assert(
    overlay.controls.panel.Position.Y + collapsedPanelHeight
        > overlay.controls.options.noSmoke.row.Position.Y + overlay.controls.options.noSmoke.row.Size.Y,
    "Collapsed cosmetics must contain every available option"
)
assert(overlay.controls.fovLabel.Text == "FOV · 180 px")
assert(
    overlay.controls.fovValue.Text == "Fullscreen Off",
    "Fullscreen aim must be an explicit control instead of a hidden numeric-value gesture"
)
overlay.controls.fovModeButton.callbacks.click()
assert(optionChanges[2].name == "fullScreenAim" and optionChanges[2].value == true)
store:Patch({
    settings = {
        fullScreenAim = true,
    },
})
assert(overlay.controls.fovValue.Text == "Fullscreen On")
assert(overlay.controls.fovCircle.Visible == false, "Fullscreen aim must hide the radius circle")
store:Patch({
    settings = {
        wallbang = true,
    },
})
assert(
    overlay.controls.options.wallbang.value.Text == "Standby",
    "Wallbang must show that it is configured but inherited from disabled Silent Aim"
)
store:Patch({
    settings = {
        silentAim = true,
    },
})
assert(overlay.controls.options.wallbang.value.Text == "On")
overlay.controls.hideButton.callbacks.click()
assert(menuVisibilityChanges[1] == false, "Hide control must request a hidden menu")

assert(
    overlay.controls.panel.callbacks.pointerenter == nil and overlay.controls.panel.callbacks.pointerleave == nil,
    "Cursor capture must follow menu visibility instead of fragile pointer edge events"
)

overlay.controls.sliderHit.callbacks.pointerdown(nil, Vector2.new(1280, 0))
assert(#fovChanges == 0, "Disabled FOV slider must ignore pointer input in fullscreen mode")
store:Patch({ settings = { fullScreenAim = false } })
overlay.controls.sliderHit.callbacks.pointerdown(nil, Vector2.new(1280, 0))
assert(fovChanges[1] == 500, "FOV pointer input must clamp through the slider")
overlay.controls.rates.headshotRate.hit.callbacks.pointerdown(
    nil,
    Vector2.new(overlay.controls.rates.headshotRate.hit.Position.X + 207, 0)
)
overlay.controls.rates.missRate.hit.callbacks.drag(
    nil,
    Vector2.new(overlay.controls.rates.missRate.hit.Position.X + 69, 0)
)
assert(
    rateChanges[1].name == "headshotRate"
        and rateChanges[1].value == 75
        and rateChanges[2].name == "missRate"
        and rateChanges[2].value == 25,
    "Accuracy sliders must publish rounded percentages"
)

local panelStart = overlay.controls.panel.Position
overlay.controls.panel.callbacks.pointerdown(nil, panelStart + Vector2.new(10, 10))
overlay.controls.panel.callbacks.drag(nil, Vector2.new(510, 40))
assert(
    overlay.controls.panel.Position ~= panelStart
        and overlay.controls.title.Position
            == overlay.controls.panel.Position + Vector2.new(12, 12),
    "Dragging the panel must move the complete Hub window as one unit within the viewport"
)

overlay.controls.cosmetics.header.callbacks.click()
assert(cosmeticsVisibilityChanges[1] == true)
store:Patch({ cosmeticsOpen = true })
assert(
    overlay.controls.panel.Size.Y > collapsedPanelHeight,
    "Opening cosmetics must expand the panel below its option controls"
)
assert(
    overlay.controls.cosmetics.skinName.Text == "Nebula (Pattern 11)",
    "Cosmetic controls must show the readable variant label without replacing its raw ID"
)
assert(overlay.controls.cosmetics.weaponModeLabel.Text == "AK-47")
assert(overlay.controls.cosmetics.gloveModeLabel.Text == "Gloves")
assert(overlay.controls.cosmetics.weaponMode.Color == Color3.fromRGB(23, 53, 45))
assert(overlay.controls.cosmetics.gloveMode.Color == Color3.fromRGB(21, 28, 35))
local weaponNext = overlay.controls.cosmetics.weaponNext
local skinNext = overlay.controls.cosmetics.next
assert(
    weaponNext.Position.Y + weaponNext.Size.Y < skinNext.Position.Y,
    "Weapon and skin arrow hit regions must remain separated by the menu spacing rhythm"
)
overlay.controls.cosmetics.weaponPrevious.callbacks.click()
overlay.controls.cosmetics.weaponNext.callbacks.click()
assert(
    cosmeticWeaponChanges[1] == -1 and cosmeticWeaponChanges[2] == 1,
    "Weapon selector arrows must browse cosmetics independently of the equipped weapon"
)
overlay.controls.cosmetics.previous.callbacks.click()
overlay.controls.cosmetics.next.callbacks.click()
overlay.controls.cosmetics.statTrak.callbacks.click()
overlay.controls.cosmetics.reset.callbacks.click()
overlay.controls.cosmetics.wearHit.callbacks.pointerdown(nil, Vector2.new(1280, 0))
assert(cosmeticActions[1].value == -1 and cosmeticActions[2].value == 1)
assert(cosmeticActions[3].action == "statTrak" and cosmeticActions[4].action == "reset")
assert(cosmeticActions[5].action == "wear" and cosmeticActions[5].value == 1)

overlay.controls.cosmetics.gloveMode.callbacks.click()
assert(cosmeticActions[6].action == "mode" and cosmeticActions[6].value == "gloves")
store:Patch({ cosmeticMode = "gloves" })
assert(overlay.controls.cosmetics.weaponModeLabel.Text == "Weapons")
assert(overlay.controls.cosmetics.gloveModeLabel.Text == "Driver Gloves")
assert(overlay.controls.cosmetics.weaponMode.Color == Color3.fromRGB(21, 28, 35))
assert(overlay.controls.cosmetics.gloveMode.Color == Color3.fromRGB(23, 53, 45))
assert(overlay.controls.cosmetics.skinName.Text == "Crimson Weave")
assert(overlay.controls.cosmetics.statTrakLabel.Text == "Solid Color")
assert(overlay.controls.cosmetics.statTrakValue.Text == "Off")
overlay.controls.cosmetics.statTrak.callbacks.click()
assert(cosmeticActions[7].action == "gloveColor" and type(cosmeticActions[7].value) == "table")
local glovePanelHeightBeforeColor = overlay.controls.panel.Size.Y
store:Patch({
    settings = {
        gloveColorOverride = {
            b = 0.75,
            g = 0.5,
            r = 0.25,
        },
    },
})
assert(
    overlay.controls.panel.Size.Y > glovePanelHeightBeforeColor,
    "Enabling glove color controls must expand the cosmetics panel"
)
assert(overlay.controls.cosmetics.statTrakValue.Text == "On")
assert(overlay.controls.cosmetics.colorChannels.r.value.Text == "64")
assert(overlay.controls.cosmetics.colorChannels.g.value.Text == "128")
assert(overlay.controls.cosmetics.colorChannels.b.value.Text == "191")
assert(overlay.controls.cosmetics.colorChannels.r.hit.Visible == true)
overlay.controls.cosmetics.colorChannels.r.hit.callbacks.pointerdown(nil, Vector2.new(0, 0))
assert(
    cosmeticActions[8].action == "gloveColor" and cosmeticActions[8].value.r == 0,
    "RGB sliders must publish a complete solid glove color"
)
overlay.controls.cosmetics.previous.callbacks.click()
overlay.controls.cosmetics.next.callbacks.click()
overlay.controls.cosmetics.wearHit.callbacks.pointerdown(nil, Vector2.new(1280, 0))
overlay.controls.cosmetics.reset.callbacks.click()
assert(cosmeticActions[9].action == "cycleGlove" and cosmeticActions[9].value == -1)
assert(cosmeticActions[10].action == "cycleGlove" and cosmeticActions[10].value == 1)
assert(cosmeticActions[11].action == "gloveWear" and cosmeticActions[11].value == 1)
assert(cosmeticActions[12].action == "resetGlove")

local player = { Name = "Opponent" }
overlay:render({
    {
        bounds = {
            position = Vector2.new(100, 100),
            size = Vector2.new(50, 100),
        },
        bodyParts = {
            {
                bounds = {
                    position = Vector2.new(116, 100),
                    size = Vector2.new(18, 18),
                },
                corners = {
                    Vector2.new(116, 100),
                    Vector2.new(132, 101),
                    Vector2.new(132, 117),
                    Vector2.new(116, 118),
                    Vector2.new(119, 103),
                    Vector2.new(135, 104),
                    Vector2.new(135, 120),
                    Vector2.new(119, 121),
                },
                visible = true,
            },
            {
                bounds = {
                    position = Vector2.new(110, 120),
                    size = Vector2.new(30, 42),
                },
                corners = {
                    Vector2.new(110, 120),
                    Vector2.new(136, 121),
                    Vector2.new(136, 158),
                    Vector2.new(110, 160),
                    Vector2.new(114, 124),
                    Vector2.new(140, 125),
                    Vector2.new(140, 162),
                    Vector2.new(114, 164),
                },
                visible = false,
            },
        },
        health = 72,
        maxHealth = 100,
        player = player,
        visible = true,
        weapon = "AK-47",
    },
}, Vector2.new(640, 360))
local playerNodes = overlay.playerNodes[player]
assert(playerNodes.box.Visible == true, "Hitboxes must draw one square around the whole character")
assert(playerNodes.box.Position == Vector2.new(100, 100))
assert(playerNodes.box.Size == Vector2.new(50, 100))
assert(#playerNodes.bodyParts == 2)
assert(playerNodes.bodyParts[1].outline == nil, "Hitboxes must not create boxes around individual body parts")
assert(#playerNodes.bodyParts[1].faces == 6)
assert(playerNodes.bodyParts[1].faces[1].Visible == true)
assert(playerNodes.bodyParts[1].faces[1].Filled == true)
assert(playerNodes.bodyParts[1].faces[1].Transparency == 0.18)
assert(playerNodes.bodyParts[1].faces[1].PointA == Vector2.new(116, 100))
assert(playerNodes.bodyParts[1].faces[1].PointB == Vector2.new(132, 101))
assert(playerNodes.bodyParts[1].faces[1].PointC == Vector2.new(132, 117))
assert(playerNodes.bodyParts[1].faces[1].PointD == Vector2.new(116, 118))
assert(playerNodes.bodyParts[1].faces[2].PointA == Vector2.new(119, 103))
assert(playerNodes.bodyParts[1].faces[2].PointB == Vector2.new(119, 121))
assert(playerNodes.bodyParts[1].faces[2].PointC == Vector2.new(135, 120))
assert(playerNodes.bodyParts[1].faces[2].PointD == Vector2.new(135, 104))
assert(playerNodes.bodyParts[1].faces[1].Color == Color3.fromRGB(98, 214, 173))
assert(#playerNodes.bodyParts[2].faces == 6)
assert(playerNodes.bodyParts[2].faces[1].Visible == true)
assert(playerNodes.bodyParts[2].faces[1].PointA == Vector2.new(110, 120))
assert(playerNodes.bodyParts[2].faces[1].PointB == Vector2.new(136, 121))
assert(playerNodes.bodyParts[2].faces[1].PointC == Vector2.new(136, 158))
assert(playerNodes.bodyParts[2].faces[1].PointD == Vector2.new(110, 160))
assert(playerNodes.bodyParts[2].faces[1].Color == Color3.fromRGB(230, 107, 110))

store:Patch({ settings = { boxes = false } })
overlay:render(overlay.observations, Vector2.new(640, 360))
assert(playerNodes.box.Visible == false, "Disabling Hitboxes must hide the character square")
assert(playerNodes.bodyParts[1].faces[1].Visible == true, "Disabling Hitboxes must preserve Chams")
store:Patch({ settings = { boxes = true, chams = false } })
overlay:render(overlay.observations, Vector2.new(640, 360))
assert(playerNodes.box.Visible == true, "Hitboxes must remain independently available")
assert(playerNodes.bodyParts[1].faces[1].Visible == false, "Chams must control only filled cuboid faces")
overlay.optionSupport.chams = false
overlay:_renderState(store:Get())
assert(overlay.controls.options.chams.value.Text == "N/A")
local optionChangeCount = #optionChanges
overlay.controls.options.chams.row.callbacks.click()
assert(#optionChanges == optionChangeCount, "Unsupported Chams must not publish a misleading setting change")
overlay.optionSupport.chams = true
store:Patch({ settings = { chams = true } })
overlay:render(overlay.observations, Vector2.new(640, 360))

assert(playerNodes.name.Text == "Opponent" and playerNodes.name.Visible == true)
assert(playerNodes.healthTrack.Visible == true and playerNodes.healthFill.Visible == true)
assert(playerNodes.healthTrack.Position == Vector2.new(93, 100))
assert(playerNodes.healthTrack.Size == Vector2.new(4, 100))
assert(playerNodes.healthFill.Position.X == 94)
assert(math.abs(playerNodes.healthFill.Position.Y - 128.44) < 1e-4)
assert(playerNodes.healthFill.Size.X == 2)
assert(math.abs(playerNodes.healthFill.Size.Y - 70.56) < 1e-4)
assert(playerNodes.weapon.Text == "AK-47")
local detailedObservations = overlay.observations
overlay:render({
    {
        bounds = {
            position = Vector2.new(40, 50),
            size = Vector2.new(60, 120),
        },
        health = 1,
        maxHealth = 1,
        player = player,
        visible = true,
    },
}, Vector2.new(100, 100))
assert(playerNodes.weapon.Visible == false, "ESP must omit a weapon label when an adapter has no weapon data")
overlay:render(detailedObservations, Vector2.new(640, 360))
overlay:render(detailedObservations, Vector2.new(640, 360), {
    {
        label = "HE",
        onScreen = true,
        polygons = {},
        screenPosition = Vector2.new(320, 240),
        tone = "danger",
    },
    {
        label = "FIRE ZONE",
        onScreen = true,
        polygons = {
            {
                Vector2.new(400, 300),
                Vector2.new(440, 300),
                Vector2.new(440, 330),
                Vector2.new(400, 330),
            },
        },
        screenPosition = Vector2.new(420, 290),
        tone = "danger",
    },
})
assert(
    overlay.utilityNodes[1].marker.Visible
        and overlay.utilityNodes[1].label.Text == "HE",
    "Moving utility observations must render a compact labeled marker"
)
assert(
    overlay.utilityNodes[2].label.Text == "FIRE ZONE",
    "Replicated damage tiles must retain their projected zone label"
)
local paintedTriangles = {}
utilityPaintCallback({
    FilledTriangle = function(pointA, pointB, pointC, color, opacity)
        table.insert(paintedTriangles, {
            color = color,
            opacity = opacity,
            points = { pointA, pointB, pointC },
        })
    end,
})
assert(
    #paintedTriangles == 2
        and paintedTriangles[1].opacity == 0.14
        and paintedTriangles[1].color == Color3.fromRGB(230, 107, 110),
    "Multi-polygon damage zones must paint as one immediate Drawing triangle mesh instead of retained square objects"
)
assert(
    overlay.utilityNodes[2].zones == nil,
    "Immediate utility meshes must not allocate one retained Drawing object per voxel"
)
store:Patch({ settings = { utilityEsp = false } })
overlay:render(detailedObservations, Vector2.new(640, 360), {
    {
        label = "HE",
        onScreen = true,
        polygons = {},
        screenPosition = Vector2.new(320, 240),
        tone = "danger",
    },
})
assert(
    overlay.utilityNodes[1].marker.Visible == false
        and overlay.utilityZonePaint.enabled == false,
    "Disabling Utility ESP must hide both moving markers and persistent zones"
)
store:Patch({ settings = { utilityEsp = true } })

store:Patch({ menuVisible = false })
assert(captures[2] == false, "Hiding the Drawing menu must restore gameplay input")
assert(overlay.controls.panel.Visible == false)
assert(overlay.controls.options.silentAim.row.Visible == false)
assert(playerNodes.box.Visible == true)
assert(playerNodes.bodyParts[1].faces[1].Visible == true, "Hiding the menu must not hide enabled player overlays")
assert(overlay.controls.fovCircle.Visible == true, "Hiding the menu must not hide the enabled FOV circle")

overlay:destroy()
overlay:destroy()
assert(destroyed == true, "Overlay destroy must tear down the Drawing surface")

store:Patch({ menuVisible = true })
local rivalsOverlay = Overlay.new({
    capabilities = {
        "aimSmoothness",
        "humanAim",
        "silentAim",
        "triggerBot",
        "headshotRate",
        "missRate",
        "boxes",
        "chams",
        "names",
        "health",
        "weapon",
    },
    cosmetics = false,
    drawing = {
        createSurface = function()
            return surface
        end,
        supports = function()
            return true
        end,
    },
    gameLabel = "RIVALS",
    getCamera = function()
        return {
            ViewportSize = Vector2.new(1280, 720),
        }
    end,
    optionLabels = {
        humanAim = "Human Aim",
        silentAim = "Camera Aim",
    },
    setRate = function() end,
    store = store,
})
assert(rivalsOverlay.controls.options.silentAim.label.Text == "Camera Aim")
assert(rivalsOverlay.controls.options.humanAim.label.Text == "Human Aim")
assert(rivalsOverlay.controls.options.triggerBot ~= nil)
assert(
    rivalsOverlay.controls.rates.aimSmoothness
        and rivalsOverlay.controls.rates.headshotRate
        and rivalsOverlay.controls.rates.missRate,
    "RIVALS must expose all configured aim-rate controls"
)
assert(rivalsOverlay.controls.options.wallbang == nil)
assert(rivalsOverlay.controls.options.noSpread == nil)
assert(rivalsOverlay.controls.options.knifeAura == nil)
assert(rivalsOverlay.controls.sections.rage ~= nil and rivalsOverlay.controls.sections.visuals ~= nil)
assert(rivalsOverlay.controls.sections.melee == nil and rivalsOverlay.controls.sections.movement == nil)
assert(
    rivalsOverlay.controls.cosmetics.header.Visible == false,
    "Adapters without cosmetics must omit the Counterblox cosmetics disclosure"
)
assert(
    rivalsOverlay.controls.panel.Size.Y < 596,
    "Capability filtering must collapse the panel around the remaining controls"
)
rivalsOverlay:destroy()
print("overlay-contracts-ok")
