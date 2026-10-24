local Agent = {}

local FOOT_NAMES = { "LeftFoot", "RightFoot" }
local DEFAULT_HIP = 2
local HIP_TOLERANCE = 0.75

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isBasePart(part)
    return type(part) == "table" and type(part.IsA) == "function" and part:IsA("BasePart")
end

-- R15 HipHeight is the gap under the root, not an R6 leg length.
-- An equipped gear can leave HipHeight at 0 or inflate it while the feet
-- stay on the ground, so the soles win when they disagree.
function Agent.footOffset(root, character, hipHeight)
    local hip = finite(hipHeight) and math.max(hipHeight, 0) or DEFAULT_HIP
    local declared = hip + root.Size.Y / 2
    local lowestSole = nil
    if type(character) == "table" and type(character.FindFirstChild) == "function" then
        for _, name in ipairs(FOOT_NAMES) do
            local foot = character:FindFirstChild(name)
            if isBasePart(foot) then
                local sole = foot.Position.Y - foot.Size.Y / 2
                if lowestSole == nil or sole < lowestSole then
                    lowestSole = sole
                end
            end
        end
    end
    if lowestSole ~= nil then
        local measured = root.Position.Y - lowestSole
        if math.abs(measured - declared) > HIP_TOLERANCE then
            return math.max(measured, root.Size.Y / 2)
        end
    end
    return declared
end

function Agent.profile(character, humanoid, root)
    local hip = humanoid and humanoid.HipHeight or DEFAULT_HIP
    local footOffset = Agent.footOffset(root, character, hip)
    local feetY = root.Position.Y - footOffset
    local head = type(character) == "table" and type(character.FindFirstChild) == "function"
            and character:FindFirstChild("Head")
        or nil
    local top
    if isBasePart(head) then
        top = head.Position.Y + head.Size.Y / 2
    else
        top = root.Position.Y + root.Size.Y / 2 + 1.5
    end
    local height = math.clamp(top - feetY, 3, 8)
    -- Radius is the R15 root, never the equipped tool. A gun or knife
    -- sticking out of the hand must not widen the pathfinding capsule.
    local radius = math.clamp(math.max(root.Size.X, root.Size.Z) / 2, 0.5, 1.5)
    return {
        bodySize = Vector3.new(math.max(root.Size.X, 1), height, math.max(root.Size.Z, 0.5)),
        footOffset = footOffset,
        height = height,
        hipHeight = footOffset - root.Size.Y / 2,
        radius = radius,
        rig = "R15",
        tightRadius = math.clamp(radius - 0.2, 0.5, radius),
    }
end

function Agent.equippedTool(character)
    if type(character) ~= "table" or type(character.GetChildren) ~= "function" then
        return nil
    end
    for _, child in ipairs(character:GetChildren()) do
        if type(child) == "table" and type(child.IsA) == "function" and child:IsA("Tool") then
            return child
        end
    end
    return nil
end

function Agent.suspendCollision(tool)
    local saved = {}
    if type(tool) ~= "table" or type(tool.GetDescendants) ~= "function" then
        return saved
    end
    local parts = { tool }
    for _, descendant in ipairs(tool:GetDescendants()) do
        table.insert(parts, descendant)
    end
    for _, part in ipairs(parts) do
        if isBasePart(part) and part.CanCollide == true then
            saved[part] = true
            part.CanCollide = false
        end
    end
    return saved
end

function Agent.restoreCollision(saved)
    for part, collide in pairs(saved or {}) do
        pcall(function()
            part.CanCollide = collide == true
        end)
    end
end

return Agent
