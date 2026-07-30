local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
CFrame = roblox.CFrame
Color3 = roblox.Color3
Enum = roblox.Enum
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3

local CheckpointStore = require("../games/town/CheckpointStore")
local Town = require("../games/Town")

local codecValues = {}
local codecSequence = 0
local function encodeInMemory(value)
    codecSequence += 1
    local token = "memory:" .. codecSequence
    codecValues[token] = value
    return token
end
local function decodeInMemory(token)
    return assert(codecValues[token], "missing in-memory checkpoint payload")
end
local function testChecksum()
    return "test-checksum"
end

local function fileSystem()
    local files = {}
    return {
        files = files,
        deleteFile = function(path)
            if files[path] then
                codecValues[files[path]] = nil
            end
            files[path] = nil
        end,
        isFile = function(path)
            return files[path] ~= nil
        end,
        listFiles = function(root)
            local result = {}
            for path in pairs(files) do
                if path:sub(1, #root + 1) == root .. "/" then
                    table.insert(result, path)
                end
            end
            return result
        end,
        makeFolder = function() end,
        readFile = function(path)
            return assert(files[path])
        end,
        writeFile = function(path, source)
            if files[path] then
                codecValues[files[path]] = nil
            end
            files[path] = source
        end,
    }
end

local fs = fileSystem()
local function newCheckpointStore()
    return CheckpointStore.new({
        checksum = testChecksum,
        checksumAlgorithm = "test-only",
        decode = decodeInMemory,
        deleteFile = fs.deleteFile,
        encode = encodeInMemory,
        isFile = fs.isFile,
        listFiles = fs.listFiles,
        makeFolder = fs.makeFolder,
        normalizePayload = false,
        now = function()
            return 100
        end,
        readFile = fs.readFile,
        root = "universal-hub/private/town-copy",
        userId = 1,
        writeFile = fs.writeFile,
    })
end
local checkpoint = newCheckpointStore()

local function part(index)
    local value = {
        _children = {},
        Anchored = true,
        BackSurface = Enum.SurfaceType.Smooth,
        BottomSurface = Enum.SurfaceType.Smooth,
        CanCollide = true,
        CFrame = CFrame.new(index % 100, math.floor(index / 100), 0),
        ClassName = "Part",
        Color = Color3.new(1, 1, 1),
        FrontSurface = Enum.SurfaceType.Smooth,
        LeftSurface = Enum.SurfaceType.Smooth,
        Material = Enum.Material.Plastic,
        Name = "Part",
        Reflectance = 0,
        RightSurface = Enum.SurfaceType.Smooth,
        Shape = Enum.PartType.Block,
        Size = Vector3.new(1, 1, 1),
        TopSurface = Enum.SurfaceType.Smooth,
        Transparency = 0,
    }
    function value:FindFirstChildOfClass(className)
        for _, child in ipairs(self._children) do
            if child.ClassName == className then
                return child
            end
        end
        return nil
    end
    function value:GetChildren()
        return self._children
    end
    function value:IsA(className)
        return className == "BasePart" or className == "Part"
    end
    return value
end

local sourceParts = {}
local largeCount = tonumber(process.env.TOWN_TEST_COUNT) or 18001
for index = 1, largeCount do
    table.insert(sourceParts, part(index))
end
if largeCount <= 1000 then
    local mesh = {
        ClassName = "SpecialMesh",
        MeshId = "mesh://one",
        MeshType = Enum.MeshType.Brick,
        Name = "Mesh",
        Offset = Vector3.new(1, 2, 3),
        Scale = Vector3.new(2, 2, 2),
        TextureId = "texture://mesh",
        VertexColor = Vector3.new(1, 0.5, 0.25),
    }
    function mesh:IsA(className)
        return className == "DataModelMesh" or className == "SpecialMesh"
    end
    function mesh:GetChildren()
        return {}
    end
    local texture = {
        ClassName = "Texture",
        Face = Enum.NormalId.Front,
        Name = "Texture",
        OffsetStudsU = 1,
        OffsetStudsV = 2,
        StudsPerTileU = 3,
        StudsPerTileV = 4,
        Texture = "texture://one",
        Transparency = 0.25,
    }
    function texture:IsA(className)
        return className == "Texture"
    end
    function texture:GetChildren()
        return {}
    end
    local light = {
        Brightness = 2,
        ClassName = "PointLight",
        Color = Color3.new(0.25, 0.5, 1),
        Enabled = true,
        Name = "PointLight",
        Range = 20,
        Shadows = true,
    }
    function light:IsA(className)
        return className == "Light" or className == "PointLight"
    end
    function light:GetChildren()
        return {}
    end
    sourceParts[1]._children = { mesh, texture, light }
    mesh.Parent = sourceParts[1]
    texture.Parent = sourceParts[1]
    light.Parent = sourceParts[1]
end
local sourceRootChildren = sourceParts
if largeCount <= 1000 then
    local model = {
        _children = sourceParts,
        ClassName = "Model",
        Name = "SourceGroup",
    }
    function model:GetChildren()
        return self._children
    end
    function model:IsA(className)
        return className == "Model"
    end
    for _, sourcePart in ipairs(sourceParts) do
        sourcePart.Parent = model
    end
    sourceRootChildren = { model }
end
local sourceBuild = {
    ClassName = "Folder",
    Name = "Build",
}
function sourceBuild:GetChildren()
    return sourceRootChildren
end
function sourceBuild:IsA(className)
    return className == "Folder"
end
function sourceBuild:GetDescendants()
    error("Production preflight must not request an all-descendants array")
end
for _, child in ipairs(sourceRootChildren) do
    child.Parent = sourceBuild
end
local targetBuild = {
    ClassName = "Folder",
    Name = "Build",
}
local targetChildren = {}
local targetNameIndex = {}
local targetIndexMisses = 0
function targetBuild:GetChildren()
    return targetChildren
end
function targetBuild:IsA(className)
    return className == "Folder"
end
function targetBuild:GetDescendants()
    error("Preflight must not enumerate destination descendants as one retained array")
end
function targetBuild:FindFirstChild(name, recursive)
    if recursive and targetNameIndex[name] then
        return targetNameIndex[name]
    end
    targetIndexMisses += 1
    local function find(children)
        for _, child in ipairs(children) do
            if child.Name == name then
                return child
            end
            if recursive and child.GetChildren then
                local nested = find(child:GetChildren())
                if nested then
                    return nested
                end
            end
        end
        return nil
    end
    return find(targetChildren)
end

local function plot(name, build, wired)
    local value = {
        CFrame = CFrame.new(),
        ClassName = "Part",
        Name = name,
        Size = Vector3.new(100, 1, 100),
        Wired = wired == true,
    }
    function value:FindFirstChild(childName)
        return childName == "Build" and build or nil
    end
    function value:GetAttribute(attribute)
        return attribute == "Wired" and self.Wired or nil
    end
    function value:IsA(className)
        return className == "BasePart"
    end
    return value
end

local sourcePlot = plot("SourceBuildArea", sourceBuild, largeCount <= 1000)
local targetPlot = plot("LocalBuildArea", targetBuild, false)
local root = {}
function root:FindFirstChild(name)
    if name == sourcePlot.Name then
        return sourcePlot
    elseif name == targetPlot.Name then
        return targetPlot
    end
    return nil
end
local workspace = {}
function workspace:FindFirstChild(name)
    return name == "Private Building Areas" and root or nil
end

local syncInvokes = 0
local lastFakeAction = "none"
local failAction
local partialCloneLimit
local partialSetNameLimit
local syncAPI = {}
function syncAPI:IsA(className)
    return className == "BindableFunction"
end
local function removeFromParent(item)
    local parent = item.Parent
    if not parent or not parent.GetChildren then
        item.Parent = nil
        return
    end
    if targetNameIndex[item.Name] == item then
        targetNameIndex[item.Name] = nil
    end
    local children = parent:GetChildren()
    for index = #children, 1, -1 do
        if children[index] == item then
            table.remove(children, index)
            break
        end
    end
    item.Parent = nil
end
local function setParent(item, parent)
    removeFromParent(item)
    item.Parent = parent
    table.insert(parent:GetChildren(), item)
end
local function clonePart(source)
    local clone = part(0)
    for _, key in ipairs({
        "Anchored",
        "BackSurface",
        "BottomSurface",
        "CanCollide",
        "CFrame",
        "ClassName",
        "Color",
        "FrontSurface",
        "LeftSurface",
        "Material",
        "Name",
        "Reflectance",
        "RightSurface",
        "Shape",
        "Size",
        "TopSurface",
        "Transparency",
    }) do
        clone[key] = source[key]
    end
    return clone
end
local function newModel()
    local model = {
        _children = {},
        ClassName = "Model",
        Name = "Model",
    }
    function model:GetChildren()
        return self._children
    end
    function model:IsA(className)
        return className == "Model"
    end
    return model
end
local function findChild(parent, className, face)
    for _, child in ipairs(parent:GetChildren()) do
        if child.ClassName == className and (face == nil or child.Face == face) then
            return child
        end
    end
    return nil
end
function syncAPI:Invoke(action, first, second, third)
    syncInvokes += 1
    lastFakeAction = action .. ":start"
    if failAction == action then
        failAction = nil
        error("synthetic cross-server interruption")
    end
    if action == "CreatePart" then
        local created = part(0)
        created.CFrame = second
        setParent(created, third)
        return created
    elseif action == "Clone" then
        local clones = {}
        for index, source in ipairs(first) do
            lastFakeAction = action .. ":clone"
            local clone = clonePart(source)
            lastFakeAction = action .. ":parent"
            setParent(clone, second)
            table.insert(clones, clone)
            if partialCloneLimit
                and #first > partialCloneLimit
                and index == partialCloneLimit
            then
                partialCloneLimit = nil
                error("synthetic disconnect after a partial Clone effect")
            end
        end
        return clones
    elseif action == "SetName" then
        lastFakeAction = action .. ":names"
        for index, item in ipairs(first) do
            lastFakeAction = action .. ":name:" .. index
            if targetNameIndex[item.Name] == item then
                targetNameIndex[item.Name] = nil
            end
            item.Name = type(second) == "table" and second[index] or second
            targetNameIndex[item.Name] = item
            local finalPartNames = type(second) == "table"
                and type(second[1]) == "string"
                and not second[1]:find("^__UH")
            if partialSetNameLimit
                and finalPartNames
                and #first > partialSetNameLimit
                and index == partialSetNameLimit
            then
                partialSetNameLimit = nil
                error("synthetic disconnect after partial final SetName")
            end
        end
        lastFakeAction = action .. ":done"
        return true
    elseif action == "CreateGroup" then
        local group = newModel()
        setParent(group, second)
        for _, item in ipairs(third or {}) do
            setParent(item, group)
        end
        return group
    elseif action == "SetParent" then
        for _, item in ipairs(first or {}) do
            setParent(item, second)
        end
        return true
    elseif action == "CreateMeshes" then
        for _, change in ipairs(first or {}) do
            local mesh = {
                ClassName = "SpecialMesh",
                MeshId = "",
                MeshType = Enum.MeshType.Brick,
                Name = "Mesh",
                Offset = Vector3.new(),
                Scale = Vector3.new(1, 1, 1),
                TextureId = "",
                VertexColor = Vector3.new(1, 1, 1),
            }
            function mesh:IsA(className)
                return className == "DataModelMesh" or className == "SpecialMesh"
            end
            function mesh:GetChildren()
                return {}
            end
            setParent(mesh, change.Part)
        end
        return true
    elseif action == "CreateTextures" then
        for _, change in ipairs(first or {}) do
            local texture = {
                ClassName = change.TextureType,
                Face = change.Face,
                Name = change.TextureType,
                OffsetStudsU = 0,
                OffsetStudsV = 0,
                StudsPerTileU = 0,
                StudsPerTileV = 0,
                Texture = "",
                Transparency = 0,
            }
            function texture:IsA(className)
                return className == self.ClassName
                    or (self.ClassName == "Texture" and className == "Decal")
            end
            function texture:GetChildren()
                return {}
            end
            setParent(texture, change.Part)
        end
        return true
    elseif action == "CreateLights" then
        for _, change in ipairs(first or {}) do
            local light = {
                Brightness = 1,
                ClassName = change.LightType,
                Color = Color3.new(1, 1, 1),
                Enabled = true,
                Name = change.LightType,
                Range = 8,
                Shadows = false,
            }
            function light:IsA(className)
                return className == "Light" or className == self.ClassName
            end
            function light:GetChildren()
                return {}
            end
            setParent(light, change.Part)
        end
        return true
    elseif action == "Remove" then
        for _, item in ipairs(first) do
            removeFromParent(item)
        end
        return true
    end
    for _, change in ipairs(first or {}) do
        local target = change.Part
        if action == "SyncResize" then
            target.CFrame = change.CFrame
            target.Size = change.Size
        elseif action == "SyncColor" then
            target.Color = change.Color
        elseif action == "SyncMaterial" then
            target.Material = change.Material
            target.Reflectance = change.Reflectance
            target.Transparency = change.Transparency
        elseif action == "SyncSurface" then
            for key, value in pairs(change.Surfaces) do
                target[key] = value
            end
        elseif action == "SyncCollision" then
            target.CanCollide = change.CanCollide
        elseif action == "SyncAnchor" then
            target.Anchored = change.Anchored
        elseif action == "SyncMesh" then
            local mesh = assert(findChild(target, "SpecialMesh"))
            mesh.MeshId = change.MeshId
            mesh.MeshType = change.MeshType
            mesh.Offset = change.Offset
            mesh.Scale = change.Scale
            mesh.TextureId = change.TextureId
            mesh.VertexColor = change.VertexColor
        elseif action == "SyncTexture" then
            local texture = assert(findChild(target, change.TextureType, change.Face))
            texture.OffsetStudsU = change.OffsetStudsU
            texture.OffsetStudsV = change.OffsetStudsV
            texture.StudsPerTileU = change.StudsPerTileU
            texture.StudsPerTileV = change.StudsPerTileV
            texture.Texture = change.Texture
            texture.Transparency = change.Transparency
        elseif action == "SyncLighting" then
            local light = assert(findChild(target, change.LightType))
            light.Brightness = change.Brightness
            light.Color = change.Color
            light.Range = change.Range
            light.Shadows = change.Shadows
        else
            error("Unexpected fake Town action " .. tostring(action))
        end
    end
    return true
end
local tool = {}
function tool:FindFirstChild(name)
    return name == "SyncAPI" and syncAPI or nil
end
local backpack = {}
function backpack:FindFirstChild(name)
    return name == "Building Tools" and tool or nil
end
local saveFolder = {}
local savedPlots = {}
function saveFolder:FindFirstChild(name)
    return savedPlots[name]
end
local plotGui = {}
local saveInvokes = 0
local failSaveAfterEffect = false
local plotServer = {}
function plotServer:InvokeServer(_, name)
    saveInvokes += 1
    local saved = {
        ClassName = "Folder",
        Name = name,
    }
    function saved:FindFirstChild()
        return nil
    end
    function saved:GetAttribute(attribute)
        return attribute == "LastEdited" and saveInvokes or nil
    end
    function saved:GetAttributes()
        return {
            LastEdited = saveInvokes,
        }
    end
    savedPlots[name] = saved
    if failSaveAfterEffect then
        failSaveAfterEffect = false
        error("synthetic disconnect after Save effect")
    end
end
function plotGui:FindFirstChild(name)
    if name == "SaveFolder" then
        return saveFolder
    elseif name == "PlotServer" then
        return plotServer
    end
    return nil
end
local commandFunction = {}
function commandFunction:InvokeServer(command)
    assert(command == "!wireconnections")
    targetPlot.Wired = true
end
local chatConsole = {}
function chatConsole:FindFirstChild(name)
    return name == "CommandFunction" and commandFunction or nil
end
local playerGui = {}
function playerGui:FindFirstChild(name)
    if name == "PlotGui" then
        return plotGui
    elseif name == "ChatConsoleGui" then
        return chatConsole
    end
    return nil
end
local localPlayer = {
    Name = "Local",
    UserId = 1,
}
function localPlayer:FindFirstChild()
    return nil
end
function localPlayer:FindFirstChildOfClass(className)
    if className == "Backpack" then
        return backpack
    elseif className == "PlayerGui" then
        return playerGui
    end
    return nil
end
local players = {}
local sourceUserId = 2
function players:FindFirstChild(name)
    return name == "Source" and { Name = "Source", UserId = sourceUserId } or nil
end

local lastView
local capturedCopyError
local startedAt = os.clock()
local runtimeMetrics = {}
local commandTime = 100
local cancelDuringScan = false
local adapter
adapter = Town.new({
    checkpoint = checkpoint,
    commandClock = function()
        return commandTime
    end,
    copyErrorCapture = function(message)
        capturedCopyError = message
    end,
    gameId = 1718755273,
    generateGuid = function()
        return "large-production-job"
    end,
    jobId = "read-only-job",
    localPlayer = localPlayer,
    now = function()
        return 100
    end,
    placeId = 4991214437,
    players = players,
    runtimeMetrics = runtimeMetrics,
    scanYield = function()
        if cancelDuringScan then
            adapter:cancelCopy()
        end
    end,
    scanErrorCapture = function(message)
        capturedCopyError = message
    end,
    store = {
        Patch = function(_, patch)
            lastView = patch.plotCopy
        end,
    },
    wait = function(duration)
        commandTime += duration or 0.01
    end,
    workspace = workspace,
})

local function newRecoveryAdapter(checkpointValue, guid, hooks)
    hooks = hooks or {}
    local viewRef = {}
    local value = Town.new({
        checkpoint = checkpointValue,
        commandClock = function()
            return commandTime
        end,
        copyAfterCleanupConfirmation = hooks.afterCleanupConfirmation,
        copyAfterRemote = hooks.afterRemote,
        copyAfterReplacement = hooks.afterReplacement,
        gameId = 1718755273,
        generateGuid = function()
            return guid
        end,
        jobId = guid .. "-session",
        localPlayer = localPlayer,
        now = function()
            return 100
        end,
        placeId = 4991214437,
        players = players,
        runtimeMetrics = {},
        store = {
            Patch = function(_, patch)
                viewRef.value = patch.plotCopy
            end,
        },
        wait = function(duration)
            commandTime += duration or 0.01
        end,
        workspace = workspace,
    })
    return value, viewRef
end

local function resetDestination()
    targetChildren = {}
    table.clear(targetNameIndex)
    targetPlot.Wired = false
end

local function targetPartCount()
    local count = 0
    local function visit(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("BasePart") then
                count += 1
            end
            visit(child)
        end
    end
    visit(targetBuild)
    return count
end

local view, preflightError = adapter:preflightCopy("Source", "copy_Source")
local preflightFinishedAt = os.clock()
assert(
    view,
    tostring(preflightError)
        .. " / "
        .. tostring(lastView and lastView.error)
        .. " / "
        .. tostring(capturedCopyError)
)
assert(view.state == "awaiting_confirmation" and view.supported == largeCount)
assert(lastView.startAvailable and lastView.cancelAvailable)
assert(adapter.copyEngine.state.execution.batches == nil)
assert(adapter.copyEngine.state.execution.batchCount > 1)
if largeCount >= 18001 then
    assert(adapter.copyEngine.state.execution.batchCount > 140)
end
assert(adapter.copyEngine.state.execution.maximumBufferedRecords <= 64)
assert(adapter.copyEngine.state.plan.supported == largeCount)
assert(checkpoint:load().status == "ready")

if largeCount <= 1000 then
    local foreign = part(999999)
    foreign.Name = "Foreign"
    foreign.Parent = targetBuild
    targetChildren = { foreign }
    adapter:inspectCopyRecovery()
    assert(lastView.state == "error" and lastView.error:find("Destination changed", 1, true))
    assert(syncInvokes == 0, "A foreign destination part must block before the first remote")
    assert(checkpoint:load().status == "ready", "Foreign ambiguity must preserve recovery")
    targetChildren = {}

    local sourceFingerprint = adapter.copyEngine.state.context.source.fingerprint
    local function assertFingerprintChange(label, mutate, restore)
        mutate()
        local changed = Town.streamingSourceFingerprint(
            sourceBuild,
            sourcePlot,
            targetPlot,
            sourcePlot.Wired
        )
        assert(changed ~= sourceFingerprint, label .. " must change the source fingerprint")
        restore()
    end
    local firstPart = sourceParts[1]
    local sourceModel = sourceRootChildren[1]
    local sourceMesh = firstPart:FindFirstChildOfClass("SpecialMesh")
    local sourceTexture = firstPart._children[2]
    local sourceLight = firstPart._children[3]
    local originalSize = firstPart.Size
    assertFingerprintChange("transform/size", function()
        firstPart.Size = Vector3.new(9, 9, 9)
    end, function()
        firstPart.Size = originalSize
    end)
    local originalColor = firstPart.Color
    assertFingerprintChange("color/material/surface/collision/anchor", function()
        firstPart.Color = Color3.new(0.1, 0.2, 0.3)
    end, function()
        firstPart.Color = originalColor
    end)
    local originalMeshId = sourceMesh.MeshId
    assertFingerprintChange("mesh", function()
        sourceMesh.MeshId = "mesh://changed"
    end, function()
        sourceMesh.MeshId = originalMeshId
    end)
    local originalTexture = sourceTexture.Texture
    assertFingerprintChange("texture/decal", function()
        sourceTexture.Texture = "texture://changed"
    end, function()
        sourceTexture.Texture = originalTexture
    end)
    local originalBrightness = sourceLight.Brightness
    assertFingerprintChange("lights", function()
        sourceLight.Brightness = 7
    end, function()
        sourceLight.Brightness = originalBrightness
    end)
    local originalGroupName = sourceModel.Name
    assertFingerprintChange("groups", function()
        sourceModel.Name = "ChangedGroup"
    end, function()
        sourceModel.Name = originalGroupName
    end)
    assertFingerprintChange("wiring", function()
        sourcePlot.Wired = false
    end, function()
        sourcePlot.Wired = true
    end)

    local fileCount = 0
    for _ in pairs(fs.files) do
        fileCount += 1
    end
    local conflict, message = adapter:preflightCopy("Source", "copy_Source")
    assert(conflict == false and message == "An unfinished Town copy already exists")
    local afterConflict = 0
    for _ in pairs(fs.files) do
        afterConflict += 1
    end
    assert(afterConflict == fileCount, "A conflicting preflight must not alter the existing job")
end

local completed, completionError = adapter:confirmCopy()
assert(
    completed,
    ("%s (%s / %s)"):format(
        tostring(completionError),
        tostring(adapter.copyEngine.state
            and adapter.copyEngine.state.progress.pendingBatch
            and adapter.copyEngine.state.progress.pendingBatch.operation),
        tostring(adapter.copyEngine.state
            and adapter.copyEngine.state.progress.pendingBatch
            and adapter.copyEngine.state.progress.pendingBatch.id)
            .. " / "
            .. lastFakeAction
            .. " / "
            .. tostring(capturedCopyError)
    )
)
assert(lastView.state == "completed")
assert(lastView.localCleanupAvailable == false)
local copiedParts = 0
local function countCopiedParts(parent)
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("BasePart") then
            copiedParts += 1
        end
        countCopiedParts(child)
    end
end
countCopiedParts(targetBuild)
assert(copiedParts == largeCount)
if largeCount <= 1000 then
    local function assertFinalNames(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("BasePart") then
                assert(
                    child.Name == "Part",
                    "REVIEW-P1-FINAL-NAMES: partial SetName recovery must restore every planned name"
                )
            end
            assertFinalNames(child)
        end
    end
    assertFinalNames(targetBuild)
end
assert(saveInvokes == 1)
assert(checkpoint:load().status == "empty")
assert(
    adapter.copyEngine.state == nil,
    "Same-session completion must release runtime recovery state"
)
assert(
    (runtimeMetrics.peakParts or 0) <= 513
        and runtimeMetrics.retainedParts == 0,
    "Production execution must retain only bounded per-batch runtime instances"
)
assert(
    (runtimeMetrics.fullPartScans or 0) <= (largeCount > 1000 and 1 or 16),
    (
        "REVIEW-P1-EXECUTION-SCANS: normal execution must not repeatedly scan the full destination (%d)"
    ):format(runtimeMetrics.fullPartScans or 0)
)
assert(
    largeCount > 1000
        or (runtimeMetrics.peakResolvedGroupMembers or math.huge) <= 128,
    "REVIEW-P1-GROUP-RUNTIME: group reconciliation must not retain source-sized membership"
)
local invokesBeforeCancelledPreflight = syncInvokes
targetChildren = {}
table.clear(targetNameIndex)
cancelDuringScan = true
local cancelledPreflight, cancelledMessage =
    adapter:preflightCopy("Source", "copy_cancelled")
cancelDuringScan = false
assert(
    cancelledPreflight == false and cancelledMessage == "Copy preparation cancelled",
    "Preflight cancellation must stop before committing an engine job"
)
assert(checkpoint:load().status == "empty")
assert(syncInvokes == invokesBeforeCancelledPreflight)

if largeCount <= 1000 then
    assert(adapter:preflightCopy("Source", "copy_cross_server"))
    failAction = "SyncResize"
    local interrupted, interruptionMessage = adapter:confirmCopy()
    assert(interrupted == false and interruptionMessage == "Town copy remote failed")
    assert(adapter.copyEngine.state.job.state == "paused")
    local createdBeforeReopen = 0
    local function countBeforeReopen(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("BasePart") then
                createdBeforeReopen += 1
            end
            countBeforeReopen(child)
        end
    end
    countBeforeReopen(targetBuild)
    assert(createdBeforeReopen == largeCount)

    local reopenedCheckpoint = newCheckpointStore()
    local reopenedView
    local reopened = Town.new({
        checkpoint = reopenedCheckpoint,
        commandClock = function()
            return commandTime
        end,
        gameId = 1718755273,
        generateGuid = function()
            return "reopened-job"
        end,
        jobId = "different-server-job",
        localPlayer = localPlayer,
        now = function()
            return 100
        end,
        placeId = 4991214437,
        players = players,
        runtimeMetrics = {},
        store = {
            Patch = function(_, patch)
                reopenedView = patch.plotCopy
            end,
        },
        wait = function(duration)
            commandTime += duration or 0.01
        end,
        workspace = workspace,
    })
    local recoveryView = reopened:inspectCopyRecovery()
    local invokesBeforeOwnerMismatch = syncInvokes
    sourceUserId = 3
    local ownerMismatchView = reopened:inspectCopyRecovery()
    assert(
        ownerMismatchView.state == "error",
        "REVIEW-P1-SOURCE-OWNER: recovery must freshly verify the source owner identity"
    )
    assert(syncInvokes == invokesBeforeOwnerMismatch)
    sourceUserId = 2
    recoveryView = reopened:inspectCopyRecovery()
    assert(
        recoveryView.state == "paused"
            and recoveryView.resumeAvailable
            and recoveryView.discardAvailable,
        "A compatible cross-server checkpoint must expose Resume and Discard privately"
    )
    assert(recoveryView.possiblyAppliedBatch ~= nil)
    local resumed, resumeError = reopened:resumeCopy()
    assert(resumed, tostring(resumeError))
    assert(reopenedView.state == "completed")
    local createdAfterResume = 0
    local function countAfterResume(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("BasePart") then
                createdAfterResume += 1
            end
            countAfterResume(child)
        end
    end
    countAfterResume(targetBuild)
    assert(
        createdAfterResume == createdBeforeReopen,
        "Cross-server resume must not duplicate already confirmed creation batches"
    )
    assert(reopenedCheckpoint:load().status == "empty")

    resetDestination()
    local finalNameStore = newCheckpointStore()
    local finalNameAdapter = newRecoveryAdapter(
        finalNameStore,
        "final-name-crash-job"
    )
    assert(finalNameAdapter:preflightCopy("Source", "copy_final_names"))
    partialSetNameLimit = 1
    local namesInterrupted, namesInterruption = finalNameAdapter:confirmCopy()
    assert(
        namesInterrupted == false and namesInterruption == "Town copy remote failed"
    )
    local nameCrashState = assert(finalNameStore:load().state)
    assert(nameCrashState.progress.pendingBatch.operation == "SetPartNames")
    local finalNameRecoveryStore = newCheckpointStore()
    local finalNameRecovery = newRecoveryAdapter(
        finalNameRecoveryStore,
        "final-name-recovery-session"
    )
    assert(finalNameRecovery:inspectCopyRecovery().resumeAvailable)
    assert(finalNameRecovery:resumeCopy())
    local function verifyRecoveredNames(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("BasePart") then
                assert(
                    child.Name == "Part",
                    "REVIEW-P1-FINAL-NAMES: partial SetName recovery must restore every planned name"
                )
            end
            verifyRecoveredNames(child)
        end
    end
    verifyRecoveredNames(targetBuild)
    assert(finalNameRecoveryStore:load().status == "empty")

    resetDestination()
    local foreignCreationStore = newCheckpointStore()
    local foreignCreation = newRecoveryAdapter(
        foreignCreationStore,
        "foreign-creation-job"
    )
    assert(foreignCreation:preflightCopy("Source", "copy_foreign_creation"))
    failAction = "CreatePart"
    local creationNotApplied = foreignCreation:confirmCopy()
    assert(creationNotApplied == false)
    local pendingCreation = assert(foreignCreationStore:load().state)
    assert(pendingCreation.progress.pendingBatch.operation == "CreatePart")
    local coincidentForeign = part(777777)
    coincidentForeign.CFrame = CFrame.new(
        table.unpack(pendingCreation.progress.pendingBatch.creationCFrame)
    )
    coincidentForeign.Name = "Foreign"
    setParent(coincidentForeign, targetBuild)
    local invokesBeforeForeignRecovery = syncInvokes
    local foreignCreationRecoveryStore = newCheckpointStore()
    local foreignCreationRecovery = newRecoveryAdapter(
        foreignCreationRecoveryStore,
        "foreign-creation-recovery-session"
    )
    local foreignCreationView = foreignCreationRecovery:inspectCopyRecovery()
    assert(
        foreignCreationView.state == "error",
        "REVIEW-P0-FOREIGN-CREATION: a coincident foreign part must never be adopted"
    )
    assert(syncInvokes == invokesBeforeForeignRecovery)
    assert(coincidentForeign.Name == "Foreign" and coincidentForeign.Parent == targetBuild)
    removeFromParent(coincidentForeign)
    assert(foreignCreationRecovery:inspectCopyRecovery().resumeAvailable)
    assert(foreignCreationRecovery:discardCopy())
    assert(foreignCreationRecoveryStore:load().status == "empty")

    resetDestination()
    local createCrashStore = newCheckpointStore()
    local createCrash = newRecoveryAdapter(createCrashStore, "create-crash-job")
    assert(createCrash:preflightCopy("Source", "copy_create_crash"))
    failAction = "SetName"
    assert(createCrash:confirmCopy() == false)
    local createCrashState = assert(createCrashStore:load().state)
    assert(createCrashState.progress.pendingBatch.operation == "CreatePart")
    assert(targetPartCount() == 1)
    local createRecoveryStore = newCheckpointStore()
    local createRecovery = newRecoveryAdapter(
        createRecoveryStore,
        "create-recovery-session"
    )
    local unprovenSeed = targetChildren[1]
    local invokesBeforeCreateRecovery = syncInvokes
    local createRecoveryView = createRecovery:inspectCopyRecovery()
    assert(
        createRecoveryView.state == "error"
            and createRecoveryView.localCleanupAvailable == true
            and createRecoveryView.resumeAvailable ~= true,
        "REVIEW-P0-CREATE-CRASH: an unmarked seed must block instead of being adopted"
    )
    assert(syncInvokes == invokesBeforeCreateRecovery)
    assert(createRecovery:cleanupCopyCheckpoint())
    assert(createRecoveryStore:load().status == "empty")
    assert(unprovenSeed.Parent == targetBuild and targetPartCount() == 1)

    resetDestination()
    local partialStore = newCheckpointStore()
    local adoptionRemoteCrash = true
    local partialAdapter = newRecoveryAdapter(partialStore, "partial-clone-job", {
        afterRemote = function(batch)
            if adoptionRemoteCrash and batch.operation == "AdoptOwnership" then
                adoptionRemoteCrash = false
                error("synthetic second crash after ownership effect")
            end
        end,
    })
    assert(partialAdapter:preflightCopy("Source", "copy_partial_clone"))
    partialCloneLimit = 2
    assert(not pcall(function()
        partialAdapter:confirmCopy()
    end))
    local partialState = assert(partialStore:load().state)
    assert(partialState.progress.pendingBatch.operation == "AdoptOwnership")
    assert(partialState.progress.pendingBatch.nextPending.operation == "Clone")
    assert(targetPartCount() > 2 and targetPartCount() < largeCount)
    local partialRecoveryStore = newCheckpointStore()
    local partialRecovery = newRecoveryAdapter(
        partialRecoveryStore,
        "partial-recovery-session"
    )
    assert(partialRecovery:inspectCopyRecovery().resumeAvailable)
    assert(partialRecovery:resumeCopy())
    assert(
        targetPartCount() == largeCount,
        "A second partial-Clone crash must resume only the durable remainder"
    )
    assert(partialRecoveryStore:load().status == "empty")

    resetDestination()
    local saveCrashStore = newCheckpointStore()
    local saveCrashAdapter = newRecoveryAdapter(saveCrashStore, "save-effect-job")
    assert(saveCrashAdapter:preflightCopy("Source", "copy_save_effect"))
    local savesBeforeEffectCrash = saveInvokes
    failSaveAfterEffect = true
    assert(saveCrashAdapter:confirmCopy())
    assert(
        saveInvokes == savesBeforeEffectCrash + 1,
        "A Save that took effect before disconnect must not be replayed"
    )
    assert(saveCrashStore:load().status == "empty")

    resetDestination()
    local cleanupResumeStore = newCheckpointStore()
    local cleanupConfirmationCrash = true
    local cleanupResumeAdapter = newRecoveryAdapter(
        cleanupResumeStore,
        "cleanup-resume-job",
        {
            afterCleanupConfirmation = function()
                if cleanupConfirmationCrash then
                    cleanupConfirmationCrash = false
                    error("synthetic crash after durable cleanup confirmation")
                end
            end,
        }
    )
    assert(cleanupResumeAdapter:preflightCopy("Source", "copy_cleanup_resume"))
    failAction = "SyncResize"
    local cleanupInterrupted = cleanupResumeAdapter:confirmCopy()
    assert(cleanupInterrupted == false)
    assert(not pcall(function()
        cleanupResumeAdapter:discardCopy()
    end))
    local cleanupCrashState = assert(cleanupResumeStore:load().state)
    assert(
        cleanupCrashState.job.state == "rollback"
            and cleanupCrashState.cleanup.removedCount > 0
    )
    local partsAfterCleanupCrash = targetPartCount()
    assert(partsAfterCleanupCrash < largeCount)
    local cleanupRetryStore = newCheckpointStore()
    local cleanupRetry = newRecoveryAdapter(
        cleanupRetryStore,
        "cleanup-retry-session"
    )
    local cleanupRetryView = cleanupRetry:inspectCopyRecovery()
    assert(
        cleanupRetryView.retryCleanupAvailable,
        "REVIEW-P1-CLEANUP-RESUME: partial cleanup must reopen as retryable recovery"
    )
    assert(cleanupRetry:retryCopyCleanup())
    assert(targetPartCount() == 0)
    assert(cleanupRetryStore:load().status == "empty")

    resetDestination()
    local groupCleanupStore = newCheckpointStore()
    local groupCleanupAdapter
    local cancelAfterGroup = true
    local crashAfterGroupRemoval = true
    groupCleanupAdapter = newRecoveryAdapter(
        groupCleanupStore,
        "group-cleanup-job",
        {
            afterCleanupConfirmation = function()
                if crashAfterGroupRemoval then
                    crashAfterGroupRemoval = false
                    error("synthetic crash after grouped artifact cleanup")
                end
            end,
            afterRemote = function(batch)
                if cancelAfterGroup and batch.operation == "SetGroupName" then
                    cancelAfterGroup = false
                    groupCleanupAdapter:cancelCopy()
                end
            end,
        }
    )
    assert(groupCleanupAdapter:preflightCopy("Source", "copy_group_cleanup"))
    assert(groupCleanupAdapter:confirmCopy())
    assert(groupCleanupAdapter.copyEngine.state.job.state == "paused")
    local groupDiscardSucceeded, groupDiscardError = pcall(function()
        groupCleanupAdapter:discardCopy()
    end)
    assert(not groupDiscardSucceeded)
    local groupCrashState = groupCleanupStore:load().state
    assert(
        groupCrashState.cleanup and groupCrashState.cleanup.removedCount == 1,
        tostring(groupDiscardError)
    )
    local groupedRetryStore = newCheckpointStore()
    local groupedRetry = newRecoveryAdapter(
        groupedRetryStore,
        "group-cleanup-retry-session"
    )
    local groupedRetryView = groupedRetry:inspectCopyRecovery()
    assert(
        groupedRetryView.retryCleanupAvailable,
        "REVIEW-P2-GROUP-CLEANUP: removed group contents must remain retryable after relaunch"
    )
    assert(groupedRetry:retryCopyCleanup())
    assert(targetPartCount() == 0)
    assert(groupedRetryStore:load().status == "empty")
end
if process.env.TOWN_TEST_TIMING then
    print(("preflight=%.3f execution=%.3f index_misses=%d codec=%d"):format(
        preflightFinishedAt - startedAt,
        os.clock() - preflightFinishedAt,
        targetIndexMisses,
        codecSequence
    ))
end

print("town-large-copy-integration-contracts-ok")
