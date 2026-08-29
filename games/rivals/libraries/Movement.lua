local TaskLocomotion = require("../tasks/TaskLocomotion")
local WeaponPolicy = require("./WeaponPolicy")

local Movement = {}
Movement.__index = Movement

function Movement.isBlockingSurface(result, maximumSlopeAngle)
    if result == nil then
        return false
    end
    return typeof(result.Normal) ~= "Vector3"
        or type(maximumSlopeAngle) ~= "number"
        or result.Normal.Y < math.cos(math.rad(maximumSlopeAngle))
end

function Movement.new(options)
    assert(options and options.controlsController, "RIVALS movement requires ControlsController")
    assert(options.mechanicsController, "RIVALS movement requires MechanicsController")
    assert(options.getFighter, "RIVALS movement requires a fighter getter")
    assert(options.getSettings, "RIVALS movement requires a settings getter")
    assert(options.isActive, "RIVALS movement requires an active-state predicate")
    assert(options.isInCombat, "RIVALS movement requires a combat-state predicate")
    assert(options.isInputCaptured, "RIVALS movement requires an input-capture predicate")
    assert(options.userInputService, "RIVALS movement requires UserInputService")

    return setmetatable({
        clock = options.clock or os.clock,
        controlsController = options.controlsController,
        getFighter = options.getFighter,
        getSettings = options.getSettings,
        isActive = options.isActive,
        isTaskActive = options.isTaskActive or options.isActive,
        isTaskInputCaptured = options.isTaskInputCaptured or options.isInputCaptured,
        isInCombat = options.isInCombat,
        isInputCaptured = options.isInputCaptured,
        infiniteJumpHeld = false,
        mechanicsController = options.mechanicsController,
        movement = nil,
        movementDirection = options.movementDirection,
        taskGroundProbe = options.taskGroundProbe,
        taskLocomotion = options.taskLocomotion or TaskLocomotion.new(),
        taskObstacleProbe = options.taskObstacleProbe,
        taskParkourProbe = options.taskParkourProbe,
        taskLineOfSightBlocked = options.taskLineOfSightBlocked,
        taskWeaponProfile = options.taskWeaponProfile or WeaponPolicy.movementProfile,
        wallNoclipModel = nil,
        wallNoclipConnection = nil,
        wallNoclipParts = {},
        taskHumanoid = nil,
        taskCrouching = false,
        taskCrouchAt = 0,
        taskMobilityAt = 0,
        taskMobilityDeadline = 0,
        taskMobilityGeneration = 0,
        taskMobilityPhase = nil,
        taskSlideCallGeneration = nil,
        taskParkourAt = 0,
        taskParkourCommit = nil,
        taskParkourDirection = nil,
        taskParkourObservation = nil,
        taskParkourObservedAt = 0,
        taskParkourObservedPosition = nil,
        taskProgressAt = 0,
        taskProgressPosition = nil,
        taskRouteObservedAt = 0,
        taskRouteObservedPosition = nil,
        taskRouteTargetKey = nil,
        taskRoutes = {},
        taskOwnsSlide = false,
        taskStrafeSign = 1,
        shouldSuppressJump = options.shouldSuppressJump,
        spawn = options.spawn or task.spawn,
        syntheticInputs = {},
        userInputService = options.userInputService,
    }, Movement)
end

function Movement:_toggleInput(input, enabled)
    local inputKey = typeof(input) == "EnumItem" and input.Name or tostring(input)
    local owned = self.syntheticInputs[inputKey]
    if enabled == true then
        if not owned then
            local previous = false
            if type(self.controlsController.IsToggled) == "function" then
                previous = self.controlsController:IsToggled(input) == true
            elseif type(self.controlsController._toggled_inputs) == "table" then
                previous = self.controlsController._toggled_inputs[input] == true
            end
            owned = {
                input = input,
                previous = previous,
            }
            self.syntheticInputs[inputKey] = owned
        end
        self.controlsController:ToggleInput(input, true)
    elseif owned then
        self.controlsController:ToggleInput(owned.input, owned.previous)
        self.syntheticInputs[inputKey] = nil
    end
end

function Movement:_clearInputs()
    local inputs = {}
    for _, owned in pairs(self.syntheticInputs) do
        table.insert(inputs, owned)
    end
    table.clear(self.syntheticInputs)
    for _, owned in ipairs(inputs) do
        self.controlsController:ToggleInput(owned.input, owned.previous)
    end
    if
        self.movement
        and self.movement.ownsSlide
        and self.mechanicsController.IsSliding
        and type(self.mechanicsController.StopSliding) == "function"
    then
        self.mechanicsController:StopSliding()
    end
