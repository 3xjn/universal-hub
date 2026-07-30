local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
CFrame = roblox.CFrame
Enum = roblox.Enum
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3

local Town = require("../games/Town")
local townSource = fs.readFile("games/Town.lua")
local initSource = fs.readFile("init.lua")

assert(not townSource:find("MAX_PARTS", 1, true), "Town must not retain an arbitrary total-part cap")
assert(not townSource:find("options.maxParts", 1, true), "Town must not accept a hidden maximum override")
assert(not townSource:find("options.limit", 1, true), "Town production copy must not truncate to a prefix")
assert(townSource:find("town/CopyEngine", 1, true), "Town must delegate durable execution to CopyEngine")
assert(townSource:find("town/ExecutionPlan", 1, true), "Town must stream its execution graph")
local preflightSource = assert(
    townSource:match("function self:preflightCopy.-function self:copyPlot")
)
assert(
    not preflightSource:find("GetDescendants()", 1, true),
    "Production preflight must not retain an all-descendants array"
)
assert(
    townSource:find("COMMAND_COOLDOWN_SECONDS = 6", 1, true),
    "Town save and wiring commands must use the planned six-second scheduler tuning"
)
assert(
    not townSource:find("status = phase", 1, true),
    "Town copy phases must not duplicate themselves in the global Hub status"
)
assert(
    initSource:find('import("games/town/CheckpointStore")', 1, true),
    "Town bootstrap must load the private checkpoint store"
)
assert(
    initSource:find("universal-hub/private/town-copy", 1, true),
    "Town bootstrap must own the documented private checkpoint root"
)
for _, capability in ipairs({
    "readFile",
    "writeFile",
    "isFile",
    "deleteFile",
    "makeFolder",
    "listFiles",
}) do
    assert(
        initSource:find(capability .. " =", 1, true),
        "Town bootstrap must inject checkpoint capability " .. capability
    )
end
assert(
    initSource:find("inspectCopyRecovery", 1, true),
    "Town startup must inspect compatible recovery state"
)

assert(Town.match({ gameId = 0, placeId = 4991214437 }) == 200)
assert(Town.match({ gameId = 1718755273, placeId = 0 }) == 100)
assert(Town.match({ gameId = 0, placeId = 0 }) == 0)

local sourcePlotFrame = CFrame.new(100, 0, -50) * CFrame.Angles(0, math.rad(90), 0)
local targetPlotFrame = CFrame.new(-200, 0, 75) * CFrame.Angles(0, math.rad(-90), 0)
local sourcePartFrame = sourcePlotFrame * CFrame.new(12, 8, -4) * CFrame.Angles(0.2, 0.4, 0.1)
local transformed = Town.transformedCFrame(sourcePlotFrame, targetPlotFrame, sourcePartFrame)
local expected = targetPlotFrame * CFrame.new(12, 8, -4) * CFrame.Angles(0.2, 0.4, 0.1)
local delta = expected:ToObjectSpace(transformed)
local deltaX, deltaY, deltaZ = delta:ToOrientation()
assert(
    delta.Position.Magnitude < 0.0001
        and math.abs(deltaX) < 0.0001
        and math.abs(deltaY) < 0.0001
        and math.abs(deltaZ) < 0.0001,
    "Town plot copies must preserve plot-local transforms"
)

local function fakePlot(name, frame, size, hasBuild)
    local plot = {
        CFrame = frame,
        Name = name,
        Size = size,
    }
    function plot:IsA(className)
        return className == "BasePart"
    end
    function plot:FindFirstChild(childName)
        return childName == "Build" and hasBuild and {} or nil
    end
    return plot
end

local localPlot = fakePlot("LocalBuildArea", CFrame.new(), Vector3.new(100, 1, 100), true)
local nearPlot = fakePlot("NearBuildArea", CFrame.new(120, 0, 0), Vector3.new(100, 1, 100), true)
local farPlot = fakePlot("FarBuildArea", CFrame.new(500, 0, 0), Vector3.new(100, 1, 100), true)
local selected, distance =
    Town.selectNearestPlot({ localPlot, farPlot, nearPlot }, "LocalBuildArea", Vector3.new(160, 0, 0))
