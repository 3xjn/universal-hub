local Ladders = {}

local MIN_UP = 0.85
local MIN_HEIGHT = 4
local MAX_HEIGHT = 80
local MAX_PARTS = 40

local function shape(width, depth, height, kind)
    return {
        depth = depth,
        height = height,
        kind = kind,
        width = width,
    }
end

function Ladders.classify(spec)
    if type(spec) ~= "table" then
        return nil
    end
    if spec.class == "TrussPart" or spec.embeddedTruss == true then
        return nil
    end
    if spec.class ~= "Model" and not (spec.class == "BasePart" and spec.named == true) then
        return nil
    end
    local size = spec.size
    if typeof(size) ~= "Vector3" or (spec.upY or 0) < MIN_UP then
        return nil
    end
    if size.Y < MIN_HEIGHT or size.Y > MAX_HEIGHT then
        return nil
    end
    local width = math.max(size.X, size.Z)
    local depth = math.min(size.X, size.Z)
    if width < 1 or width > 8 or depth > 3 then
        return nil
    end
    local parts = spec.parts or {}
    if #parts == 0 or #parts > MAX_PARTS then
        return nil
    end
    if spec.named == true then
        return shape(width, depth, size.Y, "named")
    end
    if spec.class ~= "Model" then
        return nil
    end
    local rails = 0
    local rungs = {}
    for _, part in ipairs(parts) do
        if type(part) == "table" and part.canCollide == true and (part.upY or 0) > 0.95 and typeof(part.size) == "Vector3" then
            if part.size.Y >= size.Y * 0.7 and math.min(part.size.X, part.size.Z) <= 0.6 then
                rails += 1
            end
            if part.size.Y <= 0.45
                and math.max(part.size.X, part.size.Z) >= width * 0.5
                and math.min(part.size.X, part.size.Z) <= 0.8
                and type(part.localY) == "number"
            then
                table.insert(rungs, part.localY)
            end
        end
    end
    if rails < 2 or #rungs < 4 then
        return nil
    end
    table.sort(rungs)
    for index = 2, #rungs do
        local gap = rungs[index] - rungs[index - 1]
        if gap < 0.35 or gap > 2.1 then
            return nil
        end
    end
    if rungs[#rungs] - rungs[1] < 4 then
        return nil
    end
    return shape(width, depth, size.Y, "rungs")
end

function Ladders.specFromObject(object)
    if type(object) ~= "table" or type(object.IsA) ~= "function" then
        return nil
    end
    if object:IsA("TrussPart") then
        return { class = "TrussPart" }
    end
    local named = type(object.Name) == "string" and string.find(string.lower(object.Name), "ladder", 1, true) ~= nil
    if object:IsA("Model") and type(object.GetBoundingBox) == "function" and type(object.GetDescendants) == "function" then
        local cf, size = object:GetBoundingBox()
        local parts = {}
        local embedded = false
        for _, descendant in ipairs(object:GetDescendants()) do
            if descendant:IsA("TrussPart") then
                embedded = true
                break
            end
            if descendant:IsA("BasePart") and descendant.CanCollide == true then
                local localCF = cf:ToObjectSpace(descendant.CFrame)
                table.insert(parts, {
                    canCollide = true,
                    localY = localCF.Position.Y,
                    size = descendant.Size,
                    upY = math.abs(localCF.UpVector.Y),
                })
            end
        end
        return {
            class = "Model",
            embeddedTruss = embedded,
            named = named,
            parts = parts,
            size = size,
            upY = math.abs(cf.UpVector.Y),
        }
    end
    if object:IsA("BasePart") and named and object.CanCollide == true then
        return {
            class = "BasePart",
            named = true,
            parts = {
                {
                    canCollide = true,
                    localY = 0,
                    size = object.Size,
                    upY = math.abs(object.CFrame.UpVector.Y),
                },
            },
            size = object.Size,
            upY = math.abs(object.CFrame.UpVector.Y),
        }
    end
    return nil
end

-- Place the climb truss on the face the R15 root can touch.
-- A 2xheightx2 truss at the ladder center sits inside the mesh.
function Ladders.trussPlacement(cf, size, bodyRadius, faceSign)
    local sign = faceSign == -1 and -1 or 1
    local thinIsLook = size.Z <= size.X
    local thin = thinIsLook and size.Z or size.X
    local radius = math.clamp(type(bodyRadius) == "number" and bodyRadius or 1, 0.5, 1.5)
    local depth = math.clamp(radius, 0.8, 1.4)
    local distance = thin / 2 + depth / 2
    local localOffset = thinIsLook and Vector3.new(0, 0, -sign * distance) or Vector3.new(sign * distance, 0, 0)
    local width = math.clamp(thinIsLook and size.X or size.Z, 1.2, 2.5)
    local trussSize = thinIsLook and Vector3.new(width, size.Y, depth) or Vector3.new(depth, size.Y, width)
    return {
        cframe = cf * CFrame.new(localOffset),
        size = trussSize,
    }
end

function Ladders.trussProperties()
    return {
        Anchored = true,
        CanCollide = true,
        Name = "DetectedLadder",
        Transparency = 1,
    }
end

function Ladders.approachSign(positiveClear, negativeClear)
    if negativeClear == true and positiveClear ~= true then
        return -1
    end
    return 1
end

-- localX/localY/localZ are object-space offsets from the truss center.
-- World-axis extents miss a rotated ladder and grab empty space beside it.
function Ladders.horizontalGap(localX, localZ, size)
    local dx = math.max(0, math.abs(localX) - size.X / 2)
    local dz = math.max(0, math.abs(localZ) - size.Z / 2)
    return math.sqrt(dx * dx + dz * dz)
end

function Ladders.near(localX, localY, localZ, size, reach)
    reach = type(reach) == "number" and reach or 4
    local gap = Ladders.horizontalGap(localX, localZ, size)
    local withinHeight = math.abs(localY) <= size.Y / 2 + 3
    return gap < reach and withinHeight
end

-- Dismount from the feet. The R15 root sits about a hip above them, so a
-- root-versus-lip test lets go while the feet are still on the ladder.
function Ladders.intent(info)
    if type(info) ~= "table" or info.near ~= true then
        return nil
    end
    local feetY = info.feetY
    local topY = info.topY
    if type(feetY) ~= "number" or type(topY) ~= "number" then
        return nil
    end
    if feetY >= topY - 0.35 and (info.flatToExit or math.huge) < 1.5 and info.climbing ~= true then
        return "done"
    end
    if feetY >= topY - 0.5 then
        return "dismount"
    end
    if type(info.goalY) == "number" and info.goalY < feetY - 2 then
        return "down"
    end
    if (type(info.goalY) == "number" and info.goalY > feetY + 1) or info.climbing == true then
        return "up"
    end
    return nil
end

function Ladders.lipHop(feetY, topY, stalled)
    return stalled == true and type(feetY) == "number" and type(topY) == "number" and feetY >= topY - 0.75 and feetY < topY - 0.15
end

function Ladders.direction(intent, towardLadder, exitFlat, lipHop)
    local toward = typeof(towardLadder) == "Vector3" and towardLadder or Vector3.zero
    local flat = Vector3.new(toward.X, 0, toward.Z)
    local horizontal = flat.Magnitude > 0.1 and flat.Unit or Vector3.zero
    if intent == "up" then
        return horizontal + Vector3.yAxis, false
    end
    if intent == "down" then
        return horizontal - Vector3.yAxis, false
    end
    if intent == "dismount" then
        local exit = typeof(exitFlat) == "Vector3" and exitFlat or horizontal
        local exitFlatVector = Vector3.new(exit.X, 0, exit.Z)
        local forward = exitFlatVector.Magnitude > 0.1 and exitFlatVector.Unit or horizontal
        return forward, lipHop == true
    end
    return Vector3.zero, false
end

return Ladders
