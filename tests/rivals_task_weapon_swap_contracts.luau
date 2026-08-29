local Swap = require("../games/rivals/tasks/TaskWeaponSwap")
local released = 0
local equipped
local now = 1
local empty = { Info = { Class = "Primary", ShootDamage = 12 }, Data = { Ammo = 0 } }
local rifle = { Info = { Class = "Secondary", ShootDamage = 12 }, Data = { Ammo = 18 } }
local fighter = {
    EquippedItem = empty,
    GetEquippedItems = function()
        return { empty, rifle }
    end,
    EquipItem = function(self, item)
        equipped = item
        self.EquippedItem = item
        return true
    end,
}
local swap = Swap.new({
    clock = function()
        return now
    end,
    release = function()
        released += 1
    end,
    weaponPolicy = {
        ammo = function(i)
            return i.Data and i.Data.Ammo
        end,
        automationPolicy = function(i)
            local targeted = i.Info.ShootDamage ~= nil or i.Info.AttackDamage ~= nil
            return { cameraAim = targeted, triggerBot = targeted }
        end,
        capabilities = function(i)
            return {
                attack = i.Info.Class == "Melee" and "melee" or "gun",
                maxDoubleJumps = i.Info.MaxDoubleJumps or 0,
            }
        end,
        finishingDamage = function(i)
            return i.Info.ShootDamage or i.Info.AttackDamage
        end,
        taskMeleeInRange = function(i, distance)
            return i.Info.Class == "Melee"
                and type(i.Info.AttackReach) == "number"
                and type(distance) == "number"
                and distance <= i.Info.AttackReach
        end,
        triggerDamageReady = function()
            return true
        end,
    },
})
assert(
    swap:update(true, fighter) == true and equipped == rifle and released == 1,
    "empty task weapons must release fire and switch through Fighter:EquipItem"
)
local notEmpty = { Info = { ShootDamage = 12 }, Data = { Ammo = 1 } }
fighter.EquippedItem = notEmpty
equipped = nil
assert(
    swap:update(true, fighter) == false and equipped == nil,
    "task weapon swapping must not interrupt a weapon that still has ammo"
)

local primary =
    { Info = { Class = "Primary", ShootDamage = 12, MaxAmmo = 20 }, Data = { Ammo = 2 } }
local secondary = { Info = { Class = "Secondary", ShootDamage = 20 }, Data = { Ammo = 8 } }
local utility = { Info = { Class = "Utility", ShootDamage = 5 } }
fighter.EquippedItem = primary
fighter.GetEquippedItems = function()
    return { primary, false, utility, secondary }
end
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, { health = 100 }, 40) == true and equipped == secondary,
    "task combat must switch to a secondary whose available clip can finish when the primary remainder cannot"
)
local healthyPrimary =
    { Info = { Class = "Primary", ShootDamage = 12, MaxAmmo = 20 }, Data = { Ammo = 10 } }
fighter.EquippedItem = healthyPrimary
fighter.GetEquippedItems = function()
    return { healthyPrimary, secondary }
end
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, { health = 100 }, 40) == false and equipped == nil,
    "task combat must keep a primary whose remaining clip can finish"
)

fighter.EquippedItem = healthyPrimary
fighter.GetEquippedItems = function()
    return { healthyPrimary, secondary }
end
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, { health = 15 }, 40) == true and equipped == secondary,
    "a ready secondary must take a confirmed one-hit finish instead of passively holding primary"
)

local emptyPressure =
    { Info = { Class = "Primary", ShootDamage = 12, MaxAmmo = 20 }, Data = { Ammo = 0 } }
local utility = { Info = { Class = "Utility", Type = "Gun", ShootDamage = 30 }, Data = { Ammo = 2 } }
fighter.EquippedItem = emptyPressure
fighter.GetEquippedItems = function()
    return { emptyPressure, utility }
end
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, { health = 80 }, 20) == true and equipped == utility,
    "a ready targeted utility must sustain pressure when it has the strongest verified capacity"
)

local fists = {
    Info = {
        Class = "Melee",
        Type = "Melee",
        AttackDamage = 50,
        AttackReach = 7,
        MaxDoubleJumps = 1,
    },
    Data = {},
}
fighter.EquippedItem = emptyPressure
fighter.GetEquippedItems = function()
    return { emptyPressure, fists }
end
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, { health = 40 }, 5) == true and equipped == fists,
    "native melee reach must allow fists to secure a close finish"
)
fighter.EquippedItem = healthyPrimary
fighter.GetEquippedItems = function()
    return { healthyPrimary, fists }