assert(selected == nearPlot and distance == 0, "Town must select the nearby non-local plot")
assert(Town.plotDistance(nearPlot, Vector3.new(180, 0, 0)) == 10)

local notAPart = fakePlot("IgnoredBuildArea", CFrame.new(), Vector3.new(100, 1, 100), true)
function notAPart:IsA()
    return false
end
local owners = Town.plotOwners({
    fakePlot("zebraBuildArea", CFrame.new(), Vector3.new(100, 1, 100), true),
    localPlot,
    fakePlot("AlphaBuildArea", CFrame.new(), Vector3.new(100, 1, 100), true),
    fakePlot("NoBuildArea", CFrame.new(), Vector3.new(100, 1, 100), false),
    fakePlot("MalformedPlot", CFrame.new(), Vector3.new(100, 1, 100), true),
    notAPart,
}, "LocalBuildArea")
assert(
    #owners == 2 and owners[1] == "Alpha" and owners[2] == "zebra",
    "Town plot owners must be sorted case-insensitively and exclude the local or unusable plots"
)

assert(Town.validSaveName("exact_Save-name_17"))
assert(Town.ownershipName("job-a", "Normal") ~= Town.ownershipName("job-b", "Normal"))
assert(Town.validSaveName(string.rep("a", 32)))
for _, invalidName in ipairs({
    "",
    "has spaces",
    "has/slash",
    "punctuation!",
    string.rep("a", 33),
}) do
    assert(
        not Town.validSaveName(invalidName),
        ("Town must reject invalid plot save name %q"):format(invalidName)
    )
end
assert(not Town.validSaveName(nil), "Town must reject non-string plot save names")

local pointLight = {
    Brightness = 5,
    ClassName = "PointLight",
    Color = "warm",
    Enabled = true,
    Range = 10,
    Shadows = true,
}
function pointLight:IsA(className)
    return className == "Light" or className == "PointLight"
end
local surfaceLight = {
    Brightness = 1,
    ClassName = "SurfaceLight",
    Color = "cool",
    Enabled = false,
    Face = Enum.NormalId.Front,
    Range = 16,
    Shadows = false,
}
function surfaceLight:IsA(className)
    return className == "Light" or className == "SurfaceLight"
end
local lightSnapshots = Town.snapshotLights({
    GetChildren = function()
        return { pointLight, surfaceLight }
    end,
})
assert(
    #lightSnapshots == 2
        and lightSnapshots[1].LightType == "PointLight"
        and lightSnapshots[1].Brightness == 5
        and lightSnapshots[1].Face == nil
        and lightSnapshots[2].LightType == "SurfaceLight"
        and lightSnapshots[2].Face == Enum.NormalId.Front
        and lightSnapshots[2].Enabled == false,
    "Town plot copies must snapshot replicated light type and appearance"
)

local build = {}
local outer = {
    Name = "Outer",
    Parent = build,
}
local inner = {
    Name = "Inner",
    Parent = outer,
}
local includedPart = {
    Parent = inner,
}
local excludedPart = {
    Parent = outer,
}
function outer:IsA(className)
    return className == "Model"
end
function inner:IsA(className)
    return className == "Model"
end
function includedPart:IsA(className)
    return className == "BasePart"
end
function excludedPart:IsA(className)
    return className == "BasePart"
end
function outer:GetChildren()
    return { inner, excludedPart }
end
function inner:GetChildren()
    return { includedPart }
end
function build:GetDescendants()
    return { outer, inner, includedPart, excludedPart }
end
local modelSnapshots = Town.snapshotModels(build, {
    [includedPart] = true,
})
assert(
    #modelSnapshots == 2
        and modelSnapshots[1].Source == inner
        and modelSnapshots[1].Depth == 2
        and modelSnapshots[1].Parts[1] == includedPart
        and modelSnapshots[2].Source == outer
        and modelSnapshots[2].Models[1] == inner
        and #modelSnapshots[2].Parts == 0,
    "Town plot copies must preserve supported nested F3X group structure from the inside out"
)

