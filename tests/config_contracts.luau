local Config = require("../modules/Config")

local files = {
    ["universal-hub/configs/counterblox.json"] = "saved",
}
local writes = {}
local decoded = {
    fov = 320,
    espOutlineColor = "#123456",
    espFillAlpha = 0.73,
    fullScreenAim = true,
    silentAim = true,
    taskAutomationPaused = false,
    teleportBehind = true,
    gloveOverride = {
        skin = "Crimson Weave",
        wear = 0.63,
        weapon = "Driver Gloves",
    },
    gloveColorOverride = {
        b = 0.7,
        g = 0.4,
        r = 0.2,
    },
    skinOverrides = {
        ["AK-47"] = {
            skin = "PinPoint",
            statTrak = true,
            wear = 0.1,
        },
        ["T Knife"] = {
            skin = "Fade",
            statTrak = false,
            wear = 0.07,
            weapon = "Karambit",
        },
    },
    unknown = "ignored",
}

local config = Config.new({
    decode = function(source)
        assert(source == "saved")
        return decoded
    end,
    encode = function(value)
        assert(value.fullScreenAim == true)
        assert(value.cameraFov == 320 and value.shotFov == 320)
        assert(value.cameraFullScreenAim == true and value.shotFullScreenAim == true)
        assert(value.cameraTargetMode == "fullscreen" and value.shotTargetMode == "fullscreen")
        assert(value.espOutlineColor == "#123456" and value.espFillAlpha == 0.73)
        assert(value.skinOverrides["AK-47"].skin == "PinPoint")
        assert(value.skinOverrides["T Knife"].weapon == "Karambit")
        assert(value.gloveOverride.skin == "Crimson Weave")
        assert(value.gloveOverride.wear == 0.63)
        assert(value.gloveColorOverride.r == 0.2)
        assert(value.taskAutomationEnabled == true and value.taskAutomationPaused == nil)
        assert(value.unknown == nil)
        assert(value.teleportBehind == nil, "Ephemeral settings must be omitted from config writes")
        return "encoded"
    end,
    isFile = function(path)
        return files[path] ~= nil
    end,
    omittedKeys = {
        teleportBehind = true,
    },
    path = "universal-hub/configs/counterblox.json",
    readFile = function(path)
        return files[path]
    end,
    writeFile = function(path, value)
        writes[path] = value
    end,
})

local loaded = config:load({
    cameraFov = 180,
    cameraFullScreenAim = false,
    cameraTargetMode = "radius",
    fov = 180,
    espOutlineColor = "",
    espFillAlpha = -1,
    fullScreenAim = false,
    gloveOverride = false,
    gloveColorOverride = false,
    silentAim = false,
    shotFov = 180,
    shotFullScreenAim = false,
    shotTargetMode = "radius",
    teleportBehind = false,
    skinOverrides = {},
    taskAutomationEnabled = false,
})
assert(loaded.fov == 320 and loaded.fullScreenAim == true and loaded.silentAim == true)
assert(loaded.cameraFov == 320 and loaded.shotFov == 320)
assert(loaded.cameraFullScreenAim == true and loaded.shotFullScreenAim == true)
assert(loaded.cameraTargetMode == "fullscreen" and loaded.shotTargetMode == "fullscreen")
assert(loaded.espOutlineColor == "#123456" and loaded.espFillAlpha == 0.73)
assert(loaded.skinOverrides["AK-47"].wear == 0.1)
assert(loaded.skinOverrides["T Knife"].skin == "Fade")
assert(loaded.skinOverrides["T Knife"].weapon == "Karambit")
assert(loaded.gloveOverride.weapon == "Driver Gloves")
assert(loaded.gloveOverride.wear == 0.63)
assert(loaded.gloveColorOverride.b == 0.7)
assert(loaded.taskAutomationEnabled == true, "Legacy pause=false must migrate to enabled=true")
assert(loaded.unknown == nil, "Per-game config must ignore unknown top-level settings")
assert(loaded.teleportBehind == false, "Old configs must not restore ephemeral Rage settings")

loaded.teleportBehind = true
loaded.worldRenderer = "native"
config:save(loaded)
assert(writes["universal-hub/configs/counterblox.json"] == "encoded")

local function loadTaskAutomation(saved)
    return Config.new({
        decode = function()
            return saved
        end,
        isFile = function()
            return true
        end,
        path = "task.json",
        readFile = function()
            return "saved"
        end,
    }):load({ taskAutomationEnabled = false }).taskAutomationEnabled
end
assert(loadTaskAutomation({ taskAutomationPaused = true }) == false)
assert(loadTaskAutomation({ taskAutomationPaused = false }) == true)
assert(
    loadTaskAutomation({ taskAutomationEnabled = false, taskAutomationPaused = false }) == false,
    "The positive task setting must win when both schemas are present"
)
assert(loadTaskAutomation({ taskAutomationPaused = "false" }) == false)

local prettyWrites = {}
local prettyConfig = Config.new({
    encode = function()
        return '{"enabled":true,"label":"commas, braces { and escapes \\" stay intact","nested":{"value":3},"items":[1,2]}'
    end,
    path = "pretty.json",
    writeFile = function(path, value)
        prettyWrites[path] = value
    end,
})
prettyConfig:save({})
assert(
    prettyWrites["pretty.json"]
        == '{\n    "enabled": true,\n    "label": "commas, braces { and escapes \\" stay intact",\n    "nested": {\n        "value": 3\n    },\n    "items": [\n        1,\n        2\n    ]\n}'
)
print("config-contracts-ok")
