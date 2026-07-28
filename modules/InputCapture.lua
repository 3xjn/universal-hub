local InputCapture = {}
InputCapture.__index = InputCapture

local ACTION_NAME = "UniversalHubMenuCapture"

function InputCapture.new(services)
    services = services or {}
    local localPlayer = services.localPlayer
    if not localPlayer then
        local players = services.players or game:GetService("Players")
        localPlayer = players.LocalPlayer
    end
    return setmetatable({
        contextActionService = services.contextActionService or game:GetService("ContextActionService"),
        enabled = false,
        guiService = services.guiService or game:GetService("GuiService"),
        localPlayer = localPlayer,
        releaseMouseOnDisable = services.releaseMouseOnDisable == true,
        runService = services.runService or game:GetService("RunService"),
        userInputService = services.userInputService or game:GetService("UserInputService"),
    }, InputCapture)
end

function InputCapture:_enforceCursor()
    self.localPlayer.CameraMode = Enum.CameraMode.Classic
    self.userInputService.MouseBehavior = Enum.MouseBehavior.Default
    self.userInputService.MouseIconEnabled = true
    self.userInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceShow
end

function InputCapture:_guardProperty(instance, propertyName)
    return instance:GetPropertyChangedSignal(propertyName):Connect(function()
        if self.enabled then
            self:_enforceCursor()
        end
    end)
end

function InputCapture:SetEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled

    if enabled then
        self.previousMouseBehavior = self.userInputService.MouseBehavior
        self.previousMouseIconEnabled = self.userInputService.MouseIconEnabled
        self.previousMouseIconOverride = self.userInputService.OverrideMouseIconBehavior
        self.previousCameraMode = self.localPlayer.CameraMode
        self.propertyConnections = {
            self:_guardProperty(self.localPlayer, "CameraMode"),
            self:_guardProperty(self.userInputService, "MouseBehavior"),
            self:_guardProperty(self.userInputService, "MouseIconEnabled"),
            self:_guardProperty(self.userInputService, "OverrideMouseIconBehavior"),
        }
        self.contextActionService:BindActionAtPriority(
            ACTION_NAME,
            function()
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.ContextActionPriority.High.Value + 100,
            Enum.UserInputType.MouseButton1,
            Enum.UserInputType.MouseButton2,
            Enum.UserInputType.MouseWheel,
            Enum.UserInputType.Touch
        )
        self.heartbeatConnection = self.runService.Heartbeat:Connect(function()
            self:_enforceCursor()
        end)
        self.menuClosedConnection = self.guiService.MenuClosed:Connect(function()
            self:_enforceCursor()
        end)
        self:_enforceCursor()
        return
    end

    self.contextActionService:UnbindAction(ACTION_NAME)
    self.heartbeatConnection:Disconnect()
    self.heartbeatConnection = nil
    self.menuClosedConnection:Disconnect()
    self.menuClosedConnection = nil
    for _, connection in ipairs(self.propertyConnections) do
        connection:Disconnect()
    end
    self.propertyConnections = nil
    self.localPlayer.CameraMode = self.previousCameraMode
    self.userInputService.MouseBehavior = self.releaseMouseOnDisable
        and Enum.MouseBehavior.Default
        or self.previousMouseBehavior
    self.userInputService.MouseIconEnabled = self.previousMouseIconEnabled
    self.userInputService.OverrideMouseIconBehavior = self.previousMouseIconOverride
    self.previousCameraMode = nil
    self.previousMouseBehavior = nil
    self.previousMouseIconEnabled = nil
    self.previousMouseIconOverride = nil
end

function InputCapture:IsEnabled()
    return self.enabled
end

function InputCapture:Destroy()
    self:SetEnabled(false)
end

return InputCapture
