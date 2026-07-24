local Config = require("../modules/Config")

local files = {
    ["universal-hub/configs/counterblox.json"] = "saved",
}
local writes = {}
local decoded = {
    fov = 320,
    fullScreenAim = true,
    silentAim = true,
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
        assert(value.skinOverrides["AK-47"].skin == "PinPoint")
        assert(value.skinOverrides["T Knife"].weapon == "Karambit")
        assert(value.gloveOverride.skin == "Crimson Weave")
        assert(value.gloveOverride.wear == 0.63)
        assert(value.gloveColorOverride.r == 0.2)
        assert(value.unknown == nil)
        return "encoded"
    end,
    isFile = function(path)
        return files[path] ~= nil
    end,
    path = "universal-hub/configs/counterblox.json",
    readFile = function(path)
        return files[path]
    end,
    writeFile = function(path, value)
        writes[path] = value
    end,
})

local loaded = config:load({
    fov = 180,
    fullScreenAim = false,
    gloveOverride = false,
    gloveColorOverride = false,
    silentAim = false,
    skinOverrides = {},
})
assert(loaded.fov == 320 and loaded.fullScreenAim == true and loaded.silentAim == true)
assert(loaded.skinOverrides["AK-47"].wear == 0.1)
assert(loaded.skinOverrides["T Knife"].skin == "Fade")
assert(loaded.skinOverrides["T Knife"].weapon == "Karambit")
assert(loaded.gloveOverride.weapon == "Driver Gloves")
assert(loaded.gloveOverride.wear == 0.63)
assert(loaded.gloveColorOverride.b == 0.7)
assert(loaded.unknown == nil, "Per-game config must ignore unknown top-level settings")

config:save(loaded)
assert(writes["universal-hub/configs/counterblox.json"] == "encoded")
print("config-contracts-ok")
