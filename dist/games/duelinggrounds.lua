return {
    buildId = [[610c86b0]],
    id = [[duelinggrounds]],
    sources = {
        ["games/duelinggrounds/Adapter.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local AutoMovement =
    importDependency("games/duelinggrounds/features/AutoMovement", "./features/AutoMovement")
local CombatPipeline =
    importDependency("games/duelinggrounds/features/CombatPipeline", "./features/CombatPipeline")
local CombatRuntime =
    importDependency("games/duelinggrounds/features/CombatRuntime", "./features/CombatRuntime")
local Noclip = importDependency("games/duelinggrounds/features/Noclip", "./features/Noclip")
local TeleportBehind =
    importDependency("games/duelinggrounds/features/TeleportBehind", "./features/TeleportBehind")
local WinTitles =
    importDependency("games/duelinggrounds/features/WinTitles", "./features/WinTitles")
local Persistence =
    importDependency("games/duelinggrounds/recording/Persistence", "./recording/Persistence")
local Recording = importDependency("games/duelinggrounds/recording/Runtime", "./recording/Runtime")
local Styles =
    importDependency("games/duelinggrounds/features/combat/Styles", "./features/combat/Styles")

local Adapter = {}

local DEFAULT_PROFILE = {
    approachDistance = 7.25,
    orbitDistance = 5.25,
    retreatDistance = 3.25,
}

local function weaponInfo(handler)
    local weapon = handler and handler:GetEquippedWeaponHandler()
    return weapon and weapon.WeaponInfo
end

function Adapter.new(context)
    assert(context and context.store and context.players and context.render)
    local Players = context.players
    local LocalPlayer = Players.LocalPlayer
    local Workspace = context.workspace or workspace
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local GameManager = require(ReplicatedStorage.GameManager)
    local characterController = GameManager:GetController("CharacterController")
    local targetLockController = GameManager:GetController("TargetLockController")
    local playerInputController = GameManager:GetController("PlayerInputController")
    local pingController = GameManager:GetController("PingController")
    local environment = type(getgenv) == "function" and getgenv() or _G
    local recording
    recording = Recording.new({
        environment = environment,
        persistence = Persistence.new({
            writefile = type(writefile) == "function" and writefile or nil,
            makefolder = type(makefolder) == "function" and makefolder or nil,
            isfolder = type(isfolder) == "function" and isfolder or nil,
            jsonEncode = function(value)
                return game:GetService("HttpService"):JSONEncode(value)
            end,
        }),
    })
    local combat = CombatRuntime.new({
        players = Players,
        workspace = Workspace,
        characterController = characterController,
        targetLockController = targetLockController,
        ping = function()
            return pingController:GetPing()
        end,
        criticalStrike = function(model)
            ReplicatedStorage.Remotes.PlayerCharacter.Request.CriticalStrike:FireServer(model)
        end,
        record = function(kind, data)
            if string.find(kind, "defense", 1, true) then
                recording:recordDecision(kind, data)
            else
                recording:recordEvent(kind, data)
            end
        end,
    })
    local movement = AutoMovement.new()
    local noclip = Noclip.new()
    local winTitles = WinTitles.new()
    local stopped = false

    local function frame(settings)
        local target = targetLockController.Target
        local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
        local localHandler = characterController:GetLocalCharacterHandler()
        local targetHandler = targetModel and characterController:GetCharacterHandler(targetModel)
        local localModel = localHandler and (localHandler.OriginalModel or localHandler.Model)
        local targetRoot = targetHandler and targetHandler.Root or target
        local localRoot = localHandler and localHandler.Root
        local localWeapon = weaponInfo(localHandler)
        local targetWeapon = weaponInfo(targetHandler)
        local targetPlayer = targetModel and Players:GetPlayerFromCharacter(targetModel)
        local localState = {
            health = localModel and localModel:GetAttribute("Health"),
            maximumHealth = localModel and localModel:GetAttribute("MaxHealth"),
            posture = localModel and localModel:GetAttribute("Posture"),
            maximumPosture = localModel and localModel:GetAttribute("MaxPosture"),
        }
        return {
            settings = settings,
            target = target,
            targetModel = targetModel,
            targetHandler = targetHandler,
            targetRoot = targetRoot,
            localHandler = localHandler,
            localRoot = localRoot,
            localModel = localModel,
            localState = localState,
            targetDead = targetModel and targetModel:GetAttribute("IsDead") == true,
            selfDead = localModel and localModel:GetAttribute("IsDead") == true,
            metadata = {
                gameId = game.GameId,
                placeId = game.PlaceId,
                jobId = game.JobId,
                localPlayer = LocalPlayer.Name,
                localUserId = LocalPlayer.UserId,
                target = targetPlayer and targetPlayer.Name or targetModel and targetModel.Name,
                targetUserId = targetPlayer and targetPlayer.UserId,
                selfWeapon = localWeapon and localWeapon.WeaponName,
                targetWeapon = targetWeapon and targetWeapon.WeaponName,
            },
        }
    end

    local function render(settings)
        local observations = settings.showEnemies == false and {}
            or context.oh.targeting.observePlayers({
                isEligible = function(player)
                    return player ~= LocalPlayer
                end,
                screenOrigin = Vector2.zero,
            })
        for _, observation in ipairs(observations) do
            local humanoid = observation.character
                and observation.character:FindFirstChildOfClass("Humanoid")
            observation.health = humanoid and humanoid.Health
            observation.maxHealth = humanoid and humanoid.MaxHealth
            observation.tone = "enemy"
        end
        context.render(observations, Vector2.zero, {})
        context.store:Patch({
            observations = observations,
            status = ("%d players visible"):format(#observations),
        })
    end

    local connection = RunService.RenderStepped:Connect(function()
        if stopped then
            return
        end
        local settings = context.store:Get().settings or {}
        local current = frame(settings)
        CombatPipeline.run({
            record = function()
                local disposition = combat:disposition()
                current.dynamicMode = disposition.dynamicState.mode
                current.defense = disposition.defenseIntent and disposition.defenseIntent.kind
                current.critical = targetLockController.CriticalStrikeTarget ~= nil
                recording:update(current, settings)
            end,
            defend = function()
                combat:observeAndDefend(settings, current)
            end,
            relocate = function()
                TeleportBehind.update(settings, {
                    targetDead = current.targetDead,
                    localRoot = current.localRoot,
                    targetRoot = current.targetRoot,
                    distance = 4,
                })
            end,
            attack = function()
                combat:attack(settings, current)
            end,
            move = function()
                local disposition = combat:disposition()
                local actions = current.localHandler and current.localHandler.ActionManager
                local style = Styles.preferences(
                    settings.combatStyle,
                    current.localState,
                    disposition.dynamicState
                )
                movement:update(settings, {
                    input = playerInputController.CurrentInput,
                    target = current.target,
                    localPosition = current.localRoot and current.localRoot.Position,
                    targetPosition = current.targetRoot and current.targetRoot.Position,
                    profile = {
                        approachDistance = DEFAULT_PROFILE.approachDistance,
                        orbitDistance = DEFAULT_PROFILE.orbitDistance
                            * ((style.movement and style.movement.orbitDistanceScale) or 1),
                        retreatDistance = DEFAULT_PROFILE.retreatDistance,
                    },
                    movement = style.movement,
                    now = os.clock(),
                }, {
                    canMove = not disposition.defenseIntent
                        and not disposition.incomingThreat
                        and actions ~= nil
                        and not actions._queuedActionType
                        and not actions.BlockAction
                        and not current.localHandler.IsDodging
                        and not current.localHandler.IsParrying,
                })
            end,
            effects = function()
                noclip:update(settings.noclip == true, LocalPlayer.Character)
                winTitles:update(settings.showWins == true, Players)
            end,
            render = function()
                render(settings)
            end,
        }, current)
    end)

    return {
        capabilities = {
            "boxes",
            "chams",
            "chamsExcludeAccessories",
            "chamsPerPart",
            "showEnemies",
            "worldRenderer",
            "names",
            "health",
            "showWins",
            "autoFight",
            "autoMovement",
            "botSkill",
            "combatStyle",
            "teleportBehind",
            "noclip",
        },
        isOpponent = function(player)
            return player ~= nil and player ~= LocalPlayer
        end,
        stop = function()
            if stopped then
                return
            end
            stopped = true
            connection:Disconnect()
            combat:stop()
            movement:stop()
            recording:stop("sessionStopped")
            noclip:stop()
            winTitles:stop()
        end,
    }
end

return Adapter
]],
        ["games/duelinggrounds/Presentation.lua"] = [[local Presentation = {}

function Presentation.mount(host)
    if type(host.page) == "function" then
        host:page("Visuals", {
            layout = "toggle-grid",
            views = {
                { id = "preview", label = "Preview" },
                { id = "colors", label = "ESP Colors" },
            },
            preview = { kind = "character" },
        })
    end
    host:segmented("Visuals", {
        id = "worldRenderer",
        sectionLabel = "ESP",
        label = "Style",
        treatment = "style",
        options = {
            { label = "Classic", value = "limn", when = { worldRenderer = "limn" }, patch = { { "worldRenderer", "limn" } } },
            { label = "Highlights", value = "native", when = { worldRenderer = "native" }, patch = { { "worldRenderer", "native" } } },
        },
    })
    host:section("Visuals", "visuals", "PLAYERS", 70, false, 1, { treatment = "grid" })
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "chamsExcludeAccessories", "Ignore Accessories", "chams", {
        setting = "worldRenderer", equals = "native",
    })
    host:option("visuals", 2, "chamsPerPart", "Part Highlights", "chams", {
        setting = "worldRenderer", equals = "native",
    })
    host:option("visuals", 3, "names", "Names")
    host:option("visuals", 3, "health", "Health")
    host:option("visuals", 4, "showWins", "Show Wins", "names")
    host:option("visuals", 20, "showEnemies", "Players", "audience")

    host:section("Combat", "offense", "OFFENSE", 70)
    host:option("offense", 1, "autoFight", "Auto Fight")
    host:option("offense", 2, "autoMovement", "Auto Movement", "autoFight")
    if type(host.slider) == "function" then
        host:slider("offense", "botSkill", "Bot Skill", {
            min = 0,
            max = 100,
            step = 1,
            unit = "%",
            parent = "autoFight",
        })
    end
    host:segmented("Combat", {
        id = "combatStyle",
        label = "Fight Style",
        emphasis = "prominent",
        options = {
            {
                label = "Offensive",
                value = "offensive",
                when = { combatStyle = "offensive" },
                patch = { { "combatStyle", "offensive" } },
            },
            {
                label = "Defensive",
                value = "defensive",
                when = { combatStyle = "defensive" },
                patch = { { "combatStyle", "defensive" } },
            },
            {
                label = "Dynamic",
                value = "dynamic",
                when = { combatStyle = "dynamic" },
                patch = { { "combatStyle", "dynamic" } },
            },
            {
                label = "Flashy",
                value = "flashy",
                when = { combatStyle = "flashy" },
                patch = { { "combatStyle", "flashy" } },
            },
        },
    })

    host:section("Movement", "movement", "MOVEMENT", 70)
    host:option("movement", 1, "noclip", "Noclip")
    host:option("movement", 2, "teleportBehind", "Teleport Behind Target")
end

return Presentation
]],
        ["games/duelinggrounds/features/AutoMovement.lua"] = [[local AutoMovement = {}
AutoMovement.__index = AutoMovement

local ZERO = Vector3.zero
local DEFAULT_RANDOM = {
    NextNumber = function(_, minimum, maximum)
        local value = math.random()
        if minimum ~= nil and maximum ~= nil then
            return minimum + (maximum - minimum) * value
        end
        return value
    end,
}

function AutoMovement.new(options)
    options = options or {}
    return setmetatable({
        input = nil,
        lastDirection = nil,
        mode = nil,
        target = nil,
        orbitDirection = 1,
        nextOrbitSwitchAt = 0,
        lastMovementCheckAt = 0,
        lastMovementCheckPosition = nil,
        owned = false,
        random = options.random or (Random and Random.new and Random.new()) or DEFAULT_RANDOM,
        feintUntil = -math.huge,
        radiusScale = 1,
        stopped = false,
    }, AutoMovement)
end

function AutoMovement:_release()
    if self.owned and self.input and self.input.MoveDirection == self.lastDirection then
        self.input.MoveDirection = ZERO
    end
    self.input = nil
    self.lastDirection = nil
    self.owned = false
end

function AutoMovement:_reset()
    self:_release()
    self.mode = nil
    self.target = nil
    self.lastMovementCheckPosition = nil
end

function AutoMovement:_move(input, direction)
    if self.input and self.input ~= input then
        self:_release()
    end
    self.input = input
    self.lastDirection = direction
    self.owned = true
    input.MoveDirection = direction
end

function AutoMovement:update(settings, frame, combatDisposition)
    if self.stopped then
        return
    end
    if
        settings.autoMovement ~= true
        or settings.autoFight ~= true
        or not frame
        or not frame.input
        or not frame.target
        or not frame.localPosition
        or not frame.targetPosition
        or not frame.profile
    then
        self:_reset()
        return
    end

    if combatDisposition and combatDisposition.canMove == false then
        self:_release()
        return
    end

    local now = frame.now or os.clock()
    if frame.target ~= self.target then
        self.target = frame.target
        self.mode = nil
        self.orbitDirection = 1
        self.lastMovementCheckPosition = frame.localPosition
        self.lastMovementCheckAt = now
        self.nextOrbitSwitchAt = now + (frame.orbitInterval or 1.9)
        self.feintUntil = -math.huge
        self.radiusScale = 1
    end

    local offset = frame.targetPosition - frame.localPosition
    local flatOffset = Vector3.new(offset.X, 0, offset.Z)
    local distance = flatOffset.Magnitude
    if distance <= 0.001 then
        self:_move(frame.input, ZERO)
        return
    end

    local profile = frame.profile
    local movement = frame.movement or {}
    local toward = flatOffset.Unit
    if self.mode == "approach" then
        if distance <= profile.orbitDistance + 0.5 then
            self.mode = "orbit"
        end
    elseif self.mode == "retreat" then
        if distance >= profile.orbitDistance - 0.5 then
            self.mode = "orbit"
        end
    elseif distance > profile.approachDistance then
        self.mode = "approach"
    elseif distance < profile.retreatDistance then
        self.mode = "retreat"
    else
        self.mode = "orbit"
    end

    local direction
    if self.mode == "approach" then
        direction = toward
    elseif self.mode == "retreat" then
        direction = -toward
    else
        if now >= self.nextOrbitSwitchAt then
            self.orbitDirection = self.random:NextNumber() < 0.5 and -1 or 1
            self.nextOrbitSwitchAt = now + (movement.orbitInterval or frame.orbitInterval or 1.9)
            self.radiusScale = 1
                + self.random:NextNumber(
                    -(movement.radiusVariance or 0),
                    movement.radiusVariance or 0
                )
            if self.random:NextNumber() < (movement.feintChance or 0) then
                self.feintUntil = now + (movement.feintDuration or 0)
            end
        end
        local tangent = Vector3.new(-toward.Z, 0, toward.X) * self.orbitDirection
        local desiredOrbitDistance = profile.orbitDistance * self.radiusScale
        local radialCorrection = math.clamp((distance - desiredOrbitDistance) / 2, -0.6, 0.6)
        direction = tangent + toward * radialCorrection
        direction = direction.Magnitude > 0 and direction.Unit or tangent
    end

    local tangent = Vector3.new(-toward.Z, 0, toward.X) * self.orbitDirection
    if now < self.feintUntil then
        direction = (-toward * 0.65 + tangent * 0.75).Unit
    elseif self.mode == "approach" and (movement.angularApproach or 0) > 0 then
        direction = (toward + tangent * movement.angularApproach).Unit
    elseif self.mode == "retreat" and (movement.angularApproach or 0) > 0 then
        direction = (-toward + tangent * movement.angularApproach * 0.5).Unit
    end

    if frame.isObstacle and frame.isObstacle(direction) then
        self.orbitDirection = -self.orbitDirection
        direction = Vector3.new(-toward.Z, 0, toward.X) * self.orbitDirection
        self.mode = "orbit"
    end

    if now - self.lastMovementCheckAt >= 0.75 then
        if
            self.lastMovementCheckPosition
            and (frame.localPosition - self.lastMovementCheckPosition).Magnitude < 0.6
        then
            self.orbitDirection = -self.orbitDirection
        end
        self.lastMovementCheckPosition = frame.localPosition
        self.lastMovementCheckAt = now
    end

    self:_move(frame.input, direction)
end

function AutoMovement:stop()
    if self.stopped then
        return
    end
    self:_reset()
    self.stopped = true
end

return AutoMovement
]],
        ["games/duelinggrounds/features/CombatPipeline.lua"] = [[local CombatPipeline = {}

function CombatPipeline.run(phases, frame)
    phases.record(frame)
    phases.defend(frame)
    phases.relocate(frame)
    phases.attack(frame)
    phases.move(frame)
    phases.effects(frame)
    phases.render(frame)
end

return CombatPipeline
]],
        ["games/duelinggrounds/features/CombatRuntime.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Attacks = importDependency("games/duelinggrounds/features/combat/Attacks", "./combat/Attacks")
local DynamicStyle =
    importDependency("games/duelinggrounds/features/combat/DynamicStyle", "./combat/DynamicStyle")
local EnemyObserver =
    importDependency("games/duelinggrounds/features/combat/EnemyObserver", "./combat/EnemyObserver")
local Skill = importDependency("games/duelinggrounds/features/combat/Skill", "./combat/Skill")
local Planner = importDependency(
    "games/duelinggrounds/features/combat/defense/Planner",
    "./combat/defense/Planner"
)
local DefenseExecutor = importDependency(
    "games/duelinggrounds/features/combat/defense/Executor",
    "./combat/defense/Executor"
)
local OffenseExecutor = importDependency(
    "games/duelinggrounds/features/combat/offense/Executor",
    "./combat/offense/Executor"
)

local CombatRuntime = {}
CombatRuntime.__index = CombatRuntime

local function addAnimation(set, animation)
    if typeof(animation) == "Instance" and animation:IsA("Animation") then
        set[animation.AnimationId] = true
    end
end

local function collectAnimations(value, set, seen)
    if typeof(value) == "Instance" then
        addAnimation(set, value)
        return
    end
    if type(value) ~= "table" or seen[value] then
        return
    end
    seen[value] = true
    for _, child in pairs(value) do
        collectAnimations(child, set, seen)
    end
end

local function weaponInfo(handler)
    local weapon = handler and handler:GetEquippedWeaponHandler()
    return weapon and weapon.WeaponInfo
end

local function targetAnimationSets(handler)
    local sets = { block = {}, parry = {}, stagger = {} }
    local info = weaponInfo(handler)
    if not info then
        return sets
    end
    addAnimation(sets.block, info.BlockAnimation)
    addAnimation(sets.block, info.Animations and info.Animations.Block)
    local stagger = info.StaggerTypes or {}
    collectAnimations(stagger.Parry, sets.parry, {})
    collectAnimations(stagger.PostureBreak, sets.stagger, {})
    collectAnimations(stagger.PostureParry, sets.stagger, {})
    for _, attackInfo in pairs(info.BasicAttackTypes or {}) do
        collectAnimations(attackInfo.deflectStun, sets.stagger, {})
    end
    return sets
end

local function trackRemaining(track, fallback)
    local speed = math.max(math.abs(track.Speed), 0.05)
    return type(track.Length) == "number"
            and track.Length > 0
            and math.max((track.Length - track.TimePosition) / speed, 0.05)
        or fallback
end

function CombatRuntime.new(context)
    assert(
        context and context.players and context.players.LocalPlayer,
        "CombatRuntime requires Players"
    )
    assert(
        context.characterController and context.targetLockController,
        "CombatRuntime requires controllers"
    )
    local self = setmetatable({
        context = context,
        record = context.record or function() end,
        activeThreats = {},
        targetState = {
            blockTracks = {},
            dodgeUntil = -math.huge,
            parryUntil = -math.huge,
            staggerUntil = -math.huge,
        },
        dynamicState = DynamicStyle.new(),
        skillRandom = context.skillRandom or Random.new(),
        defenseIntent = nil,
        boundTarget = nil,
        animationSets = {},
        localHandler = nil,
        localWeapon = nil,
        localConnection = nil,
        localDeflectAnimations = {},
        lastCombatStyle = nil,
        stopped = false,
    }, CombatRuntime)
    self.defense = DefenseExecutor.new(context)
    self.offense = OffenseExecutor.new({
        characterController = context.characterController,
        targetLockController = context.targetLockController,
        random = context.offenseRandom,
        ping = context.ping,
        criticalStrike = context.criticalStrike,
        record = self.record,
        recordProbeAttack = function(at)
            self.dynamicState = DynamicStyle.recordProbeAttack(self.dynamicState, at)
        end,
    })
    self.enemies = EnemyObserver.new({
        players = context.players,
        localPlayer = context.players.LocalPlayer,
        characterController = context.characterController,
        observeTrack = function(handler, track, model)
            self:_observeTrack(handler, track, model)
        end,
        removeHandler = function(handler)
            for track, threat in pairs(self.activeThreats) do
                if threat.handler == handler then
                    self.activeThreats[track] = nil
                end
            end
        end,
    })
    return self
end

function CombatRuntime:_observeTrack(handler, track, model)
    local animation = track.Animation
    local target = self.context.targetLockController.Target
    local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
    self.record("animation", {
        side = model == targetModel and "target" or "enemy",
        id = animation and animation.AnimationId or "",
        name = animation and animation.Name or "",
    })
    local info = weaponInfo(handler)
    local attackInfo, attackName =
        Attacks.findByAnimation(info and info.BasicAttackTypes, animation)
    if attackInfo then
        if not self.activeThreats[track] then
            self.activeThreats[track] = {
                attackInfo = attackInfo,
                attackName = attackName,
                isHeavy = Attacks.isHeavy(attackName, attackInfo),
                handler = handler,
                reacted = {},
            }
            local localHandler = self.context.characterController:GetLocalCharacterHandler()
            local actions = localHandler and localHandler.ActionManager
            if actions then
                actions:_clearQueuedAction()
                local current = actions.CurrentAction
                if current and current.ActionType == "BasicAttack" and current.CanCancel then
                    actions:SwitchToAction(nil)
                end
            end
        end
        return
    end
    if model ~= targetModel then
        return
    end
    local sets = self.animationSets[model] or targetAnimationSets(handler)
    self.animationSets[model] = sets
    local id = animation and animation.AnimationId or ""
    local name = string.lower(animation and animation.Name or "")
    local now = os.clock()
    if sets.block[id] or name == "block" then
        self.targetState.blockTracks[track] = now
    elseif sets.parry[id] then
        self.targetState.parryUntil =
            math.max(self.targetState.parryUntil, now + trackRemaining(track, 0.45))
    elseif string.find(name, "dodge", 1, true) then
        self.targetState.dodgeUntil =
            math.max(self.targetState.dodgeUntil, now + trackRemaining(track, 0.65))
    elseif sets.stagger[id] or string.find(name, "posturebreak", 1, true) then
        self.targetState.staggerUntil =
            math.max(self.targetState.staggerUntil, now + trackRemaining(track, 0.5))
    end
end

function CombatRuntime:_observeLocal()
    local handler = self.context.characterController:GetLocalCharacterHandler()
    local weapon = handler and handler:GetEquippedWeaponHandler()
    if handler == self.localHandler and weapon == self.localWeapon then
        return
    end
    if self.localConnection then
        self.localConnection:Disconnect()
        self.localConnection = nil
    end
    table.clear(self.localDeflectAnimations)
    self.localHandler, self.localWeapon = handler, weapon
    local animator = handler and handler.Animator
    local info = weapon and weapon.WeaponInfo
    if not animator or not info then
        return
    end
    for _, attackInfo in pairs(info.BasicAttackTypes or {}) do
        collectAnimations(attackInfo.deflectStun, self.localDeflectAnimations, {})
    end
    self.localConnection = animator.AnimationPlayed:Connect(function(track)
        local animation = track.Animation
        local id = animation and animation.AnimationId or ""
        local name = string.lower(animation and animation.Name or "")
        self.record("animation", {
            side = "self",
            id = id,
            name = animation and animation.Name or "",
        })
        if self.localDeflectAnimations[id] or string.find(name, "deflected", 1, true) then
            self.dynamicState = DynamicStyle.recordDeflect(
                self.dynamicState,
                os.clock(),
                self.lastCombatStyle == "dynamic",
                self.offense:disposition().lastAttackAt
            )
        end
        self.offense:recordAnimation(animation and animation.Name or "")
    end)
end

function CombatRuntime:_resetTarget(targetModel)
    if targetModel == self.boundTarget then
        return
    end
    self.boundTarget = targetModel
    table.clear(self.targetState.blockTracks)
    self.targetState.dodgeUntil = -math.huge
    self.targetState.parryUntil = -math.huge
    self.targetState.staggerUntil = -math.huge
end

function CombatRuntime:_targetBlocking()
    for track in pairs(self.targetState.blockTracks) do
        if not track.IsPlaying then
            self.targetState.blockTracks[track] = nil
        end
    end
    return next(self.targetState.blockTracks) ~= nil
end

function CombatRuntime:_punishWindow()
    local longest = 0
    for track, threat in pairs(self.activeThreats) do
        if track.IsPlaying then
            local lastImpact = Attacks.lastImpactTime(threat.attackInfo)
            local canCancel = Attacks.marker(threat.attackInfo, "canCancel")
            if lastImpact and canCancel and track.TimePosition >= lastImpact - 0.03 then
                longest = math.max(
                    longest,
                    (canCancel - track.TimePosition) / math.max(math.abs(track.Speed), 0.05)
                )
            end
        end
    end
    return math.max(longest, 0)
end

function CombatRuntime:_hasIncomingThreat(localRoot)
    for track, threat in pairs(self.activeThreats) do
        if track.IsPlaying then
            local speed = math.max(math.abs(track.Speed), 0.05)
            for index, impact in ipairs(threat.attackInfo.impacts or {}) do
                if
                    not threat.reacted[index]
                    and (impact.markerTime - track.TimePosition) / speed >= -0.08
                    and Attacks.impactCanReach(
                        threat.handler and threat.handler.Root,
                        localRoot,
                        impact
                    )
                then
                    return true
                end
            end
        end
    end
    return false
end

function CombatRuntime:_executeDefense(settings, target)
    local intent = self.defenseIntent
    if not intent then
        return
    end
    local now = os.clock()
    if now > intent.expiresAt then
        self.record("defenseExpired", intent)
        self.defenseIntent = nil
        return
    end
    local succeeded, reason = self.defense:execute(intent, settings, target, self.dynamicState)
    if succeeded then
        self.record("defenseExecuted", intent)
        local pendingAt, pendingUntil, counterAttack = self.defense:consumeCounter()
        if pendingUntil then
            self.offense:setDodgeCounter(pendingAt, pendingUntil, counterAttack)
        end
        self.defenseIntent = nil
    elseif now >= intent.impactAt - 0.04 then
        local fallback = Planner.fallback(intent, self.defense:availability())
        if fallback then
            local replacement = table.clone(intent)
            replacement.kind = fallback
            if self.defense:execute(replacement, settings, target, self.dynamicState) then
                self.record("defenseFallback", replacement)
                local pendingAt, pendingUntil, counterAttack = self.defense:consumeCounter()
                if pendingUntil then
                    self.offense:setDodgeCounter(pendingAt, pendingUntil, counterAttack)
                end
                self.defenseIntent = nil
                return
            end
        end
        intent.lastFailure = reason
    end
end

function CombatRuntime:_updateThreats(settings, frame)
    local localHandler = frame.localHandler
        or self.context.characterController:GetLocalCharacterHandler()
    local localRoot = localHandler and localHandler.Root
    if not localRoot then
        return
    end
    local skill = Skill.profile(settings.botSkill)
    local lead = math.clamp(
        (self.context.ping() or 0) + 0.04 - Skill.reactionDelay(skill, self.skillRandom),
        0.01,
        0.16
    )
    for track, threat in pairs(self.activeThreats) do
        if not track.IsPlaying then
            self.activeThreats[track] = nil
            continue
        end
        local speed = math.max(math.abs(track.Speed), 0.05)
        local impactInputs = {}
        for index, impact in ipairs(threat.attackInfo.impacts or {}) do
            local untilImpact = (impact.markerTime - track.TimePosition) / speed
            impactInputs[index] = {
                parryable = Attacks.isParryable(impact),
                timeUntilImpact = untilImpact,
                source = impact,
            }
            if untilImpact < -0.08 then
                threat.reacted[index] = true
            end
        end
        local availability = self.defense:availability()
        local intent = Planner.plan({
            attackName = threat.attackName,
            isHeavy = threat.isHeavy,
            impacts = impactInputs,
            canDodge = availability.canDodge,
            canParry = availability.canParry,
            canReach = function(impact, index)
                local reactionLead = threat.isHeavy and math.max(lead, 0.2) or lead
                return not threat.reacted[index]
                    and impact.timeUntilImpact <= reactionLead
                    and Attacks.impactCanReach(
                        threat.handler and threat.handler.Root,
                        localRoot,
                        impact.source
                    )
            end,
        })
        if intent and Skill.shouldAct(skill, self.skillRandom) then
            local now = os.clock()
            intent.impactAt = now + intent.timeUntilImpact
            intent.expiresAt = intent.impactAt + 0.08
            if not self.defenseIntent or intent.impactAt < self.defenseIntent.impactAt then
                self.defenseIntent = intent
                threat.reacted[intent.impactIndex] = true
                self.record("defenseSelected", intent)
            end
        elseif intent then
            threat.reacted[intent.impactIndex] = true
            self.record("defenseMissed", {
                attack = intent.attackName,
                impactIndex = intent.impactIndex,
                skill = skill.level,
            })
        end
    end
end

function CombatRuntime:observeAndDefend(settings, frame)
    if self.stopped then
        return
    end
    frame = frame or {}
    if settings.combatStyle ~= self.lastCombatStyle then
        self.dynamicState = DynamicStyle.reset()
        self.lastCombatStyle = settings.combatStyle
    end
    self:_observeLocal()
    if settings.autoFight ~= true then
        self.defenseIntent = nil
        self.enemies:clear()
        return
    end
    local target = frame.target or self.context.targetLockController.Target
    local targetModel = frame.targetModel or target and target:FindFirstAncestorWhichIsA("Model")
    self:_resetTarget(targetModel)
    self.enemies:refresh(target)
    self:_executeDefense(settings, target)
    self:_updateThreats(settings, frame)
    self:_executeDefense(settings, target)
end

function CombatRuntime:attack(settings, frame)
    if self.stopped then
        return
    end
    frame = frame or {}
    local target = frame.target or self.context.targetLockController.Target
    local targetModel = frame.targetModel or target and target:FindFirstAncestorWhichIsA("Model")
    local targetHandler = frame.targetHandler
        or targetModel and self.context.characterController:GetCharacterHandler(targetModel)
    local localHandler = frame.localHandler
        or self.context.characterController:GetLocalCharacterHandler()
    local disposition = self:disposition()
    local viablePunish = disposition.targetStaggered or disposition.punishWindow >= 0.35
    local behavior
    self.dynamicState, behavior = DynamicStyle.update(self.dynamicState, os.clock(), viablePunish)
    disposition.dynamicState = self.dynamicState
    if settings.combatStyle == "dynamic" and behavior == "hold" then
        return
    end
    frame.target = target
    frame.targetModel = targetModel
    frame.targetHandler = targetHandler
    frame.targetRoot = frame.targetRoot or targetHandler and targetHandler.Root or target
    frame.localHandler = localHandler
    self.offense:attack(settings, frame, disposition)
end

function CombatRuntime:disposition()
    local now = os.clock()
    local localHandler = self.context.characterController:GetLocalCharacterHandler()
    local target = self.context.targetLockController.Target
    local targetModel = target and target:FindFirstAncestorWhichIsA("Model")
    local targetHandler = targetModel
        and self.context.characterController:GetCharacterHandler(targetModel)
    return {
        defenseIntent = self.defenseIntent,
        incomingThreat = self:_hasIncomingThreat(localHandler and localHandler.Root),
        targetBlocking = self:_targetBlocking()
            or targetHandler and targetHandler.IsBlocking
            or false,
        targetDodging = now <= self.targetState.dodgeUntil
            or targetHandler and targetHandler.IsDodging
            or false,
        targetParrying = now <= self.targetState.parryUntil
            or targetHandler and targetHandler.IsParrying
            or false,
        targetStaggered = now <= self.targetState.staggerUntil,
        targetStaggerRemaining = math.max(self.targetState.staggerUntil - now, 0),
        punishWindow = self:_punishWindow(),
        dynamicState = self.dynamicState,
        defense = self.defense:disposition(),
        offense = self.offense:disposition(),
    }
end

function CombatRuntime:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self.enemies:stop()
    self.defense:stop()
    self.offense:stop()
    if self.localConnection then
        self.localConnection:Disconnect()
        self.localConnection = nil
    end
    table.clear(self.activeThreats)
    table.clear(self.targetState.blockTracks)
    table.clear(self.animationSets)
    table.clear(self.localDeflectAnimations)
    self.defenseIntent = nil
    self.localHandler = nil
    self.localWeapon = nil
end

return CombatRuntime
]],
        ["games/duelinggrounds/features/Noclip.lua"] = [[local Noclip = {}
Noclip.__index = Noclip

function Noclip.new()
    return setmetatable({
        character = nil,
        originals = {},
        stopped = false,
    }, Noclip)
end

function Noclip:_restore()
    for part, canCollide in pairs(self.originals) do
        if part.Parent then
            part.CanCollide = canCollide
        end
    end
    table.clear(self.originals)
end

function Noclip:update(enabled, character)
    if self.stopped then
        return
    end
    if self.character ~= character then
        self:_restore()
        self.character = character
    end
    if enabled ~= true or not character then
        self:_restore()
        return
    end

    for part in pairs(self.originals) do
        if not part:IsDescendantOf(character) then
            if part.Parent then
                part.CanCollide = self.originals[part]
            end
            self.originals[part] = nil
        end
    end
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if self.originals[descendant] == nil then
                self.originals[descendant] = descendant.CanCollide
            end
            descendant.CanCollide = false
        end
    end
end

function Noclip:stop()
    if self.stopped then
        return
    end
    self:_restore()
    self.character = nil
    self.stopped = true
end

return Noclip
]],
        ["games/duelinggrounds/features/TeleportBehind.lua"] = [[local TeleportBehind = {}

function TeleportBehind.update(settings, frame)
    if settings.teleportBehind ~= true
        or not frame
        or frame.targetDead == true
        or not frame.localRoot
        or not frame.targetRoot
    then
        return false
    end

    local targetLook = frame.targetRoot.CFrame.LookVector
    local flatLook = Vector3.new(targetLook.X, 0, targetLook.Z)
    if flatLook.Magnitude <= 0.001 then
        return false
    end

    local destination = frame.targetRoot.Position
        - flatLook.Unit * (frame.distance or 3)
    frame.localRoot.CFrame = CFrame.lookAt(
        destination,
        Vector3.new(
            frame.targetRoot.Position.X,
            destination.Y,
            frame.targetRoot.Position.Z
        )
    )
    return true
end

return TeleportBehind
]],
        ["games/duelinggrounds/features/WinTitles.lua"] = [[local WinTitles = {}
WinTitles.__index = WinTitles

local function hasWinTitle(title)
    return string.match(title, "%(%d+ Wins?%)$") ~= nil
        or string.match(title, "^%d+ Wins?$") ~= nil
end

function WinTitles.new()
    return setmetatable({
        originals = {},
        stopped = false,
    }, WinTitles)
end

function WinTitles:_restore(label)
    if label.Parent then
        label.Text = self.originals[label]
    end
    self.originals[label] = nil
end

function WinTitles:update(enabled, players)
    if self.stopped then
        return
    end

    local active = {}
    for _, player in ipairs(players:GetPlayers()) do
        local character = player.Character
        local label = character and character:FindFirstChild("PlayerTitleLabel", true)
        local title = player:GetAttribute("TitleDisplayName")
        if label and label:IsA("TextLabel") and type(title) == "string" then
            active[label] = true
            if self.originals[label] == nil then
                self.originals[label] = label.Text
            end
            local wins = player:GetAttribute("TotalWins")
            if enabled == true
                and title ~= ""
                and not hasWinTitle(title)
                and type(wins) == "number"
            then
                label.Text = ("%s (%d Wins)"):format(title, wins)
            else
                label.Text = self.originals[label]
            end
        end
    end

    for label in pairs(self.originals) do
        if not active[label] then
            self:_restore(label)
        end
    end
end

function WinTitles:stop()
    if self.stopped then
        return
    end
    for label in pairs(self.originals) do
        self:_restore(label)
    end
    self.stopped = true
end

return WinTitles
]],
        ["games/duelinggrounds/features/combat/Attacks.lua"] = [[local Attacks = {}

local UNKNOWN_ATTACK_REACH = 12

local function impacts(attackInfo)
    return attackInfo and attackInfo.impacts or {}
end

function Attacks.sameAnimation(left, right)
    return left ~= nil
        and right ~= nil
        and (left == right or left.AnimationId == right.AnimationId)
end

function Attacks.findByAnimation(attackTypes, animation)
    if not attackTypes or not animation then
        return nil
    end
    for attackName, attackInfo in pairs(attackTypes) do
        if Attacks.sameAnimation(attackInfo.animation, animation) then
            return attackInfo, attackName
        end
    end
    return nil
end

function Attacks.firstImpactTime(attackInfo)
    local first = math.huge
    for _, impact in ipairs(impacts(attackInfo)) do
        if type(impact.markerTime) == "number" then
            first = math.min(first, impact.markerTime)
        end
    end
    return first < math.huge and first or nil
end

function Attacks.lastImpactTime(attackInfo)
    local last = -math.huge
    for _, impact in ipairs(impacts(attackInfo)) do
        if type(impact.markerTime) == "number" then
            last = math.max(last, impact.markerTime)
        end
    end
    return last > -math.huge and last or nil
end

function Attacks.marker(attackInfo, markerName)
    local timeMarkers = attackInfo and attackInfo.timeMarkers
    return timeMarkers and timeMarkers[markerName] or nil
end

function Attacks.impactResultValue(attackInfo, resultName, valueName)
    local impact = impacts(attackInfo)[1]
    local results = impact and impact.impactInfo and impact.impactInfo.impactResults
    local result = results and results[resultName]
    return result and result[valueName] or 0
end

function Attacks.triggersUltimateDamage(attackInfo)
    for _, impact in ipairs(impacts(attackInfo)) do
        local results = impact.impactInfo
            and impact.impactInfo.impactResults
        if results and results.GetHit and results.GetHit.triggerUltimate == true then
            return true
        end
    end
    return false
end

function Attacks.isHeavy(attackName, attackInfo)
    if string.find(string.lower(attackName or ""), "heavy", 1, true) then
        return true
    end
    return Attacks.impactResultValue(attackInfo, "GetHit", "healthDamage") >= 50
        or Attacks.impactResultValue(attackInfo, "Block", "postureDamage") >= 30
end

function Attacks.isParryable(impact)
    local results = impact and impact.impactInfo and impact.impactInfo.impactResults
    return results ~= nil and results.Parry ~= nil
end

function Attacks.isMultiHit(attackInfo)
    return #impacts(attackInfo) > 1
end

function Attacks.impactContainsPoint(attackerCFrame, point, impact, margin)
    local impactInfo = impact and impact.impactInfo
    local hitboxCFrame = impactInfo and impactInfo.hitboxCFrame
    local hitboxSize = impactInfo and impactInfo.hitboxSize
    if typeof(hitboxCFrame) ~= "CFrame" or typeof(hitboxSize) ~= "Vector3" then
        return false
    end
    local localPoint = (attackerCFrame * hitboxCFrame):PointToObjectSpace(point)
    local allowance = hitboxSize / 2 + (margin or Vector3.zero)
    return math.abs(localPoint.X) <= allowance.X
        and math.abs(localPoint.Y) <= allowance.Y
        and math.abs(localPoint.Z) <= allowance.Z
end

function Attacks.impactCanReach(attacker, defender, impact, options)
    if not attacker or not defender or not impact then
        return false
    end
    options = options or {}
    if Attacks.impactContainsPoint(attacker.CFrame, defender.Position, impact, options.margin) then
        return true
    end
    if options.strict then
        return false
    end

    local offset = defender.Position - attacker.Position
    local flatOffset = Vector3.new(offset.X, 0, offset.Z)
    if flatOffset.Magnitude <= 0 then
        return false
    end
    local impactInfo = impact.impactInfo
    local hitboxCFrame = impactInfo and impactInfo.hitboxCFrame
    local hitboxSize = impactInfo and impactInfo.hitboxSize
    local maximumReach = options.unknownReach or UNKNOWN_ATTACK_REACH
    local minimumFacing = 0
    if typeof(hitboxCFrame) == "CFrame" and typeof(hitboxSize) == "Vector3" then
        maximumReach = math.abs(hitboxCFrame.Position.Z) + hitboxSize.Z / 2
            + (options.reachAllowance or 4)
        minimumFacing = options.minimumFacing or 0.15
    end
    return flatOffset.Magnitude <= maximumReach
        and attacker.CFrame.LookVector:Dot(flatOffset.Unit) >= minimumFacing
end

function Attacks.canReach(attacker, defender, attackInfo, options)
    for _, impact in ipairs(impacts(attackInfo)) do
        if Attacks.impactCanReach(attacker, defender, impact, options) then
            return true
        end
    end
    return false
end

function Attacks.geometricReach(attackInfo, allowance)
    local maximumReach = 0
    for _, impact in ipairs(impacts(attackInfo)) do
        local impactInfo = impact.impactInfo
        local hitboxCFrame = impactInfo and impactInfo.hitboxCFrame
        local hitboxSize = impactInfo and impactInfo.hitboxSize
        if typeof(hitboxCFrame) == "CFrame" and typeof(hitboxSize) == "Vector3" then
            maximumReach = math.max(
                maximumReach,
                math.abs(hitboxCFrame.Position.Z) + hitboxSize.Z / 2 + (allowance or 0)
            )
        end
    end
    return maximumReach
end

return Attacks
]],
        ["games/duelinggrounds/features/combat/Combos.lua"] = [[local Combos = {}

local COMBOS = {
    BoStaff = { finisherAfter = 2 },
    CurvedBlades = { finisherAfter = 2 },
    Daggers = { finisherAfter = 1 },
    Gauntlets = { finisherAfter = 2 },
    Katana = { finisherAfter = 3 },
    Kusarigama = { finisherAfter = 2 },
    Naginata = { finisherAfter = 2 },
    ["War Hammer"] = { finisherAfter = 1 },
}

function Combos.profile(weaponName)
    return COMBOS[weaponName] or { finisherAfter = 2 }
end

function Combos.nextAttack(state)
    state = state or {}
    local lightCount = state.lightCount or 0
    local profile = Combos.profile(state.weaponName)
    local finisherAfter = profile.finisherAfter
    local canHeavy = state.hasHeavy == true
    local flashy = state.style == "flashy"

    if state.recentDeflects and state.recentDeflects >= 2 then
        return nil, "disengageAfterDeflects"
    end
    if state.targetBlocking and canHeavy then
        return "Heavy", "guardPressure"
    end
    if canHeavy and lightCount >= finisherAfter then
        return "Heavy", "comboFinisher"
    end
    if flashy and state.canDashHeavy and state.afterDodge then
        return "Heavy", "dodgeHeavyVariation"
    end
    return "Light", lightCount == 0 and "comboStarter" or "comboContinue"
end

return Combos
]],
        ["games/duelinggrounds/features/combat/DefensiveStyle.lua"] = [[local DefensiveStyle = {}

function DefensiveStyle.preferences()
    return {
        allowOffense = false,
        counterAllowed = false,
        movement = {
            orbitDistanceScale = 1.2,
        },
    }
end

return DefensiveStyle
]],
        ["games/duelinggrounds/features/combat/DynamicStyle.lua"] = [[local DynamicStyle = {}

local DEFLECT_WINDOW = 8

function DynamicStyle.new()
    return {
        mode = "offensive",
        deflectTimes = {},
        defensiveUntil = -math.huge,
        probeUntil = nil,
    }
end

local function copy(state)
    local nextState = {
        mode = state.mode,
        deflectTimes = {},
        defensiveUntil = state.defensiveUntil,
        probeUntil = state.probeUntil,
    }
    for _, time in ipairs(state.deflectTimes or {}) do
        table.insert(nextState.deflectTimes, time)
    end
    return nextState
end

function DynamicStyle.reset()
    return DynamicStyle.new()
end

function DynamicStyle.recordDeflect(state, now, isDynamic, lastAttackAt)
    local nextState = copy(state)
    if not isDynamic or now - lastAttackAt > 1.2 then
        return nextState
    end
    table.insert(nextState.deflectTimes, now)
    while nextState.deflectTimes[1] and now - nextState.deflectTimes[1] > DEFLECT_WINDOW do
        table.remove(nextState.deflectTimes, 1)
    end
    if isDynamic and (#nextState.deflectTimes >= 3 or nextState.mode == "probing") then
        nextState.mode = "defensive"
        nextState.probeUntil = nil
        nextState.defensiveUntil = now + math.min(2.5 + #nextState.deflectTimes * 0.5, 5)
    end
    return nextState
end

function DynamicStyle.update(state, now, viablePunish)
    local nextState = copy(state)
    if nextState.mode == "probing" and nextState.probeUntil then
        if now >= nextState.probeUntil then
            return DynamicStyle.new(), "resume"
        end
        return nextState, "hold"
    end
    if nextState.mode == "defensive" then
        if now < nextState.defensiveUntil and not viablePunish then
            return nextState, "hold"
        end
        nextState.mode = "probing"
        nextState.probeUntil = nil
        return nextState, "probe"
    end
    return nextState, "attack"
end

function DynamicStyle.recordProbeAttack(state, attackAt)
    local nextState = copy(state)
    if nextState.mode == "probing" then
        nextState.probeUntil = attackAt + 1.25
    end
    return nextState
end

function DynamicStyle.preferences(state)
    local defensive = state and state.mode == "defensive"
    return {
        allowOffense = not defensive,
        counterAllowed = not defensive,
        movement = {
            orbitDistanceScale = defensive and 1.2 or 1,
        },
    }
end

return DynamicStyle
]],
        ["games/duelinggrounds/features/combat/EnemyObserver.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local EnemyPolicy =
    importDependency("games/duelinggrounds/features/combat/EnemyPolicy", "./EnemyPolicy")

local EnemyObserver = {}
EnemyObserver.__index = EnemyObserver

local function characterSnapshot(model)
    return model
            and {
                model = model,
                isDead = model:GetAttribute("IsDead") == true,
                teamGroup = model:GetAttribute("TeamGroup"),
            }
        or nil
end

function EnemyObserver.new(context)
    assert(context and context.players and context.localPlayer, "EnemyObserver requires players")
    assert(context.characterController, "EnemyObserver requires CharacterController")
    assert(type(context.observeTrack) == "function", "EnemyObserver requires observeTrack")
    return setmetatable({
        context = context,
        observations = {},
        stopped = false,
    }, EnemyObserver)
end

function EnemyObserver:_disconnect(model)
    local observation = self.observations[model]
    if not observation then
        return
    end
    observation.connection:Disconnect()
    self.observations[model] = nil
    if self.context.removeHandler then
        self.context.removeHandler(observation.handler)
    end
end

function EnemyObserver:_observe(model)
    if self.observations[model] then
        return
    end
    local handler = self.context.characterController:GetCharacterHandler(model)
    local animator = handler and handler.Animator
    if not animator then
        return
    end
    local function observe(track)
        self.context.observeTrack(handler, track, model)
    end
    self.observations[model] = {
        connection = animator.AnimationPlayed:Connect(observe),
        handler = handler,
    }
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        observe(track)
    end
end

function EnemyObserver:refresh(lockedTarget)
    if self.stopped then
        return
    end
    local lockedModel = lockedTarget and lockedTarget:FindFirstAncestorWhichIsA("Model")
    local localPlayer = self.context.localPlayer
    local candidates = {}
    local modelBySnapshot = {}
    for _, player in ipairs(self.context.players:GetPlayers()) do
        local snapshot = {
            player = player,
            character = characterSnapshot(player.Character),
        }
        table.insert(candidates, snapshot)
        if snapshot.character then
            modelBySnapshot[snapshot] = snapshot.character.model
        end
    end
    local localSnapshot = {
        player = localPlayer,
        character = characterSnapshot(localPlayer.Character),
    }
    local lockedSnapshot = lockedModel and {
        character = characterSnapshot(lockedModel),
    } or nil
    local current = {}
    for _, candidate in ipairs(EnemyPolicy.filter(localSnapshot, candidates, lockedSnapshot)) do
        local model = modelBySnapshot[candidate]
        if model then
            current[model] = true
        end
    end

    -- A lock can point at an NPC or a player omitted by Players:GetPlayers().
    if lockedModel and lockedModel:GetAttribute("IsDead") ~= true then
        current[lockedModel] = true
    end
    for model in pairs(current) do
        self:_observe(model)
    end
    for model in pairs(self.observations) do
        if not current[model] then
            self:_disconnect(model)
        end
    end
end

function EnemyObserver:clear()
    for model in pairs(self.observations) do
        self:_disconnect(model)
    end
end

function EnemyObserver:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:clear()
end

return EnemyObserver
]],
        ["games/duelinggrounds/features/combat/EnemyPolicy.lua"] = [[local EnemyPolicy = {}

local function isValidCharacter(character)
    if character == nil then
        return false
    end
    local isDead = character.isDead
    if type(character.GetAttribute) == "function" then
        isDead = character:GetAttribute("IsDead")
    end
    return isDead ~= true
end

local function teamGroup(character)
    if type(character.GetAttribute) == "function" then
        return character:GetAttribute("TeamGroup")
    end
    return character.teamGroup
end

function EnemyPolicy.isEnemy(localPlayer, candidate, lockedTarget)
    if
        candidate == nil
        or candidate == localPlayer
        or candidate.player ~= nil and candidate.player == localPlayer.player
        or not isValidCharacter(candidate.character)
    then
        return false
    end
    if candidate == lockedTarget or candidate.character == lockedTarget then
        return true
    end

    local localCharacter = localPlayer and localPlayer.character
    local localTeamGroup = localCharacter and teamGroup(localCharacter)
    local candidateTeamGroup = teamGroup(candidate.character)
    return localTeamGroup ~= nil
        and candidateTeamGroup ~= nil
        and candidateTeamGroup ~= localTeamGroup
end

function EnemyPolicy.filter(localPlayer, candidates, lockedTarget)
    local enemies = {}
    for _, candidate in ipairs(candidates or {}) do
        if EnemyPolicy.isEnemy(localPlayer, candidate, lockedTarget) then
            table.insert(enemies, candidate)
        end
    end
    return enemies
end

return EnemyPolicy
]],
        ["games/duelinggrounds/features/combat/FlashyStyle.lua"] = [[local FlashyStyle = {}

function FlashyStyle.preferences(state)
    state = state or {}
    local health = state.health or math.huge
    local maximumHealth = math.max(state.maximumHealth or health, 1)
    local posture = state.posture or math.huge
    local maximumPosture = math.max(state.maximumPosture or posture, 1)
    local pressured = health / maximumHealth < 0.35
        or posture / maximumPosture < 0.3
        or state.defenseReady == false

    return {
        allowOffense = true,
        aggressiveCombos = true,
        counterAllowed = not pressured,
        proactiveDashCounter = not pressured,
        punishOnly = true,
        suppressTraversalDodge = true,
        movement = {
            angularApproach = pressured and 0.35 or 0.72,
            feintChance = pressured and 0.08 or 0.28,
            feintDuration = pressured and 0.12 or 0.22,
            orbitInterval = pressured and 1.1 or 0.65,
            orbitDistanceScale = pressured and 1.2 or 0.9,
            radiusVariance = pressured and 0.08 or 0.28,
        },
    }
end

return FlashyStyle
]],
        ["games/duelinggrounds/features/combat/JumpAttackPolicy.lua"] = [[local JumpAttackPolicy = {}

function JumpAttackPolicy.shouldJump(state)
    state = state or {}
    if
        not state.available
        or not state.jumpReady
        or not state.cooldownReady
        or not state.canQueue
    then
        return false
    end
    local postureBreak = state.targetBlocking
        and state.postureDamage > 0
        and type(state.targetPosture) == "number"
        and state.targetPosture <= state.postureDamage
    local staggerPunish = state.targetStaggered
        and state.healthDamage > 0
        and state.healthDamage >= state.heavyHealthDamage
        and state.staggerRemaining >= 0.9
    return (postureBreak or staggerPunish) and (state.inRange or state.canLunge),
        postureBreak and "postureBreak" or "staggerPunish"
end

return JumpAttackPolicy
]],
        ["games/duelinggrounds/features/combat/OffensiveStyle.lua"] = [[local OffensiveStyle = {}

function OffensiveStyle.preferences()
    return {
        allowOffense = true,
        counterAllowed = true,
        movement = {
            orbitDistanceScale = 1,
        },
    }
end

return OffensiveStyle
]],
        ["games/duelinggrounds/features/combat/Skill.lua"] = [[local Skill = {}

local function clampLevel(level)
    return math.clamp(type(level) == "number" and level or 85, 0, 100)
end

function Skill.profile(level)
    local normalized = clampLevel(level) / 100
    return {
        level = clampLevel(level),
        reactionDelay = 0.02 + (1 - normalized) * 0.28,
        reactionJitter = (1 - normalized) * 0.12,
        defenseAccuracy = 0.55 + normalized * 0.45,
        punishAccuracy = 0.45 + normalized * 0.55,
        movementPrecision = 0.5 + normalized * 0.5,
    }
end

function Skill.shouldAct(profile, random)
    return random:NextNumber() <= profile.defenseAccuracy
end

function Skill.reactionDelay(profile, random)
    return profile.reactionDelay
        + random:NextNumber(-profile.reactionJitter, profile.reactionJitter)
end

function Skill.shouldPunish(profile, random)
    return random:NextNumber() <= profile.punishAccuracy
end

return Skill
]],
        ["games/duelinggrounds/features/combat/Styles.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local DefensiveStyle = importDependency(
    "games/duelinggrounds/features/combat/DefensiveStyle",
    "./DefensiveStyle"
)
local DynamicStyle = importDependency(
    "games/duelinggrounds/features/combat/DynamicStyle",
    "./DynamicStyle"
)
local FlashyStyle = importDependency(
    "games/duelinggrounds/features/combat/FlashyStyle",
    "./FlashyStyle"
)
local OffensiveStyle = importDependency(
    "games/duelinggrounds/features/combat/OffensiveStyle",
    "./OffensiveStyle"
)

local Styles = {}

function Styles.preferences(name, state, dynamicState)
    if name == "defensive" then
        return DefensiveStyle.preferences(state)
    end
    if name == "dynamic" then
        return DynamicStyle.preferences(dynamicState)
    end
    if name == "flashy" then
        return FlashyStyle.preferences(state)
    end
    return OffensiveStyle.preferences(state)
end

return Styles
]],
        ["games/duelinggrounds/features/combat/UltimatePolicy.lua"] = [[local UltimatePolicy = {}

function UltimatePolicy.shouldUseNeutral(state)
    state = state or {}
    if state.targetDodging or state.targetParrying then
        return false, "targetInvulnerable"
    end
    if
        state.targetHealth
        and state.ultimateDamage
        and state.ultimateDamage >= state.targetHealth
    then
        return true, "lethal"
    end
    if
        (state.punishWindow or 0)
        >= (state.impactTime or math.huge) + (state.networkMargin or 0)
    then
        return true, "confirmedPunish"
    end
    return false, "reserveForCritical"
end

return UltimatePolicy
]],
        ["games/duelinggrounds/features/combat/defense/Executor.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Styles = importDependency("games/duelinggrounds/features/combat/Styles", "../Styles")

local Executor = {}
Executor.__index = Executor

local DODGE_COOLDOWN = 0.35
local PARRY_COOLDOWN = 0.05
local PARRY_HOLD_TIME = 0.12

function Executor.new(context)
    assert(context and context.characterController, "Defense Executor requires CharacterController")
    return setmetatable({
        context = context,
        lastDodgeAt = -math.huge,
        lastParryAt = -math.huge,
        activeParryBlock = nil,
        dodgeCounterDirection = 1,
        pendingCounterAt = nil,
        pendingCounterUntil = nil,
        pendingCounterAttack = "Light",
        stopped = false,
    }, Executor)
end

function Executor:_parry()
    local handler = self.context.characterController:GetLocalCharacterHandler()
    local actionManager = handler and handler.ActionManager
    if not actionManager then
        return false, "action manager unavailable"
    end
    if actionManager.BlockAction then
        return false, "block action active"
    end
    local now = os.clock()
    if now - self.lastParryAt < PARRY_COOLDOWN then
        return false, "parry cooldown"
    end
    if (actionManager._blockStrength or 0) <= 0.01 then
        return false, "block strength depleted"
    end
    local canStart, replaceCurrent = actionManager:CanStartBlock()
    if not canStart then
        return false, actionManager.CurrentAction and "current action locked" or "parry unavailable"
    end
    local currentAction = actionManager.CurrentAction
    actionManager:_clearQueuedAction()
    local block = actionManager:SwitchBlock(true, {
        blockStrength = actionManager._blockStrength or 1,
    })
    if replaceCurrent and currentAction then
        actionManager:_replaceActionWith(currentAction, block)
        actionManager.CurrentAction = nil
    end
    self.activeParryBlock = block
    self.lastParryAt = now
    task.delay(PARRY_HOLD_TIME, function()
        if self.activeParryBlock == block then
            block._wantsToRelease = true
            self.activeParryBlock = nil
        end
    end)
    return true
end

function Executor:_dodge(intent, settings, target, dynamicState)
    local now = os.clock()
    if now - self.lastDodgeAt < DODGE_COOLDOWN then
        return false, "dodge cooldown"
    end
    local handler = self.context.characterController:GetLocalCharacterHandler()
    local actionManager = handler and handler.ActionManager
    if not actionManager then
        return false, "action manager unavailable"
    end
    if not actionManager:CanStartDodge() then
        return false, actionManager.CurrentAction and "current action locked" or "dodge unavailable"
    end
    local root = handler.Root
    local offset = target and root and target.Position - root.Position or Vector3.zero
    local direction = Vector3.new(offset.X, 0, offset.Z)
    if direction.Magnitude <= 0.001 then
        local camera = self.context.workspace.CurrentCamera
        local look = camera and camera.CFrame.LookVector or Vector3.zAxis
        direction = Vector3.new(look.X, 0, look.Z)
    end
    direction = direction.Magnitude > 0 and direction.Unit or Vector3.zAxis
    local model = handler.OriginalModel or handler.Model
    local preferences = Styles.preferences(settings.combatStyle, {
        health = model and model:GetAttribute("Health"),
        maximumHealth = model and model:GetAttribute("MaxHealth"),
        posture = model and model:GetAttribute("Posture"),
        maximumPosture = model and model:GetAttribute("MaxPosture"),
        defenseReady = (actionManager._dodgeStamina or 0) >= 0.99
            and (actionManager._blockStrength or 0) > 0.01,
    }, dynamicState)
    local counterAllowed = preferences.counterAllowed
    local reverse = true
    if intent.mode == "heavy" and target and root then
        local lateral = Vector3.new(-direction.Z, 0, direction.X) * self.dodgeCounterDirection
        local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
        direction = distance > 9 and (lateral * 0.8 + direction * 0.6).Unit or lateral
        self.dodgeCounterDirection = -self.dodgeCounterDirection
        reverse = false
    elseif counterAllowed and target and root then
        if Vector3.new(offset.X, 0, offset.Z).Magnitude <= 8 then
            direction = Vector3.new(-direction.Z, 0, direction.X) * self.dodgeCounterDirection
            self.dodgeCounterDirection = -self.dodgeCounterDirection
        end
        reverse = false
    else
        direction = -direction
    end
    actionManager:_clearQueuedAction()
    actionManager:SwitchToAction("Dodge", {
        direction = direction,
        isReverse = reverse,
        dodgeStamina = actionManager._dodgeStamina,
    })
    self.lastDodgeAt = now
    if counterAllowed then
        self.pendingCounterAt = intent.mode == "heavy" and now or now + 0.16
        self.pendingCounterUntil = now + 0.32
        self.pendingCounterAttack = intent.mode == "heavy"
                and settings.combatStyle == "flashy"
                and "Heavy"
            or "Light"
    else
        self.pendingCounterAt = nil
        self.pendingCounterUntil = nil
    end
    return true
end

function Executor:availability()
    local handler = self.context.characterController:GetLocalCharacterHandler()
    local actionManager = handler and handler.ActionManager
    if not actionManager then
        return { canDodge = false, canParry = false, dodgeStamina = 0 }
    end
    local now = os.clock()
    local dodgeStamina = actionManager._dodgeStamina or 0
    local canDodge = dodgeStamina >= 0.99
        and now - self.lastDodgeAt >= DODGE_COOLDOWN
        and actionManager:CanStartDodge()
    local canParry = false
    if
        not actionManager.BlockAction
        and (actionManager._blockStrength or 0) > 0.01
        and now - self.lastParryAt >= PARRY_COOLDOWN
    then
        canParry = actionManager:CanStartBlock()
    end
    return {
        canDodge = canDodge == true,
        canParry = canParry == true,
        dodgeStamina = dodgeStamina,
        currentAction = actionManager.CurrentAction,
    }
end

function Executor:execute(intent, settings, target, dynamicState)
    if self.stopped then
        return false, "stopped"
    end
    if intent.kind == "dodge" then
        return self:_dodge(intent, settings, target, dynamicState)
    end
    return self:_parry()
end

function Executor:disposition()
    return {
        lastDodgeAt = self.lastDodgeAt,
        lastParryAt = self.lastParryAt,
        pendingCounterAt = self.pendingCounterAt,
        pendingCounterUntil = self.pendingCounterUntil,
        activeParry = self.activeParryBlock ~= nil,
    }
end

function Executor:consumeCounter()
    local pendingAt, pendingUntil, attack =
        self.pendingCounterAt, self.pendingCounterUntil, self.pendingCounterAttack
    self.pendingCounterAt = nil
    self.pendingCounterUntil = nil
    self.pendingCounterAttack = "Light"
    return pendingAt, pendingUntil, attack
end

function Executor:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self.pendingCounterAt = nil
    self.pendingCounterUntil = nil
    if self.activeParryBlock then
        self.activeParryBlock._wantsToRelease = true
        self.activeParryBlock = nil
    end
end

return Executor
]],
        ["games/duelinggrounds/features/combat/defense/Planner.lua"] = [[local Planner = {}

local function selectImpact(impacts, canReach)
    local reachable = {}
    for index, impact in ipairs(impacts or {}) do
        if canReach(impact, index) then
            table.insert(reachable, { impact = impact, index = index })
        end
    end
    if #reachable == 0 then
        return nil
    end
    if #reachable > 1 then
        for _, entry in ipairs(reachable) do
            if entry.impact.parryable then
                return entry, #reachable
            end
        end
    end
    return reachable[1], #reachable
end

function Planner.plan(input)
    local selected, reachableCount = selectImpact(input.impacts, input.canReach or function()
        return true
    end)
    if not selected then
        return nil
    end

    local impact = selected.impact
    local canParry = input.canParry == true and impact.parryable == true
    local canDodge = input.canDodge == true
    local kind
    local reason
    if math.max(reachableCount, input.chainImpactCount or 0) > 1 and canParry then
        kind = "parry"
        reason = "interrupt multi-hit chain"
    elseif input.isHeavy and canDodge then
        kind = "dodge"
        reason = "heavy counter"
    elseif canParry then
        kind = "parry"
        reason = input.isHeavy and "dodge unavailable" or "parryable impact"
    elseif canDodge then
        kind = "dodge"
        reason = impact.parryable and "parry unavailable" or "unparryable impact"
    else
        return nil
    end

    return {
        kind = kind,
        mode = input.isHeavy and "heavy" or nil,
        attackName = input.attackName,
        impactIndex = selected.index,
        impactCount = #(input.impacts or {}),
        reachableImpactCount = reachableCount,
        parryable = impact.parryable == true,
        timeUntilImpact = impact.timeUntilImpact,
        reason = reason,
    }
end

function Planner.fallback(intent, availability)
    if intent.kind == "dodge" and intent.parryable and availability.canParry == true then
        return "parry"
    end
    if intent.kind == "parry" and availability.canDodge == true then
        return "dodge"
    end
    return nil
end

return Planner
]],
        ["games/duelinggrounds/features/combat/offense/Executor.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Attacks = importDependency("games/duelinggrounds/features/combat/Attacks", "../Attacks")
local Combos = importDependency("games/duelinggrounds/features/combat/Combos", "../Combos")
local JumpAttackPolicy =
    importDependency("games/duelinggrounds/features/combat/JumpAttackPolicy", "../JumpAttackPolicy")
local Skill = importDependency("games/duelinggrounds/features/combat/Skill", "../Skill")
local Styles = importDependency("games/duelinggrounds/features/combat/Styles", "../Styles")
local UltimatePolicy =
    importDependency("games/duelinggrounds/features/combat/UltimatePolicy", "../UltimatePolicy")

local Executor = {}
Executor.__index = Executor

local FIGHT_RETRY_INTERVAL = 0.05
local ULTIMATE_RETRY_INTERVAL = 0.2
local RECOVERY_MIN = 0.18
local RECOVERY_MAX = 0.65
local IMPACT_MARGIN = Vector3.new(1.5, 2.5, 0.75)

local function canReach(attacker, defender, attackInfo)
    if not attacker or not defender or not attackInfo then
        return false
    end
    local velocity = defender.AssemblyLinearVelocity or Vector3.zero
    local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
    if horizontal.Magnitude > 18 then
        horizontal = horizontal.Unit * 18
    end
    for _, impact in ipairs(attackInfo.impacts or {}) do
        local impactTime = type(impact.markerTime) == "number" and impact.markerTime or 0
        local predicted = defender.Position + horizontal * math.clamp(impactTime, 0, 0.65)
        if Attacks.impactContainsPoint(attacker.CFrame, predicted, impact, IMPACT_MARGIN) then
            return true
        end
    end
    return false
end

function Executor.new(context)
    assert(context and context.characterController, "Offense Executor requires CharacterController")
    assert(context.targetLockController, "Offense Executor requires TargetLockController")
    return setmetatable({
        context = context,
        random = context.random or Random.new(),
        nextFightAt = 0,
        nextNeutralAttackAt = -math.huge,
        lastAttackAt = -math.huge,
        lastCriticalAt = -math.huge,
        lastUltimateAttemptAt = -math.huge,
        lastJumpAt = -math.huge,
        nextMixupAt = 0,
        pendingJumpUntil = nil,
        pendingCounterAt = nil,
        pendingCounterUntil = nil,
        pendingCounterAttack = "Light",
        comboLightCount = 0,
        stopped = false,
    }, Executor)
end

function Executor:setDodgeCounter(pendingAt, pendingUntil, attack)
    self.pendingCounterAt = pendingAt
    self.pendingCounterUntil = pendingUntil
    self.pendingCounterAttack = attack or "Light"
end

function Executor:_tryDodgeCounter(actionManager, targetRoot, disposition)
    if not self.pendingCounterUntil then
        return false
    end
    local now = os.clock()
    if now > self.pendingCounterUntil then
        self:_record("dodgeCounter", { result = "expired" })
        self.pendingCounterAt = nil
        self.pendingCounterUntil = nil
        return false
    end
    if now < (self.pendingCounterAt or 0) then
        return true
    end
    if disposition.incomingThreat then
        return true
    end
    if disposition.targetDodging or disposition.targetParrying then
        self:_record("dodgeCounter", { result = "targetInvulnerable" })
        return true
    end
    local handler = self.context.characterController:GetLocalCharacterHandler()
    local root = handler and handler.Root
    local weapon = handler and handler:GetEquippedWeaponHandler()
    local attackTypes = weapon and weapon.WeaponInfo.BasicAttackTypes
    local attack = self.pendingCounterAttack
    local resolved = actionManager:_resolveAttackName(attack)
    local attackInfo = resolved and attackTypes and attackTypes[resolved]
    if not canReach(root, targetRoot, attackInfo) then
        self:_record("dodgeCounter", { result = "outOfRange", attack = resolved })
        return true
    end
    if actionManager:TryQueueBasicAttack(attack) then
        self:_record("dodgeCounter", {
            result = "queued",
            attack = resolved,
            variation = attack,
        })
        self.lastAttackAt = now
        self.pendingCounterAt = nil
        self.pendingCounterUntil = nil
    end
    return true
end

function Executor:recordAnimation(name)
    if string.match(name or "", "^Light%d+$") then
        self.comboLightCount += 1
    elseif
        string.match(name or "", "^Heavy%d+$")
        or name == "DashHeavy"
        or name == "JumpAttack"
    then
        self.comboLightCount = 0
    end
end

function Executor:_record(kind, data)
    if self.context.record then
        self.context.record(kind, data)
    end
end

function Executor:_queue(actionManager, attack, attackInfo, settings, disposition)
    local queued = actionManager:TryQueueBasicAttack(attack)
    local now = os.clock()
    if attack == "Ultimate" then
        self.lastUltimateAttemptAt = now
        self:_record("ultimateAttempt", { result = queued and "queueAccepted" or "rejected" })
    end
    if queued then
        self.lastAttackAt = now
        local recovery = disposition.targetBlocking
            or disposition.targetStaggered
            or disposition.punishWindow > 0 and RECOVERY_MIN
            or self.random:NextNumber(RECOVERY_MIN, RECOVERY_MAX)
        self.nextNeutralAttackAt = now
            + (Attacks.marker(attackInfo, "canCancel") or Attacks.firstImpactTime(attackInfo) or 0.5)
            + recovery
        if self.context.recordProbeAttack and settings.combatStyle == "dynamic" then
            self.context.recordProbeAttack(now)
        end
    end
    return queued
end

function Executor:attack(settings, frame, disposition)
    if self.stopped or settings.autoFight ~= true then
        return
    end
    local now = os.clock()
    if now < self.nextFightAt then
        return
    end
    self.nextFightAt = now + FIGHT_RETRY_INTERVAL

    local target = frame.target or self.context.targetLockController.Target
    local targetModel = frame.targetModel or target and target:FindFirstAncestorWhichIsA("Model")
    if not targetModel or targetModel:GetAttribute("IsDead") == true then
        return
    end
    local targetHandler = frame.targetHandler
        or self.context.characterController:GetCharacterHandler(targetModel)
    local targetRoot = frame.targetRoot or targetHandler and targetHandler.Root or target
    local handler = frame.localHandler
        or self.context.characterController:GetLocalCharacterHandler()
    local actionManager = handler and handler.ActionManager
    if not actionManager or not handler.EquippedWeapon then
        return
    end
    local localModel = handler.OriginalModel or handler.Model
    local localPosture = localModel and localModel:GetAttribute("Posture")
    local maximumPosture = localModel and localModel:GetAttribute("MaxPosture")
    if
        type(localPosture) == "number"
        and type(maximumPosture) == "number"
        and maximumPosture > 0
        and localPosture / maximumPosture <= 0.25
    then
        if actionManager._queuedActionType then
            actionManager:_clearQueuedAction()
        end
        local current = actionManager.CurrentAction
        if current and current.ActionType == "BasicAttack" and current.CanCancel then
            actionManager:SwitchToAction(nil)
        end
        return
    end

    if settings.combatStyle == "defensive" then
        self.pendingJumpUntil = nil
        if
            actionManager._queuedActionType == "Jump"
            or actionManager._queuedActionType == "BasicAttack"
        then
            actionManager:_clearQueuedAction()
        end
        local current = actionManager.CurrentAction
        if current and current.ActionType == "BasicAttack" and current.CanCancel then
            actionManager:SwitchToAction(nil)
        end
        return
    end

    local criticalTarget = self.context.targetLockController.CriticalStrikeTarget
    local criticalModel = criticalTarget and criticalTarget.Parent
    if criticalModel and now - self.lastCriticalAt >= 0.25 then
        local criticalHandler = self.context.characterController:GetCharacterHandler(criticalModel)
        local criticalRoot = criticalHandler and criticalHandler.Root or criticalModel.PrimaryPart
        local weapon = handler:GetEquippedWeaponHandler()
        local attackTypes = weapon and weapon.WeaponInfo.BasicAttackTypes
        local ultimate = attackTypes and attackTypes.Ultimate
        if actionManager._queuedActionType then
            actionManager:_clearQueuedAction()
        end
        local current = actionManager.CurrentAction
        if current and current.ActionType == "BasicAttack" and current.CanCancel then
            actionManager:SwitchToAction(nil)
            current = nil
        end
        if
            ultimate
            and handler:CanPerformUltimate()
            and not current
            and not actionManager._queuedActionType
        then
            if self:_queue(actionManager, "Ultimate", ultimate, settings, disposition) then
                self:_record("criticalDecision", {
                    choice = "ultimate",
                    ultimateResult = "queued",
                    reason = "nativeCriticalTarget",
                })
                return
            end
        end
        self.context.criticalStrike(criticalModel)
        self.lastCriticalAt = now
        self.lastAttackAt = now
        return
    end

    if disposition.defenseIntent or disposition.incomingThreat then
        self.pendingJumpUntil = nil
        return
    end
    if self:_tryDodgeCounter(actionManager, targetRoot, disposition) then
        return
    end
    if disposition.targetDodging or disposition.targetParrying then
        self.pendingJumpUntil = nil
        return
    end
    if handler.IsParrying or actionManager.BlockAction then
        return
    end

    local current = actionManager.CurrentAction
    if
        current
        and current.ActionType == "BasicAttack"
        and current.CanQueueBasicAttacks
        and not actionManager._queuedActionType
    then
        local skill = Skill.profile(settings.botSkill)
        local preferences = Styles.preferences(settings.combatStyle, nil, disposition.dynamicState)
        local weapon = handler:GetEquippedWeaponHandler()
        local attackTypes = weapon and weapon.WeaponInfo.BasicAttackTypes
        local nextAttack, reason = Combos.nextAttack({
            weaponName = weapon and weapon.WeaponInfo.WeaponName,
            lightCount = self.comboLightCount,
            hasHeavy = attackTypes
                and attackTypes[actionManager:_resolveAttackName("Heavy")] ~= nil,
            targetBlocking = disposition.targetBlocking,
            style = settings.combatStyle,
            recentDeflects = #(disposition.dynamicState.deflectTimes or {}),
        })
        if
            nextAttack
            and (preferences.aggressiveCombos or Skill.shouldPunish(skill, self.random))
            and actionManager:TryQueueBasicAttack(nextAttack)
        then
            self.lastAttackAt = now
            self:_record("comboAttack", {
                result = "queued",
                attack = actionManager:_resolveAttackName(nextAttack),
                reason = reason,
                lightCount = self.comboLightCount,
                skill = skill.level,
            })
        elseif reason == "disengageAfterDeflects" then
            self.nextNeutralAttackAt = now + self.random:NextNumber(0.35, 0.7)
        end
        return
    end
    if current or actionManager._queuedActionType or now < self.nextNeutralAttackAt then
        return
    end

    local root = handler.Root
    local weapon = handler:GetEquippedWeaponHandler()
    local attackTypes = weapon and weapon.WeaponInfo.BasicAttackTypes
    if not root or not targetRoot or not attackTypes then
        return
    end
    local light = attackTypes[actionManager:_resolveAttackName("Light")]
    local heavy = attackTypes[actionManager:_resolveAttackName("Heavy")]
    local ultimate = attackTypes.Ultimate
    local skill = Skill.profile(settings.botSkill)
    local preferences =
        Styles.preferences(settings.combatStyle, frame.localState, disposition.dynamicState)
    local ultimateImpact = Attacks.firstImpactTime(ultimate) or math.huge
    local networkMargin = math.clamp((self.context.ping() or 0) + 0.05, 0.08, 0.18)
    local ultimateAllowed, ultimateReason = UltimatePolicy.shouldUseNeutral({
        targetDodging = disposition.targetDodging,
        targetParrying = disposition.targetParrying,
        targetHealth = targetModel:GetAttribute("Health"),
        ultimateDamage = Attacks.impactResultValue(ultimate, "GetHit", "healthDamage"),
        punishWindow = math.max(
            disposition.punishWindow,
            disposition.targetStaggered and disposition.targetStaggerRemaining or 0
        ),
        impactTime = ultimateImpact,
        networkMargin = networkMargin,
    })
    local attack
    if
        ultimate
        and handler:CanPerformUltimate()
        and now - self.lastUltimateAttemptAt >= ULTIMATE_RETRY_INTERVAL
        and canReach(root, targetRoot, ultimate)
        and ultimateAllowed
    then
        if not Skill.shouldPunish(skill, self.random) then
            return
        end
        attack = "Ultimate"
    elseif disposition.targetBlocking or disposition.targetStaggered then
        if not Skill.shouldPunish(skill, self.random) then
            return
        end
        attack = "Heavy"
    elseif preferences.allowOffense ~= false and canReach(root, targetRoot, light) then
        local canMixHeavy = heavy ~= nil
            and canReach(root, targetRoot, heavy)
            and now >= self.nextMixupAt
        if settings.combatStyle == "flashy" and canMixHeavy and self.random:NextNumber() < 0.28 then
            attack = "Heavy"
            self.nextMixupAt = now + self.random:NextNumber(1.2, 2.4)
            self:_record("offenseMixup", { kind = "neutralHeavy" })
        else
            attack = "Light"
        end
    elseif canReach(root, targetRoot, heavy) then
        attack = "Heavy"
    else
        return
    end
    if attack == "Ultimate" then
        self:_record("ultimateDecision", { reason = ultimateReason })
    end
    local jump = attackTypes.JumpAttack
    local jumpPostureDamage = Attacks.impactResultValue(jump, "Block", "postureDamage")
    local jumpReach = Attacks.geometricReach(jump, 4)
    local distance = (Vector3.new(targetRoot.Position.X, 0, targetRoot.Position.Z) - Vector3.new(
        root.Position.X,
        0,
        root.Position.Z
    )).Magnitude
    local shouldJump, jumpReason = JumpAttackPolicy.shouldJump({
        available = attack ~= "Ultimate" and jump ~= nil and Attacks.firstImpactTime(jump) ~= nil,
        jumpReady = (actionManager._jumpStamina or 0) >= 0.9,
        cooldownReady = now - self.lastJumpAt >= 2.5,
        canQueue = actionManager:CanQueueJump(),
        targetBlocking = disposition.targetBlocking,
        targetPosture = targetModel:GetAttribute("Posture"),
        postureDamage = jumpPostureDamage,
        targetStaggered = disposition.targetStaggered,
        staggerRemaining = disposition.targetStaggerRemaining,
        healthDamage = Attacks.impactResultValue(jump, "GetHit", "healthDamage"),
        heavyHealthDamage = Attacks.impactResultValue(heavy, "GetHit", "healthDamage"),
        inRange = canReach(root, targetRoot, jump),
        canLunge = jumpReach > 0 and distance <= jumpReach + 6,
    })
    if shouldJump then
        local offset = targetRoot.Position - root.Position
        local direction = Vector3.new(offset.X, 0, offset.Z)
        direction = direction.Magnitude > 0 and direction.Unit or Vector3.zero
        if actionManager:TryQueueJump(direction) then
            self.pendingJumpUntil = now + 0.65
            self.lastJumpAt = now
            self.lastAttackAt = now
            self:_record("jumpAttack", {
                result = "jumpQueued",
                reason = jumpReason,
                targetPosture = targetModel:GetAttribute("Posture"),
                postureDamage = jumpPostureDamage,
                distance = distance,
            })
        end
        return
    end
    local resolved = actionManager:_resolveAttackName(attack)
    local attackInfo = attackTypes[resolved]
    if
        attack ~= "Ultimate"
        and disposition.punishWindow > 0
        and not disposition.targetStaggered
        and (Attacks.firstImpactTime(attackInfo) or math.huge)
                + math.clamp((self.context.ping() or 0) + 0.05, 0.08, 0.18)
            >= disposition.punishWindow
    then
        return
    end
    if canReach(root, targetRoot, attackInfo) then
        self:_queue(actionManager, attack, attackInfo, settings, disposition)
    end
end

function Executor:disposition()
    return {
        lastAttackAt = self.lastAttackAt,
        nextNeutralAttackAt = self.nextNeutralAttackAt,
        lastUltimateAttemptAt = self.lastUltimateAttemptAt,
        pendingJumpUntil = self.pendingJumpUntil,
    }
end

function Executor:stop()
    self.stopped = true
    self.pendingJumpUntil = nil
end

return Executor
]],
        ["games/duelinggrounds/recording/Persistence.lua"] = [[local Persistence = {}
Persistence.__index = Persistence

local ROOT_FOLDER = "universal-hub/beta/logs"
local MATCH_FOLDER = ROOT_FOLDER .. "/duelinggrounds_1v1s"

function Persistence.new(dependencies)
    dependencies = dependencies or {}
    return setmetatable({
        writefile = dependencies.writefile,
        makefolder = dependencies.makefolder,
        isfolder = dependencies.isfolder,
        jsonEncode = dependencies.jsonEncode,
    }, Persistence)
end

local function ensureFolder(self, folder)
    if self.makefolder and (not self.isfolder or not self.isfolder(folder)) then
        self.makefolder(folder)
    end
end

function Persistence:save(version, match)
    if type(self.writefile) ~= "function" or type(self.jsonEncode) ~= "function" then
        return false
    end

    return pcall(function()
        ensureFolder(self, ROOT_FOLDER)
        ensureFolder(self, MATCH_FOLDER)
        local safeTarget = string.gsub(match.metadata.target or "opponent", "[^%w_%-]", "_")
        local fileName = ("match_%d_%04d_%s.json"):format(
            match.metadata.startedAt,
            match.metadata.id,
            safeTarget
        )
        match.metadata.file = MATCH_FOLDER .. "/" .. fileName
        self.writefile(match.metadata.file, self.jsonEncode({
            version = version,
            metadata = match.metadata,
            events = match.events,
            samples = match.samples,
        }))
    end)
end

return Persistence
]],
        ["games/duelinggrounds/recording/Runtime.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Sampler = importDependency(
    "games/duelinggrounds/recording/Sampler",
    "./Sampler"
)