end

function Movement:_advance(fighter)
    local movement = self.movement
    local function readState(name, fallback)
        local value = fighter[name]
        if type(value) == "function" then
            return value(fighter)
        end
        if type(value) == "boolean" then
            return value
        end
        return fallback
    end

    self:_toggleInput(Enum.KeyCode.LeftShift, true)
    if movement.phase == "jump" then
        self:_toggleInput(Enum.KeyCode.Space, false)
        self:_toggleInput(Enum.KeyCode.C, false)
        movement.phase = "airborne"
    elseif movement.phase == "airborne" then
        self:_toggleInput(Enum.KeyCode.Space, false)
        self:_toggleInput(Enum.KeyCode.C, false)
        if readState("IsGrounded", false) then
            movement.phase = "waitingSlide"
        end
    elseif movement.phase == "sliding" then
        self:_toggleInput(Enum.KeyCode.Space, false)
        self:_toggleInput(Enum.KeyCode.C, true)
        if self.mechanicsController.IsSliding == true or readState("IsSlidingLocally", false) then
            movement.slideWaitFrames = 0
            movement.slideFrames += 1
            if movement.slideFrames >= 2 then
                if self.shouldSuppressJump and self.shouldSuppressJump() then
                    self:_toggleInput(Enum.KeyCode.Space, false)
                    return
                end
                self:_toggleInput(Enum.KeyCode.Space, true)
                movement.ownsSlide = false
                self.mechanicsController:HighJump()
                movement.phase = "jump"
            end
        else
            movement.slideWaitFrames += 1
            if movement.slideWaitFrames >= 3 then
                movement.ownsSlide = false
                movement.phase = "waitingSlide"
            end
        end
    else
        self:_toggleInput(Enum.KeyCode.Space, false)
        self:_toggleInput(Enum.KeyCode.C, false)
        local grounded = readState("IsGrounded", true)
        local canSlide = readState("CanSlide", true)
        if grounded and canSlide then
            self:_toggleInput(Enum.KeyCode.C, true)
            movement.phase = "sliding"
            movement.slideFrames = 0
            movement.slideWaitFrames = 0
            movement.ownsSlide = true
            self.spawn(function()
                self.mechanicsController:Slide()
            end)
        end
    end
end

local function taskHazardRepulsion(position, hazards)
    local repulsion = Vector3.zero
    local nearby = false
    for _, hazard in ipairs(hazards or {}) do
        local hazardPosition = hazard.worldPosition
        local hazardous = hazard.tone == "danger"
            or hazard.label == "GRENADE"
            or hazard.label == "THROWABLE"
            or hazard.label == "FIRE"
        if hazardous and typeof(hazardPosition) == "Vector3" then
            local away =
                Vector3.new(position.X - hazardPosition.X, 0, position.Z - hazardPosition.Z)
            local hazardDistance = away.Magnitude
            local avoidanceRadius = hazard.label == "GRENADE" and 38
                or hazard.label == "THROWABLE" and 34
                or hazard.label == "FIRE" and 30
                or 28
            if hazardDistance > 0.01 and hazardDistance < avoidanceRadius then
                nearby = true
                repulsion += away.Unit * ((avoidanceRadius - hazardDistance) / avoidanceRadius) * 4
            end
        end
    end
    return repulsion, nearby
end

function Movement:stopTaskCombat()
    self.taskMobilityGeneration += 1
    local humanoid = self.taskHumanoid
    self.taskHumanoid = nil
    if self.taskCrouching and type(self.mechanicsController.SetCrouching) == "function" then
        pcall(self.mechanicsController.SetCrouching, self.mechanicsController, false)
    end
    self.taskCrouching = false
    self.taskCrouchAt = 0
    if self.taskOwnsSlide and type(self.mechanicsController.StopSliding) == "function" then
        pcall(self.mechanicsController.StopSliding, self.mechanicsController)
    end
    self.taskOwnsSlide = false
    self.taskMobilityPhase = nil
    self.taskMobilityAt = 0
    self.taskMobilityDeadline = 0
    self.taskParkourAt = 0
    self.taskParkourCommit = nil
    self.taskParkourDirection = nil
    self.taskParkourObservation = nil
    self.taskParkourObservedAt = 0
    self.taskParkourObservedPosition = nil
    self.taskProgressAt = 0
    self.taskProgressPosition = nil
    self.taskRouteObservedAt = 0
    self.taskRouteObservedPosition = nil
    self.taskRouteTargetKey = nil
    table.clear(self.taskRoutes)
    if self.taskLocomotion and type(self.taskLocomotion.reset) == "function" then
        self.taskLocomotion:reset()
    end
    if humanoid and type(humanoid.Move) == "function" then
        pcall(humanoid.Move, humanoid, Vector3.zero, false)
    end
