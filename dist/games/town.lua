return {
    buildId = [[610c86b0]],
    id = [[town]],
    sources = {
        ["games/Town.lua"] = [=[local function importDependency(path, relativePath)
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

local Town = {}

local PREFERRED_BATCH_SIZE = 128
local CLONE_REQUEST_SIZE = 513
-- Scheduler tuning from current Town behavior; requires a separately authorized live probe.
local COMMAND_COOLDOWN_SECONDS = 6
local PLOT_ROOT_NAME = "Private Building Areas"

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
]=],
        ["games/town/Canonical.lua"] = [[local Canonical = {}

local CHECKSUM_PREFIX = "sha256-c14n-v1:"
local UINT32 = 4294967296

local SHA256_CONSTANTS = {
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
}

local ESCAPES = {
    [34] = "\\\"",
    [92] = "\\\\",
}

local function add32(...)
    local total = 0
    for index = 1, select("#", ...) do
        total += select(index, ...)
    end
    return total % UINT32
end

local function validUtf8(value)
    local succeeded, length = pcall(utf8.len, value)
    return succeeded and length ~= nil
end

local function encodeString(value)
    assert(validUtf8(value), "Canonical strings must contain valid UTF-8")
    local output = { "\"" }
    for index = 1, #value do
        local byte = string.byte(value, index)
        local escaped = ESCAPES[byte]
        if escaped then
            table.insert(output, escaped)
        elseif byte < 32 then
            table.insert(output, ("\\u%04x"):format(byte))
        else
            table.insert(output, string.char(byte))
        end
    end
    table.insert(output, "\"")
    return table.concat(output)
end

local function encodeNumber(value)
    assert(value == value and value ~= math.huge and value ~= -math.huge, "Canonical numbers must be finite")
    if value == 0 then
        return "0"
    end
    if value % 1 == 0 then
        return ("%.0f"):format(value)
    end

    local encoded = ("%.17g"):format(value):lower():gsub("e%+", "e")
    local mantissa, sign, exponent = encoded:match("^(.-)e([%-]?)(%d+)$")
    if mantissa then
        exponent = exponent:gsub("^0+", "")
        if exponent == "" then
            exponent = "0"
        end
        encoded = mantissa .. "e" .. sign .. exponent
    end
    return encoded
end

local function tableKind(value)
    local count = 0
    local maximum = 0
    local numeric = true
    local textual = true
    for key in pairs(value) do
        count += 1
        if type(key) == "number" and key >= 1 and key % 1 == 0 then
            maximum = math.max(maximum, key)
        else
            numeric = false
        end
        if type(key) ~= "string" then
            textual = false
        end
    end
    if count == 0 then
        return "array", 0
    end
    if numeric then
        assert(maximum == count, "Canonical arrays must be dense")
        return "array", count
    end
    assert(textual, "Canonical objects require string keys and cannot mix key types")
    return "object", count
end

local encodeValue

local function encodeArray(value, length)
    local output = { "[" }
    for index = 1, length do
        if index > 1 then
            table.insert(output, ",")
        end
        table.insert(output, encodeValue(value[index]))
    end
    table.insert(output, "]")
    return table.concat(output)
end

local function encodeObject(value)
    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    table.sort(keys)

    local output = { "{" }
    for index, key in ipairs(keys) do
        if index > 1 then
            table.insert(output, ",")
        end
        table.insert(output, encodeString(key))
        table.insert(output, ":")
        table.insert(output, encodeValue(value[key]))
    end
    table.insert(output, "}")
    return table.concat(output)
end

encodeValue = function(value)
    local valueType = type(value)
    if valueType == "boolean" then
        return value and "true" or "false"
    elseif valueType == "number" then
        return encodeNumber(value)
    elseif valueType == "string" then
        return encodeString(value)
    elseif valueType == "table" then
        local kind, length = tableKind(value)
        return kind == "array" and encodeArray(value, length) or encodeObject(value)
    end
    error("Canonical values must be booleans, finite numbers, UTF-8 strings, dense arrays, or objects", 2)
end

function Canonical.encode(value)
    return encodeValue(value)
end

function Canonical.sha256Bytes(source)
    assert(type(source) == "string", "SHA-256 source must be a string")
    local bytes = {}
    for index = 1, #source do
        bytes[index] = string.byte(source, index)
    end
    local bitLength = #bytes * 8
    table.insert(bytes, 0x80)
    while #bytes % 64 ~= 56 do
        table.insert(bytes, 0)
    end

    local highLength = math.floor(bitLength / UINT32)
    local lowLength = bitLength % UINT32
    for shift = 24, 0, -8 do
        table.insert(bytes, bit32.band(bit32.rshift(highLength, shift), 0xff))
    end
    for shift = 24, 0, -8 do
        table.insert(bytes, bit32.band(bit32.rshift(lowLength, shift), 0xff))
    end

    local hash = {
        0x6a09e667,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19,
    }

    for offset = 1, #bytes, 64 do
        local words = {}
        for wordIndex = 1, 16 do
            local byteIndex = offset + (wordIndex - 1) * 4
            words[wordIndex] = add32(
                bit32.lshift(bytes[byteIndex], 24),
                bit32.lshift(bytes[byteIndex + 1], 16),
                bit32.lshift(bytes[byteIndex + 2], 8),
                bytes[byteIndex + 3]
            )
        end
        for wordIndex = 17, 64 do
            local previous = words[wordIndex - 15]
            local sigma0 = bit32.bxor(
                bit32.rrotate(previous, 7),
                bit32.rrotate(previous, 18),
                bit32.rshift(previous, 3)
            )
            previous = words[wordIndex - 2]
            local sigma1 = bit32.bxor(
                bit32.rrotate(previous, 17),
                bit32.rrotate(previous, 19),
                bit32.rshift(previous, 10)
            )
            words[wordIndex] = add32(sigma1, words[wordIndex - 7], sigma0, words[wordIndex - 16])
        end

        local a, b, c, d, e, f, g, h = table.unpack(hash)
        for wordIndex = 1, 64 do
            local sum1 = bit32.bxor(
                bit32.rrotate(e, 6),
                bit32.rrotate(e, 11),
                bit32.rrotate(e, 25)
            )
            local choice = bit32.bxor(bit32.band(e, f), bit32.band(bit32.bnot(e), g))
            local temporary1 = add32(h, sum1, choice, SHA256_CONSTANTS[wordIndex], words[wordIndex])
            local sum0 = bit32.bxor(
                bit32.rrotate(a, 2),
                bit32.rrotate(a, 13),
                bit32.rrotate(a, 22)
            )
            local majority = bit32.bxor(bit32.band(a, b), bit32.band(a, c), bit32.band(b, c))
            local temporary2 = add32(sum0, majority)
            h = g
            g = f
            f = e
            e = add32(d, temporary1)
            d = c
            c = b
            b = a
            a = add32(temporary1, temporary2)
        end

        hash[1] = add32(hash[1], a)
        hash[2] = add32(hash[2], b)
        hash[3] = add32(hash[3], c)
        hash[4] = add32(hash[4], d)
        hash[5] = add32(hash[5], e)
        hash[6] = add32(hash[6], f)
        hash[7] = add32(hash[7], g)
        hash[8] = add32(hash[8], h)
    end

    local output = {}
    for _, value in ipairs(hash) do
        table.insert(output, ("%08x"):format(value))
    end
    return table.concat(output)
end

function Canonical.checksum(value)
    local encoded = Canonical.encode(value)
    return CHECKSUM_PREFIX .. Canonical.sha256Bytes(encoded) .. ":" .. tostring(#encoded)
end

function Canonical.verify(value, expected)
    return type(expected) == "string" and Canonical.checksum(value) == expected
end

Canonical.algorithm = "sha256-c14n-v1"

return Canonical
]],
        ["games/town/CheckpointStore.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Canonical = importDependency("games/town/Canonical", "./Canonical")

local CheckpointStore = {}
CheckpointStore.__index = CheckpointStore

local ACTIVE_RETENTION_SECONDS = 7 * 24 * 60 * 60
local QUARANTINE_RETENTION_SECONDS = 7 * 24 * 60 * 60
local PUBLIC_ERROR = "Persistent recovery is unavailable in this executor"
local QUARANTINE_MESSAGE = "Checkpoint unavailable; recovery data was quarantined"
local ACTIVE_JOB_MESSAGE = "An unfinished Town copy already exists"
local STATE_AUTHORIZATION = {
    awaiting_confirmation = "awaiting_confirmation",
    cancel_requested = "copy_authorized",
    cleanup_pending = "copy_authorized",
    completed = "copy_authorized",
    copy_authorized = "copy_authorized",
    copying = "copy_authorized",
    paused = "copy_authorized",
    reconciling = "copy_authorized",
    resuming = "copy_authorized",
    rollback = "copy_authorized",
    rollback_incomplete = "copy_authorized",
}
local OPERATIONS = {
    AddGroupMembers = true,
    AdoptOwnership = true,
    AdoptGroupOwnership = true,
    AdoptChildOwnership = true,
    Clone = true,
    CreateGroup = true,
    CreateLights = true,
    CreateMeshes = true,
    CreatePart = true,
    CreateTextures = true,
    Save = true,
    SetGroupName = true,
    SetPartNames = true,
    SyncAnchor = true,
    SyncCollision = true,
    SyncColor = true,
    SyncLighting = true,
    SyncMaterial = true,
    SyncMesh = true,
    SyncResize = true,
    SyncSurface = true,
    SyncTexture = true,
    Wire = true,
}
local DESTINATION_CONTEXT_KEYS = {
    "baselineFingerprint",
    "baselineInventory",
    "buildClassName",
    "buildIdentity",
    "buildName",
    "ownerName",
    "ownerUserId",
    "plotFrame",
    "plotName",
    "plotPath",
    "plotSize",
}
local SOURCE_CONTEXT_KEYS = {
    "fingerprint",
    "ownerName",
    "ownerUserId",
    "plotName",
    "plotPath",
}
local REQUIRED_FUNCTIONS = {
    "decode",
    "deleteFile",
    "encode",
    "isFile",
    "listFiles",
    "makeFolder",
    "readFile",
    "writeFile",
}

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[key] = copy(child)
    end
    return result
end

local function copyMutableState(state)
    local result = {}
    for key, value in pairs(state) do
        if key == "context"
            or key == "execution"
            or key == "manifest"
            or key == "plan"
            or key == "request"
        then
            result[key] = value
        else
            result[key] = copy(value)
        end
    end
    return result
end

local function withoutKey(value, omitted)
    local result = {}
    for key, child in pairs(value) do
        if key ~= omitted then
            result[key] = child
        end
    end
    return result
end

local function dirname(path)
    return path:match("^(.*)[/\\][^/\\]+$")
end

local function normalize(path)
    return tostring(path):gsub("\\", "/"):gsub("/+", "/"):gsub("/$", "")
end

local function hasUnsafePathSegments(path)
    if type(path) ~= "string" or path:find("\0", 1, true) then
        return true
    end
    for component in path:gsub("\\", "/"):gmatch("[^/]+") do
        if component == "." or component == ".." then
            return true
        end
    end
    return false
end

local function isSafeJobId(jobId)
    return type(jobId) == "string"
        and #jobId > 0
        and #jobId <= 128
        and jobId:match("^[%w_%-]+$") ~= nil
end

local function isInteger(value, minimum)
    return type(value) == "number"
        and value % 1 == 0
        and value >= (minimum or 0)
end

local function same(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not same(value, right[key]) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function hasExactKeys(value, keys)
    if type(value) ~= "table" then
        return false
    end
    for _, key in ipairs(keys) do
        if value[key] == nil then
            return false
        end
    end
    return true
end

local function validPendingRemainder(pending)
    if pending == nil then
        return true
    end
    return type(pending) == "table"
        and type(pending.operation) == "string"
        and OPERATIONS[pending.operation] == true
        and (pending.originalOperation == nil
            or OPERATIONS[pending.originalOperation] == true)
        and type(pending.planIds or {}) == "table"
        and pending.nextPending == nil
end

local function validPendingBatch(jobId, pending, lastConfirmed, batchCount)
    if pending == nil then
        return true
    end
    return type(pending) == "table"
        and type(pending.id) == "string"
        and pending.id:sub(1, #jobId + 1) == jobId .. ":"
        and type(pending.operation) == "string"
        and OPERATIONS[pending.operation] == true
        and isInteger(pending.sequence, 1)
        and pending.sequence == lastConfirmed + 1
        and pending.sequence <= batchCount
        and type(pending.planIds or {}) == "table"
        and (pending.originalOperation == nil
            or OPERATIONS[pending.originalOperation] == true)
        and validPendingRemainder(pending.nextPending)
end

local function validStringList(values, minimum)
    if type(values) ~= "table" or #values < (minimum or 0) then
        return false
    end
    local seen = {}
    for index, value in ipairs(values) do
        if type(value) ~= "string" or value == "" or seen[value] then
            return false
        end
        seen[value] = true
        if values[index] ~= value then
            return false
        end
    end
    for key in pairs(values) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #values then
            return false
        end
    end
    return true
end

local function validRecoveryArtifacts(jobId, progress, lastConfirmed, batchCount)
    local adoption = progress.pendingAdoption
    if adoption ~= nil
        and (type(adoption) ~= "table"
            or type(adoption.batchId) ~= "string"
            or adoption.batchId:sub(1, #jobId + 1) ~= jobId .. ":"
            or not isInteger(adoption.count, 1)
            or not validStringList(adoption.planIds, 1)
            or adoption.count ~= #adoption.planIds
            or adoption.sequence ~= lastConfirmed + 1
            or adoption.sequence > batchCount)
    then
        return false
    end
    local raw = progress.pendingRawCreation
    if raw ~= nil
        and (not validPendingRemainder(raw)
            or not validStringList(raw.planIds, 1))
    then
        return false
    end
    local group = progress.pendingGroupArtifact
    if group ~= nil
        and (type(group) ~= "table"
            or type(group.groupId) ~= "string"
            or group.groupId == ""
            or type(group.groupFingerprint) ~= "string"
            or group.groupFingerprint == ""
            or not isInteger(group.sequence, 1)
            or group.sequence > batchCount)
    then
        return false
    end
    return true
end

local function countValues(values)
    local total = 0
    for _, value in pairs(values or {}) do
        if not isInteger(value, 0) then
            return nil
        end
        total += value
    end
    return total
end

local function executionHash(execution)
    return Canonical.checksum({
        batchCount = execution.batchCount,
        chunks = execution.chunks,
        operationCounts = execution.operationCounts,
        phaseCounts = execution.phaseCounts,
        planHash = execution.planHash,
        strategy = execution.strategy,
        totalWeight = execution.totalWeight,
    })
end

local function mapNeverDecreases(previous, newer)
    for key, previousValue in pairs(previous or {}) do
        local newerValue = newer and newer[key] or 0
        if type(previousValue) ~= "number"
            or type(newerValue) ~= "number"
            or newerValue < previousValue
        then
            return false
        end
    end
    return true
end

local function mapNeverIncreases(previous, newer)
    for key, previousValue in pairs(previous or {}) do
        local newerValue = newer and newer[key]
        if type(previousValue) ~= "number"
            or type(newerValue) ~= "number"
            or newerValue > previousValue
        then
            return false
        end
    end
    return true
end

local function coherentSuccessor(previous, newer)
    if newer.generation ~= previous.generation + 1 then
        return false
    end
    local previousProgress = previous.progress
    local newerProgress = newer.progress
    if newerProgress.lastConfirmedSequence < previousProgress.lastConfirmedSequence
        or newerProgress.confirmedWeight < previousProgress.confirmedWeight
        or not mapNeverDecreases(
            previousProgress.phaseConfirmed,
            newerProgress.phaseConfirmed
        )
        or not mapNeverIncreases(
            previousProgress.remainingOperationCounts,
            newerProgress.remainingOperationCounts
        )
        or (previousProgress.terminalStarted == true
            and newerProgress.terminalStarted ~= true)
    then
        return false
    end

    local previousCleanup = previous.cleanup
    local newerCleanup = newer.cleanup
    if previousCleanup ~= nil
        and (newerCleanup == nil
            or (newerCleanup.lastConfirmedSequence or 0)
                < (previousCleanup.lastConfirmedSequence or 0)
            or (newerCleanup.removedCount or 0)
                < (previousCleanup.removedCount or 0))
    then
        return false
    end

    local previousState = previous.job.state
    local newerState = newer.job.state
    if previousState == "rollback" or previousState == "rollback_incomplete" then
        return newerState == "rollback" or newerState == "rollback_incomplete"
    elseif previousState == "completed" then
        return newerState == "completed" or newerState == "cleanup_pending"
    elseif previousState == "cleanup_pending" then
        return newerState == "cleanup_pending"
    end
    return true
end

function CheckpointStore.new(options)
    options = options or {}
    local self = setmetatable({
        adapterId = options.adapterId or "town",
        available = true,
        checksum = options.checksum or Canonical.checksum,
        checksumAlgorithm = options.checksumAlgorithm or Canonical.algorithm,
        decode = options.decode,
        deleteFile = options.deleteFile,
        encode = options.encode,
        isFile = options.isFile,
        listFiles = options.listFiles,
        makeFolder = options.makeFolder,
        now = options.now or os.time,
        normalizePayload = options.normalizePayload ~= false,
        planVersion = options.planVersion or 1,
        publicError = nil,
        readFile = options.readFile,
        schemaVersion = options.schemaVersion or 1,
        userId = options.userId,
        verifiedJobs = {},
        writeFile = options.writeFile,
    }, CheckpointStore)

    if type(options.root) ~= "string"
        or options.root == ""
        or hasUnsafePathSegments(options.root)
        or options.userId == nil
    then
        self.available = false
    end
    for _, name in ipairs(REQUIRED_FUNCTIONS) do
        if type(self[name]) ~= "function" then
            self.available = false
        end
    end
    if not self.available then
        self.publicError = PUBLIC_ERROR
        self.root = type(options.root) == "string" and options.root or ""
        return self
    end

    self.root = options.root:gsub("[/\\]+$", "") .. "/" .. tostring(options.userId)
    self.jobsRoot = self.root .. "/jobs"
    self.stateA = self.root .. "/state.a.json"
    self.stateB = self.root .. "/state.b.json"
    self:_ensureFolder(self.root)
    self:_ensureFolder(self.jobsRoot)
    return self
end

function CheckpointStore:_ensureFolder(path)
    local current = ""
    for component in path:gmatch("[^/\\]+") do
        current = current == "" and component or (current .. "/" .. component)
        pcall(self.makeFolder, current)
    end
end

function CheckpointStore:_envelope(payload)
    return {
        checksum = self.checksum(payload),
        checksumAlgorithm = self.checksumAlgorithm,
        format = "uh-town-checkpoint",
        payload = payload,
    }
end

function CheckpointStore:_decodeEnvelope(source)
    local decoded = self.decode(source)
    assert(type(decoded) == "table", "Checkpoint envelope must be an object")
    assert(decoded.format == "uh-town-checkpoint", "Unknown checkpoint format")
    assert(decoded.checksumAlgorithm == self.checksumAlgorithm, "Unknown checkpoint checksum algorithm")
    assert(type(decoded.payload) == "table", "Checkpoint payload is missing")
    assert(self.checksum(decoded.payload) == decoded.checksum, "Checkpoint checksum mismatch")
    return decoded
end

function CheckpointStore:_readEnvelope(path)
    if not self.isFile(path) then
        return "missing"
    end
    local succeeded, result = pcall(function()
        return self:_decodeEnvelope(self.readFile(path))
    end)
    if not succeeded then
        return "corrupt", result
    end
    return "valid", result
end

function CheckpointStore:_writeVerified(path, payload)
    assert(self.available, PUBLIC_ERROR)
    local parent = dirname(path)
    if parent then
        self:_ensureFolder(parent)
    end
    local normalizedPayload = self.normalizePayload
            and self.decode(self.encode(payload))
        or payload
    local envelope = self:_envelope(normalizedPayload)
    local encoded = self.encode(envelope)
    self.writeFile(path, encoded)
    local decoded = self:_decodeEnvelope(self.readFile(path))
    assert(same(decoded.payload, normalizedPayload), "Checkpoint readback payload mismatch")
    return {
        byteLength = #encoded,
        bytes = #encoded,
        checksum = decoded.checksum,
    }
end

function CheckpointStore:_manifestPath(jobId)
    return self:_jobRoot(jobId) .. "/manifest.json"
end

function CheckpointStore:_writeState(path, state)
    local hydrated = state
    local manifest = hydrated.manifest
    if not manifest then
        local manifestPath = self:_manifestPath(hydrated.job.id)
        local metadata = self:_writeVerified(manifestPath, {
            executionChunks = hydrated.execution.chunks,
            executionHash = hydrated.execution.hash,
            jobId = hydrated.job.id,
            kind = "manifest",
            planChunks = hydrated.plan.chunks,
            planFingerprint = hydrated.plan.fingerprint,
        })
        metadata.file = self:_relative(manifestPath)
        metadata.jobId = hydrated.job.id
        metadata.kind = "manifest"
        manifest = metadata
        hydrated = copyMutableState(hydrated)
        hydrated.manifest = metadata
    end
    local compact = copyMutableState(hydrated)
    compact.plan = withoutKey(hydrated.plan, "chunks")
    compact.execution = withoutKey(hydrated.execution, "chunks")
    self:_writeVerified(path, compact)
    return hydrated
end

function CheckpointStore:_hydrateState(state)
    if state.plan and state.plan.chunks
        and state.execution and state.execution.chunks
    then
        return state
    end
    local manifest = state.manifest
    assert(type(manifest) == "table", "Checkpoint manifest is missing")
    assert(manifest.jobId == state.job.id and manifest.kind == "manifest", "Checkpoint manifest binding mismatch")
    local relative = ("jobs/%s/manifest.json"):format(state.job.id)
    assert(normalize(manifest.file) == relative, "Checkpoint manifest path mismatch")
    local path = self.root .. "/" .. relative
    assert(self.isFile(path), "Checkpoint manifest is unavailable")
    local source = self.readFile(path)
    assert(#source == manifest.byteLength, "Checkpoint manifest byte length mismatch")
    local status, envelope = self:_readEnvelope(path)
    assert(status == "valid" and envelope.checksum == manifest.checksum, "Checkpoint manifest checksum mismatch")
    local payload = envelope.payload
    assert(
        payload.kind == "manifest"
            and payload.jobId == state.job.id
            and payload.planFingerprint == state.plan.fingerprint
            and payload.executionHash == state.execution.hash,
        "Checkpoint manifest content mismatch"
    )
    local hydrated = copy(state)
    hydrated.plan.chunks = payload.planChunks
    hydrated.execution.chunks = payload.executionChunks
    return hydrated
end

function CheckpointStore:_readState(path)
    local status, envelope = self:_readEnvelope(path)
    if status ~= "valid" then
        return status, envelope
    end
    local succeeded, hydrated = pcall(self._hydrateState, self, envelope.payload)
    if not succeeded then
        return "corrupt", hydrated
    end
    envelope.payload = hydrated
    return "valid", envelope
end

function CheckpointStore:_jobRoot(jobId)
    assert(isSafeJobId(jobId), "Checkpoint job id is invalid")
    return self.jobsRoot .. "/" .. jobId
end

function CheckpointStore:_relative(path)
    assert(not hasUnsafePathSegments(path), "Checkpoint path contains unsafe segments")
    local root = normalize(self.root)
    local normalized = normalize(path)
    assert(normalized:sub(1, #root + 1) == root .. "/", "Checkpoint path escapes the private root")
    return normalized:sub(#root + 2)
end

function CheckpointStore:_filesUnder(root)
    local files = {}
    local visited = {}
    local privateRoot = normalize(self.root)
    local function visit(path, depth)
        if hasUnsafePathSegments(path) then
            return
        end
        local normalized = normalize(path)
        if visited[normalized] or depth > 8 then
            return
        end
        assert(
            normalized == privateRoot or normalized:sub(1, #privateRoot + 1) == privateRoot .. "/",
            "Checkpoint listing escaped the private root"
        )
        visited[normalized] = true
        local succeeded, entries = pcall(self.listFiles, path)
        if not succeeded or type(entries) ~= "table" then
            return
        end
        for _, entry in ipairs(entries) do
            local child = not hasUnsafePathSegments(entry) and normalize(entry) or nil
            if child and child:sub(1, #privateRoot + 1) == privateRoot .. "/" then
                if self.isFile(entry) then
                    files[child] = entry
                else
                    visit(entry, depth + 1)
                end
            end
        end
    end
    visit(root, 0)
    local result = {}
    for _, original in pairs(files) do
        table.insert(result, original)
    end
    table.sort(result)
    return result
end

function CheckpointStore:_validState(state, trustCachedChunks)
    if type(state) ~= "table" then
        return false, "corrupt"
    end
    if state.schemaVersion ~= self.schemaVersion
        or state.planVersion ~= self.planVersion
        or state.adapterId ~= self.adapterId
    then
        return false, "version"
    end
    local context = state.context
    if not isInteger(state.generation, 1)
        or type(context) ~= "table"
        or context.gameId == nil
        or context.placeId == nil
        or context.localUserId == nil
        or not hasExactKeys(context.destination, DESTINATION_CONTEXT_KEYS)
        or not hasExactKeys(context.source, SOURCE_CONTEXT_KEYS)
        or type(state.job) ~= "table"
        or not isSafeJobId(state.job.id)
        or STATE_AUTHORIZATION[state.job.state] == nil
        or type(state.job.lastUpdatedAt) ~= "number"
        or type(state.authorization) ~= "table"
        or state.authorization.state ~= STATE_AUTHORIZATION[state.job.state]
        or type(state.plan) ~= "table"
        or not isInteger(state.plan.supported, 1)
        or not isInteger(state.plan.chunkCount, 1)
        or type(state.plan.chunks) ~= "table"
        or #state.plan.chunks ~= state.plan.chunkCount
        or type(state.plan.fingerprint) ~= "string"
        or not isInteger(state.plan.totalWeight, 1)
        or type(state.execution) ~= "table"
        or not isInteger(state.execution.batchCount, 1)
        or not isInteger(state.execution.chunkCount, 1)
        or type(state.execution.chunks) ~= "table"
        or #state.execution.chunks ~= state.execution.chunkCount
        or type(state.execution.hash) ~= "string"
        or type(state.execution.operationCounts) ~= "table"
        or type(state.execution.phaseCounts) ~= "table"
        or state.execution.planHash ~= state.plan.fingerprint
        or state.execution.totalWeight ~= state.plan.totalWeight
        or countValues(state.execution.operationCounts) ~= state.execution.batchCount
        or countValues(state.execution.phaseCounts) ~= state.execution.batchCount
        or type(state.progress) ~= "table"
        or not isInteger(state.progress.lastConfirmedSequence, 0)
        or state.progress.lastConfirmedSequence > state.execution.batchCount
        or type(state.progress.confirmedWeight) ~= "number"
        or state.progress.confirmedWeight < 0
        or state.progress.confirmedWeight > state.plan.totalWeight
        or not validPendingBatch(
            state.job.id,
            state.progress.pendingBatch,
            state.progress.lastConfirmedSequence,
            state.execution.batchCount
        )
        or not validRecoveryArtifacts(
            state.job.id,
            state.progress,
            state.progress.lastConfirmedSequence,
            state.execution.batchCount
        )
    then
        return false, "corrupt"
    end
    local immutableKey = state.job.id
        .. "|"
        .. state.plan.fingerprint
        .. "|"
        .. state.execution.hash
    if not (trustCachedChunks and self.verifiedJobs[state.job.id] == immutableKey)
        and state.execution.hash ~= executionHash(state.execution)
    then
        return false, "corrupt"
    end
    local localCleanupOnly = state.job.state == "completed"
        or state.job.state == "cleanup_pending"
    if state.job.state == "awaiting_confirmation"
        and (state.progress.lastConfirmedSequence ~= 0
            or state.progress.confirmedWeight ~= 0
            or state.progress.pendingBatch ~= nil)
    then
        return false, "corrupt"
    end
    if state.progress.terminalStarted == true
        and (state.job.state == "paused"
            or state.job.state == "rollback"
            or state.job.state == "rollback_incomplete"
            or state.job.state == "cancel_requested")
    then
        return false, "corrupt"
    end
    for phase, confirmed in pairs(state.progress.phaseConfirmed or {}) do
        if not isInteger(confirmed, 0)
            or confirmed > (state.execution.phaseCounts[phase] or 0)
        then
            return false, "corrupt"
        end
    end
    for operation, remaining in pairs(state.progress.remainingOperationCounts or {}) do
        if not isInteger(remaining, 0)
            or remaining > (state.execution.operationCounts[operation] or 0)
        then
            return false, "corrupt"
        end
    end
    if localCleanupOnly
        and (state.progress.lastConfirmedSequence ~= state.execution.batchCount
            or state.progress.pendingBatch ~= nil
            or state.progress.confirmedWeight ~= state.plan.totalWeight)
    then
        return false, "corrupt"
    end
    local cleanup = state.cleanup
    if cleanup ~= nil then
        if type(cleanup) ~= "table"
            or not isInteger(cleanup.lastConfirmedSequence or 0, 0)
            or not isInteger(cleanup.removedCount or 0, 0)
            or cleanup.removedCount > state.plan.supported + (state.plan.groups or 0)
            or not isInteger(
                cleanup.cursorSequence or state.progress.lastConfirmedSequence,
                0
            )
            or (cleanup.cursorSequence or state.progress.lastConfirmedSequence)
                > state.progress.lastConfirmedSequence
        then
            return false, "corrupt"
        end
        local pendingCleanup = cleanup.pendingBatch
        if pendingCleanup ~= nil
            and (type(pendingCleanup) ~= "table"
                or pendingCleanup.operation ~= "Remove"
                or type(pendingCleanup.id) ~= "string"
                or pendingCleanup.id:sub(1, #state.job.id + 1) ~= state.job.id .. ":")
        then
            return false, "corrupt"
        end
    end
    if not localCleanupOnly
        and not (trustCachedChunks and self.verifiedJobs[state.job.id] == immutableKey)
    then
        if not self:verifyPlan(state.job.id, state.plan.chunks, state.plan.supported)
            or not self:verifyJobChunks(
                state.job.id,
                "execution",
                state.execution.chunks,
                state.execution.batchCount
            )
        then
            return false, "corrupt"
        end
        self.verifiedJobs[state.job.id] = immutableKey
    end
    return true
end

function CheckpointStore:_stateSlots(trustCachedChunks)
    local stateA, envelopeA = self:_readState(self.stateA)
    local stateB, envelopeB = self:_readState(self.stateB)
    local candidates = {}
    local validA, invalidReasonA
    if stateA == "valid" then
        validA, invalidReasonA = self:_validState(envelopeA.payload, trustCachedChunks)
    end
    if stateA == "valid" and validA then
        table.insert(candidates, {
            envelope = envelopeA,
            path = self.stateA,
        })
    elseif stateA == "valid" then
        stateA = invalidReasonA
    end
    local validB, invalidReasonB
    if stateB == "valid" then
        validB, invalidReasonB = self:_validState(envelopeB.payload, trustCachedChunks)
    end
    if stateB == "valid" and validB then
        table.insert(candidates, {
            envelope = envelopeB,
            path = self.stateB,
        })
    elseif stateB == "valid" then
        stateB = invalidReasonB
    end
    table.sort(candidates, function(left, right)
        return left.envelope.payload.generation > right.envelope.payload.generation
    end)
    if #candidates > 1
        and candidates[1].envelope.payload.job.id ~= candidates[2].envelope.payload.job.id
    then
        return nil, "corrupt", "corrupt", {}
    end
    if #candidates > 1 then
        local newer = candidates[1].envelope.payload
        local previous = candidates[2].envelope.payload
        if newer.generation == previous.generation then
            if not same(newer, previous) then
                return nil, "corrupt", "corrupt", {}
            end
        elseif not coherentSuccessor(previous, newer) then
            table.remove(candidates, 1)
        end
    end
    return candidates[1], stateA, stateB, candidates
end

function CheckpointStore:writeJobChunk(jobId, kind, index, chunk)
    assert(self.available, PUBLIC_ERROR)
    assert(isSafeJobId(jobId), "Plan chunks require a safe job id")
    assert(type(kind) == "string" and kind:match("^[a-z]+$"), "Job chunk kind is invalid")
    assert(isInteger(index, 1), "Plan chunk index must be positive")
    assert(type(chunk) == "table", "Plan chunk must be an object")
    assert(chunk.jobId == jobId, "Plan chunk job id mismatch")
    assert(chunk.kind == kind, "Job chunk kind mismatch")
    assert(chunk.index == index, "Plan chunk index mismatch")
    assert(type(chunk.records) == "table" and #chunk.records > 0, "Plan chunks cannot be empty")
    local path = ("%s/%s-%05d.json"):format(self:_jobRoot(jobId), kind, index)
    local metadata = self:_writeVerified(path, chunk)
    metadata.file = self:_relative(path)
    metadata.index = index
    metadata.jobId = jobId
    metadata.kind = kind
    metadata.recordCount = #chunk.records
    return metadata
end

function CheckpointStore:writePlanChunk(jobId, index, chunk)
    local payload = copy(chunk)
    payload.kind = "plan"
    return self:writeJobChunk(jobId, "plan", index, payload)
end

function CheckpointStore:stagePlan(job, chunkIterator)
    assert(type(job) == "table" and type(job.id) == "string", "Plan staging requires a job")
    local chunks = {}
    local index = 0
    if type(chunkIterator) == "function" then
        while true do
            local chunk = chunkIterator()
            if chunk == nil then
                break
            end
            index += 1
            table.insert(chunks, self:writePlanChunk(job.id, index, {
                index = index,
                jobId = job.id,
                records = chunk.records or chunk,
            }))
        end
    else
        for _, chunk in ipairs(chunkIterator or {}) do
            index += 1
            table.insert(chunks, self:writePlanChunk(job.id, index, {
                index = index,
                jobId = job.id,
                records = chunk.records or chunk,
            }))
        end
    end
    return chunks
end

function CheckpointStore:_chunkPath(jobId, kind, metadata, expectedIndex)
    if not isSafeJobId(jobId)
        or type(kind) ~= "string"
        or kind:match("^[a-z]+$") == nil
        or type(metadata) ~= "table"
        or metadata.jobId ~= jobId
        or metadata.kind ~= kind
        or metadata.index ~= expectedIndex
        or not isInteger(metadata.recordCount, 1)
        or not isInteger(metadata.byteLength, 1)
        or type(metadata.checksum) ~= "string"
    then
        return nil
    end
    local expectedRelative = ("jobs/%s/%s-%05d.json"):format(jobId, kind, expectedIndex)
    if normalize(metadata.file) ~= expectedRelative
        or metadata.file:find("..", 1, true)
        or metadata.file:sub(1, 1) == "/"
    then
        return nil
    end
    return self.root .. "/" .. expectedRelative
end

function CheckpointStore:verifyJobChunks(jobId, kind, chunks, expectedRecordCount)
    if not self.available then
        return false
    end
    if not isSafeJobId(jobId)
        or type(chunks) ~= "table"
        or #chunks == 0
        or not isInteger(expectedRecordCount, 1)
    then
        return false
    end
    local records = 0
    for index, metadata in ipairs(chunks) do
        local path = self:_chunkPath(jobId, kind, metadata, index)
        if not path or not self.isFile(path) then
            return false
        end
        local source = self.readFile(path)
        if #source ~= metadata.byteLength then
            return false
        end
        local status, envelope = self:_readEnvelope(path)
        local payload = status == "valid" and envelope.payload or nil
        if status ~= "valid"
            or envelope.checksum ~= metadata.checksum
            or type(payload) ~= "table"
            or payload.jobId ~= jobId
            or payload.kind ~= kind
            or payload.index ~= index
            or type(payload.records) ~= "table"
            or #payload.records ~= metadata.recordCount
            or #payload.records == 0
        then
            return false
        end
        records += metadata.recordCount
    end
    return records == expectedRecordCount
end

function CheckpointStore:verifyPlan(jobId, chunks, expectedRecordCount)
    return self:verifyJobChunks(jobId, "plan", chunks, expectedRecordCount)
end

function CheckpointStore:readJobChunk(jobId, kind, metadata)
    assert(self.available, PUBLIC_ERROR)
    local path = self:_chunkPath(jobId, kind, metadata, metadata and metadata.index)
    assert(path, "Plan chunk metadata is invalid")
    assert(#self.readFile(path) == metadata.byteLength, "Plan chunk byte length mismatch")
    local status, envelope = self:_readEnvelope(path)
    assert(status == "valid", "Plan chunk is unavailable")
    assert(envelope.checksum == metadata.checksum, "Plan chunk checksum mismatch")
    assert(
        envelope.payload.jobId == jobId
            and envelope.payload.kind == kind
            and envelope.payload.index == metadata.index
            and #envelope.payload.records == metadata.recordCount,
        "Plan chunk binding mismatch"
    )
    return copy(envelope.payload)
end

function CheckpointStore:readPlanChunk(jobId, metadata)
    return self:readJobChunk(jobId, "plan", metadata)
end

function CheckpointStore:beginStaging(jobId, liveContext)
    if not self.available then
        return false, PUBLIC_ERROR
    end
    if not isSafeJobId(jobId) then
        return false, "Town copy job identity is invalid"
    end
    local loaded = self:load(liveContext)
    if loaded.status == "ready" or loaded.status == "incompatible" then
        return false, ACTIVE_JOB_MESSAGE
    end
    if loaded.status ~= "empty" and loaded.status ~= "quarantined" then
        return false, loaded.message or "Town recovery state is unavailable"
    end
    local jobRoot = self:_jobRoot(jobId)
    if #self:_filesUnder(jobRoot) > 0 then
        self:_quarantinePaths(self:_filesUnder(jobRoot), "orphan")
    end
    local succeeded = pcall(function()
        self:_writeVerified(jobRoot .. "/staging.json", {
            context = copy(liveContext or {}),
            createdAt = self.now(),
            jobId = jobId,
        })
    end)
    if not succeeded then
        return false, PUBLIC_ERROR
    end
    return true
end

function CheckpointStore:abortStaging(jobId)
    if not self.available or not isSafeJobId(jobId) then
        return false, PUBLIC_ERROR
    end
    local current = self:_stateSlots()
    if current and current.envelope.payload.job.id == jobId then
        return false, "Active Town recovery cannot be removed as staging"
    end
    local jobRoot = self:_jobRoot(jobId)
    for _, path in ipairs(self:_filesUnder(jobRoot)) do
        self.deleteFile(path)
    end
    return #self:_filesUnder(jobRoot) == 0
end

function CheckpointStore:commitInitial(state)
    if not self.available then
        return false, PUBLIC_ERROR
    end
    local initial = copy(state)
    initial.generation = 1
    initial.job.lastUpdatedAt = initial.job.lastUpdatedAt or self.now()
    local succeeded, result = pcall(function()
        assert(isSafeJobId(initial.job and initial.job.id), "Town copy job identity is invalid")
        local existing, stateA, stateB = self:_stateSlots()
        assert(not existing and stateA == "missing" and stateB == "missing", ACTIVE_JOB_MESSAGE)
        local stagingPath = self:_jobRoot(initial.job.id) .. "/staging.json"
        assert(self.isFile(stagingPath), "Town copy staging marker is unavailable")
        assert(self:_validState(initial), "Initial Town checkpoint is invalid")
        return self:_writeState(self.stateA, initial)
    end)
    if not succeeded then
        local message = tostring(result)
        if message:find(ACTIVE_JOB_MESSAGE, 1, true) then
            return false, ACTIVE_JOB_MESSAGE
        end
        return false, PUBLIC_ERROR
    end
    local stagingPath = self:_jobRoot(initial.job.id) .. "/staging.json"
    if self.isFile(stagingPath) then
        self.deleteFile(stagingPath)
    end
    local hydrated = result
    self.currentState = copy(hydrated)
    self.currentPath = self.stateA
    return true, copy(hydrated)
end

function CheckpointStore:advance(mutator)
    assert(self.available, PUBLIC_ERROR)
    local current
    if self.currentState and self.currentPath then
        current = {
            envelope = {
                payload = self.currentState,
            },
            path = self.currentPath,
        }
    else
        current = self:_stateSlots(true)
    end
    assert(current, "No valid Town checkpoint is available")
    local nextState = copyMutableState(current.envelope.payload)
    mutator(nextState)
    assert(
        nextState.job
            and nextState.job.id == current.envelope.payload.job.id,
        "Town checkpoint identity cannot change"
    )
    nextState.generation = current.envelope.payload.generation + 1
    nextState.job.lastUpdatedAt = self.now()
    local valid = self:_validState(nextState, true)
    assert(valid, "Town checkpoint transition is semantically invalid")
    local target = current.path == self.stateA and self.stateB or self.stateA
    nextState = self:_writeState(target, nextState)
    self.currentState = nextState
    self.currentPath = target
    return copyMutableState(nextState)
end

function CheckpointStore:_compatible(saved, live)
    if type(saved) ~= "table"
        or type(live) ~= "table"
        or saved.gameId == nil
        or saved.placeId == nil
        or saved.localUserId == nil
        or live.gameId == nil
        or live.placeId == nil
        or live.localUserId == nil
        or not hasExactKeys(saved.destination, DESTINATION_CONTEXT_KEYS)
        or not hasExactKeys(live.destination, DESTINATION_CONTEXT_KEYS)
        or not hasExactKeys(saved.source, SOURCE_CONTEXT_KEYS)
        or not hasExactKeys(live.source, SOURCE_CONTEXT_KEYS)
    then
        return false
    end
    if saved.gameId ~= live.gameId
        or saved.placeId ~= live.placeId
        or saved.localUserId ~= live.localUserId
    then
        return false
    end

    local savedDestination = saved.destination
    local liveDestination = live.destination
    for _, key in ipairs(DESTINATION_CONTEXT_KEYS) do
        if not same(savedDestination[key], liveDestination[key]) then
            return false
        end
    end

    local savedSource = saved.source
    local liveSource = live.source
    for _, key in ipairs(SOURCE_CONTEXT_KEYS) do
        if not same(savedSource[key], liveSource[key]) then
            return false
        end
    end
    return true
end

function CheckpointStore:load(liveContext)
    if not self.available then
        return {
            message = PUBLIC_ERROR,
            status = "unavailable",
        }
    end

    local current, stateA, stateB = self:_stateSlots()
    if not current then
        if stateA == "version" or stateB == "version" then
            return self:quarantine("version")
        elseif stateA == "corrupt" or stateB == "corrupt" then
            return self:quarantine("corrupt")
        end
        if #self:_filesUnder(self.jobsRoot) > 0 then
            return self:quarantine("orphan")
        end
        return {
            status = "empty",
        }
    end

    local state = current.envelope.payload
    self.currentState = copy(state)
    self.currentPath = current.path
    if type(state.job) ~= "table"
        or type(state.job.lastUpdatedAt) ~= "number"
        or self.now() - state.job.lastUpdatedAt > ACTIVE_RETENTION_SECONDS
    then
        return self:quarantine("stale")
    end
    if liveContext and not self:_compatible(state.context or {}, liveContext) then
        return {
            message = "Checkpoint does not match the current Town source or destination",
            state = copy(state),
            status = "incompatible",
        }
    end
    return {
        state = copy(state),
        status = "ready",
    }
end

function CheckpointStore:_quarantinePaths(paths, reason)
    local safeReason = tostring(reason):gsub("[^%w_%-]", "_"):sub(1, 48)
    local quarantineRoot = ("%s/quarantine/%d-%s"):format(self.root, self.now(), safeReason)
    self:_ensureFolder(quarantineRoot)
    local index = 0
    for _, path in ipairs(paths) do
        if not normalize(path):find(normalize(self.root) .. "/quarantine/", 1, true)
            and self.isFile(path)
        then
            index += 1
            local source = self.readFile(path)
            local relative = self:_relative(path):gsub("[^%w_.%-]", "_")
            local destination = ("%s/%04d-%s"):format(quarantineRoot, index, relative)
            self.writeFile(destination, source)
            assert(self.readFile(destination) == source, "Checkpoint quarantine verification failed")
            self.deleteFile(path)
        end
    end
end

function CheckpointStore:quarantine(reason)
    if not self.available then
        return {
            message = PUBLIC_ERROR,
            reason = reason,
            status = "unavailable",
        }
    end
    self:_quarantinePaths(self:_filesUnder(self.root), reason)
    return {
        message = QUARANTINE_MESSAGE,
        reason = reason,
        status = "quarantined",
    }
end

function CheckpointStore:deleteJob(expectedJobId)
    if not self.available then
        return false, PUBLIC_ERROR
    end
    local current = self:_stateSlots()
    if not current then
        return false, "No valid Town checkpoint is available"
    end
    local state = current.envelope.payload
    local jobId = state.job.id
    if expectedJobId ~= nil and expectedJobId ~= jobId then
        return false, "Town checkpoint identity changed"
    end
    local paths = {}
    local statePaths = {}
    for _, statePath in ipairs({ self.stateA, self.stateB }) do
        local status, envelope = self:_readEnvelope(statePath)
        if status == "valid" then
            if not envelope.payload.job or envelope.payload.job.id ~= jobId then
                return false, "Checkpoint cleanup is blocked by unrelated recovery data"
            end
            table.insert(statePaths, statePath)
        elseif status == "corrupt" then
            return false, "Checkpoint cleanup is blocked by unreadable recovery data"
        end
    end
    for _, path in ipairs(self:_filesUnder(self:_jobRoot(jobId))) do
        table.insert(paths, path)
    end
    for _, statePath in ipairs(statePaths) do
        table.insert(paths, statePath)
    end
    for _, path in ipairs(paths) do
        if self.isFile(path) then
            self.deleteFile(path)
        end
    end
    for _, path in ipairs(paths) do
        if self.isFile(path) then
            return false, "Checkpoint cleanup is incomplete"
        end
    end
    self.verifiedJobs[jobId] = nil
    self.currentState = nil
    self.currentPath = nil
    return true
end

function CheckpointStore:prune(now)
    now = now or self.now()
    for _, path in ipairs(self:_filesUnder(self.root)) do
        local quarantinedAt = path:match("[/\\]quarantine[/\\](%d+)%-")
        if quarantinedAt
            and now - tonumber(quarantinedAt) > QUARANTINE_RETENTION_SECONDS
            and self.isFile(path)
        then
            self.deleteFile(path)
        end
    end
    local loaded = self:load()
    if loaded.status == "ready" then
        local activePrefix = normalize(self:_jobRoot(loaded.state.job.id)) .. "/"
        local orphans = {}
        for _, path in ipairs(self:_filesUnder(self.jobsRoot)) do
            if normalize(path):sub(1, #activePrefix) ~= activePrefix then
                table.insert(orphans, path)
            end
        end
        if #orphans > 0 then
            self:_quarantinePaths(orphans, "orphan")
        end
    end
    if loaded.status == "ready"
        and now - loaded.state.job.lastUpdatedAt > ACTIVE_RETENTION_SECONDS
    then
        return self:quarantine("stale")
    end
    return loaded
end

CheckpointStore.publicUnavailableError = PUBLIC_ERROR

return CheckpointStore
]],
        ["games/town/Composition.lua"] = [[local Composition = {
    dependencies = {
        checkpointStore = "games/town/CheckpointStore",
    },
}

local function unavailable(message)
    return false, message
end

function Composition.bind(context, dependencies)
    assert(type(context) == "table", "Town composition requires a context")
    assert(type(dependencies) == "table", "Town composition requires dependencies")
    local CheckpointStore = assert(
        dependencies.checkpointStore,
        "Town composition requires its checkpoint store"
    )
    local checkpoint = CheckpointStore.new({
        decode = context.decode,
        deleteFile = context.files.delete,
        encode = context.encode,
        isFile = context.files.isFile,
        listFiles = context.files.list,
        makeFolder = context.files.makeFolder,
        readFile = context.files.read,
        root = context.config("TownCopyCheckpointRoot", "universal-hub/private/town-copy"),
        userId = context.userId,
        writeFile = context.files.write,
    })
    if checkpoint.available then
        pcall(function()
            checkpoint:prune()
        end)
    end

    local function adapter()
        return context.getAdapter()
    end

    local function spawn(methodName, message, ...)
        local current = adapter()
        if not current or type(current[methodName]) ~= "function" then
            return unavailable(message)
        end
        local arguments = { ... }
        context.spawn(function()
            current[methodName](current, table.unpack(arguments))
        end)
        return true
    end

    local result = {
        adapter = {
            checkpoint = checkpoint,
        },
        inputCapture = {
            releaseMouseOnDisable = true,
        },
        overlay = {
            listPlotOwners = function()
                local current = adapter()
                if current and type(current.listPlotOwners) == "function" then
                    return current:listPlotOwners()
                end
                return {}
            end,
            copyPlot = function(ownerName, saveName)
                return spawn("copyPlot", "Plot copying is not ready", ownerName, saveName)
            end,
            cancelPlotCopy = function()
                return spawn("cancelCopy", "Plot copy cancellation is not ready")
            end,
            confirmPlotCopy = function()
                return spawn("confirmCopy", "Plot copy confirmation is not ready")
            end,
            discardPlotCopy = function()
                return spawn("discardCopy", "Plot copy discard is not ready")
            end,
            resumePlotCopy = function()
                return spawn("resumeCopy", "Plot copy resume is not ready")
            end,
            retryPlotCopyCleanup = function()
                return spawn("retryCopyCleanup", "Plot copy cleanup is not ready")
            end,
            cleanupPlotCopyCheckpoint = function()
                return spawn(
                    "cleanupCopyCheckpoint",
                    "Local copy recovery cleanup is not ready"
                )
            end,
            reportPlotCopyError = function(message)
                context.getStore():Patch({
                    plotCopy = {
                        active = false,
                        confirmedProgress = 0,
                        context = message,
                        error = message,
                        phase = "Copy blocked",
                        state = "error",
                    },
                })
            end,
        },
    }

    function result.afterAdapter(current)
        if type(current.inspectCopyRecovery) ~= "function" then
            return
        end
        local recovered = pcall(function()
            current:inspectCopyRecovery()
        end)
        if not recovered then
            context.getStore():Patch({
                plotCopy = {
                    active = false,
                    context = "Recovery inspection failed before any Town mutation",
                    error = "Persistent copy recovery could not be inspected",
                    phase = "Copy blocked",
                    state = "error",
                },
            })
        end
    end

    return result
end

return Composition
]],
        ["games/town/CopyEngine.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local CopyPlan = importDependency("games/town/CopyPlan", "./CopyPlan")

local CopyEngine = {}
CopyEngine.__index = CopyEngine

local FORWARD_RESUME_STATES = {
    copy_authorized = true,
    copying = true,
    paused = true,
    reconciling = true,
    resuming = true,
}
local TERMINAL_OPERATIONS = {
    Save = true,
    Wire = true,
}

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[key] = copy(child)
    end
    return result
end

local function totalWeight(batches)
    local total = 0
    for _, batch in ipairs(batches or {}) do
        total += batch.weight or 1
    end
    return total
end

local function appliedPrefix(batch, remainder)
    local remaining = {}
    for _, id in ipairs(remainder and remainder.planIds or {}) do
        remaining[id] = true
    end
    local applied = {}
    for _, id in ipairs(batch.planIds or {}) do
        if not remaining[id] then
            table.insert(applied, id)
        end
    end
    return applied
end

function CopyEngine.new(context)
    context = context or {}
    return setmetatable({
        afterAuthorization = context.afterAuthorization,
        afterCleanupConfirmation = context.afterCleanupConfirmation,
        afterPartialAdoption = context.afterPartialAdoption,
        afterReplacement = context.afterReplacement,
        afterRemote = context.afterRemote,
        applyBatch = context.applyBatch,
        beforeRemote = context.beforeRemote,
        cancelRequested = false,
        checkpoint = context.checkpoint,
        clock = context.clock or os.clock,
        captureError = context.captureError,
        generateGuid = context.generateGuid or function()
            return ("%d-%d"):format(os.time(), math.random(1, 1000000000))
        end,
        now = context.now or os.time,
        publish = context.publish or function() end,
        reconcileBatch = context.reconcileBatch,
        reconcileCleanup = context.reconcileCleanup,
        releaseBatchState = context.releaseBatchState,
        removeBatch = context.removeBatch,
        nextCleanupBatch = context.nextCleanupBatch or context.cleanupBatches,
        state = nil,
        executionCache = nil,
        stopped = false,
        validateContext = context.validateContext,
        waitForCooling = context.waitForCooling or function()
            return true
        end,
    }, CopyEngine)
end

function CopyEngine:_batchCount()
    local execution = self.state and self.state.execution or {}
    return execution.batchCount or #(execution.batches or {})
end

function CopyEngine:_batchAt(sequence)
    local execution = self.state and self.state.execution or {}
    if execution.batches then
        return execution.batches[sequence]
    end
    local offset = 0
    for _, metadata in ipairs(execution.chunks or {}) do
        local final = offset + metadata.recordCount
        if sequence <= final then
            if not self.executionCache or self.executionCache.index ~= metadata.index then
                self.executionCache = self.checkpoint:readJobChunk(
                    self.state.job.id,
                    "execution",
                    metadata
                )
            end
            return self.executionCache.records[sequence - offset]
        end
        offset = final
    end
    return nil
end

function CopyEngine:getBatch(sequence)
    local batch = self:_batchAt(sequence)
    return batch and copy(batch) or nil
end

function CopyEngine:_view(overrides)
    local state = self.state or {}
    local job = state.job or {}
    local progress = state.progress or {}
    local plan = state.plan or {}
    local jobState = overrides and overrides.state or job.state or "idle"
    local phase = overrides and overrides.phase or jobState
    local execution = state.execution or {}
    local phaseCompleted = progress.phaseConfirmed
            and progress.phaseConfirmed[phase]
        or 0
    local phaseTotal = execution.phaseCounts and execution.phaseCounts[phase] or 0
    local estimatedRemaining = 0
    local estimateKnown = false
    for operation, count in pairs(progress.remainingOperationCounts or {}) do
        local timing = progress.timing and progress.timing[operation]
        if timing and timing.ewma then
            estimatedRemaining += timing.ewma * count
            estimateKnown = true
        end
    end
    local view = {
        active = jobState == "copying"
            or jobState == "copy_authorized"
            or jobState == "reconciling"
            or jobState == "resuming"
            or jobState == "rollback",
        cancelAvailable = jobState == "awaiting_confirmation"
            or (jobState == "copying" and progress.terminalStarted ~= true),
        confirmedProgress = plan.totalWeight and plan.totalWeight > 0
                and (progress.confirmedWeight or 0) / plan.totalWeight
            or 0,
        context = overrides and overrides.context or nil,
        discardAvailable = jobState == "paused",
        error = overrides and overrides.error or nil,
        etaRange = estimateKnown and {
            maximum = math.ceil(estimatedRemaining * 1.25),
            minimum = math.max(0, math.floor(estimatedRemaining * 0.8)),
        } or nil,
        phase = phase,
        phaseCompleted = phaseCompleted,
        phaseTotal = phaseTotal,
        baseParts = plan.baseParts,
        markerBearing = plan.markerBearing,
        planBytes = plan.bytes,
        possiblyAppliedBatch = progress.pendingBatch and progress.pendingBatch.id or nil,
        localCleanupAvailable = jobState == "cleanup_pending",
        resumeAvailable = FORWARD_RESUME_STATES[jobState] == true,
        retryCleanupAvailable = jobState == "rollback"
            or jobState == "rollback_incomplete",
        startAvailable = jobState == "awaiting_confirmation",
        state = jobState,
        supported = plan.supported,
        totalDescendants = plan.totalDescendants,
        unsupported = plan.unsupported,
        work = copy(plan.work),
    }
    if overrides then
        for key, value in pairs(overrides) do
            view[key] = value
        end
    end
    return view
end

function CopyEngine:_publish(overrides)
    local view = self:_view(overrides)
    self.publish(view)
    return view
end

function CopyEngine:preflight(request)
    request = request or {}
    if not self.checkpoint or self.checkpoint.available ~= true then
        local message = self.checkpoint and self.checkpoint.publicError
            or "Persistent recovery is unavailable in this executor"
        self:_publish({
            error = message,
            phase = "Copy blocked",
            state = "error",
        })
        return false, message
    end
    assert(request.source, "Copy preflight requires a source")

    local jobId = self.generateGuid()
    local mayStage, stagingMessage = self.checkpoint:beginStaging(jobId, request.source.context)
    if not mayStage then
        local message = stagingMessage or "Persistent copy plan could not be secured"
        self:_publish({
            error = message,
            phase = "Copy blocked",
            state = "error",
        })
        return false, message
    end
    local chunkMetadata = {}
    local compiled, plan = pcall(CopyPlan.compile, request.source, {
        cloneRequestSize = request.cloneRequestSize,
        onChunk = function(chunk)
            table.insert(
                chunkMetadata,
                self.checkpoint:writePlanChunk(jobId, chunk.index, {
                    index = chunk.index,
                    jobId = jobId,
                    records = chunk.records,
                })
            )
        end,
        preferredBatchSize = request.preferredBatchSize,
    })
    if not compiled then
        pcall(function()
            self.checkpoint:abortStaging(jobId)
        end)
        local message = "Persistent copy plan could not be secured"
        self:_publish({
            error = message,
            phase = "Copy blocked",
            state = "error",
        })
        return false, message
    end
    local batches = copy(request.batches or {})
    local operationCounts = {}
    local phaseCounts = {}
    for _, batch in ipairs(batches) do
        local operation = batch.operation or "unknown"
        local phase = batch.phase or operation
        operationCounts[operation] = (operationCounts[operation] or 0) + 1
        phaseCounts[phase] = (phaseCounts[phase] or 0) + 1
    end
    local execution = {
        batchCount = #batches,
        batches = batches,
        operationCounts = operationCounts,
        phaseCounts = phaseCounts,
    }
    local weight = totalWeight(batches)
    if request.compileExecution then
        local executionCompiled, compiledExecution = pcall(
            request.compileExecution,
            jobId,
            copy(chunkMetadata),
            copy(plan)
        )
        if not executionCompiled
            or type(compiledExecution) ~= "table"
            or type(compiledExecution.chunks) ~= "table"
            or not compiledExecution.batchCount
        then
            self.checkpoint:abortStaging(jobId)
            local message = "Persistent execution plan could not be secured"
            self:_publish({
                error = message,
                phase = "Copy blocked",
                state = "error",
            })
            return false, message
        end
        execution = compiledExecution
        weight = compiledExecution.totalWeight or compiledExecution.batchCount
        plan.work.remoteCalls = compiledExecution.batchCount
        plan.work.operationCalls = copy(compiledExecution.operationCounts or {})
    end
    local planBytes = 0
    for _, metadata in ipairs(chunkMetadata) do
        planBytes += metadata.bytes or 0
    end
    local now = self.now()
    local persistedContext = copy(plan.context)
    persistedContext.source = persistedContext.source or {}
    persistedContext.source.fingerprint =
        persistedContext.source.fingerprint or plan.fingerprint
    local initial = {
        adapterId = "town",
        authorization = {
            state = "awaiting_confirmation",
        },
        context = persistedContext,
        execution = execution,
        generation = 1,
        job = {
            createdAt = now,
            id = jobId,
            lastUpdatedAt = now,
            originJobId = request.originJobId or "",
            state = "awaiting_confirmation",
        },
        plan = {
            baseParts = plan.baseParts,
            bytes = planBytes,
            chunkCount = #chunkMetadata,
            chunks = chunkMetadata,
            fingerprint = plan.fingerprint,
            groups = plan.groups,
            markerBearing = plan.markerBearing,
            supported = plan.supported,
            totalDescendants = plan.totalDescendants,
            totalWeight = weight,
            unsupported = plan.unsupported,
            work = plan.work,
        },
        planVersion = 1,
        progress = {
            confirmedWeight = 0,
            lastConfirmedSequence = 0,
            phaseConfirmed = {},
            remainingOperationCounts = copy(execution.operationCounts or {}),
            timing = {},
        },
        request = {
            copyWiring = request.copyWiring == true,
            saveName = request.saveName or "",
        },
        schemaVersion = 1,
    }

    local committed, stateOrMessage = self.checkpoint:commitInitial(initial)
    local verified = committed
        and self.checkpoint:verifyPlan(jobId, chunkMetadata, plan.supported)
    if not committed or not verified then
        if committed then
            self.checkpoint:deleteJob(jobId)
        else
            self.checkpoint:abortStaging(jobId)
        end
        local message = type(stateOrMessage) == "string"
                and stateOrMessage
            or "Persistent copy plan verification failed"
        self:_publish({
            error = message,
            phase = "Copy blocked",
            state = "error",
        })
        return false, message
    end
    self.state = stateOrMessage
    local confidence = request.estimateConfidence or "uncalibrated"
    local eta = request.etaRange
        or (confidence == "uncalibrated" and "ETA uncalibrated")
        or "ETA unavailable"
    return self:_publish({
        cancelAvailable = true,
        confidence = confidence,
        context = ("%d supported · %d unsupported · %d planned calls · %d plan bytes · %s"):format(
            plan.supported,
            plan.unsupported,
            plan.work.remoteCalls,
            planBytes,
            eta
        ),
        phase = "Plan secured",
        startAvailable = true,
        state = "awaiting_confirmation",
    })
end

function CopyEngine:_pause(phase)
    if not self.state or not self.checkpoint or not self.checkpoint.available then
        return false
    end
    self.state = self.checkpoint:advance(function(state)
        state.job.state = "paused"
    end)
    self:_publish({
        context = phase or "Confirmed work is safe to resume",
        phase = "Copy paused",
        state = "paused",
    })
    return true
end

function CopyEngine:_terminalPending()
    local progress = self.state and self.state.progress or {}
    local pending = progress.pendingBatch
    return progress.terminalStarted == true
        or (pending and TERMINAL_OPERATIONS[pending.operation] == true)
end

function CopyEngine:_durableError(message)
    local terminal = self:_terminalPending()
    self.state = self.checkpoint:advance(function(state)
        state.job.error = message
        state.job.state = terminal and "reconciling" or "paused"
    end)
    self:_publish({
        context = terminal
                and "Irreversible terminal work will be reconciled before any retry"
            or "Confirmed work and the pending intent remain safe for recovery",
        error = message,
        discardAvailable = false,
        phase = terminal and "Recovery required" or "Copy paused",
        state = terminal and "reconciling" or "paused",
    })
    return false, message
end

function CopyEngine:_confirmBatch(batch, sequence, duration)
    self.state = self.checkpoint:advance(function(state)
        state.job.state = "copying"
        state.progress.confirmedWeight += batch.confirmWeight or batch.weight or 1
        state.progress.lastConfirmedBatchId = batch.id
        state.progress.lastConfirmedSequence = sequence
        state.progress.pendingBatch = nil
        state.progress.pendingAdoption = nil
        state.progress.phaseConfirmed = state.progress.phaseConfirmed or {}
        local phase = batch.phase or batch.operation
        state.progress.phaseConfirmed[phase] =
            (state.progress.phaseConfirmed[phase] or 0) + 1
        state.progress.remainingOperationCounts =
            state.progress.remainingOperationCounts or {}
        local operation = batch.originalOperation or batch.operation
        state.progress.remainingOperationCounts[operation] = math.max(
            0,
            (state.progress.remainingOperationCounts[operation] or 1) - 1
        )
        if duration then
            operation = operation or "unknown"
            local timing = state.progress.timing[operation] or {
                count = 0,
                samples = {},
            }
            timing.count += 1
            timing.ewma = timing.ewma and (timing.ewma * 0.8 + duration * 0.2) or duration
            table.insert(timing.samples, duration)
            if #timing.samples > 20 then
                table.remove(timing.samples, 1)
            end
            local ordered = copy(timing.samples)
            table.sort(ordered)
            timing.p90 = ordered[math.max(1, math.ceil(#ordered * 0.9))]
            state.progress.timing[operation] = timing
        end
    end)
    local estimated = self:_view().etaRange
    local etaText = estimated
            and (" · ETA %d-%d sec"):format(estimated.minimum, estimated.maximum)
        or ""
    self:_publish({
        context = ("Batch %d/%d%s"):format(
            sequence,
            self:_batchCount(),
            etaText
        ),
        phase = batch.phase or batch.operation or "Copying",
        state = "copying",
    })
end

function CopyEngine:_reconcile(batch, applied, recovering)
    local succeeded, result = pcall(function()
        return self.reconcileBatch
                and self.reconcileBatch(batch, applied, recovering == true)
            or (applied == true and "confirmed" or "not_applied")
    end)
    if not succeeded then
        return "ambiguous"
    end
    if type(result) == "table" then
        return result.status, result.remainder, result.appliedPlanIds
    end
    return result
end

function CopyEngine:_reconcileCleanup(batch, applied, recovering)
    local succeeded, result = pcall(function()
        return self.reconcileCleanup
                and self.reconcileCleanup(batch, applied, recovering == true)
            or (applied ~= false and "confirmed" or "not_applied")
    end)
    if not succeeded then
        return "ambiguous"
    end
    return result
end

function CopyEngine:_persistPartial(batch, remainder, sequence, appliedPlanIds)
    local adopted = appliedPlanIds or appliedPrefix(batch, remainder)
    assert(#adopted > 0, "Partial reconciliation did not identify an applied prefix")
    self.state = self.checkpoint:advance(function(state)
        state.progress.pendingAdoption = {
            batchId = batch.id,
            count = #adopted,
            planIds = copy(adopted),
            sequence = sequence,
        }
    end)
    if self.afterPartialAdoption then
        self.afterPartialAdoption(copy(self.state.progress.pendingAdoption))
    end
    remainder.id = remainder.id or (tostring(batch.id) .. ":remainder")
    remainder.sequence = sequence
    remainder.confirmWeight = batch.confirmWeight or batch.weight or 1
    self.state = self.checkpoint:advance(function(state)
        state.progress.pendingBatch = copy(remainder)
        state.progress.pendingAdoption = nil
    end)
end

function CopyEngine:_persistReplacement(batch, replacement, sequence)
    replacement.id = replacement.id or (tostring(batch.id) .. ":ownership")
    replacement.sequence = sequence
    replacement.confirmWeight = batch.confirmWeight or batch.weight or 1
    replacement.originalOperation = batch.originalOperation or batch.operation
    self.state = self.checkpoint:advance(function(state)
        state.progress.pendingBatch = copy(replacement)
        state.progress.pendingAdoption = nil
    end)
    if self.afterReplacement then
        self.afterReplacement(copy(self.state.progress.pendingBatch))
    end
end

function CopyEngine:_applyPending(batch, sequence)
    local terminal = TERMINAL_OPERATIONS[batch.operation] == true
    if self.validateContext then
        local valid, message = self.validateContext(copy(self.state), copy(batch))
        if valid ~= true then
            return self:_durableError(message or "Town destination context changed")
        end
    end
    if not self.waitForCooling(function()
        return (self.cancelRequested and not terminal) or self.stopped
    end) then
        if terminal then
            return self:_durableError("Terminal Town work stopped before reconciliation")
        end
        return self:_pause("Stopped while waiting for Town cooling")
    end
    if (self.cancelRequested and not terminal) or self.stopped then
        if terminal then
            return self:_durableError("Terminal Town work stopped before reconciliation")
        end
        return self:_pause("Stopped before the pending remote")
    end
    if self.beforeRemote then
        local scheduled = pcall(self.beforeRemote, copy(batch))
        if not scheduled then
            return self:_durableError("Town command scheduling failed")
        end
    end
    if (self.cancelRequested and not terminal) or self.stopped then
        if terminal then
            return self:_durableError("Terminal Town work stopped before reconciliation")
        end
        return self:_pause("Stopped before the pending remote")
    end

    assert(type(self.applyBatch) == "function", "CopyEngine requires applyBatch for mutation")
    local startedAt = self.clock()
    local succeeded, applied = pcall(self.applyBatch, batch)
    if not succeeded and self.captureError then
        self.captureError(tostring(applied))
    end
    local duration = math.max(0, self.clock() - startedAt)
    if succeeded and self.afterRemote then
        self.afterRemote(copy(batch), applied)
    end
    local reconciliation, remainder, appliedPlanIds = self:_reconcile(
        batch,
        succeeded and applied or nil,
        not succeeded
    )
    local function release()
        if self.releaseBatchState then
            self.releaseBatchState()
        end
    end
    if reconciliation == "confirmed" then
        if batch.nextPending then
            release()
            self:_persistReplacement(batch, batch.nextPending, sequence)
            return self:_applyPending(batch.nextPending, sequence)
        end
        release()
        self:_confirmBatch(batch, sequence, duration)
        return true
    elseif reconciliation == "ownership_pending" and type(remainder) == "table" then
        release()
        self:_persistReplacement(batch, remainder, sequence)
        return self:_applyPending(remainder, sequence)
    elseif reconciliation == "partially_applied" and type(remainder) == "table" then
        release()
        self:_persistPartial(batch, remainder, sequence, appliedPlanIds)
        return self:_applyPending(remainder, sequence)
    elseif reconciliation == "not_applied" then
        release()
        return self:_durableError(
            succeeded and "Town copy batch was not confirmed" or "Town copy remote failed"
        )
    end
    release()
    return self:_durableError("Town copy state is ambiguous; no remote was replayed")
end

function CopyEngine:_run()
    local startSequence = (self.state.progress.lastConfirmedSequence or 0) + 1
    for sequence = startSequence, self:_batchCount() do
        local batch = copy(self:_batchAt(sequence))
        local phaseId = tostring(batch.phase or batch.operation or "batch")
            :lower()
            :gsub("[^%w]+", "_")
            :gsub("^_+", "")
            :gsub("_+$", "")
        batch.id = batch.id
            or ("%s:%s:%06d"):format(self.state.job.id, phaseId, sequence)
        batch.sequence = sequence

        if self.cancelRequested or self.stopped then
            return self:_pause("Stopped before the next remote")
        end

        self.state = self.checkpoint:advance(function(state)
            state.job.state = "copying"
            state.progress.pendingBatch = copy(batch)
            if TERMINAL_OPERATIONS[batch.operation] then
                state.progress.terminalStarted = true
            end
        end)

        local continued, message = self:_applyPending(batch, sequence)
        if not continued then
            return false, message
        end

        if (self.cancelRequested or self.stopped)
            and not self.state.progress.terminalStarted
        then
            return self:_pause("Stopped after confirming the current batch")
        end
    end

    self.state = self.checkpoint:advance(function(state)
        state.job.state = "completed"
    end)
    self.state = self.checkpoint:advance(function(state)
        state.job.state = "cleanup_pending"
    end)
    local deleted, deleteError = self.checkpoint:deleteJob(self.state.job.id)
    if not deleted then
        self:_publish({
            context = deleteError,
            phase = "Copy complete; local recovery cleanup pending",
            state = "cleanup_pending",
        })
        return false, deleteError
    end
    local supported = self.state.plan.supported
    self.state = nil
    self.executionCache = nil
    self:_publish({
        confirmedProgress = 1,
        context = ("%d supported parts confirmed"):format(supported),
        localCleanupAvailable = false,
        phase = "Copy complete",
        state = "completed",
    })
    return true
end

function CopyEngine:resume()
    assert(self.state, "No Town checkpoint is loaded")
    assert(
        FORWARD_RESUME_STATES[self.state.job.state] == true,
        "Town checkpoint is not eligible for forward resume"
    )
    self.cancelRequested = false
    self.stopped = false
    self.state = self.checkpoint:advance(function(state)
        state.job.state = "resuming"
    end)
    self:_publish({
        context = "Checking the last durable batch",
        phase = "Resuming copy",
        state = "resuming",
    })

    local pending = self.state.progress.pendingBatch
    if pending then
        self:_publish({
            context = pending.id,
            phase = "Checking previous work",
            state = "reconciling",
        })
        local reconciliation, remainder, appliedPlanIds = self:_reconcile(pending, nil, true)
        if reconciliation == "confirmed" then
            if pending.nextPending then
                self:_persistReplacement(pending, pending.nextPending, pending.sequence)
                local continued, message = self:_applyPending(
                    self.state.progress.pendingBatch,
                    pending.sequence
                )
                if not continued then
                    return false, message
                end
            else
                self:_confirmBatch(pending, pending.sequence)
            end
        elseif reconciliation == "not_applied" then
            local continued, message = self:_applyPending(pending, pending.sequence)
            if not continued then
                return false, message
            end
        elseif reconciliation == "partially_applied" and type(remainder) == "table" then
            self:_persistPartial(pending, remainder, pending.sequence, appliedPlanIds)
            local continued, message = self:_applyPending(remainder, pending.sequence)
            if not continued then
                return false, message
            end
        elseif reconciliation == "ownership_pending" and type(remainder) == "table" then
            self:_persistReplacement(pending, remainder, pending.sequence)
            local continued, message = self:_applyPending(remainder, pending.sequence)
            if not continued then
                return false, message
            end
        else
            if self:_terminalPending() then
                return self:_durableError("Pending terminal batch could not be reconciled safely")
            end
            self.state = self.checkpoint:advance(function(state)
                state.job.state = "paused"
                state.job.error = "Pending batch could not be reconciled safely"
            end)
            self:_publish({
                context = "Destination state is ambiguous; no remote was replayed",
                error = "Pending batch could not be reconciled safely",
                phase = "Recovery required",
                state = "paused",
            })
            return false, "Pending batch could not be reconciled safely"
        end
    end
    return self:_run()
end

function CopyEngine:confirmStart()
    assert(self.state and self.state.job.state == "awaiting_confirmation", "Copy is not awaiting confirmation")
    self.state = self.checkpoint:advance(function(state)
        state.authorization.confirmedAt = self.now()
        state.authorization.state = "copy_authorized"
        state.job.state = "copy_authorized"
    end)
    self:_publish({
        cancelAvailable = false,
        context = "Start confirmed; waiting for the first safe batch",
        phase = "Starting copy",
        startAvailable = false,
        state = "copy_authorized",
    })
    if self.afterAuthorization then
        self.afterAuthorization(copy(self.state))
    end
    return self:_run()
end

function CopyEngine:inspectRecovery(liveContext)
    if not self.checkpoint or self.checkpoint.available ~= true then
        return self:_publish({
            active = false,
            error = self.checkpoint and self.checkpoint.publicError,
            phase = "Copy blocked",
            state = "error",
        })
    end
    local loaded = self.checkpoint:load(liveContext)
    if loaded.status ~= "ready" then
        return self:_publish({
            active = false,
            context = loaded.message,
            error = loaded.status ~= "empty" and loaded.message or nil,
            phase = loaded.status == "empty" and "Ready" or "Copy blocked",
            state = loaded.status == "empty" and "idle" or "error",
        })
    end
    self.state = loaded.state
    local savedState = self.state.job.state
    if savedState == "awaiting_confirmation" then
        return self:_publish({
            active = false,
            cancelAvailable = true,
            context = "Verified plan is waiting for Start copy",
            phase = "Plan secured",
            startAvailable = true,
            state = "awaiting_confirmation",
        })
    end
    if savedState == "rollback" or savedState == "rollback_incomplete" then
        return self:_publish({
            active = false,
            context = "Plan-owned cleanup can be retried",
            discardAvailable = false,
            phase = savedState == "rollback" and "Cleaning copied parts" or "Recovery required",
            resumeAvailable = false,
            retryCleanupAvailable = true,
            state = savedState,
        })
    end
    if savedState == "completed" or savedState == "cleanup_pending" then
        return self:_publish({
            active = false,
            context = "The finished build is preserved; only local recovery data needs cleanup",
            discardAvailable = false,
            localCleanupAvailable = true,
            phase = "Copy complete; local recovery cleanup pending",
            resumeAvailable = false,
            state = savedState,
        })
    end
    if not FORWARD_RESUME_STATES[savedState] then
        return self:_publish({
            active = false,
            error = "Town recovery state is not eligible for resume",
            phase = "Recovery required",
            resumeAvailable = false,
            state = savedState,
        })
    end
    return self:_publish({
        active = false,
        context = "A compatible authorized copy can be resumed or discarded",
        phase = "Copy paused",
        state = savedState,
    })
end

function CopyEngine:requestCancel()
    if not self.state then
        return false
    end
    if self.state.job.state == "awaiting_confirmation" then
        local deleted, message = self.checkpoint:deleteJob(self.state.job.id)
        if not deleted then
            return false, message
        end
        self.state = nil
        self:_publish({
            phase = "Ready",
            state = "idle",
        })
        return true
    end
    if self:_terminalPending() then
        self:_publish({
            cancelAvailable = false,
            context = "Terminal save or wiring work must be reconciled before another action",
            discardAvailable = false,
            phase = "Recovery required",
            state = self.state.job.state,
        })
        return false
    end
    self.cancelRequested = true
    self:_publish({
        context = "Finishing the current batch safely",
        phase = "Cancel requested",
        state = "cancel_requested",
    })
    return true
end

function CopyEngine:_rollbackIncomplete(message)
    self.state = self.checkpoint:advance(function(state)
        state.cleanup = state.cleanup or {}
        state.job.state = "rollback_incomplete"
        state.job.error = message
    end)
    self:_publish({
        context = message,
        error = message,
        phase = "Recovery required",
        retryCleanupAvailable = true,
        state = "rollback_incomplete",
    })
    return false, message
end

function CopyEngine:discard()
    assert(self.state, "No Town checkpoint is loaded")
    assert(
        self.state.job.state ~= "completed" and self.state.job.state ~= "cleanup_pending",
        "Completed Town copies allow local checkpoint cleanup only"
    )
    assert(
        not self.state.progress.terminalStarted,
        "Terminal Town work must be reconciled and cannot be discarded"
    )
    self.cancelRequested = false
    local progress = self.state.progress or {}
    local pending = progress.pendingBatch
    if pending and (
        pending.operation == "CreatePart"
        or pending.operation == "Clone"
        or pending.operation == "AdoptOwnership"
        or pending.operation == "CreateGroup"
        or pending.operation == "AdoptGroupOwnership"
    ) then
        local reconciliation, remainder, appliedPlanIds = self:_reconcile(pending, nil, true)
        if reconciliation == "confirmed" then
            self.state = self.checkpoint:advance(function(state)
                if pending.operation == "CreateGroup"
                    or pending.operation == "AdoptGroupOwnership"
                then
                    state.progress.pendingGroupArtifact = {
                        groupFingerprint = pending.groupFingerprint,
                        groupId = pending.groupId,
                        sequence = pending.sequence,
                    }
                else
                    state.progress.pendingAdoption = {
                        batchId = pending.id,
                        count = #(pending.planIds or {}),
                        planIds = copy(pending.planIds or {}),
                        sequence = pending.sequence,
                    }
                end
                state.progress.pendingBatch = nil
            end)
        elseif reconciliation == "partially_applied" and type(remainder) == "table" then
            self:_persistPartial(pending, remainder, pending.sequence, appliedPlanIds)
        elseif reconciliation == "ownership_pending" and type(remainder) == "table" then
            self.state = self.checkpoint:advance(function(state)
                if remainder.operation == "AdoptGroupOwnership" then
                    state.progress.pendingGroupArtifact = {
                        groupFingerprint = remainder.groupFingerprint,
                        groupId = remainder.groupId,
                        raw = true,
                        sequence = pending.sequence,
                    }
                else
                    state.progress.pendingRawCreation = copy(remainder)
                    state.progress.pendingRawCreation.nextPending = nil
                end
                state.progress.pendingBatch = nil
            end)
        elseif reconciliation == "not_applied" then
            self.state = self.checkpoint:advance(function(state)
                state.progress.pendingBatch = nil
            end)
        elseif reconciliation ~= "not_applied" then
            return self:_rollbackIncomplete(
                "Pending created parts cannot be attributed safely for cleanup"
            )
        end
        progress = self.state.progress or {}
    end
    local hasMutation = (progress.lastConfirmedSequence or 0) > 0
        or progress.pendingBatch ~= nil
        or progress.pendingAdoption ~= nil
        or progress.pendingRawCreation ~= nil
        or progress.pendingGroupArtifact ~= nil
    if not hasMutation then
        local deleted, message = self.checkpoint:deleteJob(self.state.job.id)
        if not deleted then
            return self:_rollbackIncomplete(message or "Checkpoint cleanup is incomplete")
        end
        self.state = nil
        self:_publish({
            phase = "Ready",
            state = "idle",
        })
        return true
    end

    if type(self.nextCleanupBatch) ~= "function"
        or type(self.removeBatch) ~= "function"
    then
        return self:_rollbackIncomplete("Cleanup cannot identify all plan-owned destination items")
    end

    self.state = self.checkpoint:advance(function(state)
        state.cleanup = state.cleanup or {
            cursorSequence = state.progress.lastConfirmedSequence or 0,
            lastConfirmedSequence = 0,
            removedCount = 0,
        }
        state.cleanup.cursorSequence =
            state.cleanup.cursorSequence or state.progress.lastConfirmedSequence or 0
        state.cleanup.lastConfirmedSequence = state.cleanup.lastConfirmedSequence or 0
        state.cleanup.removedCount = state.cleanup.removedCount or 0
        state.job.state = "rollback"
    end)

    local cleanupPending = self.state.cleanup.pendingBatch
    if cleanupPending then
        local recovery = self:_reconcileCleanup(cleanupPending, nil, true)
        if recovery == "confirmed" then
            self.state = self.checkpoint:advance(function(state)
                state.cleanup.lastConfirmedSequence += 1
                state.cleanup.removedCount += cleanupPending.itemCount
                    or #(cleanupPending.planIds or {})
                state.cleanup.cursorSequence =
                    cleanupPending.nextCursor or state.cleanup.cursorSequence
                state.cleanup.cursorItemOffset =
                    cleanupPending.nextOffset or state.cleanup.cursorItemOffset
                if cleanupPending.clearsPendingAdoption then
                    state.cleanup.pendingAdoptionRemoved = true
                end
                if cleanupPending.clearsPendingRawCreation then
                    state.cleanup.pendingRawCreationRemoved = true
                end
                if cleanupPending.clearsPendingGroup then
                    state.cleanup.pendingGroupRemoved = true
                end
                state.cleanup.pendingBatch = nil
            end)
            if self.afterCleanupConfirmation then
                self.afterCleanupConfirmation(copy(cleanupPending))
            end
        elseif recovery ~= "not_applied" then
            return self:_rollbackIncomplete("Cleanup pending batch is ambiguous")
        end
    end

    self:_publish({
        context = ("%d plan-owned items removed"):format(self.state.cleanup.removedCount),
        phase = "Cleaning copied parts",
        state = "rollback",
    })

    while true do
        local identified, nextBatch = pcall(self.nextCleanupBatch, copy(self.state))
        if not identified then
            return self:_rollbackIncomplete("Cleanup cannot identify all plan-owned destination items")
        end
        if nextBatch == nil then
            break
        end
        if type(nextBatch) == "table"
            and nextBatch.operation == nil
            and type(nextBatch[1]) == "table"
        then
            nextBatch = nextBatch[(self.state.cleanup.lastConfirmedSequence or 0) + 1]
            if nextBatch == nil then
                break
            end
        end
        if type(nextBatch) ~= "table" then
            return self:_rollbackIncomplete("Cleanup cannot identify all plan-owned destination items")
        end
        local batch = copy(nextBatch)
        batch.id = batch.id
            or ("%s:remove:%06d"):format(
                self.state.job.id,
                (self.state.cleanup.lastConfirmedSequence or 0) + 1
            )
        batch.sequence = (self.state.cleanup.lastConfirmedSequence or 0) + 1
        self.state = self.checkpoint:advance(function(state)
            state.cleanup.pendingBatch = copy(batch)
            state.job.state = "rollback"
        end)

        if self.cancelRequested or self.stopped then
            return self:_rollbackIncomplete("Cleanup stopped before the next Remove")
        end
        local cooled = self.waitForCooling(function()
            return self.cancelRequested or self.stopped
        end)
        if not cooled then
            return self:_rollbackIncomplete("Cleanup stopped while waiting for Town cooling")
        end
        if self.cancelRequested or self.stopped then
            return self:_rollbackIncomplete("Cleanup stopped before the next Remove")
        end
        local succeeded, applied = pcall(self.removeBatch, batch)
        local reconciliation = self:_reconcileCleanup(
            batch,
            succeeded and applied or nil,
            not succeeded
        )
        if reconciliation ~= "confirmed" then
            return self:_rollbackIncomplete(
                succeeded and "Cleanup batch was not confirmed"
                    or "Cleanup remote result is ambiguous"
            )
        end
        self.state = self.checkpoint:advance(function(state)
            state.cleanup.lastConfirmedSequence += 1
            state.cleanup.removedCount += batch.itemCount or #(batch.planIds or {})
            state.cleanup.cursorSequence =
                batch.nextCursor or state.cleanup.cursorSequence
            state.cleanup.cursorItemOffset =
                batch.nextOffset or state.cleanup.cursorItemOffset
            if batch.clearsPendingAdoption then
                state.cleanup.pendingAdoptionRemoved = true
            end
            if batch.clearsPendingRawCreation then
                state.cleanup.pendingRawCreationRemoved = true
            end
            if batch.clearsPendingGroup then
                state.cleanup.pendingGroupRemoved = true
            end
            state.cleanup.pendingBatch = nil
        end)
        if self.afterCleanupConfirmation then
            self.afterCleanupConfirmation(copy(batch))
        end
        self:_publish({
            context = ("%d plan-owned items removed"):format(
                self.state.cleanup.removedCount
            ),
            phase = "Cleaning copied parts",
            state = "rollback",
        })
    end

    local deleted, message = self.checkpoint:deleteJob(self.state.job.id)
    if not deleted then
        return self:_rollbackIncomplete(message or "Checkpoint cleanup is incomplete")
    end
    self.state = nil
    self:_publish({
        phase = "Ready",
        state = "idle",
    })
    return true
end

function CopyEngine:retryCleanup()
    assert(
        self.state
            and (self.state.job.state == "rollback"
                or self.state.job.state == "rollback_incomplete"),
        "Cleanup is not awaiting retry"
    )
    return self:discard()
end

function CopyEngine:cleanupLocalCheckpoint(allowIncomplete)
    local completed = self.state
        and (self.state.job.state == "completed"
            or self.state.job.state == "cleanup_pending")
    assert(
        self.state and (completed or allowIncomplete == true),
        "Local checkpoint cleanup is unavailable"
    )
    local deleted, message = self.checkpoint:deleteJob(self.state.job.id)
    if not deleted then
        return false, message or "Checkpoint cleanup is incomplete"
    end
    self.state = nil
    self:_publish({
        confirmedProgress = completed and 1 or 0,
        phase = completed and "Copy complete" or "Ready",
        state = completed and "completed" or "idle",
    })
    return true
end

function CopyEngine:stop()
    self.stopped = true
    if self.state and self.state.job.state ~= "awaiting_confirmation" then
        self.cancelRequested = true
    end
end

return CopyEngine
]],
        ["games/town/CopyPlan.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Canonical = importDependency("games/town/Canonical", "./Canonical")

local CopyPlan = {}

local DEFAULT_CHUNK_SIZE = 256
local DEFAULT_CLONE_REQUEST_SIZE = 513
local DEFAULT_PREFERRED_BATCH_SIZE = 128

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[key] = copy(child)
    end
    return result
end

local function batchCount(count, size)
    return count > 0 and math.ceil(count / size) or 0
end

local function cloneCallCount(count, requestSize)
    if count <= 1 then
        return 0
    end
    local created = 1
    local calls = 0
    while created < count do
        created += math.min(count - created, created, requestSize)
        calls += 1
    end
    return calls
end

local function eachPart(source, emit)
    if type(source.iterParts) == "function" then
        source.iterParts(emit)
        return
    end
    for _, record in ipairs(source.parts or {}) do
        emit(record)
    end
end

local function increment(map, key, amount)
    map[key] = (map[key] or 0) + (amount or 1)
end

function CopyPlan.cloneCallCount(count, requestSize)
    return cloneCallCount(count, requestSize or DEFAULT_CLONE_REQUEST_SIZE)
end

function CopyPlan.fingerprint(value)
    return Canonical.checksum(value)
end

function CopyPlan.estimateWork(summary, preferredBatchSize)
    preferredBatchSize = preferredBatchSize or DEFAULT_PREFERRED_BATCH_SIZE
    local phases = {}
    local phaseOrder = {}
    local remoteCalls = summary.seeds + summary.cloneCalls
    for phase, records in pairs(summary.phaseCounts) do
        local batches = batchCount(records, preferredBatchSize)
        phases[phase] = {
            batches = batches,
            records = records,
        }
        table.insert(phaseOrder, phase)
        remoteCalls += batches
    end
    table.sort(phaseOrder)
    remoteCalls += summary.groups
    remoteCalls += summary.groupNames or 0
    if summary.copyWiring then
        remoteCalls += 1
    end
    if summary.save then
        remoteCalls += 1
    end
    return {
        cloneCalls = summary.cloneCalls,
        groups = summary.groups,
        groupNames = summary.groupNames or 0,
        phaseOrder = phaseOrder,
        phases = phases,
        remoteCalls = remoteCalls,
        seeds = summary.seeds,
        terminal = {
            save = summary.save == true,
            wiring = summary.copyWiring == true,
        },
    }
end

function CopyPlan.compile(source, options)
    assert(type(source) == "table", "CopyPlan requires a source")
    options = options or {}
    assert(options.maxParts == nil, "CopyPlan does not accept maxParts")
    assert(options.limit == nil, "CopyPlan does not accept limit")

    local chunkSize = options.chunkSize or DEFAULT_CHUNK_SIZE
    local cloneRequestSize = options.cloneRequestSize or DEFAULT_CLONE_REQUEST_SIZE
    local preferredBatchSize = options.preferredBatchSize or DEFAULT_PREFERRED_BATCH_SIZE
    assert(chunkSize >= 1 and chunkSize % 1 == 0, "CopyPlan chunkSize must be a positive integer")
    assert(
        cloneRequestSize >= 1 and cloneRequestSize % 1 == 0,
        "CopyPlan cloneRequestSize must be a positive integer"
    )
    assert(
        preferredBatchSize >= 1 and preferredBatchSize % 1 == 0,
        "CopyPlan preferredBatchSize must be a positive integer"
    )

    local buffer = {}
    local chunkChecksums = {}
    local chunks = options.retainChunks and {} or nil
    local peakBuffer = 0
    local phaseCounts = {}
    local supportedClasses = {}
    local typeCounts = {}
    local supported = 0
    local markerBearing = 0

    local function flush()
        if #buffer == 0 then
            return
        end
        local chunk = {
            index = #chunkChecksums + 1,
            records = buffer,
        }
        local checksum = Canonical.checksum(chunk)
        table.insert(chunkChecksums, checksum)
        if chunks then
            table.insert(chunks, copy(chunk))
        end
        if options.onChunk then
            options.onChunk(copy(chunk), checksum)
        end
        buffer = {}
    end

    eachPart(source, function(record)
        assert(type(record) == "table" and type(record.id) == "string", "CopyPlan parts require stable ids")
        assert(type(record.className) == "string", "CopyPlan parts require className")
        assert(type(record.type) == "string", "CopyPlan parts require Town part type")
        supported += 1
        if record.markerBearing == true then
            markerBearing += 1
        end
        increment(supportedClasses, record.className)
        increment(typeCounts, record.type)
        local operations = record.operations or { "resize" }
        for _, operation in ipairs(operations) do
            assert(type(operation) == "string", "CopyPlan operation names must be strings")
            increment(phaseCounts, operation)
        end
        table.insert(buffer, copy(record))
        peakBuffer = math.max(peakBuffer, #buffer)
        if #buffer == chunkSize then
            flush()
        end
    end)
    flush()

    local seeds = 0
    local cloneCalls = 0
    for _, count in pairs(typeCounts) do
        seeds += 1
        cloneCalls += cloneCallCount(count, cloneRequestSize)
    end

    local groups = source.groupCount or #(source.groups or {})
    local groupNames = 0
    for _, group in ipairs(source.groups or {}) do
        if group.name and group.name ~= "Model" then
            groupNames += 1
        end
    end
    local work = CopyPlan.estimateWork({
        cloneCalls = cloneCalls,
        copyWiring = source.copyWiring == true,
        groups = groups,
        groupNames = groupNames,
        phaseCounts = phaseCounts,
        save = source.save ~= false,
        seeds = seeds,
    }, preferredBatchSize)

    local plan = {
        baseParts = source.baseParts or supported + (source.unsupported or 0),
        chunkChecksums = chunkChecksums,
        chunks = chunks,
        context = copy(source.context or {}),
        groups = groups,
        markerBearing = markerBearing,
        peakBuffer = peakBuffer,
        requestSizing = {
            clone = cloneRequestSize,
            preferredBatch = preferredBatchSize,
            provenApiLimits = false,
        },
        schemaVersion = 1,
        supported = supported,
        supportedClasses = supportedClasses,
        typeCounts = typeCounts,
        totalDescendants = source.totalDescendants
            or supported + (source.unsupported or 0),
        unsupported = source.unsupported or 0,
        unsupportedClasses = copy(source.unsupportedClasses or {}),
        work = work,
    }
    plan.fingerprint = Canonical.checksum({
        baseParts = plan.baseParts,
        chunkChecksums = chunkChecksums,
        context = plan.context,
        groups = source.groups or {},
        markerBearing = markerBearing,
        requestSizing = plan.requestSizing,
        supported = supported,
        supportedClasses = supportedClasses,
        typeCounts = typeCounts,
        totalDescendants = plan.totalDescendants,
        unsupported = plan.unsupported,
        unsupportedClasses = plan.unsupportedClasses,
        work = work,
    })
    return plan
end

function CopyPlan.iterChunks(plan)
    local index = 0
    return function()
        index += 1
        return plan.chunks and plan.chunks[index] or nil
    end
end

return CopyPlan
]],
        ["games/town/ExecutionPlan.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Canonical = importDependency("games/town/Canonical", "./Canonical")

local ExecutionPlan = {}

local DEFAULT_BATCH_SIZE = 128
local DEFAULT_CLONE_REQUEST_SIZE = 513
local EXECUTION_CHUNK_SIZE = 64

local OPERATION_DEFINITIONS = {
    { key = "resize", operation = "SyncResize", phase = "Shaping geometry" },
    { key = "color", operation = "SyncColor", phase = "Painting colors" },
    { key = "material", operation = "SyncMaterial", phase = "Applying materials" },
    { key = "surface", operation = "SyncSurface", phase = "Finishing surfaces" },
    { entry = "mesh", key = "meshCreate", operation = "CreateMeshes", phase = "Creating mesh details" },
    { entry = "mesh", key = "meshSync", operation = "SyncMesh", phase = "Applying mesh details" },
    { entry = "textures", key = "textureCreate", operation = "CreateTextures", phase = "Creating textures" },
    { entry = "textures", key = "textureSync", operation = "SyncTexture", phase = "Applying textures" },
    { entry = "lights", key = "lightCreate", operation = "CreateLights", phase = "Creating lights" },
    { entry = "lights", key = "lightSync", operation = "SyncLighting", phase = "Configuring lights" },
    { key = "collision", operation = "SyncCollision", phase = "Setting collisions" },
    { key = "anchor", operation = "SyncAnchor", phase = "Securing parts" },
}

local function hasOperation(record, key)
    for _, operation in ipairs(record.operations or {}) do
        if operation == key then
            return true
        end
    end
    return false
end

local function eachRecord(checkpoint, jobId, chunks, visit)
    for _, metadata in ipairs(chunks) do
        local chunk = checkpoint:readPlanChunk(jobId, metadata)
        for _, record in ipairs(chunk.records) do
            visit(record)
        end
    end
end

local function stagingCFrame(jobId, record)
    local digest = Canonical.sha256Bytes(Canonical.encode({
        jobId = jobId,
        planId = record.id,
        purpose = "create-ownership",
    }))
    local result = {}
    for index, value in ipairs(record.cframe) do
        result[index] = value
    end
    for axis = 1, 3 do
        local value = tonumber(digest:sub((axis - 1) * 8 + 1, axis * 8), 16)
        local sign = value % 2 == 0 and 1 or -1
        local magnitude = 0.01 + ((value % 1000000) / 1000000) * 0.04
        result[axis] += sign * magnitude
    end
    return result
end

function ExecutionPlan.compile(checkpoint, jobId, planChunks, plan, options)
    options = options or {}
    local batchSize = options.preferredBatchSize or DEFAULT_BATCH_SIZE
    local cloneSize = options.cloneRequestSize or DEFAULT_CLONE_REQUEST_SIZE
    local chunkMetadata = {}
    local buffer = {}
    local batchCount = 0
    local maximumBufferedRecords = 0
    local operationCounts = {}
    local phaseCounts = {}

    local function flushExecution()
        if #buffer == 0 then
            return
        end
        local index = #chunkMetadata + 1
        table.insert(chunkMetadata, checkpoint:writeJobChunk(jobId, "execution", index, {
            index = index,
            jobId = jobId,
            kind = "execution",
            records = buffer,
        }))
        buffer = {}
    end

    local function emit(batch)
        batchCount += 1
        operationCounts[batch.operation] = (operationCounts[batch.operation] or 0) + 1
        phaseCounts[batch.phase] = (phaseCounts[batch.phase] or 0) + 1
        batch.sequence = batchCount
        batch.weight = batch.weight or 1
        table.insert(buffer, batch)
        maximumBufferedRecords = math.max(maximumBufferedRecords, #buffer)
        if #buffer == EXECUTION_CHUNK_SIZE then
            flushExecution()
        end
    end

    local types = {}
    local operationStates = {}
    for _, definition in ipairs(OPERATION_DEFINITIONS) do
        table.insert(operationStates, {
            definition = definition,
            entries = {},
            planIds = {},
        })
    end

    local function flushOperation(state)
        if #state.planIds == 0 then
            return
        end
        local definition = state.definition
        local batch = {
            operation = definition.operation,
            phase = definition.phase,
            planIds = state.planIds,
        }
        if #state.entries > 0 then
            batch.entries = state.entries
        end
        emit(batch)
        state.planIds = {}
        state.entries = {}
    end

    local function appendOperation(state, record)
        local definition = state.definition
        if not hasOperation(record, definition.key) then
            return
        end
        if definition.entry == "textures" or definition.entry == "lights" then
            for index, item in ipairs(record[definition.entry] or {}) do
                if definition.entry ~= "lights" or item.enabled then
                    table.insert(state.entries, { index = index, partId = record.id })
                    if #state.planIds == 0 or state.planIds[#state.planIds] ~= record.id then
                        table.insert(state.planIds, record.id)
                    end
                    if #state.entries == batchSize then
                        flushOperation(state)
                    end
                end
            end
        else
            table.insert(state.planIds, record.id)
            if definition.entry then
                table.insert(state.entries, { index = 1, partId = record.id })
            end
            if #state.planIds == batchSize then
                flushOperation(state)
            end
        end
    end

    local function flushClones(typeState)
        if #typeState.pending == 0 then
            return
        end
        local sourceIds = {}
        for index = 1, #typeState.pending do
            table.insert(sourceIds, typeState.sources[index])
        end
        emit({
            operation = "Clone",
            ownershipRequired = true,
            phase = "Creating parts",
            planIds = typeState.pending,
            sourceIds = sourceIds,
            townType = typeState.name,
        })
        for _, id in ipairs(typeState.pending) do
            if #typeState.sources < cloneSize then
                table.insert(typeState.sources, id)
            end
        end
        typeState.created += #typeState.pending
        typeState.pending = {}
    end

    eachRecord(checkpoint, jobId, planChunks, function(record)
        local typeState = types[record.type]
        if not typeState then
            typeState = {
                created = 1,
                name = record.type,
                pending = {},
                sources = { record.id },
            }
            types[record.type] = typeState
            emit({
                creationCFrame = stagingCFrame(jobId, record),
                operation = "CreatePart",
                ownershipRequired = true,
                phase = "Creating parts",
                planIds = { record.id },
                townType = record.type,
            })
        else
            table.insert(typeState.pending, record.id)
            if #typeState.pending == math.min(typeState.created, cloneSize) then
                flushClones(typeState)
            end
        end
    end)
    for _, typeState in pairs(types) do
        flushClones(typeState)
    end
    eachRecord(checkpoint, jobId, planChunks, function(record)
        for _, operationState in ipairs(operationStates) do
            appendOperation(operationState, record)
        end
    end)
    for _, operationState in ipairs(operationStates) do
        flushOperation(operationState)
    end
    local nameState = {
        definition = {
            key = "name",
            operation = "SetPartNames",
            phase = "Restoring part names",
        },
        entries = {},
        planIds = {},
    }
    eachRecord(checkpoint, jobId, planChunks, function(record)
        appendOperation(nameState, record)
    end)
    flushOperation(nameState)

    local function emitGroup(group)
        local memberCount = 0
        local membershipChecksums = {}
        local fingerprintBuffer = {}
        local function flushFingerprint()
            if #fingerprintBuffer > 0 then
                table.insert(membershipChecksums, Canonical.checksum(fingerprintBuffer))
                fingerprintBuffer = {}
            end
        end
        local function fingerprintMember(kind, id)
            memberCount += 1
            table.insert(fingerprintBuffer, {
                id = id,
                kind = kind,
            })
            if #fingerprintBuffer == batchSize then
                flushFingerprint()
            end
        end
        if group.iterMembers then
            group.iterMembers(fingerprintMember)
        else
            for _, id in ipairs(group.partIds or {}) do
                fingerprintMember("part", id)
            end
            for _, id in ipairs(group.modelIds or {}) do
                fingerprintMember("model", id)
            end
        end
        flushFingerprint()
        local groupFingerprint = Canonical.checksum({
            chunks = membershipChecksums,
            id = group.id,
            memberCount = memberCount,
            name = group.name,
        })
        local memberBuffer = {}
        local created = false
        local function flushMembers()
            if #memberBuffer == 0 and created then
                return
            end
            emit({
                groupFingerprint = groupFingerprint,
                groupId = group.id,
                groupName = group.name,
                memberCount = memberCount,
                memberIds = memberBuffer,
                operation = created and "AddGroupMembers" or "CreateGroup",
                ownershipRequired = not created,
                phase = "Building groups",
            })
            created = true
            memberBuffer = {}
        end
        local function appendMember(kind, id)
            table.insert(memberBuffer, {
                id = id,
                kind = kind,
            })
            if #memberBuffer == batchSize then
                flushMembers()
            end
        end
        if group.iterMembers then
            group.iterMembers(appendMember)
        else
            for _, id in ipairs(group.partIds or {}) do
                appendMember("part", id)
            end
            for _, id in ipairs(group.modelIds or {}) do
                appendMember("model", id)
            end
        end
        flushMembers()
        if group.name ~= "Model" then
            emit({
                groupFingerprint = groupFingerprint,
                groupId = group.id,
                groupName = group.name,
                memberCount = memberCount,
                operation = "SetGroupName",
                phase = "Naming groups",
            })
        end
    end
    if options.iterGroups then
        options.iterGroups(emitGroup)
    else
        for _, group in ipairs(plan.groups or {}) do
            emitGroup(group)
        end
    end
    if options.copyWiring then
        emit({
            operation = "Wire",
            phase = "Compiling wiring",
            wiringFingerprint = options.wiringFingerprint,
        })
    end
    emit({
        operation = "Save",
        phase = "Saving copy",
        priorSaveIdentity = options.priorSaveIdentity,
        saveName = options.saveName,
    })
    flushExecution()

    local result = {
        batchCount = batchCount,
        chunkCount = #chunkMetadata,
        chunks = chunkMetadata,
        maximumBufferedRecords = maximumBufferedRecords,
        operationCounts = operationCounts,
        phaseCounts = phaseCounts,
        planHash = plan.fingerprint,
        strategy = "town-stream-v1",
        totalWeight = batchCount,
    }
    result.hash = Canonical.checksum({
        batchCount = result.batchCount,
        chunks = result.chunks,
        operationCounts = result.operationCounts,
        phaseCounts = result.phaseCounts,
        planHash = result.planHash,
        strategy = result.strategy,
        totalWeight = result.totalWeight,
    })
    return result
end

return ExecutionPlan
]],
        ["games/town/Presentation.lua"] = [[local Presentation = {}

local OWNER_VALUE_LIMIT = 22
local SAVE_VALUE_LIMIT = 24
local LAYOUT = {
    actionLabelX = 195,
    actionLabelY = 99,
    actionTop = 88,
    contentInset = 20,
    contentWidth = 350,
    dropdownLabelInset = 36,
    dropdownLabelTop = 43,
    dropdownRowHeight = 32,
    dropdownRowTop = 36,
    ownerIndicatorX = 350,
    ownerIndicatorY = 10,
    ownerLabelX = 36,
    ownerRowHeight = 36,
    ownerTextY = 11,
    ownerValueX = 120,
    panelHeight = 216,
    progressContextTop = 184,
    progressLabelInset = 36,
    progressPhaseTop = 168,
    progressTrackTop = 204,
    progressValueX = 350,
    saveLabelX = 36,
    saveRowTop = 44,
    saveTextY = 55,
    saveValueX = 98,
    secondaryHeight = 32,
    secondaryLabelX = 195,
    secondaryLabelY = 142,
    secondaryTop = 132,
    sectionHeaderHeight = 32,
    sectionLineX = 20,
    sectionLineY = 24,
    sectionWidth = 350,
}

local LAYER = {
    background = 202,
    control = 203,
    foreground = 204,
    popup = 212,
    popupLabel = 213,
}

local function compactText(value, limit)
    value = tostring(value or "")
    if #value <= limit then
        return value
    end
    return value:sub(1, math.max(1, limit - 3)) .. "..."
end

local function setVisible(nodes, visible)
    for _, node in pairs(nodes or {}) do
        if type(node) == "table" and (type(node.set) == "function" or node.Visible ~= nil) then
            node.Visible = visible
        elseif type(node) == "table" then
            setVisible(node, visible)
        end
    end
end

local function report(host, message)
    pcall(host.action, host, "reportPlotCopyError", message)
end

local function invoke(host, callbackName)
    local succeeded, accepted, message = pcall(host.action, host, callbackName)
    if not succeeded then
        report(host, "Plot copy action failed")
    elseif accepted == false then
        report(host, message or "Plot copy action could not start")
    end
end

local function createPanel(host)
    local colors = host:theme()
    local tokens = assert(colors.tokens, "Presentation theme requires shared tokens")
    local controls = host:controls()
    local state = {
        connections = {},
        dropdownItems = {},
        dropdownOpen = false,
        saveName = "",
        selectedOwner = nil,
        page = "Tools",
    }
    local function node(kind, properties, pointerEvents)
        local result = host:node(kind, properties, pointerEvents)
        return pointerEvents and host:interactive(result) or result
    end
    local function text(properties)
        return host:text(properties)
    end

    controls.sections.plotCopy = {
        label = text({
            Color = colors.text,
            Size = tokens.type.section,
            Text = "PLOT COPY",
            ZIndex = LAYER.control,
        }),
        line = node("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(LAYOUT.sectionWidth, tokens.control.borderThickness),
            Visible = true,
            ZIndex = LAYER.background,
        }),
    }
    local plotCopy = {
        ownerButton = node("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.ownerRowHeight),
            Visible = true,
            ZIndex = LAYER.background,
        }, true),
        ownerIndicator = text({
            Center = true, Color = colors.secondary, Size = tokens.type.label, Text = "v", ZIndex = LAYER.foreground,
        }),
        ownerLabel = text({
            Color = colors.secondary, Size = tokens.type.row, Text = "PLAYER", ZIndex = LAYER.control,
        }),
        ownerOutline = node("Square", {
            Color = colors.border,
            Filled = false,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.ownerRowHeight),
            Thickness = tokens.control.borderThickness,
            Transparency = tokens.opacity.edge,
            Visible = true,
            ZIndex = LAYER.control,
        }),
        ownerValue = text({
            Color = colors.secondary, Size = tokens.type.label, Text = "Select a plot", ZIndex = LAYER.control,
        }),
        saveButton = node("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.ownerRowHeight),
            Visible = true,
            ZIndex = LAYER.background,
        }, true),
        saveLabel = text({
            Color = colors.secondary, Size = tokens.type.row, Text = "SAVE", ZIndex = LAYER.control,
        }),
        saveOutline = node("Square", {
            Color = colors.border,
            Filled = false,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.ownerRowHeight),
            Thickness = tokens.control.borderThickness,
            Transparency = tokens.opacity.edge,
            Visible = true,
            ZIndex = LAYER.control,
        }),
        saveValue = text({
            Color = colors.secondary, Size = tokens.type.label, Text = "Enter save name", ZIndex = LAYER.control,
        }),
        actionButton = node("Square", {
            Color = colors.accentSurface,
            Filled = true,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.ownerRowHeight),
            Visible = true,
            ZIndex = LAYER.background,
        }, true),
        actionLabel = text({
            Center = true, Color = colors.accent, Size = tokens.type.primary, Text = "Copy & Save", ZIndex = LAYER.control,
        }),
        secondaryButton = node("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.secondaryHeight),
            Visible = false,
            ZIndex = LAYER.background,
        }, true),
        secondaryLabel = text({
            Center = true, Color = colors.secondary, Size = tokens.type.label, Text = "", Visible = false, ZIndex = LAYER.control,
        }),
        progressPhase = text({
            Color = colors.secondary, Size = tokens.type.row, Text = "Ready", ZIndex = LAYER.control,
        }),
        progressContext = text({
            Color = colors.secondary, Size = tokens.type.meta, Text = "", ZIndex = LAYER.control,
        }),
        progressValue = text({
            Center = true, Color = colors.secondary, Size = tokens.type.row, Text = "0%", ZIndex = LAYER.control,
        }),
        progressTrack = node("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(LAYOUT.contentWidth, tokens.control.progressTrackHeight),
            Visible = true,
            ZIndex = LAYER.background,
        }),
        progressFill = node("Square", {
            Color = colors.accent,
            Filled = true,
            Size = Vector2.new(0, tokens.control.progressTrackHeight),
            Visible = true,
            ZIndex = LAYER.control,
        }),
    }
    plotCopy.inputLayer = false
    plotCopy.saveInput = false
    plotCopy.secondaryVisible = false
    plotCopy.dropdownItems = state.dropdownItems
    controls.plotCopy = plotCopy

    local function setSaveName(saveName)
        state.saveName = tostring(saveName or "")
        plotCopy.saveValue.Text = state.saveName == ""
                and "Enter save name"
            or compactText(state.saveName, SAVE_VALUE_LIMIT)
        plotCopy.saveValue.Color = state.saveName == "" and colors.secondary or colors.text
    end
    local function clearDropdown()
        for _, item in ipairs(state.dropdownItems) do
            item.row:destroy()
            item.label:destroy()
        end
        table.clear(state.dropdownItems)
    end
    local function selectOwner(ownerName)
        local previousDefault = state.selectedOwner and ("copy_" .. state.selectedOwner) or ""
        state.selectedOwner = ownerName
        plotCopy.ownerValue.Text = compactText(ownerName, OWNER_VALUE_LIMIT)
        plotCopy.ownerValue.Color = colors.text
        if state.saveName == "" or state.saveName == previousDefault then
            setSaveName("copy_" .. ownerName)
            if plotCopy.saveInput then
                plotCopy.saveInput.Text = state.saveName
            end
        end
    end
    local function setDropdownOpen(open)
        clearDropdown()
        state.dropdownOpen = open == true
        plotCopy.ownerIndicator.Text = state.dropdownOpen and "^" or "v"
        if not state.dropdownOpen then
            return
        end
        local succeeded, owners = pcall(host.action, host, "listPlotOwners")
        if not succeeded or type(owners) ~= "table" or #owners == 0 then
            state.dropdownOpen = false
            plotCopy.ownerIndicator.Text = "v"
            plotCopy.ownerValue.Text = "No player plots"
            plotCopy.ownerValue.Color = colors.danger
            report(host, "No other player plots are available")
            return
        end
        if not table.find(owners, state.selectedOwner) then
            selectOwner(owners[1])
        end
        for _, ownerName in ipairs(owners) do
            local row = node("Square", {
                Color = ownerName == state.selectedOwner and colors.accentSurface or colors.elevated,
                Filled = true,
                Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.dropdownRowHeight),
                Visible = true,
                ZIndex = LAYER.popup,
            }, true)
            local label = text({
                Color = ownerName == state.selectedOwner and colors.accent or colors.text,
                Size = tokens.type.label,
                Text = compactText(ownerName, OWNER_VALUE_LIMIT),
                ZIndex = LAYER.popupLabel,
            })
            row:on("click", function()
                selectOwner(ownerName)
                setDropdownOpen(false)
            end)
            table.insert(state.dropdownItems, { label = label, row = row })
        end
        host:requestLayout()
    end

    local function runPrimaryAction()
        local plotCopyState = host:read().plotCopy
        local copyState = plotCopyState and plotCopyState.state or "idle"
        if plotCopyState.localCleanupAvailable then
            invoke(host, "cleanupPlotCopyCheckpoint")
        elseif plotCopyState.retryCleanupAvailable then
            invoke(host, "retryPlotCopyCleanup")
        elseif plotCopyState.resumeAvailable and copyState ~= "awaiting_confirmation" then
            invoke(host, "resumePlotCopy")
        elseif copyState == "awaiting_confirmation" then
            invoke(host, "confirmPlotCopy")
        elseif copyState == "rollback" or copyState == "rollback_incomplete" then
            invoke(host, "retryPlotCopyCleanup")
        elseif copyState == "cleanup_pending" then
            invoke(host, "cleanupPlotCopyCheckpoint")
        elseif copyState == "paused" then
            invoke(host, "resumePlotCopy")
        elseif copyState == "copying"
            or copyState == "preflight"
            or copyState == "reconciling"
            or copyState == "resuming"
        then
            invoke(host, "cancelPlotCopy")
        elseif copyState == "idle" or copyState == "completed" or copyState == "error" then
            if not state.selectedOwner then
                report(host, "Choose a player plot to copy")
            elseif state.saveName == "" then
                report(host, "Enter a save name")
            else
                setDropdownOpen(false)
                local succeeded, accepted, message = pcall(
                    host.action,
                    host,
                    "copyPlot",
                    state.selectedOwner,
                    state.saveName
                )
                if not succeeded then
                    report(host, "Plot copy could not start: " .. tostring(accepted))
                elseif accepted == false then
                    report(host, message or "Plot copy could not start")
                end
            end
        end
    end

    plotCopy.ownerButton:on("click", function()
        setDropdownOpen(not state.dropdownOpen)
    end)
    plotCopy.saveButton:on("click", function()
        setDropdownOpen(false)
        if plotCopy.saveInput then
            plotCopy.saveInput:CaptureFocus()
        end
    end)
    plotCopy.actionButton:on("click", runPrimaryAction)
    plotCopy.secondaryButton:on("click", function()
        local plotCopyState = host:read().plotCopy or {}
        if plotCopyState.state == "awaiting_confirmation" then
            invoke(host, "cancelPlotCopy")
        elseif plotCopyState.state == "paused" then
            invoke(host, "discardPlotCopy")
        end
    end)

    local uiParent = host:uiParent()
    if uiParent then
        local inputLayer = host:createInstance("ScreenGui")
        inputLayer.Name = "UniversalHubPlotCopyInput"
        inputLayer.DisplayOrder = 10000
        inputLayer.IgnoreGuiInset = true
        inputLayer.ResetOnSpawn = false
        inputLayer.Parent = uiParent

        local saveInput = host:createInstance("TextBox")
        saveInput.Name = "SaveName"
        saveInput.BackgroundTransparency = 1
        saveInput.ClearTextOnFocus = false
        saveInput.Position = UDim2.fromOffset(-20, -20)
        saveInput.Size = UDim2.fromOffset(1, 1)
        saveInput.Text = ""
        saveInput.TextTransparency = 1
        saveInput.Parent = inputLayer
        plotCopy.inputLayer = inputLayer
        plotCopy.saveInput = saveInput
        table.insert(state.connections, saveInput:GetPropertyChangedSignal("Text"):Connect(function()
            setSaveName(saveInput.Text)
        end))
        table.insert(state.connections, saveInput.Focused:Connect(function()
            plotCopy.saveOutline.Color = colors.accent
        end))
        table.insert(state.connections, saveInput.FocusLost:Connect(function(enterPressed)
            plotCopy.saveOutline.Color = colors.border
            if enterPressed then
                runPrimaryAction()
            end
        end))
    end

    function state:layout(x, _y, cursor)
        local section = controls.sections.plotCopy
        section.label.Position = Vector2.new(x + LAYOUT.contentInset, cursor)
        section.line.Position = Vector2.new(x + LAYOUT.sectionLineX, cursor + LAYOUT.sectionLineY)
        cursor = cursor + LAYOUT.sectionHeaderHeight

        plotCopy.ownerButton.Position = Vector2.new(x + LAYOUT.contentInset, cursor)
        plotCopy.ownerOutline.Position = plotCopy.ownerButton.Position
        plotCopy.ownerLabel.Position = Vector2.new(x + LAYOUT.ownerLabelX, cursor + LAYOUT.ownerTextY)
        plotCopy.ownerValue.Position = Vector2.new(x + LAYOUT.ownerValueX, cursor + LAYOUT.ownerTextY)
        plotCopy.ownerIndicator.Position = Vector2.new(
            x + LAYOUT.ownerIndicatorX,
            cursor + LAYOUT.ownerIndicatorY
        )
        plotCopy.saveButton.Position = Vector2.new(x + LAYOUT.contentInset, cursor + LAYOUT.saveRowTop)
        plotCopy.saveOutline.Position = plotCopy.saveButton.Position
        plotCopy.saveLabel.Position = Vector2.new(x + LAYOUT.saveLabelX, cursor + LAYOUT.saveTextY)
        plotCopy.saveValue.Position = Vector2.new(x + LAYOUT.saveValueX, cursor + LAYOUT.saveTextY)
        plotCopy.actionButton.Position = Vector2.new(x + LAYOUT.contentInset, cursor + LAYOUT.actionTop)
        plotCopy.actionLabel.Position = Vector2.new(x + LAYOUT.actionLabelX, cursor + LAYOUT.actionLabelY)
        plotCopy.secondaryButton.Position = Vector2.new(x + LAYOUT.contentInset, cursor + LAYOUT.secondaryTop)
        plotCopy.secondaryLabel.Position = Vector2.new(
            x + LAYOUT.secondaryLabelX,
            cursor + LAYOUT.secondaryLabelY
        )
        plotCopy.progressPhase.Position = Vector2.new(
            x + LAYOUT.progressLabelInset,
            cursor + LAYOUT.progressPhaseTop
        )
        plotCopy.progressValue.Position = Vector2.new(
            x + LAYOUT.progressValueX,
            cursor + LAYOUT.progressPhaseTop
        )
        plotCopy.progressContext.Position = Vector2.new(
            x + LAYOUT.progressLabelInset,
            cursor + LAYOUT.progressContextTop
        )
        plotCopy.progressTrack.Position = Vector2.new(
            x + LAYOUT.contentInset,
            cursor + LAYOUT.progressTrackTop
        )
        plotCopy.progressFill.Position = plotCopy.progressTrack.Position
        for index, item in ipairs(self.dropdownItems) do
            local itemOffset = (index - 1) * LAYOUT.dropdownRowHeight
            item.row.Position = Vector2.new(
                x + LAYOUT.contentInset,
                cursor + LAYOUT.dropdownRowTop + itemOffset
            )
            item.label.Position = Vector2.new(
                x + LAYOUT.dropdownLabelInset,
                cursor + LAYOUT.dropdownLabelTop + itemOffset
            )
        end
        return cursor + LAYOUT.panelHeight
    end

    function state:setVisible(visible)
        for name, item in pairs(plotCopy) do
            if name ~= "inputLayer"
                and name ~= "saveInput"
                and name ~= "dropdownItems"
                and name ~= "secondaryButton"
                and name ~= "secondaryLabel"
                and name ~= "secondaryVisible"
            then
                item.Visible = visible
            end
        end
        controls.sections.plotCopy.label.Visible = visible
        controls.sections.plotCopy.line.Visible = visible
        plotCopy.secondaryButton.Visible = visible and plotCopy.secondaryVisible == true
        plotCopy.secondaryLabel.Visible = visible and plotCopy.secondaryVisible == true
        for _, item in ipairs(self.dropdownItems) do
            setVisible(item, visible and self.dropdownOpen)
        end
        if plotCopy.inputLayer then
            plotCopy.inputLayer.Enabled = visible
        end
        if not visible then
            setDropdownOpen(false)
        end
    end

    function state:render(current)
        local plotCopyState = current.plotCopy or {}
        local progress = math.clamp(
            plotCopyState.confirmedProgress or plotCopyState.progress or 0,
            0,
            1
        )
        local active = plotCopyState.active == true
        local copyState = plotCopyState.state or (active and "copying" or "idle")
        local hasError = copyState == "error" or copyState == "rollback_incomplete"
        local primaryLabels = {
            awaiting_confirmation = "Start copy",
            cancel_requested = "Cancelling...",
            cleanup_pending = "Cleanup pending",
            completed = "Copy another",
            copying = "Cancel",
            copy_authorized = "Starting...",
            discarding = "Discarding...",
            error = "Retry",
            idle = "Copy & Save",
            paused = "Resume",
            preflight = "Cancel",
            reconciling = "Cancel",
            resuming = "Cancel",
            rollback = "Cleaning...",
            rollback_incomplete = "Retry cleanup",
            saving = "Saving...",
        }
        local primaryEnabled = copyState == "idle"
            or copyState == "completed"
            or copyState == "error"
            or copyState == "awaiting_confirmation"
            or copyState == "copying"
            or copyState == "preflight"
            or copyState == "reconciling"
            or copyState == "resuming"
            or copyState == "paused"
            or copyState == "rollback_incomplete"
            or copyState == "rollback"
            or copyState == "cleanup_pending"
        local secondaryLabel
        if copyState == "awaiting_confirmation" then
            secondaryLabel = "Cancel"
        elseif copyState == "paused" then
            secondaryLabel = "Discard"
        end
        plotCopy.progressPhase.Text = compactText(plotCopyState.phase or "Ready", 34)
        plotCopy.progressPhase.Color = hasError and colors.danger
            or (active and colors.text or colors.secondary)
        plotCopy.progressContext.Text = plotCopyState.context or ""
        plotCopy.progressContext.Color = hasError and colors.danger or colors.secondary
        plotCopy.progressValue.Text = ("%d%%"):format(math.round(progress * 100))
        plotCopy.progressValue.Color = active and colors.accent or colors.secondary
        plotCopy.progressFill.Size = Vector2.new(
            LAYOUT.contentWidth * progress,
            tokens.control.progressTrackHeight
        )
        plotCopy.progressFill.Color = hasError and colors.danger or colors.accent
        host:setControlColor(
            plotCopy.actionButton,
            primaryEnabled and colors.accentSurface or colors.panel
        )
        plotCopy.actionLabel.Text = plotCopyState.localCleanupAvailable
                and "Clear local recovery"
            or (plotCopyState.retryCleanupAvailable and "Retry cleanup")
            or (
                plotCopyState.resumeAvailable
                    and copyState ~= "awaiting_confirmation"
                    and "Resume"
            )
            or (primaryLabels[copyState] or "Working...")
        plotCopy.actionLabel.Color = primaryEnabled and colors.accent or colors.secondary
        local showSecondary = secondaryLabel ~= nil and current.menuVisible ~= false
        plotCopy.secondaryVisible = secondaryLabel ~= nil
        plotCopy.secondaryButton.Visible = showSecondary
        plotCopy.secondaryLabel.Visible = showSecondary
        plotCopy.secondaryLabel.Text = secondaryLabel or ""
    end

    function state:destroy()
        clearDropdown()
        for _, connection in ipairs(self.connections) do
            connection:Disconnect()
        end
        table.clear(self.connections)
        if plotCopy.inputLayer then
            plotCopy.inputLayer:Destroy()
            plotCopy.inputLayer = nil
            plotCopy.saveInput = nil
        end
    end

    return state
end

function Presentation.mount(host)
    if host:supports("plotCopy") then
        host:register(createPanel(host))
    end
end

return Presentation
]],
    },
}