local Runtime = {}
Runtime.__index = Runtime

local MAX_GLOBAL_EVENTS = 4000
local MAX_MATCH_EVENTS = 5000
local MAX_SAMPLES = 8000
local MAX_MATCHES = 25
local SAMPLE_INTERVAL = 0.05

local function trim(list, limit)
    while #list > limit do
        table.remove(list, 1)
    end
end

local function copyInto(destination, source)
    for key, value in pairs(source or {}) do
        destination[key] = value
    end
end

local function isDead(model)
    return model
        and type(model.GetAttribute) == "function"
        and model:GetAttribute("IsDead") == true
end

function Runtime.new(dependencies)
    dependencies = dependencies or {}
    local environment = dependencies.environment or _G
    local telemetry = environment.__DuelingGroundsCombatTelemetry
    if type(telemetry) ~= "table" or telemetry.version ~= 1 then
        telemetry = { version = 1, events = {} }
        environment.__DuelingGroundsCombatTelemetry = telemetry
    end
    telemetry.events = telemetry.events or {}
    telemetry.matches = telemetry.matches or {}
    telemetry.nextMatchId = telemetry.nextMatchId or 0
    telemetry.current = nil

    return setmetatable({
        clock = dependencies.clock or os.clock,
        wallClock = dependencies.wallClock or os.time,
        persistence = dependencies.persistence,
        sample = dependencies.sample or Sampler.sample,
        telemetry = telemetry,
        lastStyle = nil,
        stopped = false,
    }, Runtime)
