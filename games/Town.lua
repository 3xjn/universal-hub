local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Canonical = importDependency("games/town/Canonical", "./town/Canonical")
local CopyEngine = importDependency("games/town/CopyEngine", "./town/CopyEngine")
local ExecutionPlan = importDependency("games/town/ExecutionPlan", "./town/ExecutionPlan")

local Town = {
    capabilities = {
        "plotCopy",
    },
    cosmetics = false,
    id = "town",
    label = "Town",
    manifest = {
        gameIds = { 1718755273 },
        placeIds = { 4991214437 },
    },
}

local PREFERRED_BATCH_SIZE = 128
local CLONE_REQUEST_SIZE = 513
-- Scheduler tuning from current Town behavior; requires a separately authorized live probe.
local COMMAND_COOLDOWN_SECONDS = 6
local PLOT_ROOT_NAME = "Private Building Areas"

local function contains(list, value)
    for _, candidate in ipairs(list or {}) do
        if candidate == value then
            return true
        end
    end
    return false
end

local function partType(part)
    if part:IsA("TrussPart") then
        return "Truss"
    elseif part:IsA("WedgePart") then
        return "Wedge"
    elseif part:IsA("CornerWedgePart") then
        return "Corner"
    elseif part:IsA("VehicleSeat") then
        return "Vehicle Seat"
    elseif part:IsA("Seat") then
        return "Seat"
    elseif not part:IsA("Part") then
        return nil
    elseif part.Shape == Enum.PartType.Ball then
        return "Ball"
    elseif part.Shape == Enum.PartType.Cylinder then
        return "Cylinder"
    end
    return "Normal"
end

local function plotDistance(plot, position)
    local localPosition = plot.CFrame:PointToObjectSpace(position)
    local halfSize = plot.Size * 0.5
    local outsideX = math.max(math.abs(localPosition.X) - halfSize.X, 0)
    local outsideZ = math.max(math.abs(localPosition.Z) - halfSize.Z, 0)
    return Vector2.new(outsideX, outsideZ).Magnitude
end

local function transformedCFrame(sourcePlotCFrame, targetPlotCFrame, sourceCFrame)
    return targetPlotCFrame * sourcePlotCFrame:ToObjectSpace(sourceCFrame)
end

local function selectNearestPlot(plots, localPlotName, position)
    local selected
    local selectedDistance = math.huge
    for _, plot in ipairs(plots) do
        if plot:IsA("BasePart")
            and plot.Name ~= localPlotName
            and plot:FindFirstChild("Build")
        then
            local distance = plotDistance(plot, position)
            if distance < selectedDistance then
                selected = plot
                selectedDistance = distance
            end
        end
    end
    return selected, selectedDistance
end

local function plotOwnerName(plotName)
    local ownerName = type(plotName) == "string" and plotName:match("^(.*)BuildArea$") or nil
    return ownerName ~= "" and ownerName or nil
end

local function plotOwners(plots, localPlotName)
    local owners = {}
    for _, plot in ipairs(plots) do
        local ownerName = plotOwnerName(plot.Name)
        if plot:IsA("BasePart")
            and plot.Name ~= localPlotName
            and plot:FindFirstChild("Build")
            and ownerName
        then
            table.insert(owners, ownerName)
        end
    end
    table.sort(owners, function(left, right)
        return left:lower() < right:lower()
    end)
    return owners
end

local function validSaveName(saveName)
    return type(saveName) == "string"
        and #saveName >= 1
        and #saveName <= 32
        and saveName:match("^[%w_%-]+$") ~= nil
end

local function snapshotLights(part)
    local lights = {}
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("Light") then
            table.insert(lights, {
                Angle = child:IsA("SpotLight") and child.Angle or nil,
                Brightness = child.Brightness,
                Color = child.Color,
                Enabled = child.Enabled,
                Face = (child:IsA("SurfaceLight") or child:IsA("SpotLight"))
                        and child.Face
                    or nil,
                LightType = child.ClassName,
                Range = child.Range,
                Shadows = child.Shadows,
            })
        end
    end
    return lights
end

local function wireMarkerType(part)
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("Texture") and math.abs(child.Transparency) >= 499.999 then
            return child.StudsPerTileU
        end
    end
    return nil
end

local function normalizedWiringCFrames(sourceBuild)
    local normalized = {}
    for _, descendant in ipairs(sourceBuild:GetDescendants()) do
        if descendant:IsA("Model") then
            local state
            local startPart
            local endPart
            local affected = {}
            for _, child in ipairs(descendant:GetChildren()) do
                if child:IsA("BoolValue") then
                    state = child.Value
                elseif child:IsA("BasePart") then
                    local markerType = wireMarkerType(child)
                    if markerType == 1 then
                        startPart = child
                    elseif markerType == 2 then
                        endPart = child
                    elseif markerType == nil then
                        table.insert(affected, child)
                    end
                end
            end
            if state == true and startPart and endPart then
                for _, part in ipairs(affected) do
                    normalized[part] = startPart.CFrame * endPart.CFrame:ToObjectSpace(part.CFrame)
                end
            end
        end
    end
    return normalized
end

local function snapshotModels(sourceBuild, supportedSources)
    local models = {}
    for _, descendant in ipairs(sourceBuild:GetDescendants()) do
        if descendant:IsA("Model") then
            local depth = 0
            local ancestor = descendant
            while ancestor and ancestor ~= sourceBuild do
                depth += 1
                ancestor = ancestor.Parent
            end
            local modelSnapshot = {
                Depth = depth,
                Models = {},
                Name = descendant.Name,
                Parts = {},
                Source = descendant,
            }
            for _, child in ipairs(descendant:GetChildren()) do
                if child:IsA("BasePart") and supportedSources[child] then
                    table.insert(modelSnapshot.Parts, child)
                elseif child:IsA("Model") then
                    table.insert(modelSnapshot.Models, child)
                end
            end
            table.insert(models, modelSnapshot)
        end
    end
    table.sort(models, function(left, right)
        return left.Depth > right.Depth
    end)
    return models
end

local function vector3(value)
    return {
        x = value.X,
        y = value.Y,
        z = value.Z,
    }
end

local function color3(value)
    return {
        b = value.B,
        g = value.G,
        r = value.R,
    }
end

local function cframe(value)
    return { value:GetComponents() }
end

local function enum(value)
    return tostring(value)
end

local function decodeVector3(value)
    return Vector3.new(value.x, value.y, value.z)
end

local function decodeColor3(value)
    return Color3.new(value.r, value.g, value.b)
end

local function decodeCFrame(value)
    return CFrame.new(table.unpack(value))
end

local function decodeEnum(value)
    local enumType, item = value:match("^Enum%.([^.]+)%.(.+)$")
    assert(enumType and item and Enum[enumType], "Invalid persisted Town enum")
    return Enum[enumType][item]
end

local function near(left, right)
    return math.abs(left - right) <= 0.0001
end

local function sameVector(left, right)
    return (left - right).Magnitude <= 0.0001
end

local function sameCFrame(left, right)
    local leftValues = { left:GetComponents() }
    local rightValues = { right:GetComponents() }
    for index = 1, #leftValues do
        if not near(leftValues[index], rightValues[index]) then
            return false
        end
    end
    return true
end

local function matchesFinalPart(part, record)
    if partType(part) ~= record.type
        or part.Name ~= record.name
        or not sameVector(part.Size, decodeVector3(record.size))
        or not sameCFrame(part.CFrame, decodeCFrame(record.cframe))
        or not near(part.Color.R, record.color.r)
        or not near(part.Color.G, record.color.g)
        or not near(part.Color.B, record.color.b)
        or part.Material ~= decodeEnum(record.material)
        or not near(part.Reflectance, record.reflectance)
        or not near(part.Transparency, record.transparency)
        or part.CanCollide ~= record.canCollide
        or part.Anchored ~= record.anchored
        or part.BackSurface ~= decodeEnum(record.surfaces.back)
        or part.BottomSurface ~= decodeEnum(record.surfaces.bottom)
        or part.FrontSurface ~= decodeEnum(record.surfaces.front)
        or part.LeftSurface ~= decodeEnum(record.surfaces.left)
        or part.RightSurface ~= decodeEnum(record.surfaces.right)
        or part.TopSurface ~= decodeEnum(record.surfaces.top)
    then
        return false
    end
    local mesh = part:FindFirstChildOfClass("SpecialMesh")
    if record.mesh then
        if not mesh
            or mesh.MeshId ~= record.mesh.meshId
            or mesh.MeshType ~= decodeEnum(record.mesh.meshType)
            or not sameVector(mesh.Offset, decodeVector3(record.mesh.offset))
            or not sameVector(mesh.Scale, decodeVector3(record.mesh.scale))
            or mesh.TextureId ~= record.mesh.textureId
            or not sameVector(mesh.VertexColor, decodeVector3(record.mesh.vertexColor))
        then
            return false
        end
    elseif mesh then
        return false
    end
    local textures = {}
    local lights = {}
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            table.insert(textures, child)
        elseif child:IsA("Light") then
            table.insert(lights, child)
        end
    end
    if #textures ~= #(record.textures or {}) or #lights ~= #(record.lights or {}) then
        return false
    end
    for index, expected in ipairs(record.textures or {}) do
        local child = textures[index]
        if child.ClassName ~= expected.textureType
            or child.Face ~= decodeEnum(expected.face)
            or child.Texture ~= expected.texture
            or not near(child.Transparency, expected.transparency)
            or (child:IsA("Texture")
                and (not near(child.OffsetStudsU, expected.offsetStudsU)
                    or not near(child.OffsetStudsV, expected.offsetStudsV)
                    or not near(child.StudsPerTileU, expected.studsPerTileU)
                    or not near(child.StudsPerTileV, expected.studsPerTileV)))
        then
            return false
        end
    end
    for index, expected in ipairs(record.lights or {}) do
        local child = lights[index]
        if child.ClassName ~= expected.lightType
            or child.Enabled ~= expected.enabled
            or not near(child.Brightness, expected.brightness)
            or not near(child.Range, expected.range)
            or child.Shadows ~= expected.shadows
            or not near(child.Color.R, expected.color.r)
            or not near(child.Color.G, expected.color.g)
            or not near(child.Color.B, expected.color.b)
        then
            return false
        end
    end
    return true
end

