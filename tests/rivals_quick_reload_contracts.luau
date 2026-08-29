local fs = require("@lune/fs")
local QuickReload = require("../games/rivals/features/QuickReload")

local adapterSource = fs.readFile("games/rivals/Adapter.lua")
assert(adapterSource:find('require("./features/QuickReload")', 1, true))
assert(
    adapterSource:find("quickReload:update(settings, fighter and fighter.EquippedItem)", 1, true)
)
assert(adapterSource:find("quickReload:stop()", 1, true))

local quickReload = QuickReload.new()
local rifle = {
    Info = {
        ReloadLength = 3,
        ReloadActionTimestamp = 1.56,
    },
}
quickReload:update({ quickReload = true }, rifle)
assert(rifle.Info.ReloadLength == 1.56, "Quick Reload must end when native ammo insertion occurs")

local handgun = {
    Info = {
        ReloadLength = 1.9,
        ReloadActionTimestamp = 1.06,
        EmptyReloadLength = 2.06,
        EmptyReloadActionTimestamp = 1.06,
    },
}
quickReload:update({ quickReload = true }, handgun)
assert(rifle.Info.ReloadLength == 3, "switching weapons must restore the previous reload length")
assert(handgun.Info.ReloadLength == 1.06 and handgun.Info.EmptyReloadLength == 1.06)

quickReload:update({ quickReload = false }, handgun)
assert(handgun.Info.ReloadLength == 1.9 and handgun.Info.EmptyReloadLength == 2.06)

local unsupported = {
    Info = {
        ReloadLength = 2,
        ReloadActionTimestamp = 0,
    },
}
quickReload:update({ quickReload = true }, unsupported)
assert(
    unsupported.Info.ReloadLength == 2,
    "Quick Reload must not erase reloads without an ammo event"
)
quickReload:stop()

print("rivals-quick-reload-contracts-ok")
