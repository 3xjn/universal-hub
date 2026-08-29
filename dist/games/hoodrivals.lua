return {
    buildId = [[610c86b0]],
    id = [[hoodrivals]],
    sources = {
        ["games/hoodrivals/Adapter.lua"] = [[local function importDependency(path, relativePath)
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
local WeaponPolicy = importDependency("games/hoodrivals/WeaponPolicy", "./WeaponPolicy")
local SilentAim = importDependency("games/hoodrivals/features/SilentAim", "./features/SilentAim")
local TriggerBot = importDependency("games/hoodrivals/features/TriggerBot", "./features/TriggerBot")
local RapidFire = importDependency("games/hoodrivals/features/RapidFire", "./features/RapidFire")
local AutoReload = importDependency("games/hoodrivals/features/AutoReload", "./features/AutoReload")
local FastReload = importDependency("games/hoodrivals/features/FastReload", "./features/FastReload")
local NoScope = importDependency("games/hoodrivals/features/NoScope", "./features/NoScope")
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
    local noScope = NoScope.new()
    local WeaponData = require(game.ReplicatedStorage.WeaponData)

    local connection = RunService.Heartbeat:Connect(function()
        if stopped then
            return
        end
        local camera = Workspace.CurrentCamera
        local settings = store:Get().settings
        local character = LocalPlayer.Character
        local weapon = character and character:FindFirstChildWhichIsA("Tool")
        local profile = WeaponPolicy.profile(weapon, weapon and WeaponData[weapon.Name])
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
        rapidFire:update(
            settings,
            weapon,
            profile,
            firearm,
            UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        )
        autoReload:update(settings.autoReload == true, firearm.reload, weapon)
        fastReload:update(settings.fastReload == true, weapon, firearm.reloadTrack)
        noScope:update(settings.noScope == true, firearm, profile)
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
            task.spawn(function()
                RunService.Heartbeat:Wait()
                if stopped or instance.Parent ~= character then return end
                firearm:refresh(instance)
                silentAim:install(firearm.aimDirections)
            end)
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
        noScope:stop(firearm)
    end
    return self
end

return Adapter
]],
        ["games/hoodrivals/Firearm.lua"] = [[local Firearm = {}
Firearm.__index = Firearm

function Firearm.new(closure)
    return setmetatable({ closure = closure }, Firearm)
end

function Firearm:refresh(firearmLocal)
    local found = self.closure.searchClosures(firearmLocal, {
        aimDirection = { name = "GetAimDirection", upvalueIndex = 1 },
        fire = { name = "OnFire", upvalueIndex = 1 },
        reload = { name = "Reload", upvalueIndex = 1 },
        scope = { name = "ScopeToggle", upvalueIndex = 1 },
    })
    self.aimDirections = found.aimDirection and { found.aimDirection } or {}
    self.fire = found.fire or self.fire
    self.reload = found.reload or self.reload
    self.scope = found.scope or self.scope
    if self.reload and type(getupvalues) == "function" then
        local succeeded, upvalues = pcall(getupvalues, self.reload)
        if succeeded then
            for _, value in pairs(upvalues) do
                if type(value) == "table"
                    and typeof(value.Reload) == "Instance"
                    and value.Reload:IsA("AnimationTrack")
                then
                    self.reloadTrack = value.Reload
                    break
                end
            end
        end
    end
    return self
end

function Firearm:shoot()
    return self.fire and pcall(self.fire, true) or false
end

function Firearm:startReload()
    return self.reload and pcall(self.reload) or false
end

function Firearm:setScoped(scoped)
    return self.scope and pcall(self.scope, scoped == true) or false
end

function Firearm:canHit(workspace, target, weapon, localCharacter)
    local aimDirection = self.aimDirections and self.aimDirections[1]
    if not aimDirection or not target or not target.character then
        return false
    end
    local succeeded, direction, origin = pcall(aimDirection, 0)
    if not succeeded or typeof(direction) ~= "Vector3" or typeof(origin) ~= "Vector3" then
        return false
    end
    local stats = weapon and weapon:FindFirstChild("Stats")
    local range = stats and stats:FindFirstChild("Range")
    local radius = weapon and weapon:GetAttribute("DamageRadius") or 1.15
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        localCharacter,
        workspace.CurrentCamera,
        workspace:FindFirstChild("apes"),
        workspace:FindFirstChild("OBJECTS"),
    }
    params.IgnoreWater = true
    local result = workspace:Spherecast(
        origin,
        radius,
        direction.Unit * (range and range.Value or 1000),
        params
    )
    return result ~= nil
        and result.Instance ~= nil
        and result.Instance:IsDescendantOf(target.character)
end

return Firearm
]],
        ["games/hoodrivals/Presentation.lua"] = [[local Presentation = {}

function Presentation.mount(host)
    host:aim()
    host:rate("headshotRate", "Headshot Rate")
    host:rate("missRate", "Miss Rate")

    host:section("Combat", "aim", "AIM", 64)
    host:option("aim", 1, "silentAim", "Silent Aim")
    host:option("aim", 2, "triggerBot", "Trigger Bot")
    host:option("aim", 3, "rapidFire", "Rapid Fire")
    if type(host.slider) == "function" then
        host:slider("aim", "rapidFireDelay", "Delay", {
            min = 10,
            max = 200,
            step = 5,
            unit = "ms",
            parent = "rapidFire",
        })
    end

    host:section("Visuals", "visuals", "VISUALS", 70, false, 1, { treatment = "grid" })
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "names", "Names")
    host:option("visuals", 2, "health", "Health")
    host:option("visuals", 3, "weapon", "Weapons")
    host:option("visuals", 20, "showEnemies", "Enemies", "audience")
    host:option("visuals", 21, "showTeammates", "Allies", "audience")
end

return Presentation
]],
        ["games/hoodrivals/Targeting.lua"] = [[local Targeting = {}

local function aliveCharacter(player)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return character and humanoid and humanoid.Health > 0 and character or nil
end

function Targeting.isOpponent(localPlayer, player)
    if player == localPlayer or not aliveCharacter(player) then
        return false
    end
    if localPlayer.Team and localPlayer.Team.Name == "FFA" then
        return true
    end
    return localPlayer.Team == nil or player.Team == nil or player.Team ~= localPlayer.Team
end

function Targeting.point(character, preferHead)
    if not character then
        return nil
    end
    if preferHead then
        return character:FindFirstChild("HeadHitbox")
            or character:FindFirstChild("Head")
    end
    return character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")
end

function Targeting.select(players, localPlayer, camera, mousePosition, settings, random)
    local closest
    local closestDistance = math.huge
    for _, player in ipairs(players:GetPlayers()) do
        if Targeting.isOpponent(localPlayer, player) then
            local character = player.Character
            local point = Targeting.point(character, true)
            if point then
                local screen, visible = camera:WorldToViewportPoint(point.Position)
                local screenDistance = (Vector2.new(screen.X, screen.Y) - mousePosition).Magnitude
                if visible
                    and (settings.fullScreenAim == true or screenDistance <= (settings.fov or 180))
                    and screenDistance < closestDistance
                then
                    closest = {
                        character = character,
                        part = point,
                        player = player,
                        position = point.Position,
                    }
                    closestDistance = screenDistance
                end
            end
        end
    end
    if not closest then
        return nil
    end

    random = random or math.random
    if random(1, 100) <= (settings.missRate or 0) then
        local root = closest.character:FindFirstChild("HumanoidRootPart")
        if root then
            closest.part = root
            closest.position = root.Position + root.CFrame.RightVector * 4
        end
    elseif random(1, 100) > (settings.headshotRate or 0) then
        local body = Targeting.point(closest.character, false)
        if body then
            closest.part = body
            closest.position = body.Position
        end
    end
    return closest
end

function Targeting.hasLineOfFire(workspace, origin, target, localCharacter)
    if not target or typeof(origin) ~= "Vector3" or typeof(target.position) ~= "Vector3" then
        return false
    end
    local offset = target.position - origin
    if offset.Magnitude <= 1e-3 then
        return false
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = localCharacter and { localCharacter } or {}
    params.IgnoreWater = true
    local result = workspace:Raycast(origin, offset, params)
    return result ~= nil
        and result.Instance ~= nil
        and result.Instance:IsDescendantOf(target.character)
end

function Targeting.acquire(players, localPlayer, workspace, camera, mousePosition, settings)
    local target = Targeting.select(players, localPlayer, camera, mousePosition, settings)
    if target then target.lineOfFire = true end
    return target
end

function Targeting.observations(players, localPlayer, camera)
    local observations = {}
    for _, player in ipairs(players:GetPlayers()) do
        if player ~= localPlayer then
            local character = aliveCharacter(player)
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if root and humanoid then
                local screen, onScreen = camera:WorldToViewportPoint(root.Position)
                table.insert(observations, {
                    bounds = onScreen and {
                        position = Vector2.new(screen.X - 30, screen.Y - 60),
                        size = Vector2.new(60, 120),
                    } or nil,
                    character = character,
                    health = humanoid.Health,
                    maxHealth = humanoid.MaxHealth,
                    part = root,
                    player = player,
                    position = root.Position,
                    tone = Targeting.isOpponent(localPlayer, player) and "enemy" or "team",
                    visible = onScreen,
                })
            end
        end
    end
    return observations
end

return Targeting
]],
        ["games/hoodrivals/WeaponPolicy.lua"] = [[local WeaponPolicy = {}

local SCOPED = {
    R700 = true,
    ["223Rifle"] = true,
}

local MANUAL_FIRE = {
    R700 = true,
    Sawedoff = true,
    PumpShotgun = true,
    Killtec = true,
}

function WeaponPolicy.profile(weapon, data)
    local stats = weapon and weapon:FindFirstChild("Stats")
    local gunType = stats and stats:FindFirstChild("GunType")
    local shots = stats and stats:FindFirstChild("Shots")
    local fireRate = stats and stats:FindFirstChild("FireRate")
    return {
        scoped = weapon ~= nil and SCOPED[weapon.Name] == true,
        manualFire = weapon ~= nil and MANUAL_FIRE[weapon.Name] == true,
        binary = gunType ~= nil and gunType.Value == "Binary",
        pelletCount = shots and shots.Value or 1,
        nativeFireRate = fireRate and fireRate.Value or data and data.FireRate or 0.1,
        damageRadius = data and data.DamageRadius or 1.15,
    }
end

return WeaponPolicy
]],
        ["games/hoodrivals/features/AutoReload.lua"] = [[local AutoReload = {}
AutoReload.__index = AutoReload

function AutoReload.new()
    return setmetatable({ requested = false }, AutoReload)
end

function AutoReload:update(enabled, reload, weapon)
    local stats = weapon and weapon:FindFirstChild("Stats")
    local clip = stats and stats:FindFirstChild("ClipSize")
    if enabled and reload and clip and clip.Value <= 0 then
        if not self.requested then
            self.requested = true
            task.spawn(function()
                pcall(reload)
                self.requested = false
            end)
        end
    elseif not clip or clip.Value > 0 then
        self.requested = false
    end
end

return AutoReload
]],
        ["games/hoodrivals/features/FastReload.lua"] = [[local FastReload = {}
FastReload.__index = FastReload

function FastReload.new()
    return setmetatable({
        animations = {},
        reloadTimes = {},
    }, FastReload)
end

function FastReload:update(enabled, weapon, reloadTrack)
    local stats = weapon and weapon:FindFirstChild("Stats")
    local reloadTime = stats and stats:FindFirstChild("ReloadTime")
    local handle = weapon and weapon:FindFirstChild("Handle")
    local sound = handle and handle:FindFirstChild("Reload")

    if enabled and weapon and reloadTime then
        if not self.reloadTimes[reloadTime] then
            self.reloadTimes[reloadTime] = reloadTime.Value
        end
        reloadTime.Value = math.min(self.reloadTimes[reloadTime], 0.1)
        if sound then
            if not self.animations[sound] then
                self.animations[sound] = sound.PlaybackSpeed
            end
            sound.PlaybackSpeed = math.max(self.animations[sound], 10)
        end
        if reloadTrack and reloadTrack.IsPlaying then
            reloadTrack:AdjustSpeed(10)
        end
        return
    end

    self:restoreWeapon(weapon)
end

function FastReload:restoreWeapon(weapon)
    local stats = weapon and weapon:FindFirstChild("Stats")
    local reloadTime = stats and stats:FindFirstChild("ReloadTime")
    if reloadTime and self.reloadTimes[reloadTime] then
        reloadTime.Value = self.reloadTimes[reloadTime]
        self.reloadTimes[reloadTime] = nil
    end
    local handle = weapon and weapon:FindFirstChild("Handle")
    local sound = handle and handle:FindFirstChild("Reload")
    if sound and self.animations[sound] then
        sound.PlaybackSpeed = self.animations[sound]
        self.animations[sound] = nil
    end
end

function FastReload:stop()
    for reloadTime, original in pairs(self.reloadTimes) do
        if reloadTime.Parent then reloadTime.Value = original end
    end
    for sound, original in pairs(self.animations) do
        if sound.Parent then sound.PlaybackSpeed = original end
    end
    table.clear(self.reloadTimes)
    table.clear(self.animations)
end

return FastReload
]],
        ["games/hoodrivals/features/NoScope.lua"] = [[local NoScope = {}
NoScope.__index = NoScope

function NoScope.new()
    return setmetatable({ active = false }, NoScope)
end

function NoScope:update(enabled, firearm, profile)
    local shouldScope = enabled == true and profile and profile.scoped == true
    if shouldScope then
        firearm:setScoped(true)
        self.active = true
    elseif self.active then
        firearm:setScoped(false)
        self.active = false
    end
end

function NoScope:stop(firearm)
    if self.active then firearm:setScoped(false) end
    self.active = false
end

return NoScope
]],
        ["games/hoodrivals/features/RapidFire.lua"] = [[local RapidFire = {}
RapidFire.__index = RapidFire

function RapidFire.new()
    return setmetatable({
        weapons = {},
    }, RapidFire)
end

function RapidFire:update(settings, weapon, profile, firearm, primaryHeld)
    local stats = weapon and weapon:FindFirstChild("Stats")
    local fireRate = stats and stats:FindFirstChild("FireRate")
    local gunType = stats and stats:FindFirstChild("GunType")

    if settings.rapidFire == true and fireRate and gunType then
        if not self.weapons[weapon] then
            self.weapons[weapon] = {
                fireRate = fireRate.Value,
                gunType = gunType.Value,
            }
        end
        local delay = math.clamp(
            type(settings.rapidFireDelay) == "number" and settings.rapidFireDelay or 40,
            10,
            200
        ) / 1000
        fireRate.Value = math.min(self.weapons[weapon].fireRate, delay)
        if not profile or not profile.manualFire then
            gunType.Value = "Auto"
        elseif primaryHeld and firearm and os.clock() >= (self.nextManualAt or 0) then
            firearm:shoot()
            self.nextManualAt = os.clock() + delay
        end
        return
    end

    self:restore(weapon)
end

function RapidFire:restore(weapon)
    local original = self.weapons[weapon]
    if not original then
        return
    end

    local stats = weapon.Parent and weapon:FindFirstChild("Stats")
    local fireRate = stats and stats:FindFirstChild("FireRate")
    local gunType = stats and stats:FindFirstChild("GunType")
    if fireRate then
        fireRate.Value = original.fireRate
    end
    if gunType then
        gunType.Value = original.gunType
    end
    self.weapons[weapon] = nil
end

function RapidFire:stop()
    local weapons = {}
    for weapon in pairs(self.weapons) do
        table.insert(weapons, weapon)
    end
    for _, weapon in ipairs(weapons) do
        self:restore(weapon)
    end
end

return RapidFire

]],
        ["games/hoodrivals/features/SilentAim.lua"] = [[local SilentAim = {}
SilentAim.__index = SilentAim

function SilentAim.new(options)
    return setmetatable({
        debug = { calls = 0, hooks = 0, redirected = 0, stage = "starting" },
        getSettings = options.getSettings,
        getTarget = options.getTarget,
        hookFunction = options.hookFunction,
        hooks = {},
        restoreFunction = options.restoreFunction,
        stopped = false,
    }, SilentAim)
end

function SilentAim:install(closures)
    for _, closure in ipairs(closures or {}) do
        if not self.hooks[closure] then
            local original
            original = self.hookFunction(closure, function(spread)
                self.debug.calls += 1
                local direction, origin = original(spread)
                local settings = self.getSettings()
                if self.stopped or settings.silentAim ~= true or typeof(origin) ~= "Vector3" then
                    return direction, origin
                end
                local target = self.getTarget()
                local offset = target and target.position - origin
                if not offset or offset.Magnitude <= 1e-3 then
                    self.debug.stage = "no-target"
                    return direction, origin
                end
                self.debug.redirected += 1
                self.debug.stage = "redirected"
                self.debug.target = target.player and target.player.Name
                return offset.Unit, origin
            end)
            self.hooks[closure] = original
            self.debug.hooks += 1
            self.debug.stage = "hooked"
        end
    end
end

function SilentAim:stop()
    self.stopped = true
    for closure in pairs(self.hooks) do
        self.restoreFunction(closure)
    end
    table.clear(self.hooks)
end

return SilentAim
]],
        ["games/hoodrivals/features/TriggerBot.lua"] = [[local TriggerBot = {}
TriggerBot.__index = TriggerBot

function TriggerBot.new(options)
    return setmetatable({
        nextAt = 0,
        localPlayer = options.localPlayer,
        workspace = options.workspace,
    }, TriggerBot)
end

function TriggerBot.ready(workspace, localPlayer, weapon)
    local character = localPlayer and localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local stats = weapon and weapon:FindFirstChild("Stats")
    local clip = stats and stats:FindFirstChild("ClipSize")
    return workspace:GetAttribute("CanDamage") == true
        and localPlayer:GetAttribute("EndScreen") ~= true
        and humanoid ~= nil
        and humanoid.Health > 0
        and clip ~= nil
        and clip.Value > 0
end

function TriggerBot:update(settings, fire, weapon, target)
    if settings.triggerBot ~= true
        or not fire
        or not TriggerBot.ready(self.workspace, self.localPlayer, weapon)
        or not target
        or not target.lineOfFire
        or os.clock() < self.nextAt
    then
        return false
    end
    local stats = weapon:FindFirstChild("Stats")
    local fireRate = stats and stats:FindFirstChild("FireRate")
    pcall(fire, true)
    self.nextAt = os.clock() + math.max(fireRate and fireRate.Value or 0.1, 0.01)
    return true
end

return TriggerBot
]],
    },
}
