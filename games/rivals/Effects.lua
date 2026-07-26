local Effects = {}
Effects.__index = Effects

local THROWABLE_MAX_DISTANCE = 2000
local THROWABLE_REFRESH_INTERVAL = 0.2
local THROWABLE_TAGS = {
    "Grenade",
    "Throwable",
    "Projectile",
    "SubspaceTripmine",
    "JumpPadHitbox",
}
local THROWABLE_CONTAINERS = { "Projectiles", "Throwables", "Debris", "Effects" }

local THROWABLE_ATTRIBUTES = {
    "DisplayName",
    "GrenadeName",
    "ItemName",
    "ProjectileName",
    "ThrowableName",
    "ViewModelName",
    "WeaponName",
}
local THROWABLE_DESCRIPTORS = {
    {
        tokens = { "subspace tripmine", "tripmine" },
        label = "TRIPMINE",
        markerStyle = "wireframeCube",
        tone = "danger",
    },
    { tokens = { "jump pad", "jumppad" }, label = "JUMP PAD", tone = "accent" },
    { tokens = { "smoke" }, label = "SMOKE", tone = "smoke" },
    { tokens = { "flash" }, label = "FLASH", tone = "accent" },
    { tokens = { "molotov", "incendiary", "fire bomb" }, label = "MOLOTOV", tone = "danger" },
    { tokens = { "satchel" }, label = "SATCHEL", tone = "danger" },
    { tokens = { "warpstone" }, label = "WARPSTONE", tone = "accent" },
    { tokens = { "elixir" }, label = "ELIXIR", tone = "accent" },
    { tokens = { "grenade", "frag" }, label = "GRENADE", tone = "danger" },
    { tokens = { "dynamite" }, label = "DYNAMITE", tone = "danger" },
}
local THROWABLE_TAG_DESCRIPTORS = {
    JumpPadHitbox = { label = "JUMP PAD", tone = "accent" },
    SubspaceTripmine = {
        label = "TRIPMINE",
        markerStyle = "wireframeCube",
        tone = "danger",
    },
}
local WIREFRAME_CUBE_OFFSETS = {
    Vector3.new(-0.5, -0.5, -0.5),
    Vector3.new(0.5, -0.5, -0.5),
    Vector3.new(0.5, 0.5, -0.5),
    Vector3.new(-0.5, 0.5, -0.5),
    Vector3.new(-0.5, -0.5, 0.5),
    Vector3.new(0.5, -0.5, 0.5),
    Vector3.new(0.5, 0.5, 0.5),
    Vector3.new(-0.5, 0.5, 0.5),
}
local VISUAL_EFFECT_CLASSES = {
    Beam = true,
    BlurEffect = true,
    ColorCorrectionEffect = true,
    DepthOfFieldEffect = true,
    Frame = true,
    ImageLabel = true,
    ParticleEmitter = true,
    Smoke = true,
}

local function taggedThrowableDescriptor(instance)
    for tag, descriptor in pairs(THROWABLE_TAG_DESCRIPTORS) do
        local hasTag = false
        if instance.HasTag then
            local succeeded, tagged = pcall(instance.HasTag, instance, tag)
            hasTag = succeeded and tagged == true
        elseif instance.GetTags then
            local succeeded, tags = pcall(instance.GetTags, instance)
            hasTag = succeeded and table.find(tags, tag) ~= nil
        end
        if hasTag then
            return descriptor
        end
    end
    return nil
end

local function throwableDescriptor(instance)
    local current = instance
    for _depth = 1, 3 do
        if not current then
            break
        end

        local taggedDescriptor = taggedThrowableDescriptor(current)
        if taggedDescriptor then
            return taggedDescriptor, current
        end
        local values = { current.Name }
        if current.GetAttribute then
            for _, attribute in ipairs(THROWABLE_ATTRIBUTES) do
                table.insert(values, current:GetAttribute(attribute))
            end
        end
        for _, value in ipairs(values) do
            if type(value) == "string" then
                local normalized = string.lower(value)
                for _, descriptor in ipairs(THROWABLE_DESCRIPTORS) do
                    for _, token in ipairs(descriptor.tokens) do
                        if string.find(normalized, token, 1, true) then
                            return descriptor, current
                        end
                    end
                end
            end
        end
        current = current.Parent
    end
    return nil