end

function Movement:updateTaskCombat(targetPosition, hazards, tactical)
    local target = type(targetPosition) == "table" and targetPosition or nil
    targetPosition = target and target.position or targetPosition
    local fighter = self.getFighter()
    local entity = fighter and fighter.Entity
    local humanoid = entity and entity.Humanoid
    local root = entity and (entity.RootPart or entity.HumanoidRootPart)
    if
        self.isTaskInputCaptured()
        or not self.isTaskActive()
        or not self.isInCombat()
        or not humanoid
        or type(humanoid.Move) ~= "function"
        or not root
        or typeof(root.Position) ~= "Vector3"
    then
        self:stopTaskCombat()
        return
    end
    if self.taskHumanoid and self.taskHumanoid ~= humanoid then
        self:stopTaskCombat()
    end
    self.taskHumanoid = humanoid
    local repulsion, hazardNearby = taskHazardRepulsion(root.Position, hazards)
    if typeof(targetPosition) ~= "Vector3" then
        local commit = self.taskParkourCommit
        if commit and typeof(commit.landing) == "Vector3" then
            targetPosition = commit.landing
        else
            if self.taskCrouching and type(self.mechanicsController.SetCrouching) == "function" then
                pcall(self.mechanicsController.SetCrouching, self.mechanicsController, false)
                self.taskCrouching = false
            end
            humanoid:Move(repulsion.Magnitude > 0.01 and repulsion.Unit or Vector3.zero, false)
            return {
                grounded = nil,
                mobilityPhase = self.taskMobilityPhase,
                needsDoubleJump = false,
            }
        end
    end
    local now = self.clock()
    local grounded
    if type(fighter.IsGrounded) == "function" then
        local succeeded, result = pcall(fighter.IsGrounded, fighter)
        if succeeded and type(result) == "boolean" then
            grounded = result
        end
    elseif type(humanoid.FloorMaterial) == "EnumItem" then
        grounded = humanoid.FloorMaterial ~= Enum.Material.Air
    end
    local offset =
        Vector3.new(targetPosition.X - root.Position.X, 0, targetPosition.Z - root.Position.Z)
    local distance = offset.Magnitude
    if distance < 0.01 then
        local commit = self.taskParkourCommit
        local elapsed = commit and now - commit.startedAt or 0
        if commit and grounded ~= true then
            local velocity = root.AssemblyLinearVelocity
            local info = fighter.EquippedItem and fighter.EquippedItem.Info
            if
                grounded == false
                and typeof(velocity) == "Vector3"
                and velocity.Y < -1
                and not commit.usedDoubleJump
                and type(info) == "table"
                and type(info.MaxDoubleJumps) == "number"
                and info.MaxDoubleJumps > 0
                and type(self.mechanicsController.DoubleJumpRequest) == "function"
            then
                pcall(self.mechanicsController.DoubleJumpRequest, self.mechanicsController)
                commit.usedDoubleJump = true
                self.taskMobilityPhase = "doubleJump"
            end
            humanoid:Move(Vector3.zero, false)
            return {
                grounded = grounded,
                mobilityPhase = self.taskMobilityPhase,
                needsDoubleJump = true,
            }
        end
        if not commit or elapsed > 0.18 then
            self.taskParkourCommit = nil
            self.taskParkourDirection = nil
        end
        humanoid:Move(Vector3.zero, false)
        return {
            grounded = grounded,
            mobilityPhase = self.taskMobilityPhase,
            needsDoubleJump = self.taskParkourCommit ~= nil,
        }
    end
    local toward = offset.Unit

    local clear
    if type(self.taskObstacleProbe) == "function" then
        local succeeded, blocked = pcall(self.taskObstacleProbe, root.Position, toward, fighter)
        if succeeded and type(blocked) == "boolean" then
            clear = not blocked
        end
    end
    local lineBlocked
    if type(self.taskLineOfSightBlocked) == "function" then
        local succeeded, blocked =
            pcall(self.taskLineOfSightBlocked, root.Position, targetPosition, fighter)
        if succeeded and type(blocked) == "boolean" then
            lineBlocked = blocked
        end
    end

    local routes = self.taskRoutes
    local routesKnown = grounded and type(self.taskGroundProbe) == "function"
    local routeTargetKey = target and target.key or "anonymous"
    local routeMoved = self.taskRouteObservedPosition
        and (root.Position - self.taskRouteObservedPosition).Magnitude > 2.5
    local sampleRoutes = routesKnown
        and (now >= self.taskRouteObservedAt
            or routeMoved
            or self.taskRouteTargetKey ~= routeTargetKey)
    if sampleRoutes then
        routes = {}
        local left = Vector3.new(-toward.Z, 0, toward.X)
        for _, candidate in ipairs({
            { key = "forward", direction = toward },
            { key = "forwardLeft", direction = (toward + left).Unit },
            { key = "forwardRight", direction = (toward - left).Unit },
            { key = "left", direction = left },
            { key = "right", direction = -left },
            { key = "retreatLeft", direction = (-toward + left).Unit },
            { key = "retreatRight", direction = (-toward - left).Unit },
            { key = "retreat", direction = -toward },
        }) do
            local succeeded, profile = pcall(
                self.taskGroundProbe,
                root.Position,
                candidate.direction,
                fighter,
                targetPosition
            )
            if succeeded and type(profile) == "table" then
                profile.direction = candidate.direction
                profile.key = candidate.key
                table.insert(routes, profile)
            end
        end
        self.taskRoutes = routes
        self.taskRouteObservedAt = now + 0.2
        self.taskRouteObservedPosition = root.Position
        self.taskRouteTargetKey = routeTargetKey
    end

    local item = fighter and fighter.EquippedItem
    local weaponProfile: any = {}
    if type(self.taskWeaponProfile) == "function" then
        local succeeded, profile = pcall(self.taskWeaponProfile, item)
        if succeeded and type(profile) == "table" then
            weaponProfile = profile
        end
    end
    local healthRatio = type(humanoid.Health) == "number"
            and type(humanoid.MaxHealth) == "number"
            and humanoid.MaxHealth > 0
            and humanoid.Health / humanoid.MaxHealth
        or nil
    local locomotionPlan = self.taskLocomotion:plan({
        clear = clear,
        engagementSeed = target and target.engagementSeed,
        grounded = grounded,
        hazardDirection = repulsion.Magnitude > 0.01 and repulsion.Unit or nil,
        healthRatio = healthRatio,
        lineBlocked = lineBlocked,
        now = now,
        objective = target and target.objective,
        position = root.Position,
        routes = routes,
        routesKnown = routesKnown,
        tactical = tactical,
        targetHealthRatio = target and target.targetHealthRatio,
        targetKey = target and target.key,
        targetPosition = targetPosition,
        weaponProfile = weaponProfile,
    })
    local direction = locomotionPlan.direction
    if grounded == nil then
        direction = Vector3.zero
        locomotionPlan.intent = "hold"
        locomotionPlan.routeKey = "groundingUnknown"
    end
    self.taskStrafeSign = locomotionPlan.strafeSign or self.taskStrafeSign
    local strafe = Vector3.new(-toward.Z, 0, toward.X) * self.taskStrafeSign
    local sustainedRifle = weaponProfile.sustained == true
    local avoidSniperPeek = type(tactical) == "table" and tactical.avoidSniperPeek == true
    local parkour = self.taskParkourObservation
    local parkourMoved = self.taskParkourObservedPosition
        and (root.Position - self.taskParkourObservedPosition).Magnitude > 1.5
    local parkourDirectionChanged = typeof(self.taskParkourDirection) ~= "Vector3"
        or direction.Magnitude > 0.01
            and self.taskParkourDirection:Dot(direction) < 0.96
    if
        type(self.taskParkourProbe) == "function"
        and direction.Magnitude > 0.01
        and (now >= self.taskParkourObservedAt or parkourMoved or parkourDirectionChanged)
    then
        local succeeded, profile = pcall(self.taskParkourProbe, root.Position, direction, fighter)
        parkour = succeeded and type(profile) == "table" and profile or nil
        self.taskParkourDirection = direction
        self.taskParkourObservation = parkour
        self.taskParkourObservedAt = now + 0.1
        self.taskParkourObservedPosition = root.Position
    end
    local obstacleBlocked
    if type(self.taskObstacleProbe) == "function" then
        local succeeded, blocked = pcall(self.taskObstacleProbe, root.Position, direction, fighter)
        obstacleBlocked = succeeded and type(blocked) == "boolean" and blocked or nil
    end
    local performedParkour = false
    local commit = self.taskParkourCommit
    if commit then
        local landingOffset =
            Vector3.new(commit.landing.X - root.Position.X, 0, commit.landing.Z - root.Position.Z)
        local landingDistance = landingOffset.Magnitude
        local elapsed = now - commit.startedAt
        if grounded and elapsed > 0.18 and landingDistance <= 3 then
            self.taskParkourCommit = nil
            commit = nil
            self.taskParkourAt = now + 0.35
        elseif grounded and elapsed > 0.8 and landingDistance > commit.startDistance - 0.5 then
            -- Takeoff failed; cancel only while grounded, matching Baritone's
            -- safe-to-cancel-before-running rule.
            self.taskParkourCommit = nil
            commit = nil
            direction = Vector3.zero
            self.taskParkourAt = now + 0.5
            if type(self.taskLocomotion.invalidate) == "function" then
                self.taskLocomotion:invalidate()
            end
        else
            if landingDistance > 0.05 then
                direction = landingOffset.Unit
            end
            performedParkour = true
            local velocity = root.AssemblyLinearVelocity
            local descending = typeof(velocity) == "Vector3" and velocity.Y < -1
            local info = fighter.EquippedItem and fighter.EquippedItem.Info
            if
                grounded == false
                and descending
                and not commit.usedDoubleJump
                and type(info) == "table"
                and type(info.MaxDoubleJumps) == "number"
                and info.MaxDoubleJumps > 0
                and type(self.mechanicsController.DoubleJumpRequest) == "function"
            then
                pcall(self.mechanicsController.DoubleJumpRequest, self.mechanicsController)
                commit.usedDoubleJump = true
            end
        end
    end
    local parkourRequestsSlideJump = false
    if not commit and now >= self.taskParkourAt and type(parkour) == "table" then
        if
            grounded
            and typeof(parkour.jumpLanding) == "Vector3"
            and parkour.jumpConfidence == 1
        then
            local jumpMethod = type(self.mechanicsController.JumpRequest) == "function"
                    and self.mechanicsController.JumpRequest
                or self.mechanicsController.Jump
            if type(jumpMethod) == "function" then
                local landingOffset = Vector3.new(
                    parkour.jumpLanding.X - root.Position.X,
                    0,
                    parkour.jumpLanding.Z - root.Position.Z
                )
                self.taskParkourCommit = {
                    landing = parkour.jumpLanding,
                    startedAt = now,
                    startDistance = landingOffset.Magnitude,
                    usedDoubleJump = false,
                }
                if landingOffset.Magnitude > 0.05 then
                    direction = landingOffset.Unit
                end
                pcall(jumpMethod, self.mechanicsController)
                performedParkour = true
                commit = self.taskParkourCommit
                self.taskParkourAt = now + 0.2
            end
        elseif grounded and parkour.low and not parkour.middle then
            if type(self.mechanicsController.Jump) == "function" then
                pcall(self.mechanicsController.Jump, self.mechanicsController)
                performedParkour = true
                self.taskParkourAt = now + 0.42
            end
        elseif grounded and parkour.middle and not parkour.high and parkour.landing then
            parkourRequestsSlideJump = true
        elseif not parkour.landing then
            obstacleBlocked = true
        end
    end
    if
        not commit
        and (type(parkour) == "table" and not parkour.landing
            or obstacleBlocked == true and not performedParkour)
    then
        direction = Vector3.zero
        obstacleBlocked = false
        if type(self.taskLocomotion.invalidate) == "function" then
            self.taskLocomotion:invalidate()
        end
    end
    if self.taskProgressAt == 0 then
        self.taskProgressAt = now
        self.taskProgressPosition = root.Position
    elseif now - self.taskProgressAt >= 0.65 then
        local progressed = self.taskProgressPosition
            and (root.Position - self.taskProgressPosition).Magnitude >= 0.75
        if
            not commit
            and grounded
            and not progressed
            and distance > 10
            and now >= self.taskParkourAt
        then
            if type(self.taskLocomotion.invalidate) == "function" then
                self.taskLocomotion:invalidate()
            end
            self.taskParkourAt = now + 0.2
        end
        self.taskProgressAt = now
        self.taskProgressPosition = root.Position
    end
    local shouldUseMobility = (locomotionPlan.slide == true or parkourRequestsSlideJump)
        and not performedParkour
        and not (type(parkour) == "table" and not parkour.landing)
        and not avoidSniperPeek
        and not hazardNearby
        and distance > 20
    local function nativeSliding()
        if type(self.mechanicsController.IsSliding) == "boolean" then
            return self.mechanicsController.IsSliding
        end
        if type(fighter.IsSlidingLocally) == "function" then
            local succeeded, result = pcall(fighter.IsSlidingLocally, fighter)
            if succeeded and type(result) == "boolean" then
                return result
            end
        end
        return nil
    end
    if self.taskMobilityPhase == "awaitingSlide" then
        local sliding = nativeSliding()
        if sliding == true then
            local succeeded, accepted = pcall(
                self.mechanicsController.HighJump,
                self.mechanicsController
            )
            if succeeded and accepted ~= false then
                self.taskMobilityPhase = "awaitingAirborne"
                self.taskMobilityDeadline = now + 0.5
            else
                if type(self.mechanicsController.StopSliding) == "function" then
                    pcall(self.mechanicsController.StopSliding, self.mechanicsController)
                end
                self.taskOwnsSlide = false
                self.taskMobilityPhase = nil
                self.taskMobilityAt = now + 0.5
            end
        elseif now >= self.taskMobilityDeadline then
            if self.taskOwnsSlide and type(self.mechanicsController.StopSliding) == "function" then
                pcall(self.mechanicsController.StopSliding, self.mechanicsController)
            end
            self.taskOwnsSlide = false
            self.taskMobilityPhase = nil
            self.taskMobilityAt = now + 0.5
        end
    elseif self.taskMobilityPhase == "awaitingAirborne" then
        local sliding = nativeSliding()
        if grounded == false or sliding == false then
            self.taskOwnsSlide = false
            self.taskMobilityPhase = nil
            self.taskMobilityAt = now + 2.1
        elseif now >= self.taskMobilityDeadline then
            if self.taskOwnsSlide and type(self.mechanicsController.StopSliding) == "function" then
                pcall(self.mechanicsController.StopSliding, self.mechanicsController)
            end
            self.taskOwnsSlide = false
            self.taskMobilityPhase = nil
            self.taskMobilityAt = now + 0.5
        end
    elseif not self.taskMobilityPhase and shouldUseMobility and now >= self.taskMobilityAt then
        local canSlide = false
        if type(fighter.CanSlide) == "function" then
            local succeeded, result = pcall(fighter.CanSlide, fighter)
            canSlide = succeeded and result == true
        end
        if
            canSlide
            and self.taskSlideCallGeneration == nil
            and type(self.mechanicsController.Slide) == "function"
            and type(self.mechanicsController.HighJump) == "function"
        then
            if self.taskCrouching and type(self.mechanicsController.SetCrouching) == "function" then
                pcall(self.mechanicsController.SetCrouching, self.mechanicsController, false)
                self.taskCrouching = false
            end
            self.taskMobilityGeneration += 1
            local generation = self.taskMobilityGeneration
            self.taskSlideCallGeneration = generation
            self.taskOwnsSlide = true
            self.taskMobilityPhase = "awaitingSlide"
            self.taskMobilityDeadline = now + 0.5
            self.spawn(function()
                if
                    self.taskMobilityGeneration ~= generation
                    or self.taskSlideCallGeneration ~= generation
                then
                    if self.taskSlideCallGeneration == generation then
                        self.taskSlideCallGeneration = nil
                    end
                    return
                end
                pcall(self.mechanicsController.Slide, self.mechanicsController)
                if self.taskSlideCallGeneration == generation then
                    self.taskSlideCallGeneration = nil
                end
            end)
        else
            self.taskMobilityAt = now + 0.5
        end
    end

    local shouldCrouchSpam = sustainedRifle
        and locomotionPlan.intent == "hold"
        and not avoidSniperPeek
        and self.taskMobilityPhase == nil
        and not lineBlocked
        and not hazardNearby
        and distance >= 18
        and distance <= 75
        and type(self.mechanicsController.SetCrouching) == "function"
    if shouldCrouchSpam and now >= self.taskCrouchAt then
        self.taskCrouching = not self.taskCrouching
        pcall(self.mechanicsController.SetCrouching, self.mechanicsController, self.taskCrouching)
        self.taskCrouchAt = now + (self.taskCrouching and 0.22 or 0.38)
    elseif not shouldCrouchSpam and self.taskCrouching then
        pcall(self.mechanicsController.SetCrouching, self.mechanicsController, false)
        self.taskCrouching = false
        self.taskCrouchAt = now + 0.25
    end
    local needsDoubleJump = type(parkour) == "table"
            and typeof(parkour.jumpLanding) == "Vector3"
        or commit ~= nil and grounded == false
    humanoid:Move(direction, false)
    return {
        clear = clear,
        direction = direction,
        distance = distance,
        grounded = grounded,
        intent = locomotionPlan.intent,
        lineBlocked = lineBlocked,
        mobilityPhase = self.taskMobilityPhase,
        needsDoubleJump = needsDoubleJump,
        routeKey = locomotionPlan.routeKey,
        routes = routes,
    }