local function operationsFor(record)
    local operations = {
        "resize",
        "color",
        "material",
        "surface",
        "collision",
        "anchor",
        "name",
    }
    if record.mesh then
        table.insert(operations, "meshCreate")
        table.insert(operations, "meshSync")
    end
    for _ = 1, #(record.textures or {}) do
        table.insert(operations, "textureCreate")
        table.insert(operations, "textureSync")
    end
    for _, light in ipairs(record.lights or {}) do
        if light.enabled then
            table.insert(operations, "lightCreate")
            table.insert(operations, "lightSync")
        end
    end
    return operations
end

local function serializedPart(part, sourcePlot, targetPlot, normalizedCFrame, id, ordinal)
    local textures = {}
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            table.insert(textures, {
                face = enum(child.Face),
                offsetStudsU = child:IsA("Texture") and child.OffsetStudsU or 0,
                offsetStudsV = child:IsA("Texture") and child.OffsetStudsV or 0,
                studsPerTileU = child:IsA("Texture") and child.StudsPerTileU or 0,
                studsPerTileV = child:IsA("Texture") and child.StudsPerTileV or 0,
                texture = child.Texture,
                textureType = child.ClassName,
                transparency = child.Transparency,
            })
        end
    end
    local lights = {}
    for _, light in ipairs(snapshotLights(part)) do
        table.insert(lights, {
            angle = light.Angle or 0,
            brightness = light.Brightness,
            color = color3(light.Color),
            enabled = light.Enabled,
            face = light.Face and enum(light.Face) or "Enum.NormalId.Front",
            lightType = light.LightType,
            range = light.Range,
            shadows = light.Shadows,
        })
    end
    local sourceMesh = part:FindFirstChildOfClass("SpecialMesh")
    local record = {
        anchored = part.Anchored,
        canCollide = part.CanCollide,
        cframe = cframe(transformedCFrame(
            sourcePlot.CFrame,
            targetPlot.CFrame,
            normalizedCFrame or part.CFrame
        )),
        className = part.ClassName,
        color = color3(part.Color),
        id = id,
        lights = lights,
        material = enum(part.Material),
        name = part.Name,
        ordinal = ordinal,
        markerBearing = wireMarkerType(part) ~= nil,
        reflectance = part.Reflectance,
        size = vector3(part.Size),
        surfaces = {
            back = enum(part.BackSurface),
            bottom = enum(part.BottomSurface),
            front = enum(part.FrontSurface),
            left = enum(part.LeftSurface),
            right = enum(part.RightSurface),
            top = enum(part.TopSurface),
        },
        textures = textures,
        transparency = part.Transparency,
        type = partType(part),
    }
    if sourceMesh then
        record.mesh = {
            meshId = sourceMesh.MeshId,
            meshType = enum(sourceMesh.MeshType),
            offset = vector3(sourceMesh.Offset),
            scale = vector3(sourceMesh.Scale),
            textureId = sourceMesh.TextureId,
            vertexColor = vector3(sourceMesh.VertexColor),
        }
    end
    record.operations = operationsFor(record)
    return record
end

local function inventoryFingerprint(root)
    local chunk = {}
    local chunkChecksums = {}
    local classCounts = {}
    local count = 0
    local baseParts = 0
    local function flush()
        if #chunk > 0 then
            table.insert(chunkChecksums, Canonical.checksum(chunk))
            chunk = {}
        end
    end
    local function visit(parent, path)
        for index, child in ipairs(parent:GetChildren()) do
            local childPath = ("%s/%06d"):format(path, index)
            count += 1
            classCounts[child.ClassName] = (classCounts[child.ClassName] or 0) + 1
            local record = {
                className = child.ClassName,
                name = child.Name,
                path = childPath,
            }
            if child:IsA("BasePart") then
                baseParts += 1
                record.cframe = cframe(child.CFrame)
                record.size = vector3(child.Size)
                record.type = partType(child) or false
            end
            table.insert(chunk, record)
            if #chunk == 256 then
                flush()
            end
            visit(child, childPath)
        end
    end
    visit(root, "")
    flush()
    local summary = {
        baseParts = baseParts,
        chunks = chunkChecksums,
        classCounts = classCounts,
        descendants = count,
    }
    summary.fingerprint = Canonical.checksum(summary)
    return summary
end

local pathId

local function eachDescendant(root, visit, options)
    options = options or {}
    local visited = 0
    local function walk(parent, path, depth)
        for index, child in ipairs(parent:GetChildren()) do
            if options.cancelled and options.cancelled() then
                error("Town preflight cancelled", 0)
            end
            local childPath = ("%s/%06d"):format(path, index)
            visit(child, childPath, depth + 1)
            visited += 1
            if visited % (options.yieldEvery or 128) == 0 and options.yield then
                options.yield()
            end
            walk(child, childPath, depth + 1)
        end
    end
    walk(root, "", 0)
end

local function eachGroupPostOrder(root, visit)
    local function walk(parent, path)
        for index, child in ipairs(parent:GetChildren()) do
            local childPath = ("%s/%06d"):format(path, index)
            if child:IsA("Model") then
                walk(child, childPath)
                local group = {
                    id = pathId("model", childPath),
                    name = child.Name,
                }
                group.iterMembers = function(emit)
                    for childIndex, member in ipairs(child:GetChildren()) do
                        local memberPath = ("%s/%06d"):format(childPath, childIndex)
                        if member:IsA("BasePart") and partType(member) then
                            emit("part", pathId("part", memberPath))
                        elseif member:IsA("Model") then
                            emit("model", pathId("model", memberPath))
                        end
                    end
                end
                visit(group)
            end
        end
    end
    walk(root, "")
end

pathId = function(kind, path)
    return kind .. "-" .. Canonical.sha256Bytes(path):sub(1, 24)
end

local normalizedPartCFrame

local function streamingSourceFingerprint(root, sourcePlot, targetPlot, sourceWired)
    local buffer = {}
    local checksums = {}
    local supported = 0
    local ordinal = 0
    local function flush()
        if #buffer > 0 then
            table.insert(checksums, Canonical.checksum(buffer))
            buffer = {}
        end
    end
    eachDescendant(root, function(descendant, path)
        local record
        if descendant:IsA("BasePart") and partType(descendant) then
            supported += 1
            ordinal += 1
            record = serializedPart(
                descendant,
                sourcePlot,
                targetPlot,
                sourceWired and normalizedPartCFrame(descendant) or nil,
                pathId("part", path),
                ordinal
            )
            record.path = path
        elseif descendant:IsA("Model") then
            record = {
                className = "Model",
                id = pathId("model", path),
                name = descendant.Name,
                path = path,
            }
        end
        if record then
            table.insert(buffer, record)
            if #buffer == 256 then
                flush()
            end
        end
    end)
    flush()
    return Canonical.checksum({
        chunks = checksums,
        supported = supported,
        wired = sourceWired == true,
    }), supported
end

normalizedPartCFrame = function(part)
    local parent = part.Parent
    if not parent or not parent:IsA("Model") then
        return nil
    end
    local state
    local startPart
    local endPart
    for _, sibling in ipairs(parent:GetChildren()) do
        if sibling:IsA("BoolValue") then
            state = sibling.Value
        elseif sibling:IsA("BasePart") then
            local markerType = wireMarkerType(sibling)
            if markerType == 1 then
                startPart = sibling
            elseif markerType == 2 then
                endPart = sibling
            end
        end
    end
    if state == true and startPart and endPart and not wireMarkerType(part) then
        return startPart.CFrame * endPart.CFrame:ToObjectSpace(part.CFrame)
    end
    return nil
end

local function ownershipName(jobId, planId)
    return "__UH_" .. Canonical.checksum({
        jobId = jobId,
        planId = planId,
    }):match(":(%x+)"):sub(1, 24)
end

local function groupOwnershipName(jobId, groupId)
    return "__UHG_" .. Canonical.checksum({
        groupId = groupId,
        jobId = jobId,
    }):match(":(%x+)"):sub(1, 24)
end

local function childOwnershipName(jobId, operation, partId, index)
    return "__UHC_" .. Canonical.checksum({
        index = index,
        jobId = jobId,
        operation = operation,
        partId = partId,
    }):match(":(%x+)"):sub(1, 24)
end

function Town.match(context)
    if contains(Town.manifest.placeIds, context.placeId) then
        return 200
    end
    if contains(Town.manifest.gameIds, context.gameId) then
        return 100
    end
    return 0
end

Town.partType = partType
Town.plotDistance = plotDistance
Town.plotOwnerName = plotOwnerName
Town.plotOwners = plotOwners
Town.selectNearestPlot = selectNearestPlot
Town.snapshotLights = snapshotLights
Town.snapshotModels = snapshotModels
Town.normalizedWiringCFrames = normalizedWiringCFrames
Town.ownershipName = ownershipName
Town.groupOwnershipName = groupOwnershipName
Town.childOwnershipName = childOwnershipName
Town.inventoryFingerprint = inventoryFingerprint
Town.streamingSourceFingerprint = streamingSourceFingerprint
Town.transformedCFrame = transformedCFrame
Town.validSaveName = validSaveName