end

local function hierarchyAttribute(instance, name)
    local current = instance
    for _depth = 1, 32 do
        if not current then
            break
        end
        if current.GetAttribute then
            local succeeded, value = pcall(current.GetAttribute, current, name)
            if succeeded and value ~= nil then
                return value
            end
        end
        current = current.Parent
    end
    return nil
end

local function isWorldUtility(root, camera, worldRoot, localPlayer)
    local current = root
    local reachedWorld = worldRoot == nil
    local localCharacter = localPlayer and localPlayer.Character
    for _depth = 1, 32 do
        if not current then
            break
        end
        if current == worldRoot then
            reachedWorld = true
        end
        if current == camera or current == localCharacter then
            return false
        end
        local normalizedName = string.lower(current.Name or "")
        if normalizedName == "viewmodel"
            or normalizedName == "viewmodels"
            or normalizedName == "firstperson"
        then
            return false
        end
        if current.IsA then
            local succeeded, isCamera = pcall(current.IsA, current, "Camera")
            if succeeded and isCamera then
                return false
            end
        end
        current = current.Parent
    end
    return reachedWorld
end

local function projectWireframeCube(camera, boundsFrame, boundsSize)
    if not boundsFrame or not boundsSize then
        return nil
    end

    local corners = {}
    local minimumX = math.huge
    local minimumY = math.huge
    local maximumX = -math.huge
    local anyOnScreen = false
    for _, offset in ipairs(WIREFRAME_CUBE_OFFSETS) do
        local worldPosition = boundsFrame:PointToWorldSpace(Vector3.new(
            offset.X * boundsSize.X,
            offset.Y * boundsSize.Y,
            offset.Z * boundsSize.Z
        ))
        local point, onScreen = camera:WorldToViewportPoint(worldPosition)
        if point.Z <= 0 then
            return nil
        end
        local corner = Vector2.new(point.X, point.Y)
        table.insert(corners, corner)
        minimumX = math.min(minimumX, corner.X)
        minimumY = math.min(minimumY, corner.Y)
        maximumX = math.max(maximumX, corner.X)
        anyOnScreen = anyOnScreen or onScreen == true
    end
    return corners, Vector2.new((minimumX + maximumX) * 0.5, minimumY - 16), anyOnScreen
end

local function effectKind(instance)
    local name = string.lower(instance.Name or "")
    if string.find(name, "flash", 1, true)
        or string.find(name, "blind", 1, true)
        or string.find(name, "stun", 1, true)
    then
        return "flash"
    end
    if string.find(name, "smoke", 1, true) then
        return "smoke"
    end
    return nil
end

local function effectStateProperty(instance)
    local supported = false
    if instance.IsA then
        for className in pairs(VISUAL_EFFECT_CLASSES) do
            if instance:IsA(className) then
                supported = true
                break
            end
        end
    end
    if not supported then
        return nil
    end

    local enabledOk, enabled = pcall(function()
        return instance.Enabled
    end)
    if enabledOk and type(enabled) == "boolean" then
        return "Enabled", enabled
    end
    local visibleOk, visible = pcall(function()
        return instance.Visible
    end)
    if visibleOk and type(visible) == "boolean" then
        return "Visible", visible
    end
    return nil
end