end
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, { health = 100 }, 30, {
        mobilityNeedsDoubleJump = true,
    }) == true and equipped == fists,
    "a committed gap must equip the native double-jump melee item even outside attack reach"
)
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, { health = 100 }, 30, {
        mobilityNeedsDoubleJump = true,
    }) == false and equipped == nil,
    "the double-jump item must remain equipped through the committed traversal"
)

local counterGun = {
    Info = { Class = "Utility", Type = "Gun", ShootDamage = 10, DealsTrueDamage = true },
    Data = { Ammo = 10 },
}
local deflector = {
    Info = { DeflectDuration = 1, DeflectCooldown = 1 },
    _deflect_hash = 1,
}
fighter.EquippedItem = healthyPrimary
fighter.GetEquippedItems = function()
    return { healthyPrimary, counterGun }
end
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, { health = 100 }, 30, {
        counterActive = true,
        opponentItem = deflector,
    }) == true and equipped == counterGun,
    "verified defensive counters must trigger a committed true-damage weapon swap"
)
swap.pendingItem = secondary
assert(swap:update(false, fighter) == false and swap.pendingItem == nil, "disable must clear pending swaps")

local dictPrimary = { Info = { Class = "Primary", ShootDamage = 12 }, Data = { Ammo = 0 } }
local dictSecondary = { Info = { Class = "Secondary", ShootDamage = 20 }, Data = { Ammo = 8 } }
fighter.EquippedItem = dictPrimary
fighter.GetEquippedItems = function()
    return { [dictPrimary] = true, [dictSecondary] = true }
end
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, { health = 100 }, 40) == true and equipped == dictSecondary,
    "native GetEquippedItems item-to-boolean dictionaries must resolve their item keys"
)

local loadoutPrimary = { Info = { Class = "Primary", ShootDamage = 12 }, Data = { Ammo = 0 } }
local loadoutSecondary = { Info = { Class = "Secondary", ShootDamage = 20 }, Data = { Ammo = 8 } }
fighter.EquippedItem = loadoutPrimary
fighter.Items = { loadoutPrimary, loadoutSecondary }
fighter.GetEquippedItems = function()
    return { [loadoutPrimary] = true }
end
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, { health = 100 }, 40) == true and equipped == loadoutSecondary,
    "fighter.Items must supply the full native loadout when GetEquippedItems only reports the current item"
)
fighter.Items = nil

local blindPrimary =
    { Info = { Class = "Primary", ShootDamage = 12, MaxAmmo = 20 }, Data = { Ammo = 6 } }
local blindSecondary =
    { Info = { Class = "Secondary", ShootDamage = 12, MaxAmmo = 13 }, Data = { Ammo = 13 } }
fighter.EquippedItem = blindPrimary
fighter.Items = { blindPrimary, blindSecondary }
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, nil, nil) == false and equipped == nil,
    "unknown target health must not invent a full-health finish check"
)

local previousDamageReady = swap.weaponPolicy.triggerDamageReady
swap.weaponPolicy.triggerDamageReady = function()
    return false
end
fighter.EquippedItem = healthyPrimary
fighter.Items = { healthyPrimary, secondary }
equipped = nil
swap.nextAt = 0
assert(
    swap:update(true, fighter, { health = 100 }, 200) == false and equipped == nil,
    "two weapons outside their verified damage gate must not oscillate"
)
swap.weaponPolicy.triggerDamageReady = previousDamageReady
fighter.Items = nil

local delayedFighter = {
    EquippedItem = emptyPressure,
    Items = { emptyPressure, secondary },
    EquipItem = function()
        return true
    end,
}
local targetA = { character = {}, health = 100 }
local targetB = { character = {}, health = 100 }
swap:reset()
assert(swap:update(true, delayedFighter, targetA, 30) == true and swap.pendingItem == secondary)
assert(
    swap:update(true, delayedFighter, targetB, 30) == false and swap.pendingItem == nil,
    "a target replacement must cancel rather than retry a stale pending equip"
)
now = 10
secondary.Data.Ammo = 8
assert(swap:update(true, delayedFighter, targetA, 30) == true and swap.pendingItem == secondary)
secondary.Data.Ammo = 0
now = 10.2
local pendingRetry = swap:update(true, delayedFighter, targetA, 30)
assert(
    pendingRetry == false and swap.pendingItem == nil,
    "a pending equip must revalidate live ammo and readiness before retrying"
)
secondary.Data.Ammo = 8
swap.pendingItem = secondary
assert(
    swap:update(true, delayedFighter, targetB, 30, { fighterActive = false }) == false
        and swap.pendingItem == nil,
    "local death or fighter inactivity must clear pending equips"
)

print("rivals-task-weapon-swap-contracts-ok")
