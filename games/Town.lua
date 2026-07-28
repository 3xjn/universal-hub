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

local BATCH_SIZE = 128
local CLONE_BATCH_SIZE = 513
local COMMAND_COOLDOWN_SECONDS = 6
local MAX_PARTS = 2000
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

local function snapshotPart(part, sourcePlot, targetPlot, sourceCFrame)
    local sourceMesh = part:FindFirstChildOfClass("SpecialMesh")
    local textures = {}
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            table.insert(textures, {
                Face = child.Face,
                OffsetStudsU = child:IsA("Texture") and child.OffsetStudsU or nil,
                OffsetStudsV = child:IsA("Texture") and child.OffsetStudsV or nil,
                StudsPerTileU = child:IsA("Texture") and child.StudsPerTileU or nil,
                StudsPerTileV = child:IsA("Texture") and child.StudsPerTileV or nil,
                Texture = child.Texture,
                TextureType = child.ClassName,
                Transparency = child.Transparency,
            })
        end
    end
    return {
        Anchored = part.Anchored,
        CanCollide = part.CanCollide,
        CFrame = transformedCFrame(
            sourcePlot.CFrame,
            targetPlot.CFrame,
            sourceCFrame or part.CFrame
        ),
        Color = part.Color,
        Material = part.Material,
        Lights = snapshotLights(part),
        Mesh = sourceMesh and {
            MeshId = sourceMesh.MeshId,
            MeshType = sourceMesh.MeshType,
            Offset = sourceMesh.Offset,
            Scale = sourceMesh.Scale,
            TextureId = sourceMesh.TextureId,
            VertexColor = sourceMesh.VertexColor,
        } or nil,
        Name = part.Name,
        Reflectance = part.Reflectance,
        Size = part.Size,
        Transparency = part.Transparency,
        Surfaces = {
            BackSurface = part.BackSurface,
            BottomSurface = part.BottomSurface,
            FrontSurface = part.FrontSurface,
            LeftSurface = part.LeftSurface,
            RightSurface = part.RightSurface,
            TopSurface = part.TopSurface,
        },
        Source = part,
        Textures = textures,
        Type = partType(part),
    }
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