end

function Runtime:_append(kind, data)
    local match = self.telemetry.current
    if not match then
        return
    end
    local event = { kind = kind, t = self.clock() - match.startedClock }
    copyInto(event, data)
    event.kind = kind
    event.t = self.clock() - match.startedClock
    table.insert(match.events, event)
    trim(match.events, MAX_MATCH_EVENTS)
end

function Runtime:recordEvent(kind, data, global)
    if self.stopped then
        return
    end
    if global == true then
        local event = { kind = kind, t = self.clock() }
        copyInto(event, data)
        event.kind = kind
        event.t = self.clock()
        table.insert(self.telemetry.events, event)
        trim(self.telemetry.events, MAX_GLOBAL_EVENTS)
        self:_append("decision", event)
        return
    end
    self:_append(kind, data)
end

function Runtime:recordDecision(kind, data)
    self:recordEvent(kind, data, true)
end

function Runtime:_start(frame, settings)
    local telemetry = self.telemetry
    telemetry.nextMatchId += 1
    local metadata = {
        id = telemetry.nextMatchId,
        startedAt = self.wallClock(),
        style = settings.combatStyle,
        autoMovement = settings.autoMovement == true,
    }
    copyInto(metadata, frame.metadata)
    local now = self.clock()
    telemetry.current = {
        startedClock = now,
        targetModelRef = frame.targetModel,
        metadata = metadata,
        events = {},
        samples = {},
        lastSampleAt = -math.huge,
    }
    self.lastStyle = settings.combatStyle
    self:_append("matchStarted", {
        autoMovement = settings.autoMovement == true,
        style = settings.combatStyle,
    })