local function wirePart(frame, markerType)
    local part = {
        CFrame = frame,
    }
    function part:IsA(className)
        return className == "BasePart"
    end
    function part:GetChildren()
        if markerType == nil then
            return {}
        end
        return {
            {
                IsA = function(_, className)
                    return className == "Texture"
                end,
                StudsPerTileU = markerType,
                Transparency = -500,
            },
        }
    end
    return part
end
local startPart = wirePart(CFrame.new(2, 0, 0), 1)
local endPart = wirePart(CFrame.new(12, 0, 0), 2)
local movingPart = wirePart(CFrame.new(15, 0, 0))
local openState = {
    Value = true,
}
function openState:IsA(className)
    return className == "BoolValue"
end
local wiredModel = {}
function wiredModel:IsA(className)
    return className == "Model"
end
function wiredModel:GetChildren()
    return { openState, startPart, endPart, movingPart }
end
local wiredBuild = {}
function wiredBuild:GetDescendants()
    return { wiredModel, openState, startPart, endPart, movingPart }
end
local normalized = Town.normalizedWiringCFrames(wiredBuild)
assert(
    normalized[movingPart]
        and math.abs(normalized[movingPart].Position.X - 5) < 0.0001
        and normalized[startPart] == nil
        and normalized[endPart] == nil,
    "Town plot copies must normalize open moving parts to their Start Position before compiling"
)

local plotChildren = {
    fakePlot("ZuluBuildArea", CFrame.new(), Vector3.new(100, 1, 100), true),
    localPlot,
    fakePlot("bravoBuildArea", CFrame.new(), Vector3.new(100, 1, 100), true),
}
local plotRoot = {}
function plotRoot:GetChildren()
    return plotChildren
end
local workspace = {}
function workspace:FindFirstChild(name)
    if name == "Private Building Areas" then
        return plotRoot
    end
    return nil
end
local adapter = Town.new({
    localPlayer = {
        Name = "Local",
    },
    players = {},
    store = {
        Patch = function() end,
    },
    wait = function() end,
    workspace = workspace,
})
local listedOwners = adapter:listPlotOwners()
assert(
    #listedOwners == 2 and listedOwners[1] == "bravo" and listedOwners[2] == "Zulu",
    "Town listPlotOwners must source sorted non-local player names from the live plot root"
)

local function fakePart(className, shape)
    local part = {
        Shape = shape or Enum.PartType.Block,
    }
    function part:IsA(candidate)
        if candidate == className then
            return true
        end
        return candidate == "Part" and className == "Part"
    end
    return part
end

assert(Town.partType(fakePart("Part", Enum.PartType.Block)) == "Normal")
assert(Town.partType(fakePart("Part", Enum.PartType.Ball)) == "Ball")
assert(Town.partType(fakePart("Part", Enum.PartType.Cylinder)) == "Cylinder")
assert(Town.partType(fakePart("WedgePart")) == "Wedge")
assert(Town.partType(fakePart("MeshPart")) == nil)

local delegated = {}
local fakeEngine = {}
for _, method in ipairs({
    "preflight",
    "confirmStart",
    "inspectRecovery",
    "requestCancel",
    "resume",
    "discard",
    "retryCleanup",
    "cleanupLocalCheckpoint",
    "stop",
}) do
    fakeEngine[method] = function(_, ...)
        table.insert(delegated, {
            arguments = { ... },
            method = method,
        })
        return method .. "-result"
    end
end

local facade = Town.new({
    copyEngine = fakeEngine,
    localPlayer = {
        Name = "Local",
    },
    players = {},
    store = {
        Patch = function() end,
    },
    wait = function() end,
    workspace = workspace,
})
assert(facade:preflightCopy("Source", "copy_Source") == "preflight-result")
assert(facade:confirmCopy() == "confirmStart-result")
assert(facade:cancelCopy() == "requestCancel-result")
assert(facade:resumeCopy() == "resume-result")
assert(facade:discardCopy() == "discard-result")
assert(facade:retryCopyCleanup() == "retryCleanup-result")
assert(facade:cleanupCopyCheckpoint() == "cleanupLocalCheckpoint-result")
facade:stop()
assert(delegated[1].method == "preflight")
assert(delegated[#delegated].method == "stop")

print("town-adapter-contracts-ok")
