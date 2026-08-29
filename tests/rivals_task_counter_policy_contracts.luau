local Counter = require("../games/rivals/tasks/TaskCounterPolicy")
local now = 0
local c = Counter.new({
    clock = function()
        return now
    end,
})
local shield = { Info = { MaxAbsorption = 500 } }
local katana = { _deflect_hash = 1, Info = { DeflectDuration = 1, DeflectCooldown = 4 } }
local rifle = { Info = { ShootDamage = 12 } }
local spray = { Info = { DealsTrueDamage = true, BurstCount = 5, Type = "Gun" } }

assert(
    Counter.hasShieldOrKatana({ rifle, shield })
        and Counter.hasShieldOrKatana({ katana })
        and Counter.hasShieldOrKatana({ [shield] = true })
)
assert(
    Counter.shouldSelectSpray({ shield }) == true and Counter.shouldSelectSpray({ katana }) == true,
    "an absorber or deflector in the opponent loadout must make Spray available as our secondary"
)
assert(
    Counter.shouldForceSpray(spray, katana) == true
        and Counter.shouldForceSpray(spray, rifle) == false
        and Counter.shouldForceSpray({ Info = { ShootDamage = 12 } }, katana) == false,
    "true-damage spray may bypass deflection only while the opponent actually holds a defensive item"
)

assert(c:update(katana) == false)
now = 1.0
assert(c:update(katana) == false, "brief Katana holds must not force a weaker weapon")
now = 1.3
assert(c:update(katana) == true, "a sustained defensive hold may activate Spray counterplay")
now = 1.5
assert(c:update(rifle) == true, "counter release should resist one-frame equipped-item noise")
now = 2.3
assert(c:update(rifle) == false, "returning to an offensive weapon must release Spray counterplay")
now = 3
assert(c:update(katana, "target-a") == false)
now = 4.3
assert(c:update(katana, "target-a") == true)
assert(
    c:update(katana, "target-b") == false,
    "counter commitment must debounce again when task targeting changes opponents"
)
c:reset()
assert(c.active == false and c.targetKey == nil, "counter reset must clear engagement state")

print("rivals-task-counter-policy-contracts-ok")