function Town.new(context)
    assert(context and context.store, "Town adapter requires a reactive store")
    local Players = context.players or game:GetService("Players")
    local Workspace = context.workspace or game:GetService("Workspace")
    local LocalPlayer = context.localPlayer or Players.LocalPlayer
    local store = context.store
    local runtimeParts = {}
    local runtimeGroups = {}
    local currentTargetBuild
    local currentTargetPlot
    local destinationGuard
    local engineRef
    local localCleanupAuthorized = false
    local planChunkCache
    local validateRecoveryInventory

    local self = {
        localPlayer = LocalPlayer,
        preflightActive = false,
        preflightCancelRequested = false,
        stopped = false,
    }

    local function publish(view)
        store:Patch({
            plotCopy = view,
        })
        return view
    end

    local function plotRoot()
        return Workspace:FindFirstChild(PLOT_ROOT_NAME)
    end

    local function destination()
        local root = plotRoot()
        local plot = root and root:FindFirstChild(LocalPlayer.Name .. "BuildArea")
        return plot, plot and plot:FindFirstChild("Build")
    end

    local function destinationContext(plot, build, baselineInventory)
        local path = PLOT_ROOT_NAME .. "." .. plot.Name .. ".Build"
        return {
            baselineFingerprint = Canonical.checksum({
                frame = cframe(plot.CFrame),
                inventory = baselineInventory,
                size = vector3(plot.Size),
            }),
            baselineInventory = baselineInventory,
            buildClassName = build.ClassName,
            buildIdentity = path .. "|" .. build.ClassName .. "|" .. build.Name,
            buildName = build.Name,
            ownerName = LocalPlayer.Name,
            ownerUserId = LocalPlayer.UserId or 0,
            plotFrame = cframe(plot.CFrame),
            plotName = plot.Name,
            plotPath = path,
            plotSize = vector3(plot.Size),
        }
    end

    local function attachDestinationGuard(build)
        if destinationGuard then
            for _, connection in ipairs(destinationGuard.connections) do
                connection:Disconnect()
            end
        end
        destinationGuard = {
            build = build,
            connections = {},
            mutating = false,
            unexpected = false,
        }
        local function watch(signal)
            if signal and type(signal.Connect) == "function" then
                table.insert(destinationGuard.connections, signal:Connect(function()
                    if not destinationGuard.mutating then
                        destinationGuard.unexpected = true
                    end
                end))
            end
        end
        watch(build.DescendantAdded)
        watch(build.DescendantRemoving)
    end

    local function findTool()
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local character = LocalPlayer.Character
        return (backpack and backpack:FindFirstChild("Building Tools"))
            or (character and character:FindFirstChild("Building Tools"))
    end

    local function saveIdentity(saveName)
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local plotGui = playerGui and playerGui:FindFirstChild("PlotGui")
        local saves = plotGui and plotGui:FindFirstChild("SaveFolder")
        local saved = saves and saves:FindFirstChild(saveName)
        if not saved then
            return {
                exists = false,
            }
        end
        local lastEdited
        local succeeded, attribute = pcall(saved.GetAttribute, saved, "LastEdited")
        if succeeded then
            lastEdited = attribute
        end
        local marker = saved:FindFirstChild("LastEdited")
        if lastEdited == nil and marker then
            lastEdited = marker.Value
        end
        local attributes = {}
        succeeded, attribute = pcall(saved.GetAttributes, saved)
        if succeeded and type(attribute) == "table" then
            attributes = attribute
        end
        return {
            exists = true,
            fingerprint = Canonical.checksum({
                attributes = attributes,
                className = saved.ClassName,
                lastEdited = lastEdited or false,
                name = saved.Name,
            }),
            lastEdited = lastEdited or false,
        }
    end

    local function syncAPI()
        local tool = findTool()
        local api = tool and tool:FindFirstChild("SyncAPI")
        assert(api and api:IsA("BindableFunction"), "Use !btools before starting a Town copy")
        return api
    end

    local function invoke(action, ...)
        local api = syncAPI()
        if destinationGuard then
            destinationGuard.mutating = true
        end
        local succeeded, result = pcall(api.Invoke, api, action, ...)
        if destinationGuard then
            destinationGuard.mutating = false
        end
        assert(succeeded, ("%s failed: %s"):format(action, tostring(result)))
        return result
    end

    local function waitForCooling(cancelled)
        while not cancelled() do
            local cooling = LocalPlayer:FindFirstChild("BuildCooling")
            if not cooling then
                return true
            end
            local desiredTime = cooling:FindFirstChild("DesiredTime")
            local remaining = desiredTime and desiredTime.Value - Workspace:GetServerTimeNow() or 0.1
            if desiredTime and remaining <= 0 then
                return true
            end
            (context.wait or task.wait)(math.clamp(remaining, 0.05, 0.5))
        end
        return false
    end

    local function beforeRemote(batch)
        if batch.operation ~= "Wire" and batch.operation ~= "Save" then
            return
        end
        local clock = context.commandClock or context.now or os.time
        local wait = context.wait or task.wait
        local lastCommandAt = engineRef.state.progress.lastCommandAttemptAt
        while lastCommandAt
            and clock() - lastCommandAt < COMMAND_COOLDOWN_SECONDS
            and not engineRef.stopped
            and not engineRef.cancelRequested
        do
            wait(math.min(0.25, COMMAND_COOLDOWN_SECONDS - (clock() - lastCommandAt)))
        end
        assert(
            not engineRef.stopped and not engineRef.cancelRequested,
            "Town command scheduling stopped"
        )
        engineRef.state = context.checkpoint:advance(function(state)
            state.progress.lastCommandAttemptAt = clock()
        end)
    end

    local function readRecords(planIds)
        local wanted = {}
        for _, id in ipairs(planIds or {}) do
            wanted[id] = true
        end
        local found = {}
        local state = engineRef.state
        local remaining = 0
        for _ in pairs(wanted) do
            remaining += 1
        end
        if planChunkCache and planChunkCache.jobId == state.job.id then
            for id in pairs(wanted) do
                if planChunkCache.records[id] then
                    found[id] = planChunkCache.records[id]
                    remaining -= 1
                end
            end
            if remaining == 0 then
                return found
            end
        end
        local chunks = state and state.plan and state.plan.chunks or {}
        local startIndex = planChunkCache and planChunkCache.jobId == state.job.id
                and (planChunkCache.index % #chunks) + 1
            or 1
        for offset = 0, #chunks - 1 do
            local metadataIndex = ((startIndex + offset - 1) % #chunks) + 1
            local metadata = chunks[metadataIndex]
            if planChunkCache
                and planChunkCache.jobId == state.job.id
                and planChunkCache.index == metadata.index
            then
                continue
            end
            local chunk = context.checkpoint:readPlanChunk(state.job.id, metadata)
            local indexed = {}
            for _, record in ipairs(chunk.records or {}) do
                indexed[record.id] = record
                if wanted[record.id] and not found[record.id] then
                    found[record.id] = record
                    remaining -= 1
                end
            end
            planChunkCache = {
                index = metadata.index,
                jobId = state.job.id,
                records = indexed,
            }
            if remaining == 0 then
                return found
            end
        end
        for id in pairs(wanted) do
            assert(found[id], "Persisted Town plan record is unavailable")
        end
        return found
    end

    local function ensureRuntimeParts(planIds)
        table.clear(runtimeParts)
        local records = readRecords(planIds)
        local tokenIds = {}
        local finalNameIds = {}
        local unresolved = 0
        for _, id in ipairs(planIds or {}) do
            local token = ownershipName(engineRef.state.job.id, id)
            tokenIds[token] = id
            local name = records[id].name
            finalNameIds[name] = finalNameIds[name] or {}
            table.insert(finalNameIds[name], id)
            local succeeded, found = pcall(
                currentTargetBuild.FindFirstChild,
                currentTargetBuild,
                token,
                true
            )
            if succeeded and found and found:IsA("BasePart") then
                runtimeParts[id] = found
            else
                unresolved += 1
            end
        end
        if unresolved == 0 then
            if context.runtimeMetrics then
                context.runtimeMetrics.peakParts = math.max(
                    context.runtimeMetrics.peakParts or 0,
                    #planIds
                )
            end
            return
        end
        if context.runtimeMetrics then
            context.runtimeMetrics.fullPartScans =
                (context.runtimeMetrics.fullPartScans or 0) + 1
        end
        local matches = {}
        eachDescendant(currentTargetBuild, function(descendant)
            if not descendant:IsA("BasePart") then
                return
            end
            local tokenId = tokenIds[descendant.Name]
            if tokenId then
                matches[tokenId] = matches[tokenId] or {}
                table.insert(matches[tokenId], descendant)
                return
            end
            for _, id in ipairs(finalNameIds[descendant.Name] or {}) do
                if matchesFinalPart(descendant, records[id]) then
                    matches[id] = matches[id] or {}
                    table.insert(matches[id], descendant)
                end
            end
        end)
        for _, id in ipairs(planIds or {}) do
            local candidates = matches[id] or {}
            assert(#candidates == 1, "A planned Town output is missing or ambiguous")
            runtimeParts[id] = candidates[1]
        end
        if context.runtimeMetrics then
            context.runtimeMetrics.peakParts = math.max(
                context.runtimeMetrics.peakParts or 0,
                #planIds
            )
        end
    end

    local function unownedCreationParts(batch)
        local records = readRecords(batch.planIds)
        local result = {}
        if batch.originalOperation == "Clone" or batch.operation == "Clone" then
            ensureRuntimeParts(batch.sourceIds)
            local sources = {}
            for _, sourceId in ipairs(batch.sourceIds) do
                sources[runtimeParts[sourceId]] = true
            end
            local wantedNames = {}
            for _, sourceId in ipairs(batch.sourceIds) do
                wantedNames[ownershipName(engineRef.state.job.id, sourceId)] = true
            end
            for _, child in ipairs(currentTargetBuild:GetChildren()) do
                if child:IsA("BasePart")
                    and wantedNames[child.Name]
                    and not sources[child]
                then
                    table.insert(result, child)
                end
            end
        else
            local record = records[batch.planIds[1]]
            for _, child in ipairs(currentTargetBuild:GetChildren()) do
                if child:IsA("BasePart")
                    and partType(child) == record.type
                    and sameCFrame(
                        child.CFrame,
                        decodeCFrame(batch.creationCFrame or record.cframe)
                    )
                    and child.Name ~= ownershipName(engineRef.state.job.id, batch.planIds[1])
                then
                    table.insert(result, child)
                end
            end
        end
        return result
    end

    local function partArtifactStatus(id)
        local record = readRecords({ id })[id]
        local token = ownershipName(engineRef.state.job.id, id)
        local matches = 0
        eachDescendant(currentTargetBuild, function(descendant)
            if descendant:IsA("BasePart")
                and (descendant.Name == token or matchesFinalPart(descendant, record))
            then
                matches += 1
            end
        end)
        if matches == 0 then
            return "absent"
        elseif matches == 1 then
            return "present"
        end
        return "ambiguous"
    end

    local function changes(batch)
        ensureRuntimeParts(batch.planIds)
        local records = readRecords(batch.planIds)
        local entriesByPart = {}
        for _, entry in ipairs(batch.entries or {}) do
            entriesByPart[entry.partId] = entriesByPart[entry.partId] or {}
            table.insert(entriesByPart[entry.partId], entry.index)
        end
        local result = {}
        for _, id in ipairs(batch.planIds or {}) do
            local record = records[id]
            local part = assert(runtimeParts[id], "A planned destination part is unavailable")
            if batch.operation == "SyncResize" then
                table.insert(result, {
                    CFrame = decodeCFrame(record.cframe),
                    Part = part,
                    Size = decodeVector3(record.size),
                })
            elseif batch.operation == "SyncColor" then
                table.insert(result, {
                    Color = decodeColor3(record.color),
                    Part = part,
                    UnionColoring = true,
                })
            elseif batch.operation == "SyncMaterial" then
                table.insert(result, {
                    Material = decodeEnum(record.material),
                    Part = part,
                    Reflectance = record.reflectance,
                    Transparency = record.transparency,
                })
            elseif batch.operation == "SyncSurface" then
                table.insert(result, {
                    Part = part,
                    Surfaces = {
                        BackSurface = decodeEnum(record.surfaces.back),
                        BottomSurface = decodeEnum(record.surfaces.bottom),
                        FrontSurface = decodeEnum(record.surfaces.front),
                        LeftSurface = decodeEnum(record.surfaces.left),
                        RightSurface = decodeEnum(record.surfaces.right),
                        TopSurface = decodeEnum(record.surfaces.top),
                    },
                })
            elseif batch.operation == "SyncCollision" then
                table.insert(result, {
                    CanCollide = record.canCollide,
                    Part = part,
                })
            elseif batch.operation == "SyncAnchor" then
                table.insert(result, {
                    Anchored = record.anchored,
                    Part = part,
                })
            elseif batch.operation == "CreateMeshes" then
                table.insert(result, { Part = part })
            elseif batch.operation == "SyncMesh" then
                local mesh = record.mesh
                table.insert(result, {
                    MeshId = mesh.meshId,
                    MeshType = decodeEnum(mesh.meshType),
                    Offset = decodeVector3(mesh.offset),
                    Part = part,
                    Scale = decodeVector3(mesh.scale),
                    TextureId = mesh.textureId,
                    VertexColor = decodeVector3(mesh.vertexColor),
                })
            elseif batch.operation == "CreateTextures" or batch.operation == "SyncTexture" then
                for _, textureIndex in ipairs(entriesByPart[id] or {}) do
                    local texture = record.textures[textureIndex]
                    local change = {
                        Face = decodeEnum(texture.face),
                        Part = part,
                        TextureType = texture.textureType,
                    }
                    if batch.operation == "SyncTexture" then
                        change.OffsetStudsU = texture.offsetStudsU
                        change.OffsetStudsV = texture.offsetStudsV
                        change.StudsPerTileU = texture.studsPerTileU
                        change.StudsPerTileV = texture.studsPerTileV
                        change.Texture = texture.texture
                        change.Transparency = texture.transparency
                    end
                    table.insert(result, change)
                end
            elseif batch.operation == "CreateLights" or batch.operation == "SyncLighting" then
                for _, lightIndex in ipairs(entriesByPart[id] or {}) do
                    local light = record.lights[lightIndex]
                    local change = {
                        LightType = light.lightType,
                        Part = part,
                    }
                    if batch.operation == "SyncLighting" then
                        change.Angle = light.angle
                        change.Brightness = light.brightness
                        change.Color = decodeColor3(light.color)
                        change.Face = decodeEnum(light.face)
                        change.Range = light.range
                        change.Shadows = light.shadows
                    end
                    if light.enabled then
                        table.insert(result, change)
                    end
                end
            end
        end
        return result
    end

    local createdChildren
    local resolveGroup

    local function memberInstances(memberIds)
        local partIds = {}
        for _, member in ipairs(memberIds or {}) do
            if member.kind == "part" then
                table.insert(partIds, member.id)
            end
        end
        if #partIds > 0 then
            ensureRuntimeParts(partIds)
        end
        local result = {}
        for _, member in ipairs(memberIds or {}) do
            if member.kind == "part" then
                local part = assert(runtimeParts[member.id], "Town group part is unavailable")
                table.insert(result, part)
            else
                local group = resolveGroup(member.id)
                assert(group, "Town nested group is unavailable")
                table.insert(result, group)
            end
        end
        return result
    end

    local function applyBatch(batch)
        if batch.operation == "CreatePart" then
            local record = readRecords(batch.planIds)[batch.planIds[1]]
            local part = invoke(
                "CreatePart",
                batch.townType,
                decodeCFrame(batch.creationCFrame or record.cframe),
                currentTargetBuild
            )
            assert(part, "Town refused a planned seed part")
            invoke(
                "SetName",
                { part },
                { ownershipName(engineRef.state.job.id, batch.planIds[1]) }
            )
            return true
        elseif batch.operation == "Clone" then
            ensureRuntimeParts(batch.sourceIds)
            local sources = {}
            for _, id in ipairs(batch.sourceIds) do
                local source = assert(runtimeParts[id], "Town clone source is unavailable")
                table.insert(sources, source)
            end
            local clones = invoke("Clone", sources, currentTargetBuild)
            assert(type(clones) == "table" and #clones == #batch.planIds, "Town refused a planned clone batch")
            local names = {}
            for index, id in ipairs(batch.planIds) do
                names[index] = ownershipName(engineRef.state.job.id, id)
            end
            invoke("SetName", clones, names)
            return true
        elseif batch.operation == "AdoptOwnership" then
            local parts = unownedCreationParts(batch)
            assert(
                #parts == #(batch.planIds or {}),
                "Unowned Town creation delta is missing or ambiguous"
            )
            local names = {}
            for index, id in ipairs(batch.planIds) do
                names[index] = ownershipName(engineRef.state.job.id, id)
            end
            invoke("SetName", parts, names)
            return true
        elseif batch.operation == "SetPartNames" then
            ensureRuntimeParts(batch.planIds)
            local records = readRecords(batch.planIds)
            local parts = {}
            local names = {}
            for index, id in ipairs(batch.planIds) do
                parts[index] = assert(runtimeParts[id], "Town name target is unavailable")
                names[index] = records[id].name
            end
            invoke("SetName", parts, names)
            return true
        elseif batch.operation == "CreateMeshes"
            or batch.operation == "CreateTextures"
            or batch.operation == "CreateLights"
        then
            invoke(batch.operation, changes(batch))
            local children, status = createdChildren(batch, true)
            assert(status == "confirmed", "Created Town detail identity is ambiguous")
            local names = {}
            local entries = batch.entries or {}
            for index, child in ipairs(children) do
                local entry = entries[index]
                    or { index = 1, partId = batch.planIds[index] }
                names[index] = childOwnershipName(
                    engineRef.state.job.id,
                    batch.operation,
                    entry.partId,
                    entry.index
                )
            end
            invoke("SetName", children, names)
            return true
        elseif batch.operation == "AdoptChildOwnership" then
            local children, status = createdChildren(batch, true)
            assert(status == "confirmed", "Unowned Town detail identity is ambiguous")
            local names = {}
            for index, entry in ipairs(batch.entries or {}) do
                names[index] = childOwnershipName(
                    engineRef.state.job.id,
                    batch.originalOperation,
                    entry.partId,
                    entry.index
                )
            end
            invoke("SetName", children, names)
            return true
        elseif batch.operation == "CreateGroup" then
            local selection = memberInstances(batch.memberIds)
            local group = invoke("CreateGroup", "Model", currentTargetBuild, selection)
            assert(group, "Town refused a planned group")
            invoke(
                "SetName",
                { group },
                { groupOwnershipName(engineRef.state.job.id, batch.groupId) }
            )
            return true
        elseif batch.operation == "AdoptGroupOwnership" then
            local group = assert(
                resolveGroup(batch.groupId, true),
                "Unowned Town group delta is missing or ambiguous"
            )
            invoke(
                "SetName",
                { group },
                { groupOwnershipName(engineRef.state.job.id, batch.groupId) }
            )
            return true
        elseif batch.operation == "AddGroupMembers" then
            local group = assert(
                resolveGroup(batch.groupId, false, batch.sequence - 1),
                "Town planned group is unavailable"
            )
            invoke("SetParent", memberInstances(batch.memberIds), group)
            return true
        elseif batch.operation == "SetGroupName" then
            local group = assert(resolveGroup(batch.groupId), "Town planned group is unavailable")
            invoke("SetName", { group }, batch.groupName)
            return true
        elseif batch.operation == "Wire" then
            local playerGui = assert(LocalPlayer:FindFirstChildOfClass("PlayerGui"), "Town player GUI is unavailable")
            local console = playerGui:FindFirstChild("ChatConsoleGui")
            local command = console and console:FindFirstChild("CommandFunction")
            assert(command, "Town command function is unavailable")
            command:InvokeServer("!wireconnections")
            return true
        elseif batch.operation == "Save" then
            local playerGui = assert(LocalPlayer:FindFirstChildOfClass("PlayerGui"), "Town player GUI is unavailable")
            local plotGui = assert(playerGui:FindFirstChild("PlotGui"), "Open Town's save GUI before starting the copy")
            local remote = assert(plotGui:FindFirstChild("PlotServer"), "Town save remote is unavailable")
            local saves = assert(plotGui:FindFirstChild("SaveFolder"), "Town save list is unavailable")
            remote:InvokeServer(saves:FindFirstChild(batch.saveName) and "save" or "create", batch.saveName)
            return true
        end
        invoke(batch.operation, changes(batch))
        return true
    end

    createdChildren = function(batch, allowRaw)
        ensureRuntimeParts(batch.planIds)
        local records = readRecords(batch.planIds)
        local originalOperation = batch.originalOperation or batch.operation
        local children = {}
        local claimed = {}
        local present = 0
        local entries = batch.entries or {}
        if #entries == 0 and originalOperation == "CreateMeshes" then
            for _, id in ipairs(batch.planIds or {}) do
                table.insert(entries, {
                    index = 1,
                    partId = id,
                })
            end
        end
        for _, entry in ipairs(entries) do
            local record = records[entry.partId]
            local expected = originalOperation == "CreateTextures"
                    and record.textures[entry.index]
                or (originalOperation == "CreateLights"
                    and record.lights[entry.index])
                or record.mesh
            local token = childOwnershipName(
                engineRef.state.job.id,
                originalOperation,
                entry.partId,
                entry.index
            )
            local matches = {}
            for _, child in ipairs(runtimeParts[entry.partId]:GetChildren()) do
                local className = originalOperation == "CreateTextures"
                        and expected.textureType
                    or (originalOperation == "CreateLights"
                        and expected.lightType)
                    or "SpecialMesh"
                local rawMatch = child.ClassName == className
                    and (originalOperation ~= "CreateTextures"
                        or child.Face == decodeEnum(expected.face))
                if not claimed[child]
                    and (child.Name == token or (allowRaw and rawMatch))
                then
                    table.insert(matches, child)
                end
            end
            if #matches > 1 and not allowRaw then
                return nil, "ambiguous"
            elseif #matches > 0 then
                local selected = matches[1]
                claimed[selected] = true
                table.insert(children, selected)
                present += 1
            end
        end
        if present == #entries then
            return children, "confirmed"
        elseif present == 0 then
            return nil, "not_applied"
        end
        return nil, "ambiguous"
    end

    local function reconcileConfiguredChildren(batch, kind)
        ensureRuntimeParts(batch.planIds)
        local records = readRecords(batch.planIds)
        local creationOperation = kind == "texture" and "CreateTextures" or "CreateLights"
        for _, entry in ipairs(batch.entries or {}) do
            local record = records[entry.partId]
            local expected = kind == "texture"
                    and record.textures[entry.index]
                or record.lights[entry.index]
            local token = childOwnershipName(
                engineRef.state.job.id,
                creationOperation,
                entry.partId,
                entry.index
            )
            local matches = {}
            for _, child in ipairs(runtimeParts[entry.partId]:GetChildren()) do
                if child.Name == token then
                    table.insert(matches, child)
                end
            end
            if #matches ~= 1 then
                return #matches == 0 and "not_applied" or "ambiguous"
            end
            local child = matches[1]
            if kind == "texture" then
                if child.ClassName ~= expected.textureType
                    or child.Face ~= decodeEnum(expected.face)
                    or child.Texture ~= expected.texture
                    or not near(child.Transparency, expected.transparency)
                    or (child:IsA("Texture")
                        and (not near(child.OffsetStudsU, expected.offsetStudsU)
                            or not near(child.OffsetStudsV, expected.offsetStudsV)
                            or not near(child.StudsPerTileU, expected.studsPerTileU)
                            or not near(child.StudsPerTileV, expected.studsPerTileV)))
                then
                    return "not_applied"
                end
            elseif child.ClassName ~= expected.lightType
                or child.Enabled ~= expected.enabled
                or not near(child.Brightness, expected.brightness)
                or not near(child.Range, expected.range)
                or child.Shadows ~= expected.shadows
                or not near(child.Color.R, expected.color.r)
                or not near(child.Color.G, expected.color.g)
                or not near(child.Color.B, expected.color.b)
                or ((child:IsA("SpotLight") or child:IsA("SurfaceLight"))
                    and (not near(child.Angle, expected.angle)
                        or child.Face ~= decodeEnum(expected.face)))
            then
                return "not_applied"
            end
        end
        return "confirmed"
    end

    resolveGroup = function(groupId, allowRaw, maximumSequence)
        table.clear(runtimeGroups)
        local groupName
        local groupFingerprint
        local memberCount = 0
        maximumSequence = maximumSequence
            or (engineRef.state.progress.pendingBatch
                and engineRef.state.progress.pendingBatch.sequence)
            or engineRef.state.progress.lastConfirmedSequence
        for sequence = 1, engineRef:_batchCount() do
            local planned = engineRef:getBatch(sequence)
            if planned.groupId == groupId then
                groupName = planned.groupName
                groupFingerprint = planned.groupFingerprint
                if sequence <= maximumSequence
                    and (planned.operation == "CreateGroup"
                        or planned.operation == "AddGroupMembers")
                then
                    memberCount += #(planned.memberIds or {})
                end
            end
        end
        if not groupName or not groupFingerprint then
            return nil, "ambiguous"
        end
        local candidate
        local ambiguous = false
        local function exactMembership(descendant)
            for sequence = 1, maximumSequence do
                local planned = engineRef:getBatch(sequence)
                if planned.groupId == groupId
                    and (planned.operation == "CreateGroup"
                        or planned.operation == "AddGroupMembers")
                then
                    local members = memberInstances(planned.memberIds or {})
                    if context.runtimeMetrics then
                        context.runtimeMetrics.peakResolvedGroupMembers = math.max(
                            context.runtimeMetrics.peakResolvedGroupMembers or 0,
                            #members
                        )
                    end
                    for _, item in ipairs(members) do
                        if item.Parent ~= descendant then
                            return false
                        end
                    end
                end
            end
            return true
        end
        eachDescendant(currentTargetBuild, function(descendant)
            if not ambiguous and descendant:IsA("Model") then
                local expectedName = descendant.Name
                    == groupOwnershipName(engineRef.state.job.id, groupId)
                    or descendant.Name == groupName
                    or (allowRaw and descendant.Name == "Model")
                if expectedName
                    and #descendant:GetChildren() == memberCount
                    and exactMembership(descendant)
                then
                    if candidate then
                        ambiguous = true
                    else
                        candidate = descendant
                    end
                end
            end
        end)
        if candidate and not ambiguous then
            runtimeGroups[groupId] = candidate
            return candidate, "confirmed"
        elseif not candidate then
            return nil, "not_applied"
        end
        return nil, "ambiguous"
    end

    local function reconcileProperties(batch)
        ensureRuntimeParts(batch.planIds)
        local records = readRecords(batch.planIds)
        for _, id in ipairs(batch.planIds) do
            local part = runtimeParts[id]
            local record = records[id]
            if batch.operation == "SyncResize" then
                if not sameVector(part.Size, decodeVector3(record.size))
                    or not sameCFrame(part.CFrame, decodeCFrame(record.cframe))
                then
                    return "not_applied"
                end
            elseif batch.operation == "SyncColor" then
                if not sameVector(
                    Vector3.new(part.Color.R, part.Color.G, part.Color.B),
                    Vector3.new(record.color.r, record.color.g, record.color.b)
                ) then
                    return "not_applied"
                end
            elseif batch.operation == "SyncMaterial" then
                if part.Material ~= decodeEnum(record.material)
                    or not near(part.Reflectance, record.reflectance)
                    or not near(part.Transparency, record.transparency)
                then
                    return "not_applied"
                end
            elseif batch.operation == "SyncSurface" then
                if part.BackSurface ~= decodeEnum(record.surfaces.back)
                    or part.BottomSurface ~= decodeEnum(record.surfaces.bottom)
                    or part.FrontSurface ~= decodeEnum(record.surfaces.front)
                    or part.LeftSurface ~= decodeEnum(record.surfaces.left)
                    or part.RightSurface ~= decodeEnum(record.surfaces.right)
                    or part.TopSurface ~= decodeEnum(record.surfaces.top)
                then
                    return "not_applied"
                end
            elseif batch.operation == "SyncCollision" and part.CanCollide ~= record.canCollide then
                return "not_applied"
            elseif batch.operation == "SyncAnchor" and part.Anchored ~= record.anchored then
                return "not_applied"
            elseif batch.operation == "SyncMesh" then
                local mesh = part:FindFirstChildOfClass("SpecialMesh")
                if not mesh
                    or mesh.MeshId ~= record.mesh.meshId
                    or mesh.MeshType ~= decodeEnum(record.mesh.meshType)
                    or not sameVector(mesh.Offset, decodeVector3(record.mesh.offset))
                    or not sameVector(mesh.Scale, decodeVector3(record.mesh.scale))
                    or mesh.TextureId ~= record.mesh.textureId
                    or not sameVector(mesh.VertexColor, decodeVector3(record.mesh.vertexColor))
                then
                    return "not_applied"
                end
            end
        end
        return "confirmed"
    end

    local function reconcileBatch(batch, applied, recovering)
        if batch.operation == "CreatePart"
            or batch.operation == "Clone"
            or batch.operation == "AdoptOwnership"
        then
            if pcall(ensureRuntimeParts, batch.planIds) then
                return "confirmed"
            end
            local creationOperation =
                (batch.originalOperation or batch.operation) == "CreatePart"
            if creationOperation and recovering then
                local raw = unownedCreationParts(batch)
                if batch.operation == "CreatePart" and #raw == 0 then
                    return "not_applied"
                end
                return "ambiguous"
            end
            if batch.operation == "AdoptOwnership" then
                local raw = unownedCreationParts(batch)
                return #raw == #(batch.planIds or {}) and "not_applied" or "ambiguous"
            end
            local raw = unownedCreationParts(batch)
            if #raw == 0 then
                return "not_applied"
            elseif #raw > #(batch.planIds or {}) then
                return "ambiguous"
            end
            local adoptedIds = {}
            for index = 1, #raw do
                adoptedIds[index] = batch.planIds[index]
            end
            local adoption = {
                operation = "AdoptOwnership",
                originalOperation = batch.originalOperation or batch.operation,
                phase = batch.phase,
                planIds = adoptedIds,
                sourceIds = batch.sourceIds,
                townType = batch.townType,
                creationCFrame = batch.creationCFrame,
                weight = batch.weight,
            }
            if #raw < #(batch.planIds or {}) then
                local remainderIds = {}
                local remainderSources = {}
                for index = #raw + 1, #batch.planIds do
                    table.insert(remainderIds, batch.planIds[index])
                    if batch.sourceIds then
                        table.insert(remainderSources, batch.sourceIds[index])
                    end
                end
                adoption.nextPending = {
                    operation = batch.originalOperation or batch.operation,
                    originalOperation = batch.originalOperation or batch.operation,
                    phase = batch.phase,
                    planIds = remainderIds,
                    sourceIds = remainderSources,
                    townType = batch.townType,
                    weight = batch.weight,
                }
            end
            return {
                remainder = adoption,
                status = "ownership_pending",
            }
        elseif batch.operation == "Wire" then
            local currentFingerprint = Canonical.checksum({
                buildIdentity = engineRef.state.context.destination.buildIdentity,
                groups = engineRef.state.plan.groups,
                planHash = engineRef.state.plan.fingerprint,
            })
            if currentFingerprint ~= batch.wiringFingerprint then
                return "ambiguous"
            end
            return currentTargetPlot:GetAttribute("Wired") == true and "confirmed" or "not_applied"
        elseif batch.operation == "Save" then
            local prior = batch.priorSaveIdentity or { exists = false }
            local current = saveIdentity(batch.saveName)
            if not current.exists then
                return "not_applied"
            elseif not prior.exists then
                return "confirmed"
            elseif current.fingerprint ~= prior.fingerprint
                and current.lastEdited ~= prior.lastEdited
            then
                return "confirmed"
            end
            return "ambiguous"
        elseif batch.operation == "CreateTextures"
            or batch.operation == "CreateLights"
            or batch.operation == "CreateMeshes"
            or batch.operation == "AdoptChildOwnership"
        then
            local _, status = createdChildren(batch, false)
            if status == "confirmed" then
                return "confirmed"
            end
            local raw, rawStatus = createdChildren(batch, true)
            if batch.operation == "AdoptChildOwnership" then
                return raw and "not_applied" or rawStatus
            end
            if raw then
                return {
                    remainder = {
                        entries = batch.entries,
                        operation = "AdoptChildOwnership",
                        originalOperation = batch.operation,
                        phase = batch.phase,
                        planIds = batch.planIds,
                        weight = batch.weight,
                    },
                    status = "ownership_pending",
                }
            end
            return rawStatus
        elseif batch.operation == "CreateGroup"
            or batch.operation == "AdoptGroupOwnership"
        then
            local _, status = resolveGroup(batch.groupId, false, batch.sequence)
            if status == "confirmed" then
                return "confirmed"
            end
            local raw, rawStatus = resolveGroup(batch.groupId, true, batch.sequence)
            if batch.operation == "AdoptGroupOwnership" then
                return raw and "not_applied" or rawStatus
            end
            if raw then
                return {
                    remainder = {
                        groupFingerprint = batch.groupFingerprint,
                        groupId = batch.groupId,
                        groupName = batch.groupName,
                        memberCount = batch.memberCount,
                        memberIds = batch.memberIds,
                        operation = "AdoptGroupOwnership",
                        originalOperation = "CreateGroup",
                        phase = batch.phase,
                        weight = batch.weight,
                    },
                    status = "ownership_pending",
                }
            end
            return rawStatus
        elseif batch.operation == "AddGroupMembers" then
            local group = resolveGroup(batch.groupId, false, batch.sequence)
            if not group then
                return "ambiguous"
            end
            for _, item in ipairs(memberInstances(batch.memberIds)) do
                if item.Parent ~= group then
                    return "not_applied"
                end
            end
            return "confirmed"
        elseif batch.operation == "SetGroupName" then
            local group = resolveGroup(batch.groupId)
            if not group then
                return "ambiguous"
            end
            return group.Name == batch.groupName and "confirmed" or "not_applied"
        elseif batch.operation == "SetPartNames" then
            local records = readRecords(batch.planIds)
            if not applied and not pcall(ensureRuntimeParts, batch.planIds) then
                return "ambiguous"
            end
            for _, id in ipairs(batch.planIds) do
                if not runtimeParts[id]
                    or not runtimeParts[id].Parent
                    or runtimeParts[id].Name ~= records[id].name
                then
                    return "not_applied"
                end
            end
            return "confirmed"
        elseif batch.operation == "SyncTexture" then
            return reconcileConfiguredChildren(batch, "texture")
        elseif batch.operation == "SyncLighting" then
            return reconcileConfiguredChildren(batch, "light")
        end
        return reconcileProperties(batch)
    end

    local function nextCleanupBatch(state)
        local cleanup = state.cleanup or {}
        local rawCreation = state.progress.pendingRawCreation
        if rawCreation and not cleanup.pendingRawCreationRemoved then
            return {
                clearsPendingRawCreation = true,
                itemCount = #(rawCreation.planIds or {}),
                nextCursor = cleanup.cursorSequence,
                nextOffset = cleanup.cursorItemOffset or 0,
                operation = "Remove",
                planIds = rawCreation.planIds,
                rawCreation = rawCreation,
            }
        end
        local pendingGroup = state.progress.pendingGroupArtifact
        if pendingGroup and not cleanup.pendingGroupRemoved then
            return {
                artifacts = {
                    {
                        groupFingerprint = pendingGroup.groupFingerprint,
                        id = pendingGroup.groupId,
                        kind = "model",
                        raw = pendingGroup.raw,
                    },
                },
                clearsPendingGroup = true,
                itemCount = 1,
                nextCursor = cleanup.cursorSequence,
                nextOffset = cleanup.cursorItemOffset or 0,
                operation = "Remove",
                planIds = {},
            }
        end
        local adoption = state.progress.pendingAdoption
        if adoption
            and not cleanup.pendingAdoptionRemoved
            and #(adoption.planIds or {}) > 0
        then
            local first = (cleanup.cursorItemOffset or 0) + 1
            local last = math.min(first + PREFERRED_BATCH_SIZE - 1, #adoption.planIds)
            local ids = {}
            for index = first, last do
                table.insert(ids, adoption.planIds[index])
            end
            return {
                clearsPendingAdoption = last == #adoption.planIds,
                itemCount = #ids,
                nextCursor = cleanup.cursorSequence,
                nextOffset = last == #adoption.planIds and 0 or last,
                operation = "Remove",
                planIds = ids,
            }
        end

        local cursor = cleanup.cursorSequence or state.progress.lastConfirmedSequence or 0
        local offset = cleanup.cursorItemOffset or 0
        while cursor > 0 do
            local planned = engineRef:getBatch(cursor)
            local ids
            local artifacts = {}
            if planned.operation == "CreatePart" or planned.operation == "Clone" then
                ids = planned.planIds or {}
            elseif planned.operation == "CreateGroup" then
                table.insert(artifacts, {
                    groupFingerprint = planned.groupFingerprint,
                    id = planned.groupId,
                    kind = "model",
                })
            end
            if ids and offset < #ids then
                local first = offset + 1
                local last = math.min(first + PREFERRED_BATCH_SIZE - 1, #ids)
                local selected = {}
                for index = first, last do
                    table.insert(selected, ids[index])
                    table.insert(artifacts, {
                        id = ids[index],
                        kind = "part",
                    })
                end
                return {
                    artifacts = artifacts,
                    itemCount = #selected,
                    nextCursor = last == #ids and cursor - 1 or cursor,
                    nextOffset = last == #ids and 0 or last,
                    operation = "Remove",
                    planIds = selected,
                }
            elseif #artifacts > 0 then
                return {
                    artifacts = artifacts,
                    itemCount = #artifacts,
                    nextCursor = cursor - 1,
                    nextOffset = 0,
                    operation = "Remove",
                    planIds = {},
                }
            end
            cursor -= 1
            offset = 0
        end
        return nil
    end

    local function removeBatch(batch)
        local objects = {}
        if batch.rawCreation then
            for _, part in ipairs(unownedCreationParts(batch.rawCreation)) do
                if part.Parent then
                    table.insert(objects, part)
                end
            end
        elseif #(batch.planIds or {}) > 0 and pcall(ensureRuntimeParts, batch.planIds) then
            for _, id in ipairs(batch.planIds) do
                if runtimeParts[id] and runtimeParts[id].Parent then
                    table.insert(objects, runtimeParts[id])
                end
            end
        end
        for _, artifact in ipairs(batch.artifacts or {}) do
            if artifact.kind == "model" then
                local group = resolveGroup(artifact.id, artifact.raw == true)
                if group and group.Parent then
                    table.insert(objects, group)
                end
            end
        end
        if #objects > 0 then
            invoke("Remove", objects)
        end
        return true
    end

    local engine = context.copyEngine
    if not engine then
        engine = CopyEngine.new({
            applyBatch = applyBatch,
            afterCleanupConfirmation = context.copyAfterCleanupConfirmation,
            afterPartialAdoption = context.copyAfterPartialAdoption,
            afterRemote = context.copyAfterRemote,
            afterReplacement = context.copyAfterReplacement,
            beforeRemote = beforeRemote,
            captureError = context.copyErrorCapture,
            checkpoint = context.checkpoint,
            generateGuid = context.generateGuid,
            nextCleanupBatch = nextCleanupBatch,
            now = context.now,
            publish = publish,
            reconcileBatch = reconcileBatch,
            reconcileCleanup = function(batch)
                local present = 0
                if batch.rawCreation then
                    local raw = unownedCreationParts(batch.rawCreation)
                    if #raw > #(batch.planIds or {}) then
                        return "ambiguous"
                    end
                    present += #raw
                else
                    for _, id in ipairs(batch.planIds or {}) do
                        local status = partArtifactStatus(id)
                        if status == "ambiguous" then
                            return "ambiguous"
                        elseif status == "present" then
                            present += 1
                        end
                    end
                end
                for _, artifact in ipairs(batch.artifacts or {}) do
                    if artifact.kind == "model" then
                        local group, status = resolveGroup(artifact.id, artifact.raw == true)
                        if status == "ambiguous" then
                            return "ambiguous"
                        elseif group then
                            present += 1
                        end
                    end
                end
                local total = batch.itemCount or (
                    #(batch.planIds or {}) + #(batch.artifacts or {})
                )
                return present == 0 and "confirmed"
                    or (present == total and "not_applied" or "ambiguous")
            end,
            releaseBatchState = function()
                table.clear(runtimeParts)
                table.clear(runtimeGroups)
                if context.runtimeMetrics then
                    context.runtimeMetrics.retainedParts = 0
                    context.runtimeMetrics.retainedGroups = 0
                end
            end,
            removeBatch = removeBatch,
            validateContext = function(state)
                local targetPlot, targetBuild = destination()
                if not targetPlot
                    or not targetBuild
                    or not destinationGuard
                    or destinationGuard.build ~= targetBuild
                then
                    return false, "Checkpoint destination Build was replaced or removed"
                end
                local live = destinationContext(
                    targetPlot,
                    targetBuild,
                    state.context.destination.baselineInventory
                )
                if Canonical.checksum(live)
                    ~= Canonical.checksum(state.context.destination)
                then
                    return false, "Checkpoint destination frame, size, or identity changed"
                end
                if destinationGuard.unexpected then
                    if not validateRecoveryInventory(state, targetBuild) then
                        return false, "Destination changed outside the Town copy job"
                    end
                    destinationGuard.unexpected = false
                end
                return true
            end,
            waitForCooling = waitForCooling,
        })
    end
    self.copyEngine = engine
    engineRef = engine

    function self:listPlotOwners()
        local root = plotRoot()
        return root and plotOwners(root:GetChildren(), LocalPlayer.Name .. "BuildArea") or {}
    end

    function self:preflightCopy(ownerName, saveName)
        if context.copyEngine then
            return self.copyEngine:preflight(ownerName, saveName)
        end
        if not validSaveName(saveName) then
            local message = "Save name must be 1-32 letters, numbers, dashes, or underscores"
            publish({
                active = false,
                error = message,
                phase = "Copy blocked",
                state = "error",
            })
            return false, message
        end
        local root = plotRoot()
        local sourcePlot = root and root:FindFirstChild(ownerName .. "BuildArea")
        local sourceBuild = sourcePlot and sourcePlot:FindFirstChild("Build")
        local sourcePlayer = Players:FindFirstChild(ownerName)
        local targetPlot, targetBuild = destination()
        local baseline = targetBuild and inventoryFingerprint(targetBuild)
        if not sourcePlot or not sourcePlot:IsA("BasePart") or not sourceBuild then
            return false, "The selected player's plot is unavailable"
        elseif not sourcePlayer
            or type(sourcePlayer.UserId) ~= "number"
            or sourcePlayer.UserId <= 0
        then
            return false, "The selected plot owner is unavailable"
        elseif not targetPlot or not targetBuild then
            return false, "Use !createplot before copying a Town plot"
        elseif baseline.descendants > 0 then
            return false, "Your destination plot must be empty"
        end
        local tool = findTool()
        local api = tool and tool:FindFirstChild("SyncAPI")
        if not api or not api:IsA("BindableFunction") then
            return false, "Use !btools before preparing a Town copy"
        end
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local saveGui = playerGui and playerGui:FindFirstChild("PlotGui")
        if not saveGui
            or not saveGui:FindFirstChild("PlotServer")
            or not saveGui:FindFirstChild("SaveFolder")
        then
            return false, "Open Town's save GUI before preparing a copy"
        end
        if sourcePlot:GetAttribute("Wired") == true then
            local console = playerGui and playerGui:FindFirstChild("ChatConsoleGui")
            if not console or not console:FindFirstChild("CommandFunction") then
                return false, "Town wiring controls are unavailable"
            end
        end
        currentTargetPlot = targetPlot
        currentTargetBuild = targetBuild
        attachDestinationGuard(targetBuild)
        table.clear(runtimeParts)
        table.clear(runtimeGroups)
        planChunkCache = nil

        publish({
            active = false,
            confirmedProgress = 0,
            context = "Read-only source scan",
            phase = "Preparing copy",
            state = "preflight",
        })
        self.preflightActive = true
        self.preflightCancelRequested = false
        local sourceWired = sourcePlot:GetAttribute("Wired") == true
        local unsupported = 0
        local baseParts = 0
        local unsupportedClasses = {}
        local totalDescendants = 0
        local supportedCount = 0
        local groupCount = 0
        local scanOrdinal = 0
        local identityBuffer = {}
        local identityChecksums = {}
        local function flushIdentity()
            if #identityBuffer > 0 then
                table.insert(identityChecksums, Canonical.checksum(identityBuffer))
                identityBuffer = {}
            end
        end
        local scanned, scanError = pcall(eachDescendant, sourceBuild, function(descendant, path, depth)
            totalDescendants += 1
            if descendant:IsA("BasePart") then
                baseParts += 1
                local typeName = partType(descendant)
                if typeName then
                    supportedCount += 1
                    scanOrdinal += 1
                    local identity = serializedPart(
                        descendant,
                        sourcePlot,
                        targetPlot,
                        sourceWired and normalizedPartCFrame(descendant) or nil,
                        pathId("part", path),
                        scanOrdinal
                    )
                    identity.path = path
                    table.insert(identityBuffer, identity)
                    if #identityBuffer == 256 then
                        flushIdentity()
                    end
                else
                    unsupported += 1
                    unsupportedClasses[descendant.ClassName] =
                        (unsupportedClasses[descendant.ClassName] or 0) + 1
                end
            elseif descendant:IsA("Model") then
                groupCount += 1
                table.insert(identityBuffer, {
                    className = "Model",
                    id = pathId("model", path),
                    name = descendant.Name,
                    path = path,
                })
                if #identityBuffer == 256 then
                    flushIdentity()
                end
            end
        end, {
            cancelled = function()
                return self.preflightCancelRequested or self.stopped
            end,
            yield = context.scanYield or context.wait or task.wait,
            yieldEvery = 128,
        })
        if not scanned then
            self.preflightActive = false
            if context.scanErrorCapture then
                context.scanErrorCapture(tostring(scanError))
            end
            local message = tostring(scanError):find("cancelled", 1, true)
                    and "Copy preparation cancelled"
                or "Town source scan failed"
            publish({
                active = false,
                error = message,
                phase = "Ready",
                state = "idle",
            })
            return false, message
        end
        flushIdentity()
        if supportedCount == 0 then
            self.preflightActive = false
            return false, "The selected plot has no supported parts"
        end

        local sourceFingerprint = Canonical.checksum({
            chunks = identityChecksums,
            supported = supportedCount,
            wired = sourceWired,
        })

        local source = {
            baseParts = baseParts,
            context = {
                destination = destinationContext(targetPlot, targetBuild, baseline),
                gameId = context.gameId or game.GameId,
                localUserId = LocalPlayer.UserId or 0,
                placeId = context.placeId or game.PlaceId,
                source = {
                    ownerName = ownerName,
                    ownerUserId = sourcePlayer.UserId,
                    fingerprint = sourceFingerprint,
                    plotName = sourcePlot.Name,
                    plotPath = PLOT_ROOT_NAME .. "." .. sourcePlot.Name .. ".Build",
                },
            },
            copyWiring = sourceWired,
            groupCount = groupCount,
            groups = {},
            save = true,
            totalDescendants = totalDescendants,
            unsupported = unsupported,
            unsupportedClasses = unsupportedClasses,
        }
        source.iterParts = function(emit)
            local ordinal = 0
            eachDescendant(sourceBuild, function(part, path)
                if part:IsA("BasePart") and partType(part) then
                    ordinal += 1
                    emit(serializedPart(
                        part,
                        sourcePlot,
                        targetPlot,
                        sourceWired and normalizedPartCFrame(part) or nil,
                        pathId("part", path),
                        ordinal
                    ))
                end
            end, {
                cancelled = function()
                    return self.preflightCancelRequested or self.stopped
                end,
                yield = context.scanYield or context.wait or task.wait,
                yieldEvery = 128,
            })
            assert(ordinal == supportedCount, "Town source changed during preflight")
        end
        local request = {
            cloneRequestSize = CLONE_REQUEST_SIZE,
            compileExecution = function(jobId, planChunks, compiledPlan)
                return ExecutionPlan.compile(
                    context.checkpoint,
                    jobId,
                    planChunks,
                    compiledPlan,
                    {
                        cloneRequestSize = CLONE_REQUEST_SIZE,
                        copyWiring = source.copyWiring,
                        iterGroups = function(emit)
                            eachGroupPostOrder(sourceBuild, emit)
                        end,
                        preferredBatchSize = PREFERRED_BATCH_SIZE,
                        priorSaveIdentity = saveIdentity(saveName),
                        saveName = saveName,
                        wiringFingerprint = Canonical.checksum({
                            buildIdentity = source.context.destination.buildIdentity,
                            groups = compiledPlan.groups,
                            planHash = compiledPlan.fingerprint,
                        }),
                    }
                )
            end,
            copyWiring = source.copyWiring,
            estimateConfidence = "uncalibrated",
            originJobId = context.jobId or game.JobId,
            preferredBatchSize = PREFERRED_BATCH_SIZE,
            saveName = saveName,
            source = source,
        }
        local view, message = self.copyEngine:preflight(request)
        self.preflightActive = false
        return view, message
    end

    function self:copyPlot(ownerName, saveName)
        return self:preflightCopy(ownerName, saveName)
    end

    function self:confirmCopy()
        if not context.copyEngine
            and (not self.copyEngine.state
                or self.copyEngine.state.job.state ~= "awaiting_confirmation")
        then
            local view = self:inspectCopyRecovery()
            if not view or view.state ~= "awaiting_confirmation" then
                return false, "The secured Town plan no longer matches this source or destination"
            end
        end
        return self.copyEngine:confirmStart()
    end

    function self:cancelCopy()
        if self.preflightActive and not self.copyEngine.state then
            self.preflightCancelRequested = true
            return true
        end
        return self.copyEngine:requestCancel()
    end

    validateRecoveryInventory = function(state, targetBuild)
        local actual = inventoryFingerprint(targetBuild)
        local baseline = state.context.destination.baselineInventory
        if state.job.state == "awaiting_confirmation" then
            return actual.fingerprint == baseline.fingerprint
        end
        local expectedParts = baseline.baseParts or 0
        local expectedDescendants = baseline.descendants or 0
        local maximumSequence = state.progress.lastConfirmedSequence or 0
        local cleanup = state.cleanup
        local cleanupCursor = cleanup
            and (cleanup.cursorSequence or maximumSequence)
        local cleanupOffset = cleanup and (cleanup.cursorItemOffset or 0) or 0
        local function groupRemoved(groupId, visiting)
            if not cleanup then
                return false
            end
            visiting = visiting or {}
            if visiting[groupId] then
                return false
            end
            visiting[groupId] = true
            for sequence = 1, maximumSequence do
                local planned = engineRef:getBatch(sequence)
                if planned.groupId == groupId
                    and planned.operation == "CreateGroup"
                    and sequence > cleanupCursor
                then
                    visiting[groupId] = nil
                    return true
                end
            end
            for sequence = 1, maximumSequence do
                local planned = engineRef:getBatch(sequence)
                if planned.operation == "CreateGroup"
                    or planned.operation == "AddGroupMembers"
                then
                    for _, member in ipairs(planned.memberIds or {}) do
                        if member.kind == "model"
                            and member.id == groupId
                            and groupRemoved(planned.groupId, visiting)
                        then
                            visiting[groupId] = nil
                            return true
                        end
                    end
                end
            end
            visiting[groupId] = nil
            return false
        end
        local function removedWithGroup(planId)
            if not cleanup then
                return false
            end
            for sequence = 1, maximumSequence do
                local planned = engineRef:getBatch(sequence)
                if planned.operation == "CreateGroup"
                    or planned.operation == "AddGroupMembers"
                then
                    for _, member in ipairs(planned.memberIds or {}) do
                        if member.kind == "part"
                            and member.id == planId
                            and groupRemoved(planned.groupId)
                        then
                            return true
                        end
                    end
                end
            end
            return false
        end
        local function remainingPlanIds(batch, sequence)
            local ids = batch.planIds or {}
            local remaining = {}
            local first = cleanup
                    and sequence == cleanupCursor
                    and cleanupOffset + 1
                or 1
            if cleanup and sequence > cleanupCursor then
                return remaining
            end
            for index = first, #ids do
                if not removedWithGroup(ids[index]) then
                    table.insert(remaining, ids[index])
                end
            end
            return remaining
        end
        local function retainedIds(ids)
            if not cleanup then
                return ids
            end
            local wanted = {}
            local found = {}
            for _, id in ipairs(ids or {}) do
                wanted[id] = true
            end
            for sequence = 1, maximumSequence do
                local creation = engineRef:getBatch(sequence)
                if creation.operation == "CreatePart"
                    or creation.operation == "Clone"
                then
                    for _, id in ipairs(remainingPlanIds(creation, sequence)) do
                        if wanted[id] then
                            found[id] = true
                        end
                    end
                end
            end
            local result = {}
            for _, id in ipairs(ids or {}) do
                if found[id] then
                    table.insert(result, id)
                end
            end
            return result
        end
        local function countConfirmedChildren(batch)
            local ids = retainedIds(batch.planIds or {})
            if #ids == 0 then
                return 0
            end
            local filtered = {}
            for key, value in pairs(batch) do
                filtered[key] = value
            end
            filtered.planIds = ids
            local retained = {}
            for _, id in ipairs(ids) do
                retained[id] = true
            end
            filtered.entries = {}
            for _, entry in ipairs(batch.entries or {}) do
                if retained[entry.partId] then
                    table.insert(filtered.entries, entry)
                end
            end
            local _, status = createdChildren(filtered, false)
            if status ~= "confirmed" then
                return nil
            end
            return batch.operation == "CreateMeshes" and #ids or #filtered.entries
        end
        for sequence = 1, maximumSequence do
            local batch = engineRef:getBatch(sequence)
            if batch.operation == "CreatePart" or batch.operation == "Clone" then
                local ids = remainingPlanIds(batch, sequence)
                if #ids > 0 and not pcall(ensureRuntimeParts, ids) then
                    return false
                end
                expectedParts += #ids
                expectedDescendants += #ids
            elseif batch.operation == "CreateGroup" then
                local removed = groupRemoved(batch.groupId)
                if not removed
                    and not resolveGroup(batch.groupId, false, maximumSequence)
                then
                    return false
                end
                if not removed then
                    expectedDescendants += 1
                end
            elseif batch.operation == "CreateMeshes" then
                local count = countConfirmedChildren(batch)
                if count == nil then
                    return false
                end
                expectedDescendants += count
            elseif batch.operation == "CreateTextures"
                or batch.operation == "CreateLights"
            then
                local count = countConfirmedChildren(batch)
                if count == nil then
                    return false
                end
                expectedDescendants += count
            end
        end
        local pending = state.progress.pendingBatch
        if pending then
            if pending.operation == "CreatePart"
                or pending.operation == "Clone"
                or pending.operation == "AdoptOwnership"
            then
                local owned = pcall(ensureRuntimeParts, pending.planIds)
                local pendingParts
                if owned then
                    pendingParts = #(pending.planIds or {})
                elseif (pending.originalOperation or pending.operation) == "CreatePart" then
                    local raw = unownedCreationParts(pending)
                    if #raw > 0 then
                        return false, "unproven_creation"
                    elseif pending.operation == "AdoptOwnership" then
                        return false
                    end
                    pendingParts = 0
                else
                    pendingParts = #unownedCreationParts(pending)
                end
                if pendingParts > #(pending.planIds or {}) then
                    return false
                end
                expectedParts += pendingParts
                expectedDescendants += pendingParts
            elseif pending.operation == "CreateGroup"
                or pending.operation == "AdoptGroupOwnership"
            then
                local group = resolveGroup(pending.groupId, true, pending.sequence)
                if group then
                    expectedDescendants += 1
                end
            elseif pending.operation == "CreateMeshes" then
                expectedDescendants += #(pending.planIds or {})
            elseif pending.operation == "CreateTextures"
                or pending.operation == "CreateLights"
            then
                expectedDescendants += #(pending.entries or {})
            end
        end
        local pendingRaw = state.progress.pendingRawCreation
        if pendingRaw and not (cleanup and cleanup.pendingRawCreationRemoved) then
            local raw = unownedCreationParts(pendingRaw)
            if #raw > #(pendingRaw.planIds or {}) then
                return false
            end
            expectedParts += #raw
            expectedDescendants += #raw
        end
        local pendingAdoption = state.progress.pendingAdoption
        if pendingAdoption and not (cleanup and cleanup.pendingAdoptionRemoved) then
            local first = cleanup and cleanupOffset + 1 or 1
            local ids = {}
            for index = first, #(pendingAdoption.planIds or {}) do
                table.insert(ids, pendingAdoption.planIds[index])
            end
            if #ids > 0 and not pcall(ensureRuntimeParts, ids) then
                return false
            end
            expectedParts += #ids
            expectedDescendants += #ids
        end
        local pendingGroup = state.progress.pendingGroupArtifact
        if pendingGroup and not (cleanup and cleanup.pendingGroupRemoved) then
            local group = resolveGroup(
                pendingGroup.groupId,
                pendingGroup.raw == true,
                pendingGroup.sequence
            )
            if not group then
                return false
            end
            expectedDescendants += 1
        end
        return actual.baseParts == expectedParts
            and actual.descendants == expectedDescendants
    end

    function self:inspectCopyRecovery()
        localCleanupAuthorized = false
        if context.copyEngine then
            return self.copyEngine:inspectRecovery()
        end
        local loaded = context.checkpoint:load()
        if loaded.status ~= "ready" then
            return self.copyEngine:inspectRecovery()
        end
        local targetPlot, targetBuild = destination()
        if not targetPlot or not targetBuild then
            return publish({
                active = false,
                error = "Checkpoint destination Build is unavailable",
                phase = "Copy blocked",
                state = "error",
            })
        end
        currentTargetPlot = targetPlot
        currentTargetBuild = targetBuild
        attachDestinationGuard(targetBuild)
        engineRef.state = loaded.state
        local inventoryValid, inventoryIssue =
            validateRecoveryInventory(loaded.state, targetBuild)
        if not inventoryValid then
            localCleanupAuthorized = inventoryIssue == "unproven_creation"
                and (loaded.state.progress.lastConfirmedSequence or 0) == 0
            return publish({
                active = false,
                discardAvailable = false,
                error = "Destination changed after the Town copy checkpoint",
                localCleanupAvailable = localCleanupAuthorized,
                phase = "Copy blocked",
                state = "error",
            })
        end
        local liveContext = {
            destination = destinationContext(
                targetPlot,
                targetBuild,
                loaded.state.context.destination.baselineInventory
            ),
            gameId = context.gameId or game.GameId,
            localUserId = LocalPlayer.UserId or 0,
            placeId = context.placeId or game.PlaceId,
        }
        local sourceContext = loaded.state.context.source
        local root = plotRoot()
        local sourcePlayer = sourceContext
            and Players:FindFirstChild(sourceContext.ownerName)
        local sourcePlot = sourceContext
            and root
            and root:FindFirstChild(sourceContext.plotName)
        local sourceBuild = sourcePlot and sourcePlot:FindFirstChild("Build")
        local sourcePath = sourcePlot
            and (PLOT_ROOT_NAME .. "." .. sourcePlot.Name .. ".Build")
        if not sourceBuild
            or not sourcePlot:IsA("BasePart")
            or not sourcePlayer
            or sourcePlayer.UserId ~= sourceContext.ownerUserId
            or sourcePlot.Name ~= sourcePlayer.Name .. "BuildArea"
            or sourcePath ~= sourceContext.plotPath
        then
            return publish({
                active = false,
                error = "Checkpoint source owner or Build identity changed",
                phase = "Copy blocked",
                state = "error",
            })
        end
        local fingerprint = streamingSourceFingerprint(
            sourceBuild,
            sourcePlot,
            targetPlot,
            sourcePlot:GetAttribute("Wired") == true
        )
        liveContext.source = {
            fingerprint = fingerprint,
            ownerName = sourcePlayer.Name,
            ownerUserId = sourcePlayer.UserId,
            plotName = sourcePlot.Name,
            plotPath = sourcePath,
        }
        return self.copyEngine:inspectRecovery(liveContext)
    end

    function self:resumeCopy()
        if context.copyEngine then
            return self.copyEngine:resume()
        end
        local view = self:inspectCopyRecovery()
        local eligible = view
            and (
                view.state == "paused"
                or view.state == "copy_authorized"
                or view.state == "copying"
                or view.state == "reconciling"
                or view.state == "resuming"
            )
        if not eligible then
            return false, "The Town checkpoint is not safe to resume in this plot"
        end
        local targetPlot, targetBuild = destination()
        currentTargetPlot = targetPlot
        currentTargetBuild = targetBuild
        return self.copyEngine:resume()
    end

    function self:discardCopy()
        if context.copyEngine then
            return self.copyEngine:discard()
        end
        local view = self:inspectCopyRecovery()
        if not view or view.state ~= "paused" then
            return false, "The Town checkpoint is not safe to clean in this plot"
        end
        local targetPlot, targetBuild = destination()
        currentTargetPlot = targetPlot
        currentTargetBuild = targetBuild
        return self.copyEngine:discard()
    end

    function self:retryCopyCleanup()
        if not context.copyEngine then
            local view = self:inspectCopyRecovery()
            if not view
                or (view.state ~= "rollback" and view.state ~= "rollback_incomplete")
            then
                return false, "The Town checkpoint is not safe to clean in this plot"
            end
            local targetPlot, targetBuild = destination()
            currentTargetPlot = targetPlot
            currentTargetBuild = targetBuild
        end
        return self.copyEngine:retryCleanup()
    end

    function self:cleanupCopyCheckpoint()
        local cleaned, message = self.copyEngine:cleanupLocalCheckpoint(
            localCleanupAuthorized == true
        )
        if cleaned then
            localCleanupAuthorized = false
        end
        return cleaned, message
    end

    function self:stop()
        if self.stopped then
            return
        end
        self.stopped = true
        self.copyEngine:stop()
        if destinationGuard then
            for _, connection in ipairs(destinationGuard.connections) do
                connection:Disconnect()
            end
            destinationGuard = nil
        end
    end

    return self
end

return Town
