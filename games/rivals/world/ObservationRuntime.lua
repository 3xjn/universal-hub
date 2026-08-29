local ObservationRuntime = {}
ObservationRuntime.__index = ObservationRuntime

local MOTION_WINDOW = 0.1

function ObservationRuntime.rangeHealth(humanoid)
    local health = humanoid.Health
    local maximum = humanoid.MaxHealth
    if health == math.huge or maximum == math.huge then
        return 150, 150
    end
    return health, maximum
end

function ObservationRuntime.new(options)
    assert(options and options.targeting, "RIVALS observations require Hydroxide Targeting")
    assert(options.workspace, "RIVALS observations require Workspace")
    assert(options.getFighter, "RIVALS observations require a fighter getter")
    return setmetatable({
        clock = options.clock or os.clock,
        effects = options.effects,
        equippedWeapon = options.equippedWeapon,
        getFighter = options.getFighter,
        getPlayerTone = options.getPlayerTone,
        isOpponent = options.isOpponent,
        maximumDistance = options.maximumDistance or 2000,
        motion = setmetatable({}, { __mode = "k" }),
        players = options.players,
        targeting = options.targeting,
        workspace = options.workspace,
    }, ObservationRuntime)
end

local function offscreenObservation(cameraPosition, character, player)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root or not root.Position then
        return nil
    end
    return {
        character = character,
        distance = cameraPosition and (root.Position - cameraPosition).Magnitude or nil,
        offscreen = true,
        part = root,
        player = player,
        position = root.Position,
        visible = false,
    }
end

function ObservationRuntime:_sampleVelocity(observation, now)
    local character = observation.character
    local root = character
        and type(character.FindFirstChild) == "function"
        and character:FindFirstChild("HumanoidRootPart")
    local native = root and (root.AssemblyLinearVelocity or root.Velocity)
    if not root or typeof(root.Position) ~= "Vector3" or typeof(native) ~= "Vector3" then
        return
    end

    local samples = self.motion[character]
    if not samples then
        samples = {}
        self.motion[character] = samples
    end
    table.insert(samples, { at = now, position = root.Position })
    while #samples > 2 and samples[2].at <= now - MOTION_WINDOW do
        table.remove(samples, 1)
    end

    local first = samples[1]
    local last = samples[#samples]
    local elapsed = last.at - first.at
    local vertical = native.Y
    if elapsed > 0 then
        vertical = (last.position.Y - first.position.Y) / elapsed
    end
    observation.velocity = Vector3.new(native.X, vertical, native.Z)
end

function ObservationRuntime:update(screenOrigin, includeTeammates, includeEnemies, include360)
    local raycastIgnore = self.effects and self.effects:smokeRaycastIgnore() or {}
    local eligibility = self.isOpponent
    if includeTeammates and self.getPlayerTone then
        eligibility = function(player, character)
            return self.getPlayerTone(player, character) ~= nil
        end
    end
    local observations = self.targeting.observePlayers({
        isEligible = eligibility,
        raycastIgnore = raycastIgnore,
        screenOrigin = screenOrigin,
    })
    local fighter = self.getFighter()
    local data = fighter and fighter.Data
    local camera = self.workspace.CurrentCamera
    local cameraFrame = camera
        and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
    local cameraPosition = cameraFrame and cameraFrame.Position
    if include360 and self.players and type(self.players.GetPlayers) == "function" then
        local observedCharacters = {}
        for _, observation in ipairs(observations) do
            if observation.character then
                observedCharacters[observation.character] = true
            end
        end
        for _, player in ipairs(self.players:GetPlayers()) do
            local character = player.Character
            if
                character
                and not observedCharacters[character]
                and eligibility(player, character)
            then
                local observation = offscreenObservation(cameraPosition, character, player)
                if observation then
                    table.insert(observations, observation)
                end
            end
        end
    end
    local rangeEntities = self.workspace:FindFirstChild("ShootingRangeEntities")
    if type(data) == "table" and data.IsInShootingRange and camera and rangeEntities then
        local containers = { rangeEntities }
        local hurtEffect = self.workspace:FindFirstChild("HurtEffect")
        if hurtEffect then
            table.insert(containers, hurtEffect)
        end
        for _, container in ipairs(containers) do
            for _, entity in ipairs(container:GetChildren()) do
                local humanoid = entity:FindFirstChildOfClass("Humanoid")
                local environmentID = entity:GetAttribute("EnvironmentID")
                if
                    entity:IsA("Model")
                    and humanoid
                    and humanoid.Health > 0
                    and (data.EnvironmentID == nil or environmentID == data.EnvironmentID)
                then
                    local observation = self.targeting.observeCharacter(entity, {
                        screenOrigin = screenOrigin,
                    })
                    if not observation and include360 then
                        observation = offscreenObservation(cameraPosition, entity, entity)
                    end
                    if observation then
                        observation.player = entity
                        observation.health, observation.maxHealth =
                            ObservationRuntime.rangeHealth(humanoid)
                        table.insert(observations, observation)
                    end
                end
            end
        end
    end
    local nearby = {}
    if cameraPosition then
        for _, observation in ipairs(observations) do
            if
                observation.position
                and (observation.position - cameraPosition).Magnitude <= self.maximumDistance
            then
                table.insert(nearby, observation)
            end
        end
    end
    local now = self.clock()
    for _, observation in ipairs(nearby) do
        self:_sampleVelocity(observation, now)
        if observation.player ~= observation.character then
            local character = observation.character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            observation.health = humanoid and humanoid.Health or nil
            observation.maxHealth = humanoid and humanoid.MaxHealth or nil
            observation.weapon = self.equippedWeapon and self.equippedWeapon(observation.player)
                or nil
            observation.tone = self.getPlayerTone
                    and self.getPlayerTone(observation.player, character)
                or "enemy"
        end
    end
    local opponents = {}
    local allies = {}
    local visibleOpponents = {}
    local visibleAllies = {}
    for _, observation in ipairs(nearby) do
        if observation.player ~= observation.character and observation.tone == "team" then
            table.insert(allies, observation)
            if not observation.offscreen then
                table.insert(visibleAllies, observation)
            end
        else
            table.insert(opponents, observation)
            if not observation.offscreen then
                table.insert(visibleOpponents, observation)
            end
        end
    end
    if includeTeammates and includeEnemies ~= false then
        local visual = {}
        for _, observation in ipairs(visibleOpponents) do
            table.insert(visual, observation)
        end
        for _, observation in ipairs(visibleAllies) do
            table.insert(visual, observation)
        end
        return opponents, visual
    end
    if includeTeammates then
        return opponents, visibleAllies
    end
    if includeEnemies == false then
        return opponents, {}
    end
    return opponents, visibleOpponents
end

return ObservationRuntime
