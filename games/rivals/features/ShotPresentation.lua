local ShotPresentation = {}
ShotPresentation.__index = ShotPresentation

local function maskedFrame(targetFrame, visibleFrame)
    return CFrame.new(targetFrame.Position) * visibleFrame.Rotation
end

local function frameFromRotation(position, rotation)
    return CFrame.new(position)
        * CFrame.Angles(0, rotation.Y, 0)
        * CFrame.Angles(rotation.X, 0, 0)
end

function ShotPresentation.new(options)
    assert(options and options.cameraController, "RIVALS Shot Aim requires CameraController")
    assert(options.runService, "RIVALS Shot Aim requires RunService")
    assert(options.workspace, "RIVALS Shot Aim requires Workspace")
    assert(options.getFighter, "RIVALS Shot Aim requires a fighter getter")
    assert(options.hookFunction, "RIVALS Shot Aim requires hookfunction")
    assert(options.restoreFunction, "RIVALS Shot Aim requires restorefunction")

    local self = setmetatable({
        cameraController = options.cameraController,
        cameraDataOriginal = nil,
        cameraDataTarget = nil,
        flickRotation = nil,
        frameRotation = nil,
        getFighter = options.getFighter,
        hookFunction = options.hookFunction,
        isEnabled = options.isEnabled or function()
            return false
        end,
        isInputCaptured = options.isInputCaptured or function()
            return false
        end,
        logicalTarget = nil,
        logicalRotation = nil,
        maskedFrame = nil,
        onCameraData = options.onCameraData or function() end,
        pendingTarget = nil,
        pendingRotation = nil,
        passthrough = false,
        presentedTarget = nil,
        restoreFunction = options.restoreFunction,
        runService = options.runService,
        shouldObserve = options.shouldObserve or options.isEnabled or function()
            return false
        end,
        stopped = false,
        targetFrame = nil,
        visibleCamera = nil,
        visibleFrame = nil,
        visibleRotation = nil,
        workspace = options.workspace,
    }, ShotPresentation)
    local bindingSuffix = tostring(self):gsub("[^%w]", "")
    self.postBinding = "UniversalHubShotPresentationPost" .. bindingSuffix
    self.preBinding = "UniversalHubShotPresentationPre" .. bindingSuffix

    self.cameraPriority = options.cameraPriority or Enum.RenderPriority.Camera.Value
    return self
end

function ShotPresentation:_startRuntime()
    if self.runtimeActive or self.stopped then
        return
    end
    self.runtimeActive = true
    local rotationDeltaSignal = self.cameraController.RotationDeltaApplied
    if rotationDeltaSignal and type(rotationDeltaSignal.Connect) == "function" then
        self.rotationDeltaConnection = rotationDeltaSignal:Connect(function(delta)
            self:_applyVisibleRotationDelta(delta)
        end)
    end
    self.runService:BindToRenderStep(self.preBinding, self.cameraPriority - 1, function()
        self:_prepareFrame()
    end)
    self.runService:BindToRenderStep(self.postBinding, self.cameraPriority + 1, function()
        self:_maskFrame()
    end)
end

function ShotPresentation:_stopRuntime()
    if not self.runtimeActive then
        return
    end
    self.runtimeActive = false
    if self.rotationDeltaConnection then
        self.rotationDeltaConnection:Disconnect()
        self.rotationDeltaConnection = nil
    end
    self.runService:UnbindFromRenderStep(self.preBinding)
    self.runService:UnbindFromRenderStep(self.postBinding)
    self:clear()
end

function ShotPresentation:_reset()
    self.flickRotation = nil
    self.frameRotation = nil
    self.logicalTarget = nil
    self.logicalRotation = nil
    self.maskedFrame = nil
    self.pendingTarget = nil
    self.pendingRotation = nil
    self.presentedTarget = nil
    self.targetFrame = nil
    self.visibleCamera = nil
    self.visibleFrame = nil
    self.visibleRotation = nil
end

function ShotPresentation:clear()
    if self.visibleRotation then
        self.cameraController:SetRotation(self.visibleRotation)
    end
    local camera = self.workspace.CurrentCamera
    if camera and camera == self.visibleCamera and self.maskedFrame then
        camera.CFrame = self.maskedFrame
    end
    self:_reset()
end

function ShotPresentation:setPassthrough(enabled)
    enabled = enabled == true
    if enabled == self.passthrough then
        return
    end
    self.passthrough = enabled
    if enabled then
        self:clear()
    end
end

function ShotPresentation:update(rotation, target)
    if self.stopped or self.passthrough or typeof(rotation) ~= "Vector2" then
        self:clear()
        return false
    end

    local camera = self.workspace.CurrentCamera
    if not camera then
        self:clear()
        return false
    end
    if self.visibleCamera and self.visibleCamera ~= camera then
        self:clear()
    end
    if not self.visibleFrame then
        self.visibleCamera = camera
        self.visibleFrame = camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame
        self.visibleRotation = self.cameraController.Rotation
    end
    self.pendingTarget = target
    self.pendingRotation = rotation
    return true
end

