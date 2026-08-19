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

local Targeting = importDependency("games/hoodrivals/Targeting", "./Targeting")
local Firearm = importDependency("games/hoodrivals/Firearm", "./Firearm")
local SilentAim = importDependency("games/hoodrivals/features/SilentAim", "./features/SilentAim")
local TriggerBot = importDependency("games/hoodrivals/features/TriggerBot", "./features/TriggerBot")
local RapidFire = importDependency("games/hoodrivals/features/RapidFire", "./features/RapidFire")
local AutoReload = importDependency("games/hoodrivals/features/AutoReload", "./features/AutoReload")
local FastReload = importDependency("games/hoodrivals/features/FastReload", "./features/FastReload")
local Adapter = {}

function Adapter.new(context)
    assert(context and context.store, "Hood Rivals adapter requires a store")
    assert(context.hookFunction, "Hood Rivals Silent Aim requires hookfunction")
    assert(context.restoreFunction, "Hood Rivals Silent Aim requires restorefunction")

    local Players = context.players or game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = context.workspace or workspace
    local LocalPlayer = context.localPlayer or Players.LocalPlayer
    local store = context.store
    local stopped = false
    local target
    local firearm = Firearm.new(context.oh.closure)
    local silentAim = SilentAim.new({
        getSettings = function() return store:Get().settings end,
        getTarget = function() return target end,
        hookFunction = context.hookFunction,
        restoreFunction = context.restoreFunction,
    })
    local triggerBot = TriggerBot.new({ localPlayer = LocalPlayer, workspace = Workspace })
    local rapidFire = RapidFire.new()
    local autoReload = AutoReload.new()
    local fastReload = FastReload.new()

    local connection = RunService.Heartbeat:Connect(function()
        if stopped then
            return
        end
        local camera = Workspace.CurrentCamera
        local settings = store:Get().settings
        local character = LocalPlayer.Character
        local weapon = character and character:FindFirstChildWhichIsA("Tool")
        target = camera and Targeting.acquire(
            Players,
            LocalPlayer,
            Workspace,
            camera,
            UserInputService:GetMouseLocation(),
            settings
        )
        if target then
            target.lineOfFire = firearm:canHit(Workspace, target, weapon, character)
        end
        rapidFire:update(settings, weapon)
        autoReload:update(settings.autoReload == true, firearm.reload, weapon)
        fastReload:update(settings.fastReload == true, weapon)
        triggerBot:update(settings, firearm.fire, weapon, target)
        context.render(
            camera and Targeting.observations(Players, LocalPlayer, camera) or {},
            UserInputService:GetMouseLocation(),
            {}
        )
    end)
    local firearmConnection
    local function bindCharacter(character)
        if firearmConnection then firearmConnection:Disconnect() end
        local function bind(instance)
            if instance.Name ~= "FirearmLocal" then return end
            firearm:refresh(instance)
            silentAim:install(firearm.aimDirections)
        end
        local existing = character and character:FindFirstChild("FirearmLocal")
        if existing then bind(existing) end
        firearmConnection = character and character.ChildAdded:Connect(bind) or nil
    end
    bindCharacter(LocalPlayer.Character)
    local characterConnection = LocalPlayer.CharacterAdded:Connect(bindCharacter)

    local self = {
        aimDebug = silentAim.debug,
        isOpponent = function(player)
            return Targeting.isOpponent(LocalPlayer, player)
        end,
    }
    function self:stop()
        if stopped then
            return
        end
        stopped = true
        connection:Disconnect()
        characterConnection:Disconnect()
        if firearmConnection then firearmConnection:Disconnect() end
        silentAim:stop()
        rapidFire:stop()
        fastReload:stop()
    end
    return self
end

return Adapter