end

function Movement:stopWallNoclip()
    if self.wallNoclipConnection then
        self.wallNoclipConnection:Disconnect()
        self.wallNoclipConnection = nil
    end
    for part, original in pairs(self.wallNoclipParts) do
        if typeof(part) == "Instance" and part.Parent then
            part.CanCollide = original
        end
    end
    table.clear(self.wallNoclipParts)
    self.wallNoclipModel = nil
end

function Movement:updateWallNoclip(settings)
    settings = settings or self.getSettings()
    if settings.wallNoclip ~= true then
        self:stopWallNoclip()
        return
    end
    local fighter = self.getFighter()
    local entity = fighter and fighter.Entity
    local model = entity and entity.Model
    if typeof(model) ~= "Instance" then
        self:stopWallNoclip()
        return
    end
    if model ~= self.wallNoclipModel then
        self:stopWallNoclip()
        self.wallNoclipModel = model
        local function track(descendant)
            if descendant:IsA("BasePart") and self.wallNoclipParts[descendant] == nil then
                self.wallNoclipParts[descendant] = descendant.CanCollide
                descendant.CanCollide = false
            end
        end
        for _, descendant in ipairs(model:GetDescendants()) do
            track(descendant)
        end
        self.wallNoclipConnection = model.DescendantAdded:Connect(track)
    end
    -- RIVALS may restore character collision during its own physics update.
    -- Reassert only cached character parts; no descendant traversal occurs here.
    for part in pairs(self.wallNoclipParts) do
        if part.Parent and part.CanCollide then
            part.CanCollide = false
        end
    end