function Effects.updateVisualSuppressions(settings, roots, suppressed)
    local active = {}
    for _, entry in ipairs(roots or {}) do
        local root = entry.instance or entry
        local inheritedKind = entry.kind
        local instances = { root }
        if root and root.GetDescendants then
            for _, descendant in ipairs(root:GetDescendants()) do
                table.insert(instances, descendant)
            end
        end
        for _, instance in ipairs(instances) do
            local kind = effectKind(instance) or inheritedKind
            local shouldSuppress = kind == "flash" and settings.noFlash == true
                or kind == "smoke" and settings.noSmoke == true
            if shouldSuppress then
                local property, value = effectStateProperty(instance)
                if property then
                    active[instance] = true
                    if suppressed[instance] == nil then
                        suppressed[instance] = {
                            property = property,
                            value = value,
                        }
                    end
                    pcall(function()
                        instance[property] = false
                    end)
                end
            end
        end
    end

    for instance, state in pairs(suppressed) do
        if not active[instance] then
            pcall(function()
                instance[state.property] = state.value
            end)
            suppressed[instance] = nil
        end
    end
end

function Effects.throwableObservation(camera, candidate, environmentID, worldRoot, localPlayer)
    local descriptor, root = throwableDescriptor(candidate)
    if not descriptor or not camera or not root then
        return nil
    end
    if root.Parent == nil and candidate.Parent == nil then
        return nil
    end
    if not isWorldUtility(root, camera, worldRoot, localPlayer) then
        return nil
    end

    local finished = hierarchyAttribute(root, "SimulationFinished") == true
        or hierarchyAttribute(root, "Exploded") == true
        or hierarchyAttribute(root, "Detonated") == true
    if finished then
        return nil
    end
    local observedEnvironment = hierarchyAttribute(root, "EnvironmentID")
    if environmentID ~= nil and observedEnvironment ~= nil and observedEnvironment ~= environmentID then
        return nil
    end

    local part
    if candidate.IsA and candidate:IsA("BasePart") then
        part = candidate
    elseif root.IsA and root:IsA("BasePart") then
        part = root
    else
        part = root.PrimaryPart
            or (root.FindFirstChildWhichIsA and root:FindFirstChildWhichIsA("BasePart", true))
    end
    if not part or not part.Position then
        return nil
    end

    local cameraPosition = camera.CFrame and camera.CFrame.Position
    if cameraPosition and (part.Position - cameraPosition).Magnitude > THROWABLE_MAX_DISTANCE then
        return nil
    end
    local point, onScreen = camera:WorldToViewportPoint(part.Position)
    local markerStyle
    local wireframeCorners
    local labelPosition
    local wireframeOnScreen = false
    if descriptor.markerStyle == "wireframeCube" then
        local boundsFrame
        local boundsSize
        if root.GetBoundingBox then
            local succeeded
            succeeded, boundsFrame, boundsSize = pcall(root.GetBoundingBox, root)
            if not succeeded then
                boundsFrame = nil
                boundsSize = nil
            end
        end
        boundsFrame = boundsFrame or part.CFrame
        boundsSize = boundsSize or part.Size
        wireframeCorners, labelPosition, wireframeOnScreen =
            projectWireframeCube(camera, boundsFrame, boundsSize)
        if wireframeCorners then
            markerStyle = descriptor.markerStyle
        end
    end
    return {
        key = root,
        label = descriptor.label,
        labelPosition = labelPosition,
        markerStyle = markerStyle,
        onScreen = point.Z > 0 and (onScreen == true or wireframeOnScreen),
        polygons = {},
        screenPosition = Vector2.new(point.X, point.Y),
        tone = descriptor.tone,
        wireframeCorners = wireframeCorners,
    }
end

function Effects.new(options)
    assert(options and options.workspace, "RIVALS effects require Workspace")
    assert(options.localPlayer, "RIVALS effects require LocalPlayer")
    assert(options.projectileAim, "RIVALS effects require projectile aim")

    local trajectorySurface
    local drawing = options.drawing
    if drawing and drawing.supports("Line") then
        trajectorySurface = drawing.createSurface()
    end

    return setmetatable({
        clock = options.clock or os.clock,
        collectionService = options.collectionService,
        lighting = options.lighting,
        localPlayer = options.localPlayer,
        nextThrowableRefreshAt = 0,
        nextVisualRefreshAt = 0,
        playerGui = options.playerGui,
        projectileAim = options.projectileAim,
        suppressedVisuals = setmetatable({}, { __mode = "k" }),
        throwableCandidates = {},
        trajectoryLines = {},
        trajectorySurface = trajectorySurface,
        workspace = options.workspace,
    }, Effects)