function ShotPresentation:stageFlick(rotation)
    if self.stopped or self.passthrough or typeof(rotation) ~= "Vector2" then
        self.flickRotation = nil
        return false
    end
    self.flickRotation = rotation
    return true
end

function ShotPresentation:getPresentedTarget()
    return self.targetFrame and self.frameRotation and self.presentedTarget or nil
end

function ShotPresentation:_prepareFrame()
    if self.stopped or self.passthrough or not self.pendingRotation then
        return
    end
    self.logicalTarget = self.pendingTarget
    self.logicalRotation = self.pendingRotation
    self.cameraController:SetRotation(self.logicalRotation)
end

function ShotPresentation:_maskFrame()
    if
        self.stopped
        or self.passthrough
        or not self.logicalRotation
        or not self.visibleFrame
        or not self.visibleRotation
    then
        return
    end
    local camera = self.workspace.CurrentCamera
    if not camera or camera ~= self.visibleCamera then
        self:clear()
        return
    end
    self.targetFrame = camera.CFrame
    self.frameRotation = self.logicalRotation
    self.presentedTarget = self.logicalTarget
    self.maskedFrame = maskedFrame(self.targetFrame, self.visibleFrame)
    camera.CFrame = self.maskedFrame
    self.cameraController:SetRotation(self.logicalRotation)
end

function ShotPresentation:_applyVisibleRotationDelta(delta)
    if
        self.stopped
        or not self.visibleFrame
        or not self.visibleRotation
        or typeof(delta) ~= "Vector2"
    then
        return
    end

    local previousRotation = self.visibleRotation
    local visible = previousRotation + delta
    local nextRotation =
        Vector2.new(math.clamp(visible.X, -1.5690509975429023, 1.5690509975429023), visible.Y)
    local previousBase = CFrame.Angles(0, previousRotation.Y, 0)
        * CFrame.Angles(previousRotation.X, 0, 0)
    local nextBase = CFrame.Angles(0, nextRotation.Y, 0) * CFrame.Angles(nextRotation.X, 0, 0)
    self.visibleFrame = CFrame.new(self.visibleFrame.Position)
        * nextBase
        * previousBase:ToObjectSpace(self.visibleFrame.Rotation)
    self.visibleRotation = nextRotation
    if self.logicalRotation then
        self.cameraController:SetRotation(self.logicalRotation)
    end
end

function ShotPresentation:refreshHook()
    if self.stopped then
        return
    end
    local enabled = self.isEnabled()
    local observing = self.shouldObserve()
    if enabled then
        self:_startRuntime()
    else
        self:_stopRuntime()
    end
    if not enabled and not observing then
        if self.cameraDataTarget then
            self.restoreFunction(self.cameraDataTarget)
            self.cameraDataOriginal = nil
            self.cameraDataTarget = nil
        end
        return
    end

    local fighter = self.getFighter()
    local target = fighter and fighter.GetCameraData
    if target == self.cameraDataTarget then
        return
    end
    if self.cameraDataTarget then
        self.restoreFunction(self.cameraDataTarget)
    end
    self.cameraDataOriginal = nil
    self.cameraDataTarget = nil
    if type(target) ~= "function" then
        return
    end

    self.cameraDataTarget = target
    local original
    original = self.hookFunction(target, function(fighterSelf, ...)
        if
            self.stopped
            or self.passthrough
            or fighterSelf ~= self.getFighter()
            or self.isInputCaptured()
        then
            return original(fighterSelf, ...)
        end

        local enabledNow = self.isEnabled()
        local observingNow = self.shouldObserve()
        if not enabledNow then
            local flickRotation = self.flickRotation
            local camera = self.workspace.CurrentCamera
            if observingNow and flickRotation and camera then
                self.cameraController:SetRotation(flickRotation)
                camera.CFrame = frameFromRotation(camera.CFrame.Position, flickRotation)
            end
            self.flickRotation = nil
            local returned = table.pack(original(fighterSelf, ...))
            if observingNow then
                self.onCameraData()
            end
            return table.unpack(returned, 1, returned.n)
        end

        local camera = self.workspace.CurrentCamera
        if
            not camera
            or camera ~= self.visibleCamera
            or not self.targetFrame
            or not self.frameRotation
        then
            local returned = table.pack(original(fighterSelf, ...))
            if observingNow then
                self.onCameraData()
            end
            return table.unpack(returned, 1, returned.n)
        end

        local localMaskedFrame = camera.CFrame
        camera.CFrame = self.targetFrame
        self.cameraController:SetRotation(self.frameRotation)
        local returned = table.pack(original(fighterSelf, ...))
        camera.CFrame = localMaskedFrame
        self.cameraController:SetRotation(self.frameRotation)
        if observingNow then
            self.onCameraData()
        end
        return table.unpack(returned, 1, returned.n)
    end)
    self.cameraDataOriginal = original
end

function ShotPresentation:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:_stopRuntime()
    self:clear()
    if self.cameraDataTarget then
        self.restoreFunction(self.cameraDataTarget)
        self.cameraDataTarget = nil
        self.cameraDataOriginal = nil
    end
end

return ShotPresentation
