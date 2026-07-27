local ScopedAccuracy = require("../games/rivals/ScopedAccuracy")

local enabled = false
local nativeCalls = 0
local restored = {}
local replacements = {}

local function nativeIsFullyAiming(item)
    nativeCalls += 1
    return item.nativeFullyAiming
end

local eligibleItem = {
    Data = {
        IsAiming = false,
    },
    Info = {
        AimScopePercent = 0.5,
    },
    IsFullyAiming = nativeIsFullyAiming,
    ViewModel = {
        CurrentAimValue = 0,
    },
    nativeFullyAiming = false,
}
local fighter = {
    EquippedItem = eligibleItem,
}

local alwaysScoped = ScopedAccuracy.new({
    getFighter = function()
        return fighter
    end,
    hookFunction = function(target, replacement)
        replacements[target] = replacement
        return target
    end,
    isEnabled = function()
        return enabled
    end,
    restoreFunction = function(target)
        restored[target] = (restored[target] or 0) + 1
        replacements[target] = nil
    end,
})

alwaysScoped:refreshHook()
local replacement = replacements[nativeIsFullyAiming]
assert(type(replacement) == "function", "eligible equipped items must install the native scoped-state hook")
assert(
    replacement(eligibleItem) == false and nativeCalls == 1,
    "disabled Always Scoped must preserve the native result"
)

enabled = true
assert(replacement(eligibleItem) == true, "enabled Always Scoped must report an eligible shot as scoped")
assert(
    eligibleItem.Data.IsAiming == false
        and eligibleItem.ViewModel.CurrentAimValue == 0
        and nativeCalls == 1,
    "Always Scoped must not mutate aim state or evaluate the native result when overriding it"
)

local differentItem = {
    Info = {
        AimScopePercent = 0.5,
    },
    nativeFullyAiming = false,
}
assert(
    replacement(differentItem) == false and nativeCalls == 2,
    "the hook must preserve native behavior for a different self"
)

local ineligibleItem = {
    Info = {},
    IsFullyAiming = nativeIsFullyAiming,
    nativeFullyAiming = false,
}
fighter.EquippedItem = ineligibleItem
alwaysScoped:refreshHook()
assert(
    restored[nativeIsFullyAiming] == 1 and replacements[nativeIsFullyAiming] == nil,
    "equipping an ineligible item must restore the previous eligible hook"
)

local ineligibleHooks = 0
local ineligibleAlwaysScoped = ScopedAccuracy.new({
    getFighter = function()
        return {
            EquippedItem = ineligibleItem,
        }
    end,
    hookFunction = function()
        ineligibleHooks += 1
        return nativeIsFullyAiming
    end,
    isEnabled = function()
        return true
    end,
    restoreFunction = function() end,
})
ineligibleAlwaysScoped:refreshHook()
assert(ineligibleHooks == 0, "items without a positive numeric AimScopePercent must never be hooked")
ineligibleAlwaysScoped:stop()

fighter.EquippedItem = eligibleItem
alwaysScoped:refreshHook()
assert(type(replacements[nativeIsFullyAiming]) == "function")
alwaysScoped:stop()
alwaysScoped:stop()
assert(
    restored[nativeIsFullyAiming] == 2 and replacements[nativeIsFullyAiming] == nil,
    "stopping Always Scoped must restore its hook exactly once"
)
assert(
    replacements[nativeIsFullyAiming] == nil,
    "a stopped Always Scoped instance must leave no callable override behind"
)

print("scoped-accuracy-contracts-ok")
