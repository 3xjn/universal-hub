local Jumps = {}

local DEFAULT_JUMP_HEIGHT = 7.2
local HEAD_MARGIN = 0.3
local LANDING_SLOP = 0.6

function Jumps.reach(useJumpPower, jumpPower, jumpHeight, gravity)
    local weight = math.max(type(gravity) == "number" and gravity or 196.2, 1)
    if useJumpPower == true and type(jumpPower) == "number" then
        return jumpPower * jumpPower / (2 * weight)
    end
    return type(jumpHeight) == "number" and jumpHeight or DEFAULT_JUMP_HEIGHT
end

-- Ceiling is measured from the soles to the top of the R15 head.
-- The root's top is about a stud short of that and clips box hops.
function Jumps.headClears(feetY, height, ceilingY)
    if ceilingY == nil then
        return true
    end
    if type(feetY) ~= "number" or type(height) ~= "number" or type(ceilingY) ~= "number" then
        return false
    end
    return ceilingY >= feetY + height + HEAD_MARGIN
end

function Jumps.hop(measurements)
    measurements = measurements or {}
    local topY = measurements.topY or 0
    local feetY = measurements.feetY or 0
    return {
        ceilingClear = Jumps.headClears(feetY, measurements.agentHeight, measurements.ceilingY),
        jumpHeight = Jumps.reach(
            measurements.useJumpPower,
            measurements.jumpPower,
            measurements.jumpHeight,
            measurements.gravity
        ),
        landing = measurements.landing,
        landingDistance = measurements.landingDistance,
        landingY = measurements.landingY,
        rise = topY - feetY,
        topY = topY,
    }
end

-- The landing has to be the box top just past the lip.
-- A fixed 3-stud probe lands on the floor behind a small crate.
function Jumps.accept(hop)
    if type(hop) ~= "table" then
        return false
    end
    local rise = hop.rise
    local jumpHeight = hop.jumpHeight
    local landingDistance = hop.landingDistance
    local landingY = hop.landingY
    local topY = hop.topY
    if type(rise) ~= "number"
        or type(jumpHeight) ~= "number"
        or type(landingDistance) ~= "number"
        or type(landingY) ~= "number"
        or type(topY) ~= "number"
    then
        return false
    end
    if rise < 0.25 or rise > jumpHeight - 0.75 then
        return false
    end
    if hop.ceilingClear ~= true then
        return false
    end
    if landingDistance < 0.3 or landingDistance > 4.5 then
        return false
    end
    return math.abs(landingY - topY) <= LANDING_SLOP
end

return Jumps
