local ShotPresentation = {}
ShotPresentation.__index = ShotPresentation

local nextBindingID = 0

local function maskedFrame(targetFrame, visibleFrame)
    return CFrame.new(targetFrame.Position) * visibleFrame.Rotation
end

function ShotPresentation.new(options)
    assert(options and options.cameraController, "RIVALS Shot Aim requires CameraController")
    assert(options.runService, "RIVALS Shot Aim requires RunService")
    assert(options.workspace, "RIVALS Shot Aim requires Workspace")
    assert(options.getFighter, "RIVALS Shot Aim requires a fighter getter")
    assert(options.hookFunction, "RIVALS Shot Aim requires hookfunction")
    assert(options.restoreFunction, "RIVALS Shot Aim requires restorefunction")

    nextBindingID += 1
    local bindingSuffix = tostring(nextBindingID)
    local self = setmetatable({
        cameraController = options.cameraController,
        cameraDataOriginal = nil,
        cameraDataTarget = nil,
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
        pendingTarget = nil,
        pendingRotation = nil,
        postBinding = "UniversalHubShotPresentationPost" .. bindingSuffix,
        preBinding = "UniversalHubShotPresentationPre" .. bindingSuffix,
        presentedTarget = nil,
        restoreFunction = options.restoreFunction,
        runService = options.runService,
        stopped = false,
        targetFrame = nil,
        visibleCamera = nil,
        visibleFrame = nil,
        visibleRotation = nil,
        workspace = options.workspace,
    }, ShotPresentation)

    local rotationDeltaSignal = self.cameraController.RotationDeltaApplied
    if rotationDeltaSignal and type(rotationDeltaSignal.Connect) == "function" then
        self.rotationDeltaConnection = rotationDeltaSignal:Connect(function(delta)
            self:_applyVisibleRotationDelta(delta)
        end)
    end

    local cameraPriority = options.cameraPriority or Enum.RenderPriority.Camera.Value
    self.runService:BindToRenderStep(self.preBinding, cameraPriority - 1, function()
        self:_prepareFrame()
    end)
    self.runService:BindToRenderStep(self.postBinding, cameraPriority + 1, function()
        self:_maskFrame()
    end)
    return self
end

function ShotPresentation:_reset()
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

function ShotPresentation:update(rotation, target)
    if self.stopped or typeof(rotation) ~= "Vector2" then
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
        self.visibleFrame =
            camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame
        self.visibleRotation = self.cameraController.Rotation
    end
    self.pendingTarget = target
    self.pendingRotation = rotation
    return true
end

function ShotPresentation:getPresentedTarget()
    return self.targetFrame and self.frameRotation and self.presentedTarget or nil
end

function ShotPresentation:_prepareFrame()
    if self.stopped or not self.pendingRotation then
        return
    end
    self.logicalTarget = self.pendingTarget
    self.logicalRotation = self.pendingRotation
    self.cameraController:SetRotation(self.logicalRotation)
end

function ShotPresentation:_maskFrame()
    if self.stopped
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
    if self.stopped
        or not self.visibleFrame
        or not self.visibleRotation
        or typeof(delta) ~= "Vector2"
    then
        return
    end

    local previousRotation = self.visibleRotation
    local visible = previousRotation + delta
    local nextRotation = Vector2.new(
        math.clamp(visible.X, -1.5690509975429023, 1.5690509975429023),
        visible.Y
    )
    local previousBase = CFrame.Angles(0, previousRotation.Y, 0)
        * CFrame.Angles(previousRotation.X, 0, 0)
    local nextBase = CFrame.Angles(0, nextRotation.Y, 0)
        * CFrame.Angles(nextRotation.X, 0, 0)
    self.visibleFrame = CFrame.new(self.visibleFrame.Position)
        * nextBase
        * previousBase:ToObjectSpace(self.visibleFrame.Rotation)
    self.visibleRotation = nextRotation
    if self.logicalRotation then
        self.cameraController:SetRotation(self.logicalRotation)
    end
end

function ShotPresentation:refreshHook()
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
        if self.stopped
            or not self.isEnabled()
            or fighterSelf ~= self.getFighter()
            or self.isInputCaptured()
        then
            return original(fighterSelf, ...)
        end

        local camera = self.workspace.CurrentCamera
        if not camera
            or camera ~= self.visibleCamera
            or not self.targetFrame
            or not self.frameRotation
        then
            return original(fighterSelf, ...)
        end

        local localMaskedFrame = camera.CFrame
        camera.CFrame = self.targetFrame
        self.cameraController:SetRotation(self.frameRotation)
        local returned = table.pack(original(fighterSelf, ...))
        camera.CFrame = localMaskedFrame
        self.cameraController:SetRotation(self.frameRotation)
        return table.unpack(returned, 1, returned.n)
    end)
    self.cameraDataOriginal = original
end

function ShotPresentation:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:clear()
    if self.rotationDeltaConnection then
        self.rotationDeltaConnection:Disconnect()
        self.rotationDeltaConnection = nil
    end
    self.runService:UnbindFromRenderStep(self.preBinding)
    self.runService:UnbindFromRenderStep(self.postBinding)
    if self.cameraDataTarget then
        self.restoreFunction(self.cameraDataTarget)
        self.cameraDataTarget = nil
        self.cameraDataOriginal = nil
    end
end

return ShotPresentation