end

function Runtime:_finish(reason)
    local match = self.telemetry.current
    if not match then
        return
    end
    match.metadata.duration = self.clock() - match.startedClock
    match.metadata.endedAt = self.wallClock()
    match.metadata.endReason = reason
    match.metadata.eventCount = #match.events
    match.metadata.sampleCount = #match.samples
    match.startedClock = nil
    match.targetModelRef = nil
    match.lastSampleAt = nil
    table.insert(self.telemetry.matches, match)
    trim(self.telemetry.matches, MAX_MATCHES)
    self.telemetry.current = nil
    self.lastStyle = nil
    if self.persistence then
        self.persistence:save(self.telemetry.version, match)
    end
end

function Runtime:update(frame, settings)
    if self.stopped then
        return
    end
    frame = frame or {}
    settings = settings or {}
    local targetModel = frame.targetModel
    local match = self.telemetry.current

    if settings.autoFight ~= true or not targetModel then
        self:_finish(settings.autoFight == true and "targetLost" or "autoFightOff")
        return
    end
    if frame.targetDead == true or isDead(targetModel) then
        self:_finish("targetDead")
        return
    end

    local localHandler = frame.localHandler
    local localAction = localHandler
        and localHandler.ActionManager
        and localHandler.ActionManager.CurrentAction
    if frame.selfDead == true
        or (localHandler
            and (isDead(localHandler.Model)
                or (localAction and localAction.ActionType == "Death")))
    then
        self:_finish("selfDead")
        return
    end
    if match and match.targetModelRef ~= targetModel then
        self:_finish("targetChanged")
        match = nil
    end
    if not match then
        self:_start(frame, settings)
        match = self.telemetry.current
    end
    if self.lastStyle ~= settings.combatStyle then
        self:_append("styleChanged", {
            from = self.lastStyle,
            to = settings.combatStyle,
        })
        self.lastStyle = settings.combatStyle
    end

    local now = self.clock()
    if now - match.lastSampleAt < SAMPLE_INTERVAL then
        return
    end
    match.lastSampleAt = now
    table.insert(match.samples, self.sample(frame, settings, now - match.startedClock))
    trim(match.samples, MAX_SAMPLES)