end

function Effects:_collectThrowables()
    local candidates = {}
    local seen = {}
    local function collect(values)
        for _, value in ipairs(values or {}) do
            if value and not seen[value] then
                seen[value] = true
                table.insert(candidates, value)
            end
        end
    end

    if self.collectionService and self.collectionService.GetTagged then
        for _, tag in ipairs(THROWABLE_TAGS) do
            local succeeded, tagged =
                pcall(self.collectionService.GetTagged, self.collectionService, tag)
            if succeeded then
                collect(tagged)
            end
        end
    end
    for _, name in ipairs(THROWABLE_CONTAINERS) do
        local container = self.workspace:FindFirstChild(name)
        if container and container.GetChildren then
            collect(container:GetChildren())
        end
    end
    return candidates
end

function Effects:smokeRaycastIgnore()
    if not self.collectionService or not self.collectionService.GetTagged then
        return {}
    end
    local succeeded, smokeClouds =
        pcall(self.collectionService.GetTagged, self.collectionService, "SmokeCloud")
    return succeeded and smokeClouds or {}
end

function Effects:observeThrowables(camera, environmentID)
    local now = self.clock()
    if now >= self.nextThrowableRefreshAt then
        self.throwableCandidates = self:_collectThrowables()
        self.nextThrowableRefreshAt = now + THROWABLE_REFRESH_INTERVAL
    end

    local utilities = {}
    for _, candidate in ipairs(self.throwableCandidates) do
        local observation = Effects.throwableObservation(
            camera,
            candidate,
            environmentID,
            self.workspace,
            self.localPlayer
        )
        if observation then
            table.insert(utilities, observation)
        end
    end
    return utilities
end

function Effects:update(settings)
    local now = self.clock()
    if now < self.nextVisualRefreshAt then
        return
    end
    self.nextVisualRefreshAt = now + 0.1

    local roots = { self.lighting, self.workspace.CurrentCamera }
    local playerGui = self.playerGui
    if not playerGui and self.localPlayer.FindFirstChildOfClass then
        playerGui = self.localPlayer:FindFirstChildOfClass("PlayerGui")
    end
    if playerGui then
        table.insert(roots, playerGui)
    end
    if settings.noSmoke then
        for _, candidate in ipairs(self.throwableCandidates) do
            local descriptor, root = throwableDescriptor(candidate)
            if descriptor and descriptor.tone == "smoke" then
                table.insert(roots, {
                    instance = root,
                    kind = "smoke",
                })
            end
        end
    end
    Effects.updateVisualSuppressions(settings, roots, self.suppressedVisuals)
end

function Effects:renderTrajectory(path)
    if not self.trajectorySurface then
        return
    end

    local camera = self.workspace.CurrentCamera
    local segments = camera and path
            and self.projectileAim.projectTrajectory(camera, path)
        or {}
    for index, segment in ipairs(segments) do
        local line = self.trajectoryLines[index]
        if not line then
            line = self.trajectorySurface:create("Line", {}, { pointerEvents = false })
            self.trajectoryLines[index] = line
        end
        line:set({
            Color = Color3.fromRGB(92, 214, 255),
            From = segment.from,
            Thickness = 2,
            To = segment.to,
            Transparency = 0.9,
            Visible = true,
            ZIndex = 20,
        })
    end
    for index = #segments + 1, #self.trajectoryLines do
        self.trajectoryLines[index]:set({ Visible = false })
    end
end

function Effects:stop()
    Effects.updateVisualSuppressions({}, {}, self.suppressedVisuals)
    if self.trajectorySurface then
        self.trajectorySurface:destroy()
        self.trajectorySurface = nil
    end
end

return Effects