end

function Movement:updateInfiniteJump(settings)
    settings = settings or self.getSettings()
    local held = self.userInputService:IsKeyDown(Enum.KeyCode.Space) == true
    if
        settings.infiniteJump == true
        and held
        and not self.infiniteJumpHeld
        and not self.isInputCaptured()
        and type(self.mechanicsController.DoubleJump) == "function"
    then
        pcall(self.mechanicsController.DoubleJump, self.mechanicsController)
    end
    self.infiniteJumpHeld = settings.infiniteJump == true and held
end

function Movement:stop()
    self:stopTaskCombat()
    if self.movement then
        self:_clearInputs()
        self.movement = nil
    end
end

function Movement:update(settings)
    settings = settings or self.getSettings()
    if settings.bhop ~= true then
        self:stop()
        return
    end

    local fighter = self.getFighter()
    local direction = self.movementDirection and self.movementDirection()
    local isMoving = typeof(direction) == "Vector3" and direction.Magnitude > 0.01
    if direction == nil then
        isMoving = self.userInputService:IsKeyDown(Enum.KeyCode.W)
            or self.userInputService:IsKeyDown(Enum.KeyCode.A)
            or self.userInputService:IsKeyDown(Enum.KeyCode.S)
            or self.userInputService:IsKeyDown(Enum.KeyCode.D)
    end
    if not isMoving or self.isInputCaptured() or not self.isActive() or not self.isInCombat() then
        self:stop()
        return
    end

    if not self.movement or self.movement.fighter ~= fighter then
        self:stop()
        self.movement = {
            fighter = fighter,
            phase = "waitingSlide",
            slideFrames = 0,
            slideWaitFrames = 0,
        }
    end
    self:_advance(fighter)
end

return Movement