local function batches(items, size)
    local index = 1
    return function()
        if index > #items then
            return nil
        end
        local batch = {}
        local last = math.min(index + size - 1, #items)
        for itemIndex = index, last do
            table.insert(batch, items[itemIndex])
        end
        index = last + 1
        return batch
    end
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
Town.transformedCFrame = transformedCFrame
Town.validSaveName = validSaveName

function Town.new(context)
    assert(context and context.store, "Town adapter requires a reactive store")

    local Players = context.players or game:GetService("Players")
    local Workspace = context.workspace or game:GetService("Workspace")
    local LocalPlayer = context.localPlayer or Players.LocalPlayer
    local wait = context.wait or task.wait
    local store = context.store

    local self = {
        busy = false,
        lastCreated = {},
        localPlayer = LocalPlayer,
        stopped = false,
    }
    local plotProgress = {
        active = false,
        phase = "Ready",
        progress = 0,
    }

    local function patchStatus(status, failure)
        store:Patch({
            error = failure and status or nil,
            status = status,
        })
    end

    local function publishProgress(progress, phase, active)
        plotProgress.active = active == true
        plotProgress.phase = phase
        plotProgress.progress = math.clamp(progress, 0, 1)
        store:Patch({
            plotCopy = {
                active = plotProgress.active,
                phase = plotProgress.phase,
                progress = plotProgress.progress,
            },
            status = phase,
        })
    end

    local function findTool()
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local character = LocalPlayer.Character
        return (backpack and backpack:FindFirstChild("Building Tools"))
            or (character and character:FindFirstChild("Building Tools"))
    end

    local function findCommandFunction()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local consoleGui = playerGui and playerGui:FindFirstChild("ChatConsoleGui")
        return consoleGui and consoleGui:FindFirstChild("CommandFunction")
    end

    local function prepareSaveGui()
        local playerGui = assert(
            LocalPlayer:FindFirstChildOfClass("PlayerGui"),
            "Town player GUI is unavailable"
        )
        local plotGui = playerGui:FindFirstChild("PlotGui")
        local openedForSave = false
        local commandTime
        if not plotGui then
            local commandFunction = assert(
                findCommandFunction(),
                "Town command function is unavailable"
            )
            commandFunction:InvokeServer("!savegui")
            commandTime = os.clock()
            local deadline = os.clock() + 5
            repeat
                plotGui = playerGui:FindFirstChild("PlotGui")
                if plotGui then
                    break
                end
                wait(0.05)
            until os.clock() >= deadline
            openedForSave = true
        end
        assert(plotGui, "Town save GUI did not open")
        if openedForSave then
            plotGui.Enabled = false
        end
        return plotGui, openedForSave, commandTime
    end

    local function savePlot(saveName, plotGui, openedForSave)
        if not plotGui then
            plotGui, openedForSave = prepareSaveGui()
        end
        local plotServer = assert(
            plotGui:FindFirstChild("PlotServer"),
            "Town save remote is unavailable"
        )
        local saveFolder = assert(
            plotGui:FindFirstChild("SaveFolder"),
            "Town save list is unavailable"
        )
        local previousEntry = saveFolder:FindFirstChild(saveName)
        local previousEdited = previousEntry
            and previousEntry:FindFirstChild("LastEdited")
            and previousEntry.LastEdited.Value
        local action = previousEntry and "save" or "create"
        plotServer:InvokeServer(action, saveName)

        local savedEntry
        local deadline = os.clock() + 5
        repeat
            savedEntry = saveFolder:FindFirstChild(saveName)
            local lastEdited = savedEntry and savedEntry:FindFirstChild("LastEdited")
            if savedEntry
                and (
                    not previousEntry
                    or savedEntry ~= previousEntry
                    or (lastEdited and lastEdited.Value ~= previousEdited)
                )
            then
                break
            end
            wait(0.05)
        until os.clock() >= deadline

        if openedForSave then
            plotGui:Destroy()
        end
        assert(savedEntry, ("Town did not confirm save '%s'"):format(saveName))
        if previousEntry then
            local lastEdited = savedEntry:FindFirstChild("LastEdited")
            assert(
                savedEntry ~= previousEntry
                    or (lastEdited and lastEdited.Value ~= previousEdited),
                ("Town did not confirm save '%s' was updated"):format(saveName)
            )
        end
    end

    local function waitForCooling(allowStopped)
        while allowStopped or not self.stopped do
            local cooling = LocalPlayer:FindFirstChild("BuildCooling")
            if not cooling then
                return true
            end
            local desiredTime = cooling:FindFirstChild("DesiredTime")
            local remaining = desiredTime and desiredTime.Value - Workspace:GetServerTimeNow() or 0.1
            if desiredTime and remaining <= 0 then
                return true
            end
            wait(math.clamp(remaining, 0.05, 0.5))
        end
        return false
    end

    local function compileWiring(targetPlot)
        local commandFunction = assert(
            findCommandFunction(),
            "Town command function is unavailable"
        )
        assert(waitForCooling(false), "Town plot copy stopped")
        commandFunction:InvokeServer("!wireconnections")

        local deadline = os.clock() + 15
        repeat
            if targetPlot:GetAttribute("Wired") == true then
                return
            end
            wait(0.1)
        until os.clock() >= deadline
        error("Town did not confirm wiring was applied")
    end

    local function invoke(syncAPI, action, ...)
        if not waitForCooling(false) then
            error("Town plot copy stopped")
        end
        local success, result = pcall(syncAPI.Invoke, syncAPI, action, ...)
        if not success then
            error(("%s failed: %s"):format(action, tostring(result)))
        end
        return result
    end

    local function invokeBatches(syncAPI, action, changes, onBatch)
        local completed = 0
        for batch in batches(changes, BATCH_SIZE) do
            invoke(syncAPI, action, batch)
            completed += #batch
            if onBatch then
                onBatch(completed, #changes)
            end
        end
    end

    local function removeCreated(syncAPI, created)
        if #created == 0 then
            return
        end
        for batch in batches(created, BATCH_SIZE) do
            pcall(function()
                if waitForCooling(true) then
                    syncAPI:Invoke("Remove", batch)
                end
            end)
        end
    end

    function self:listPlotOwners()
        local plotRoot = Workspace:FindFirstChild(PLOT_ROOT_NAME)
        if not plotRoot then
            return {}
        end
        return plotOwners(plotRoot:GetChildren(), LocalPlayer.Name .. "BuildArea")
    end

    function self:copyNearbyPlot(options)
        options = options or {}
        if self.busy then
            return false, "A Town plot copy is already running"
        end
        self.busy = true
        publishProgress(0, "Preparing plot copy", true)

        local tool = findTool()
        local syncAPI = tool and tool:FindFirstChild("SyncAPI")
        local plotRoot = Workspace:FindFirstChild(PLOT_ROOT_NAME)
        local localPlotName = LocalPlayer.Name .. "BuildArea"
        local targetPlot = plotRoot and plotRoot:FindFirstChild(localPlotName)
        local targetBuild = targetPlot and targetPlot:FindFirstChild("Build")
        local character = LocalPlayer.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")

        local function finish(success, message, result)
            self.busy = false
            if success then
                publishProgress(1, message, false)
                patchStatus(message, false)
            else
                publishProgress(plotProgress.progress, message, false)
                patchStatus(message, true)
            end
            return success, message, result
        end

        if not syncAPI or not syncAPI:IsA("BindableFunction") then
            return finish(false, "Use !btools before copying a Town plot")
        elseif not plotRoot or not targetPlot or not targetBuild then
            return finish(false, "Use !createplot before copying a Town plot")
        elseif #targetBuild:GetChildren() > 0 then
            return finish(false, "Your destination plot must be empty")
        elseif not options.ownerName and not rootPart then
            return finish(false, "Character position is unavailable")
        elseif options.save ~= false
            and options.saveName ~= nil
            and not validSaveName(options.saveName)
        then
            return finish(false, "Save name must be 1-32 letters, numbers, dashes, or underscores")
        end

        local sourcePlot
        if options.ownerName then
            sourcePlot = plotRoot:FindFirstChild(options.ownerName .. "BuildArea")
            if sourcePlot == targetPlot or not sourcePlot or not sourcePlot:IsA("BasePart") then
                sourcePlot = nil
            end
        else
            sourcePlot = selectNearestPlot(plotRoot:GetChildren(), localPlotName, rootPart.Position)
        end
        local sourceBuild = sourcePlot and sourcePlot:FindFirstChild("Build")
        if not sourceBuild then
            return finish(false, options.ownerName and "The selected player's plot is unavailable" or "No player plot was found")
        end
        local sourceWired = sourcePlot:GetAttribute("Wired") == true
        local copyWiring = sourceWired and options.limit == nil
        local normalizedCFrames = copyWiring
            and normalizedWiringCFrames(sourceBuild)
            or {}

        local descendants = sourceBuild:GetDescendants()
        local snapshots = {}
        local unsupported = 0
        for descendantIndex, descendant in ipairs(descendants) do
            if descendant:IsA("BasePart") then
                local snapshot = snapshotPart(
                    descendant,
                    sourcePlot,
                    targetPlot,
                    normalizedCFrames[descendant]
                )
                if snapshot.Type then
                    table.insert(snapshots, snapshot)
                else
                    unsupported += 1
                end
            end
            if descendantIndex % 100 == 0 or descendantIndex == #descendants then
                publishProgress(
                    #descendants > 0 and 0.08 * descendantIndex / #descendants or 0.08,
                    ("Reading %s's plot"):format(plotOwnerName(sourcePlot.Name) or "player"),
                    true
                )
            end
        end
        local maximum = math.min(options.maxParts or MAX_PARTS, MAX_PARTS)
        if #snapshots == 0 then
            return finish(false, "The nearby plot has no supported parts")
        elseif #snapshots > maximum then
            return finish(
                false,
                ("Plot has %d supported parts; limit is %d"):format(#snapshots, maximum)
            )
        end
        if type(options.limit) == "number" and options.limit < #snapshots then
            for index = #snapshots, math.max(math.floor(options.limit), 0) + 1, -1 do
                table.remove(snapshots, index)
            end
        end
        if #snapshots == 0 then
            return finish(false, "The requested Town copy sample is empty")
        end

        local supportedSources = {}
        for _, snapshot in ipairs(snapshots) do
            supportedSources[snapshot.Source] = true
        end
        local modelSnapshots = snapshotModels(sourceBuild, supportedSources)
        if copyWiring and #modelSnapshots == 0 then
            return finish(false, "The selected plot's wiring groups are unavailable")
        end

        local created = {}
        local mappings = {}
        local preparedPlotGui
        local openedForSave
        local saveCommandTime
        local success, failure = pcall(function()
            if options.save ~= false then
                publishProgress(0.08, "Preparing autosave", true)
                preparedPlotGui, openedForSave, saveCommandTime = prepareSaveGui()
            end

            local snapshotsByType = {}
            local typeOrder = {}
            for _, snapshot in ipairs(snapshots) do
                if not snapshotsByType[snapshot.Type] then
                    snapshotsByType[snapshot.Type] = {}
                    table.insert(typeOrder, snapshot.Type)
                end
                table.insert(snapshotsByType[snapshot.Type], snapshot)
            end

            local function reportCreated()
                publishProgress(
                    0.08 + 0.48 * #created / #snapshots,
                    ("Building parts %d/%d"):format(#created, #snapshots),
                    true
                )
            end

            for _, snapshotType in ipairs(typeOrder) do
                local typeSnapshots = snapshotsByType[snapshotType]
                local seedSnapshot = typeSnapshots[1]
                local seedPart
                for _ = 1, 3 do
                    seedPart = invoke(
                        syncAPI,
                        "CreatePart",
                        snapshotType,
                        seedSnapshot.CFrame,
                        targetBuild
                    )
                    if seedPart then
                        break
                    end
                    wait(0.1)
                end
                assert(seedPart, ("F3X refused the %s seed part"):format(snapshotType))

                local typeParts = { seedPart }
                table.insert(created, seedPart)
                reportCreated()
                while #typeParts < #typeSnapshots do
                    local cloneCount = math.min(
                        #typeSnapshots - #typeParts,
                        #typeParts,
                        CLONE_BATCH_SIZE
                    )
                    local cloneSources = {}
                    for index = 1, cloneCount do
                        table.insert(cloneSources, typeParts[index])
                    end
                    local clones = invoke(syncAPI, "Clone", cloneSources, targetBuild)
                    assert(
                        type(clones) == "table" and #clones == cloneCount,
                        ("F3X refused %s part clones"):format(snapshotType)
                    )
                    for _, clone in ipairs(clones) do
                        table.insert(typeParts, clone)
                        table.insert(created, clone)
                    end
                    reportCreated()
                end
                for index, part in ipairs(typeParts) do
                    table.insert(mappings, {
                        Part = part,
                        Snapshot = typeSnapshots[index],
                    })
                end
            end

            local destinationBySource = {}
            for _, mapping in ipairs(mappings) do
                destinationBySource[mapping.Snapshot.Source] = mapping.Part
            end

            local resize = {}
            local color = {}
            local material = {}
            local anchor = {}
            local collision = {}
            local surfaces = {}
            local meshCreate = {}
            local meshSync = {}
            local textureCreate = {}
            local textureSync = {}
            local lightCreate = {}
            local lightSync = {}
            for _, mapping in ipairs(mappings) do
                local part = mapping.Part
                local snapshot = mapping.Snapshot
                table.insert(resize, {
                    Part = part,
                    Size = snapshot.Size,
                    CFrame = snapshot.CFrame,
                })
                if part.Color ~= snapshot.Color then
                    table.insert(color, {
                        Part = part,
                        Color = snapshot.Color,
                        UnionColoring = true,
                    })
                end
                if part.Material ~= snapshot.Material
                    or part.Reflectance ~= snapshot.Reflectance
                    or part.Transparency ~= snapshot.Transparency
                then
                    table.insert(material, {
                        Part = part,
                        Material = snapshot.Material,
                        Reflectance = snapshot.Reflectance,
                        Transparency = snapshot.Transparency,
                    })
                end
                if not part.Anchored then
                    table.insert(anchor, { Part = part, Anchored = true })
                end
                if part.CanCollide ~= snapshot.CanCollide then
                    table.insert(collision, { Part = part, CanCollide = snapshot.CanCollide })
                end
                local surfacesMatch = true
                for propertyName, value in pairs(snapshot.Surfaces) do
                    if part[propertyName] ~= value then
                        surfacesMatch = false
                        break
                    end
                end
                if not surfacesMatch then
                    table.insert(surfaces, { Part = part, Surfaces = snapshot.Surfaces })
                end
                if snapshot.Mesh then
                    table.insert(meshCreate, { Part = part })
                    table.insert(meshSync, {
                        Part = part,
                        MeshId = snapshot.Mesh.MeshId,
                        MeshType = snapshot.Mesh.MeshType,
                        Offset = snapshot.Mesh.Offset,
                        Scale = snapshot.Mesh.Scale,
                        TextureId = snapshot.Mesh.TextureId,
                        VertexColor = snapshot.Mesh.VertexColor,
                    })
                end
                for _, texture in ipairs(snapshot.Textures) do
                    table.insert(textureCreate, {
                        Part = part,
                        Face = texture.Face,
                        TextureType = texture.TextureType,
                    })
                    table.insert(textureSync, {
                        OffsetStudsU = texture.OffsetStudsU,
                        OffsetStudsV = texture.OffsetStudsV,
                        Part = part,
                        Face = texture.Face,
                        StudsPerTileU = texture.StudsPerTileU,
                        StudsPerTileV = texture.StudsPerTileV,
                        Texture = texture.Texture,
                        TextureType = texture.TextureType,
                        Transparency = texture.Transparency,
                    })
                end
                for _, light in ipairs(snapshot.Lights) do
                    if light.Enabled then
                        table.insert(lightCreate, {
                            LightType = light.LightType,
                            Part = part,
                        })
                        table.insert(lightSync, {
                            Angle = light.Angle,
                            Brightness = light.Brightness,
                            Color = light.Color,
                            Face = light.Face,
                            LightType = light.LightType,
                            Part = part,
                            Range = light.Range,
                            Shadows = light.Shadows,
                        })
                    end
                end
            end

            local function stageBatches(action, changes, phase, fromProgress, toProgress)
                publishProgress(fromProgress, phase, true)
                invokeBatches(syncAPI, action, changes, function(completed, total)
                    publishProgress(
                        fromProgress + (toProgress - fromProgress) * completed / total,
                        ("%s %d/%d"):format(phase, completed, total),
                        true
                    )
                end)
            end

            stageBatches("SyncResize", resize, "Shaping geometry", 0.56, 0.65)
            stageBatches("SyncColor", color, "Painting colors", 0.65, 0.71)
            stageBatches("SyncMaterial", material, "Applying materials", 0.71, 0.77)
            stageBatches("SyncSurface", surfaces, "Finishing surfaces", 0.77, 0.82)
            if #meshCreate > 0 then
                stageBatches("CreateMeshes", meshCreate, "Creating mesh details", 0.82, 0.84)
                stageBatches("SyncMesh", meshSync, "Applying mesh details", 0.84, 0.87)
            else
                publishProgress(0.87, "No mesh details needed", true)
            end

            local textureCount = #textureCreate
            if textureCount > 0 then
                stageBatches(
                    "CreateTextures",
                    textureCreate,
                    "Creating textures",
                    0.87,
                    0.895
                )
                stageBatches(
                    "SyncTexture",
                    textureSync,
                    "Applying textures",
                    0.895,
                    0.92
                )
            else
                publishProgress(0.92, "No textures needed", true)
            end

            local lightCount = #lightCreate
            if lightCount > 0 then
                stageBatches(
                    "CreateLights",
                    lightCreate,
                    "Creating lights",
                    0.92,
                    0.935
                )
                stageBatches(
                    "SyncLighting",
                    lightSync,
                    "Configuring lights",
                    0.935,
                    0.95
                )
            else
                publishProgress(0.95, "No lights needed", true)
            end

            stageBatches("SyncCollision", collision, "Setting collisions", 0.95, 0.96)
            stageBatches("SyncAnchor", anchor, "Securing parts", 0.96, 0.97)

            local destinationModels = {}
            local groupCount = 0
            for modelIndex, modelSnapshot in ipairs(modelSnapshots) do
                local selection = {}
                for _, sourcePart in ipairs(modelSnapshot.Parts) do
                    local destinationPart = destinationBySource[sourcePart]
                    if destinationPart then
                        table.insert(selection, destinationPart)
                    end
                end
                for _, sourceModel in ipairs(modelSnapshot.Models) do
                    local destinationModel = destinationModels[sourceModel]
                    if destinationModel then
                        table.insert(selection, destinationModel)
                    end
                end

                if #selection > 0 then
                    local group = invoke(syncAPI, "CreateGroup", "Model", targetBuild, selection)
                    assert(group, "F3X refused a source plot group")
                    destinationModels[modelSnapshot.Source] = group
                    groupCount += 1
                    if not copyWiring and modelSnapshot.Name ~= "Model" then
                        invoke(syncAPI, "SetName", { group }, modelSnapshot.Name)
                    end
                end
                publishProgress(
                    0.97 + 0.015 * modelIndex / math.max(#modelSnapshots, 1),
                    ("Building wiring groups %d/%d"):format(modelIndex, #modelSnapshots),
                    true
                )
            end

            if copyWiring then
                local commandDelay = saveCommandTime
                    and COMMAND_COOLDOWN_SECONDS - (os.clock() - saveCommandTime)
                    or 0
                if commandDelay > 0 then
                    publishProgress(0.985, "Waiting for Town wiring", true)
                    wait(commandDelay)
                end
                publishProgress(0.985, "Compiling wiring", true)
                compileWiring(targetPlot)
                publishProgress(0.99, "Wiring replicated", true)
            else
                publishProgress(0.99, "Plot groups ready", true)
            end

            local saveName
            if options.save ~= false then
                local ownerName = (plotOwnerName(sourcePlot.Name) or "plot"):gsub("[^%w_%-]", "_")
                saveName = options.saveName or ("copy_%s_%d"):format(ownerName, os.time())
                publishProgress(0.995, "Saving " .. saveName, true)
                savePlot(saveName, preparedPlotGui, openedForSave)
            end
            self.lastCreated = created
            return {
                created = #created,
                saveName = saveName,
                source = sourcePlot.Name:gsub("BuildArea$", ""),
                lights = lightCount,
                groups = groupCount,
                textures = textureCount,
                unsupported = unsupported,
                wired = copyWiring,
            }
        end)

        if not success then
            if openedForSave and preparedPlotGui and preparedPlotGui.Parent then
                preparedPlotGui:Destroy()
            end
            removeCreated(syncAPI, created)
            self.lastCreated = {}
            return finish(false, "Town plot copy failed: " .. tostring(failure))
        end

        local result = failure
        local message = ("Copied %d parts from %s"):format(result.created, result.source)
        if result.saveName then
            message = message .. " and saved " .. result.saveName
        end
        if result.unsupported > 0 then
            message = message .. (" (%d unsupported parts skipped)"):format(result.unsupported)
        end
        if result.wired then
            message = message .. (" with %d wired groups"):format(result.groups)
        end
        return finish(true, message, result)
    end

    function self:copyPlot(ownerName, saveName, options)
        local copyOptions = {}
        for key, value in pairs(options or {}) do
            copyOptions[key] = value
        end
        copyOptions.ownerName = ownerName
        copyOptions.saveName = saveName
        return self:copyNearbyPlot(copyOptions)
    end

    function self:stop()
        if self.stopped then
            return
        end
        self.stopped = true
    end

    return self
end

return Town