end

function Runtime:stop(reason)
    if self.stopped then
        return
    end
    self.stopped = true
    self:_finish(reason or "sessionStopped")
end

return Runtime
]],
        ["games/duelinggrounds/recording/Sampler.lua"] = [[local Sampler = {}

local function attribute(model, name)
    if model and type(model.GetAttribute) == "function" then
        return model:GetAttribute(name)
    end
    return nil
end

local function humanoidHealth(model)
    if not model or type(model.FindFirstChildOfClass) ~= "function" then
        return nil
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health or nil
end

local function health(attributeModel, humanoidModel)
    local nativeHealth = attribute(attributeModel, "Health")
    if nativeHealth ~= nil then
        return nativeHealth
    end
    return humanoidHealth(humanoidModel or attributeModel)
end

local function action(handler)
    local manager = handler and handler.ActionManager
    return manager, manager and manager.CurrentAction
end

function Sampler.sample(frame, settings, elapsed)
    local localHandler = frame.localHandler
    local targetHandler = frame.targetHandler
    local localManager, localAction = action(localHandler)
    local targetManager, targetAction = action(targetHandler)
    local localModel = localHandler and (localHandler.OriginalModel or localHandler.Model)
        or frame.localModel
    local targetModel = frame.targetModel
    local localRoot = localHandler and localHandler.Root or frame.localRoot
    local targetRoot = targetHandler and targetHandler.Root or frame.targetRoot or frame.target
    local distance

    if localRoot and targetRoot then
        local offset = targetRoot.Position - localRoot.Position
        distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
    end

    return {
        t = elapsed,
        distance = distance,
        style = settings.combatStyle,
        dynamicMode = settings.combatStyle == "dynamic" and frame.dynamicMode or nil,
        selfAction = localAction and localAction.ActionType or nil,
        selfCanCancel = localAction and localAction.CanCancel or nil,
        selfHealth = health(localModel, localHandler and localHandler.Model),
        selfPosture = attribute(localModel, "Posture"),
        selfBlocking = localHandler and localHandler.IsBlocking or false,
        selfParrying = localHandler and localHandler.IsParrying or false,
        selfDodging = localHandler and localHandler.IsDodging or false,
        selfCanUltimate = localHandler and localHandler:CanPerformUltimate() or false,
        targetAction = targetAction and targetAction.ActionType or nil,
        targetHealth = health(targetModel),
        targetPosture = attribute(targetModel, "Posture"),
        targetBlocking = targetHandler and targetHandler.IsBlocking or false,
        targetParrying = targetHandler and targetHandler.IsParrying or false,
        targetDodging = targetHandler and targetHandler.IsDodging or false,
        dodgeStamina = localManager and localManager._dodgeStamina or nil,
        blockStrength = localManager and localManager._blockStrength or nil,
        defense = frame.defense,
        critical = frame.critical == true,
    }
end

return Sampler
]],
    },
}
