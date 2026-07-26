local Movement = {}
Movement.__index = Movement

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
        controlsController = options.controlsController,
        getFighter = options.getFighter,
        getSettings = options.getSettings,
        isActive = options.isActive,
        isInCombat = options.isInCombat,
        isInputCaptured = options.isInputCaptured,
        mechanicsController = options.mechanicsController,
        movement = nil,
        movementDirection = options.movementDirection,
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
    if self.movement
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
        if self.mechanicsController.IsSliding == true
            or readState("IsSlidingLocally", false)
        then
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

function Movement:stop()
    if self.movement then
        self:_clearInputs()
        self.movement = nil
    end
end

function Movement:update()
    local fighter = self.getFighter()
    local direction = self.movementDirection and self.movementDirection()
    local isMoving = typeof(direction) == "Vector3" and direction.Magnitude > 0.01
    if direction == nil then
        isMoving = self.userInputService:IsKeyDown(Enum.KeyCode.W)
            or self.userInputService:IsKeyDown(Enum.KeyCode.A)
            or self.userInputService:IsKeyDown(Enum.KeyCode.S)
            or self.userInputService:IsKeyDown(Enum.KeyCode.D)
    end
    if not self.getSettings().bhop
        or not isMoving
        or self.isInputCaptured()
        or not self.isActive()
        or not self.isInCombat()
    then
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
