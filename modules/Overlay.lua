local Overlay = {}
Overlay.__index = Overlay

local OPTION_GROUPS = {
    {
        id = "rage",
        label = "AIM",
        rows = {
            { "silentAim", "shotAim", "wallbang" },
            { "humanAim", "rapidFire" },
            { "triggerBot", "alwaysScoped", "noSpread" },
            { "noRecoil", "noWeaponSlow" },
        },
    },
    {
        id = "melee",
        label = "MELEE",
        rows = {
            { "knifeAura", "microStep" },
        },
    },
    {
        id = "movement",
        label = "MOVEMENT",
        rows = {
            { "spinBot", "bhop" },
        },
    },
    {
        id = "visuals",
        label = "VISUALS",
        rows = {
            { "boxes", "chams" },
            { "names", "health" },
            { "weapon", "noFlash" },
            { "noSmoke", "bombTimer" },
            { "utilityEsp" },
        },
    },
}

local OPTION_LABELS = {
    bhop = "Bunny Hop",
    bombTimer = "Bomb Timer",
    rapidFire = "Rapid Fire",
    alwaysScoped = "Always Scoped",
    shotAim = "Silent Aim",
    silentAim = "Silent Aim",
    triggerBot = "Trigger Bot",
    utilityEsp = "Utility ESP",
    noSpread = "No Spread",
    noRecoil = "No Recoil",
    noFlash = "No Flash",
    noSmoke = "No Smoke",
    noWeaponSlow = "No Weapon Slow",
    knifeAura = "Knife Aura",
    microStep = "Micro Step",
    spinBot = "Spin Bot",
    wallbang = "Wallbang",
    boxes = "Hitboxes",
    chams = "Chams",
    plotCopy = "Plot Copy",
    names = "Names",
    health = "Health",
    humanAim = "Human Aim",
    weapon = "Weapons",
}

local OPTION_PARENTS = {
    humanAim = "silentAim",
    microStep = "knifeAura",
    wallbang = "silentAim",
}

local RATE_CONTROLS = {
    { id = "aimSmoothness", label = "Aim Smoothness" },
    { id = "headshotRate", label = "Headshot Rate" },
    { id = "missRate", label = "Miss Rate" },
}

local COLORS = {
    accent = Color3.fromRGB(98, 214, 173),
    accentSurface = Color3.fromRGB(23, 53, 45),
    border = Color3.fromRGB(41, 50, 58),
    danger = Color3.fromRGB(230, 107, 110),
    elevated = Color3.fromRGB(21, 28, 35),
    hover = Color3.fromRGB(28, 37, 45),
    panel = Color3.fromRGB(17, 23, 29),
    panelShadow = Color3.fromRGB(4, 7, 9),
    secondary = Color3.fromRGB(167, 176, 184),
    text = Color3.fromRGB(243, 246, 247),
    toggleActive = Color3.fromRGB(74, 166, 139),
}

local WORLD_LAYER = {
    chams = 10,
    player = 11,
    health = 12,
    playerDetail = 13,
    utilityZone = 20,
    utility = 21,
    utilityText = 22,
}

local BODY_CUBE_FACES = {
    { 1, 2, 3, 4 },
    { 5, 8, 7, 6 },
    { 1, 5, 6, 2 },
    { 4, 3, 7, 8 },
    { 1, 4, 8, 5 },
    { 2, 6, 7, 3 },
}
local UTILITY_CUBE_EDGES = {
    { 1, 2 },
    { 2, 3 },
    { 3, 4 },
    { 4, 1 },
    { 5, 6 },
    { 6, 7 },
    { 7, 8 },
    { 8, 5 },
    { 1, 5 },
    { 2, 6 },
    { 3, 7 },
    { 4, 8 },
}

local BODY_CUBE_OPACITY = 0.18
local ACTIVE_CONTROL_LAYER = 206
local CONTENT_WIDTH = 276
local FOV_TRACK_WIDTH = 252
local HITBOX_TRANSPARENCY = 0.01
local RATE_TRACK_WIDTH = 256
local RATE_THUMB_RADIUS = 6
local PLOT_OWNER_VALUE_LIMIT = 22
local PLOT_SAVE_VALUE_LIMIT = 24
local COSMETIC_WEAPON_CONTROLS = {
    weaponBackground = true,
    weaponName = true,
    weaponNext = true,
    weaponNextLabel = true,
    weaponPrevious = true,
    weaponPreviousLabel = true,
}

local EVENT_SIGNALS = {
    click = "Clicked",
    drag = "Dragged",
    pointerdown = "PointerDown",
    pointerenter = "PointerEntered",
    pointerleave = "PointerLeft",
    pointerup = "PointerUp",
}

local function wrapElement(element, canvas)
    local object = element:getObject()
    local callbacks = {}
    local node
    local methods = {}

    function methods:on(eventName, callback)
        local signalName = assert(EVENT_SIGNALS[eventName], "Unknown Limn element event: " .. tostring(eventName))
        assert(type(callback) == "function", "Limn element event handler must be a function")
        callbacks[eventName] = callback
        element:setInteractive(true)
        return element[signalName]:Connect(function(event)
            callback(node, event.position, event.input, event.delta)
        end)
    end

    function methods:set(properties)
        element:patch(properties)
        return node
    end

    methods.patch = methods.set

    function methods:destroy()
        element:destroy()
    end

    methods.Destroy = methods.destroy
    methods.Remove = methods.destroy

    function methods:getObject()
        return object
    end

    function methods:paintCaptured(zIndex, callback)
        return canvas:paintCaptured(element, zIndex, callback)
    end

    node = setmetatable({
        callbacks = callbacks,
    }, {
        __index = function(_, key)
            local method = methods[key]
            if method ~= nil then
                return method
            end
            return object[key]
        end,
        __newindex = function(_, key, value)
            element:set(key, value)
        end,
    })
    return node
end

local function createCanvasView(runtime)
    local canvas = runtime:createCanvas()
    local surface = {
        canvas = canvas,
    }

    function surface:create(kind, properties, options)
        local interactive = options ~= nil
            and (options.interactive == true or options.pointerEvents == true)
        return wrapElement(canvas:create(kind, properties, {
            interactive = interactive,
        }), canvas)
    end

    function surface:paint(zIndex, callback)
        return canvas:paint(zIndex, callback)
    end

    function surface:bindInput(inputService)
        return canvas:bindInput(inputService)
    end

    function surface:destroy()
        canvas:destroy()
    end

    return surface
end

local function registerActiveSliderPaint(hit, draw)
    return pcall(function()
        hit:paintCaptured(ACTIVE_CONTROL_LAYER, function(painter, event)
            draw(painter, event.position)
        end)
    end)
end

local function setRetainedSliderVisible(overlay, fill, knob, visible)
    if visible then
        overlay.activeSliderVisuals[fill] = nil
        overlay.activeSliderVisuals[knob] = nil
        overlay:_setMenuVisible(overlay.context.store:Get().menuVisible ~= false)
        return
    end
    overlay.activeSliderVisuals[fill] = true
    overlay.activeSliderVisuals[knob] = true
    fill.Visible = false
    knob.Visible = false
end

local function paintActiveSlider(painter, track, fillWidth, knobX, knobRadius, fillColor)
    painter.FilledRectangle(
        track.Position,
        Vector2.new(math.max(0, fillWidth), 4),
        fillColor,
        1,
        0
    )
    painter.FilledCircle(
        Vector2.new(knobX, track.Position.Y + 2),
        knobRadius,
        COLORS.text,
        1,
        32
    )
end

local function clampCenteredUtilityLabel(position, viewportSize, textBounds)
    if not viewportSize then
        return position
    end
    local halfWidth = math.max(textBounds and textBounds.X * 0.5 or 0, 32)
    local halfHeight = math.max(textBounds and textBounds.Y * 0.5 or 0, 7)
    local marginX = halfWidth + 4
    local marginY = halfHeight + 4
    return Vector2.new(
        math.clamp(position.X, marginX, math.max(marginX, viewportSize.X - marginX)),
        math.clamp(position.Y, marginY, math.max(marginY, viewportSize.Y - marginY))
    )
end

local function setVisible(nodes, visible)
    for _, node in pairs(nodes) do
        if type(node) == "table" and node.Visible == nil then
            setVisible(node, visible)
        else
            node.Visible = visible
        end
    end
end

local function compactText(value, limit)
    value = tostring(value or "")
    if #value <= limit then
        return value
    end
    return value:sub(1, math.max(limit - 3, 0)) .. "..."
end

function Overlay.new(context)
    assert(context and context.limn, "Hub overlay requires a Limn runtime")
    assert(context.store, "Hub overlay requires a reactive store")

    local optionAvailable = {}
    if type(context.capabilities) == "table" then
        for optionName in pairs(OPTION_LABELS) do
            optionAvailable[optionName] = false
        end
        for key, value in pairs(context.capabilities) do
            local optionName = type(key) == "number" and value or key
            if value ~= false then
                optionAvailable[optionName] = true
            end
        end
    else
        for optionName in pairs(OPTION_LABELS) do
            optionAvailable[optionName] = true
        end
    end
    local primitiveSupport = {}
    for _, kind in ipairs({ "Square", "Circle", "Text", "Quad", "Line" }) do
        primitiveSupport[kind] = context.limn:supportsPrimitive(kind)
    end
    local optionSupport = {
        chams = primitiveSupport.Quad,
    }
    local rateAvailable = {}
    for _, definition in ipairs(RATE_CONTROLS) do
        rateAvailable[definition.id] = false
        for key, value in pairs(context.capabilities or {}) do
            local capability = type(key) == "number" and value or key
            if capability == definition.id and value ~= false then
                rateAvailable[definition.id] = true
                break
            end
        end
    end
    local aimControlsSupported = optionAvailable.silentAim == true
        or optionAvailable.shotAim == true
        or optionAvailable.triggerBot == true
        or rateAvailable.aimSmoothness == true
        or rateAvailable.headshotRate == true
        or rateAvailable.missRate == true
    local self = setmetatable({
        aimControlsSupported = aimControlsSupported,
        activeSliderVisuals = setmetatable({}, { __mode = "k" }),
        captured = false,
        cosmeticsSupported = context.cosmetics ~= false,
        context = context,
        controlColors = setmetatable({}, { __mode = "k" }),
        controls = {},
        destroyed = false,
        observations = {},
        optionAvailable = optionAvailable,
        optionSupport = optionSupport,
        primitiveSupport = primitiveSupport,
        optionLabels = context.optionLabels or {},
        plotDropdownItems = {},
        plotDropdownOpen = false,
        plotSaveName = "",
        selectedPlotOwner = nil,
        rateAvailable = rateAvailable,
        playerNodes = {},
        utilityNodes = {},
        chamPaint = {
            enabled = false,
            observations = {},
        },
        utilityZonePaint = {
            enabled = false,
            observations = {},
        },
        worldGui = nil,
    }, Overlay)

    local missingPrimitives = {}
    for _, kind in ipairs({ "Square", "Circle", "Text" }) do
        if not primitiveSupport[kind] then
            table.insert(missingPrimitives, kind)
        end
    end
    self.missingPrimitives = missingPrimitives
    if #missingPrimitives > 0 then
        self.available = false
        warn(
            "[Universal Hub]",
            "overlay disabled; unsupported drawing primitives:",
            table.concat(missingPrimitives, ", ")
        )
        return self
    end

    self.available = true
    self.surface = createCanvasView(context.limn)
    self.canvas = self.surface.canvas
    if context.inputService then
        self.surface:bindInput(context.inputService)
    end
    self:_build()
    self.immediateChams = pcall(function()
        self.chamPaintConnection = self.surface:paint(WORLD_LAYER.chams, function(renderer)
            self:_paintChams(renderer)
        end)
    end)
    if self.immediateChams then
        self.optionSupport.chams = true
    end
    self.immediateUtilityZones = pcall(function()
        self.utilityPaintConnection = self.surface:paint(WORLD_LAYER.utilityZone, function(renderer)
            self:_paintUtilityZones(renderer)
        end)
    end)
    self.unsubscribe = context.store:Subscribe(function(state)
        self:_renderState(state)
    end)
    return self
end

function Overlay:_capture(node)
    return node
end

function Overlay:_interactive(node)
    self.controlColors[node] = node.Color
    node:on("pointerenter", function(target)
        if target.Visible then
            target.Color = COLORS.hover
        end
    end)
    node:on("pointerleave", function(target)
        target.Color = self.controlColors[target]
    end)
    return self:_capture(node)
end

function Overlay:_setControlColor(node, color)
    self.controlColors[node] = color
    node.Color = color
end

function Overlay:_text(properties, pointerEvents)
    properties.Font = properties.Font or Drawing.Fonts.Plex
    properties.Visible = properties.Visible ~= false
    return self.surface:create("Text", properties, {
        pointerEvents = pointerEvents == true,
    })
end

function Overlay:_reportPlotCopyError(message)
    if self.context.reportPlotCopyError then
        self.context.reportPlotCopyError(message)
    end
end

function Overlay:_setPlotSaveName(saveName)
    self.plotSaveName = tostring(saveName or "")
    local controls = self.controls.plotCopy
    if controls then
        controls.saveValue.Text = self.plotSaveName == ""
            and "Enter save name"
            or compactText(self.plotSaveName, PLOT_SAVE_VALUE_LIMIT)
        controls.saveValue.Color = self.plotSaveName == "" and COLORS.secondary or COLORS.text
    end
end

function Overlay:_clearPlotDropdown()
    for _, item in ipairs(self.plotDropdownItems) do
        item.row:destroy()
        item.label:destroy()
    end
    table.clear(self.plotDropdownItems)
end

function Overlay:_selectPlotOwner(ownerName)
    local previousDefault = self.selectedPlotOwner
        and ("copy_" .. self.selectedPlotOwner)
        or ""
    self.selectedPlotOwner = ownerName
    local controls = self.controls.plotCopy
    controls.ownerValue.Text = compactText(ownerName, PLOT_OWNER_VALUE_LIMIT)
    controls.ownerValue.Color = COLORS.text
    if self.plotSaveName == "" or self.plotSaveName == previousDefault then
        self:_setPlotSaveName("copy_" .. ownerName)
        if controls.saveInput then
            controls.saveInput.Text = self.plotSaveName
        end
    end
end

function Overlay:_setPlotDropdownOpen(open)
    local controls = self.controls.plotCopy
    if not controls then
        return
    end

    self:_clearPlotDropdown()
    self.plotDropdownOpen = open == true
    controls.ownerIndicator.Text = self.plotDropdownOpen and "^" or "v"
    if not self.plotDropdownOpen then
        return
    end

    local succeeded, owners = pcall(self.context.listPlotOwners)
    if not succeeded or type(owners) ~= "table" or #owners == 0 then
        self.plotDropdownOpen = false
        controls.ownerIndicator.Text = "v"
        controls.ownerValue.Text = "No player plots"
        controls.ownerValue.Color = COLORS.danger
        self:_reportPlotCopyError("No other player plots are available")
        return
    end

    if not table.find(owners, self.selectedPlotOwner) then
        self:_selectPlotOwner(owners[1])
    end
    for _, ownerName in ipairs(owners) do
        local row = self:_interactive(self.surface:create("Square", {
            Color = ownerName == self.selectedPlotOwner and COLORS.accentSurface or COLORS.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 26),
            Visible = true,
            ZIndex = 212,
        }))
        local label = self:_text({
            Color = ownerName == self.selectedPlotOwner and COLORS.accent or COLORS.text,
            Size = 12,
            Text = compactText(ownerName, PLOT_OWNER_VALUE_LIMIT),
            ZIndex = 213,
        })
        row:on("click", function()
            self:_selectPlotOwner(ownerName)
            self:_setPlotDropdownOpen(false)
        end)
        table.insert(self.plotDropdownItems, {
            label = label,
            row = row,
        })
    end
    self:_layout()
end

function Overlay:_triggerPlotCopy()
    local plotCopyState = self.context.store:Get().plotCopy
    if plotCopyState and plotCopyState.active == true then
        return
    end
    if not self.selectedPlotOwner then
        self:_reportPlotCopyError("Choose a player plot to copy")
        return
    end
    if self.plotSaveName == "" then
        self:_reportPlotCopyError("Enter a save name")
        return
    end
    self:_setPlotDropdownOpen(false)
    local succeeded, accepted, message = pcall(
        self.context.copyPlot,
        self.selectedPlotOwner,
        self.plotSaveName
    )
    if not succeeded then
        self:_reportPlotCopyError("Plot copy could not start: " .. tostring(accepted))
    elseif accepted == false then
        self:_reportPlotCopyError(message or "Plot copy could not start")
    end
end

function Overlay:_buildPlotCopy()
    if not self.optionAvailable.plotCopy then
        return
    end

    local surface = self.surface
    local controls = self.controls
    controls.sections.plotCopy = {
        label = self:_text({
            Color = COLORS.accent,
            Size = 11,
            Text = "PLOT COPY",
            ZIndex = 203,
        }),
        line = surface:create("Square", {
            Color = COLORS.border,
            Filled = true,
            Size = Vector2.new(206, 1),
            Visible = true,
            ZIndex = 202,
        }, { pointerEvents = false }),
    }
    local plotCopy = {
        ownerButton = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 30),
            Visible = true,
            ZIndex = 202,
        })),
        ownerIndicator = self:_text({
            Center = true,
            Color = COLORS.secondary,
            Size = 12,
            Text = "v",
            ZIndex = 204,
        }),
        ownerLabel = self:_text({
            Color = COLORS.secondary,
            Size = 11,
            Text = "PLAYER",
            ZIndex = 203,
        }),
        ownerOutline = surface:create("Square", {
            Color = COLORS.border,
            Filled = false,
            Size = Vector2.new(CONTENT_WIDTH, 30),
            Thickness = 1,
            Transparency = 0.72,
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false }),
        ownerValue = self:_text({
            Color = COLORS.secondary,
            Size = 12,
            Text = "Select a plot",
            ZIndex = 203,
        }),
        saveButton = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 30),
            Visible = true,
            ZIndex = 202,
        })),
        saveLabel = self:_text({
            Color = COLORS.secondary,
            Size = 11,
            Text = "SAVE",
            ZIndex = 203,
        }),
        saveOutline = surface:create("Square", {
            Color = COLORS.border,
            Filled = false,
            Size = Vector2.new(CONTENT_WIDTH, 30),
            Thickness = 1,
            Transparency = 0.72,
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false }),
        saveValue = self:_text({
            Color = COLORS.secondary,
            Size = 12,
            Text = "Enter save name",
            ZIndex = 203,
        }),
        actionButton = self:_interactive(surface:create("Square", {
            Color = COLORS.accentSurface,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 30),
            Visible = true,
            ZIndex = 202,
        })),
        actionLabel = self:_text({
            Center = true,
            Color = COLORS.accent,
            Size = 13,
            Text = "Copy & Save",
            ZIndex = 203,
        }),
        progressPhase = self:_text({
            Color = COLORS.secondary,
            Size = 11,
            Text = "Ready",
            ZIndex = 203,
        }),
        progressValue = self:_text({
            Center = true,
            Color = COLORS.secondary,
            Size = 11,
            Text = "0%",
            ZIndex = 203,
        }),
        progressTrack = surface:create("Square", {
            Color = COLORS.border,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 4),
            Visible = true,
            ZIndex = 202,
        }, { pointerEvents = false }),
        progressFill = surface:create("Square", {
            Color = COLORS.accent,
            Filled = true,
            Size = Vector2.new(0, 4),
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false }),
    }
    controls.plotCopy = plotCopy
    local nativeSaveInput

    plotCopy.ownerButton:on("click", function()
        self:_setPlotDropdownOpen(not self.plotDropdownOpen)
    end)
    plotCopy.saveButton:on("click", function()
        self:_setPlotDropdownOpen(false)
        if nativeSaveInput then
            nativeSaveInput:CaptureFocus()
        end
    end)
    plotCopy.actionButton:on("click", function()
        self:_triggerPlotCopy()
    end)

    if self.context.uiParent then
        local createInstance = self.context.createInstance or Instance.new
        local inputLayer = createInstance("ScreenGui")
        inputLayer.Name = "UniversalHubPlotCopyInput"
        inputLayer.DisplayOrder = 10000
        inputLayer.IgnoreGuiInset = true
        inputLayer.ResetOnSpawn = false
        inputLayer.Parent = self.context.uiParent

        local saveInput = createInstance("TextBox")
        saveInput.Name = "SaveName"
        saveInput.BackgroundTransparency = 1
        saveInput.ClearTextOnFocus = false
        saveInput.Position = UDim2.fromOffset(-20, -20)
        saveInput.Size = UDim2.fromOffset(1, 1)
        saveInput.Text = ""
        saveInput.TextTransparency = 1
        saveInput.Parent = inputLayer
        nativeSaveInput = saveInput
        plotCopy.inputLayer = inputLayer
        plotCopy.saveInput = saveInput
        self.nativeConnections = self.nativeConnections or {}
        table.insert(self.nativeConnections, saveInput:GetPropertyChangedSignal("Text"):Connect(function()
            self:_setPlotSaveName(saveInput.Text)
        end))
        table.insert(self.nativeConnections, saveInput.Focused:Connect(function()
            plotCopy.saveOutline.Color = COLORS.accent
        end))
        table.insert(self.nativeConnections, saveInput.FocusLost:Connect(function(enterPressed)
            plotCopy.saveOutline.Color = COLORS.border
            if enterPressed then
                self:_triggerPlotCopy()
            end
        end))
    end
end

function Overlay:_build()
    local surface = self.surface
    local controls = self.controls
    local function card(options)
        return {
            background = surface:create("Square", options.background, { pointerEvents = false }),
            border = surface:create("Square", options.border, { pointerEvents = false }),
        }
    end
    local function slider(options)
        return {
            hit = surface:create("Square", options.hit, { pointerEvents = true }),
            track = surface:create("Square", options.track, { pointerEvents = false }),
            fill = surface:create("Square", options.fill, { pointerEvents = false }),
            knob = surface:create("Circle", options.knob, { pointerEvents = false }),
        }
    end

    controls.panelShadow = surface:create("Square", {
        Color = COLORS.panelShadow,
        Filled = true,
        Size = Vector2.new(300, 596),
        Transparency = 0.42,
        Visible = true,
        ZIndex = 198,
    }, { pointerEvents = false })
    controls.panel = self:_capture(surface:create("Square", {
        Color = COLORS.panel,
        Filled = true,
        Size = Vector2.new(300, 596),
        Transparency = 0.97,
        Visible = true,
        ZIndex = 200,
    }))
    controls.panelBorder = surface:create("Square", {
        Color = COLORS.border,
        Filled = false,
        Size = Vector2.new(300, 596),
        Thickness = 1,
        Transparency = 0.9,
        Visible = true,
        ZIndex = 206,
    }, { pointerEvents = false })
    controls.headerSurface = surface:create("Square", {
        Color = COLORS.elevated,
        Filled = true,
        Size = Vector2.new(300, 54),
        Transparency = 0.96,
        Visible = true,
        ZIndex = 201,
    }, { pointerEvents = false })
    controls.headerRail = surface:create("Square", {
        Color = COLORS.accent,
        Filled = true,
        Size = Vector2.zero,
        Visible = false,
        ZIndex = 202,
    }, { pointerEvents = false })
    controls.panel:on("pointerdown", function(_node, point)
        self.panelDragOffset = point - controls.panel.Position
    end)
    controls.panel:on("drag", function(_node, point)
        if not self.panelDragOffset then
            return
        end
        self.panelPosition = point - self.panelDragOffset
        self:_layout()
    end)
    controls.title = self:_text({
        Color = COLORS.text,
        Size = 16,
        Text = "Universal Hub · " .. (self.context.gameLabel or "Universal"),
        ZIndex = 202,
    })
    controls.hideButton = self:_interactive(surface:create("Square", {
        Color = COLORS.elevated,
        Filled = true,
        Size = Vector2.new(58, 22),
        Visible = true,
        ZIndex = 202,
    }))
    controls.hideLabel = self:_text({
        Center = true,
        Color = COLORS.secondary,
        Size = 11,
        Text = "RSHIFT",
        ZIndex = 203,
    })
    controls.hideButton:on("click", function()
        self.context.setMenuVisible(false)
    end)
    controls.status = self:_text({
        Color = COLORS.secondary,
        Size = 13,
        Text = "Inspecting client",
        ZIndex = 202,
    })
    controls.statusDot = surface:create("Circle", {
        Color = COLORS.accent,
        Filled = true,
        NumSides = 20,
        Radius = 3,
        Visible = false,
        ZIndex = 203,
    }, { pointerEvents = false })
    controls.weaponLabel = self:_text({
        Color = COLORS.secondary,
        Size = 13,
        Text = "Weapon",
        ZIndex = 202,
    })
    controls.weaponValue = self:_text({
        Center = true,
        Color = COLORS.accent,
        Size = 13,
        Text = "Spectating",
        ZIndex = 202,
    })
    local weaponCard = card({
        background = {
            Color = COLORS.elevated, Filled = true, Size = Vector2.new(CONTENT_WIDTH, 32), Visible = true, ZIndex = 201,
        },
        border = {
            Color = COLORS.border, Filled = false, Size = Vector2.new(CONTENT_WIDTH, 32), Thickness = 1, Transparency = 0.72, Visible = true, ZIndex = 202,
        },
    })
    controls.weaponSurface = weaponCard.background
    controls.weaponBorder = weaponCard.border
    local fovCard = card({
        background = {
            Color = COLORS.elevated, Filled = true, Size = Vector2.new(CONTENT_WIDTH, 86), Visible = true, ZIndex = 201,
        },
        border = {
            Color = COLORS.border, Filled = false, Size = Vector2.new(CONTENT_WIDTH, 86), Thickness = 1, Transparency = 0.72, Visible = true, ZIndex = 202,
        },
    })
    controls.fovCard = fovCard.background
    controls.fovCardBorder = fovCard.border
    controls.fovLabel = self:_text({
        Color = COLORS.text,
        Size = 14,
        Text = "FOV",
        ZIndex = 202,
    })
    controls.fovValue = self:_text({
        Center = true,
        Color = COLORS.secondary,
        Size = 13,
        Text = "",
        ZIndex = 202,
    })
    controls.fovAmount = self:_text({
        Color = COLORS.text,
        Size = 13,
        Text = "500 px",
        ZIndex = 203,
    })
    controls.fovModeButton = self:_interactive(surface:create("Square", {
        Color = COLORS.elevated,
        Filled = true,
        Size = Vector2.new(60, 30),
        Visible = true,
        ZIndex = 201,
    }))
    controls.fovModeButton:on("click", function()
        local settings = self.context.store:Get().settings
        self.context.setOption("fullScreenAim", not settings.fullScreenAim)
    end)
    local fovSlider = slider({
        hit = { Color = COLORS.panel, Filled = true, Size = Vector2.new(FOV_TRACK_WIDTH, 28), Transparency = HITBOX_TRANSPARENCY, Visible = true, ZIndex = 202 },
        track = { Color = COLORS.border, Filled = true, Size = Vector2.new(FOV_TRACK_WIDTH, 4), Visible = true, ZIndex = 203 },
        fill = { Color = COLORS.accent, Filled = true, Visible = true, ZIndex = 204 },
        knob = { Color = COLORS.text, Filled = true, NumSides = 32, Radius = 7, Visible = true, ZIndex = 205 },
    })
    controls.sliderHit = self:_capture(fovSlider.hit)
    controls.sliderTrack = fovSlider.track
    controls.sliderFill = fovSlider.fill
    controls.sliderKnob = fovSlider.knob
    controls.fovCircle = surface:create("Circle", {
        Color = COLORS.accent,
        Filled = false,
        NumSides = 96,
        Radius = 180,
        Thickness = 1.5,
        Transparency = 0.8,
        Visible = true,
        ZIndex = 50,
    }, { pointerEvents = false })

    controls.rates = {}
    for _, definition in ipairs(RATE_CONTROLS) do
        if self.rateAvailable[definition.id] then
            local control = {
                background = surface:create("Square", {
                    Color = COLORS.elevated,
                    Filled = true,
                    Size = Vector2.new(CONTENT_WIDTH, 54),
                    Visible = true,
                    ZIndex = 201,
                }, { pointerEvents = false }),
                border = surface:create("Square", {
                    Color = COLORS.border,
                    Filled = false,
                    Size = Vector2.new(CONTENT_WIDTH, 54),
                    Thickness = 1,
                    Transparency = 0.72,
                    Visible = true,
                    ZIndex = 202,
                }, { pointerEvents = false }),
                slider = slider({
                    hit = { Color = COLORS.panel, Filled = true, Size = Vector2.new(RATE_TRACK_WIDTH, 28), Transparency = HITBOX_TRANSPARENCY, Visible = true, ZIndex = 202 },
                    track = { Color = COLORS.border, Filled = true, Size = Vector2.new(RATE_TRACK_WIDTH, 4), Visible = true, ZIndex = 203 },
                    fill = { Color = COLORS.accent, Filled = true, Visible = true, ZIndex = 204 },
                    knob = { Color = COLORS.text, Filled = true, NumSides = 32, Radius = RATE_THUMB_RADIUS, Visible = true, ZIndex = 205 },
                }),
                label = self:_text({
                    Color = COLORS.text,
                    Size = 13,
                    Text = definition.label,
                    ZIndex = 203,
                }),
                value = self:_text({
                    Center = true,
                    Color = COLORS.secondary,
                    Size = 12,
                    Text = "0%",
                    ZIndex = 203,
                }),
                valueSurface = surface:create("Square", {
                    Color = COLORS.panel,
                    Filled = true,
                    Size = Vector2.new(42, 24),
                    Visible = true,
                    ZIndex = 202,
                }, { pointerEvents = false }),
                valueBorder = surface:create("Square", {
                    Color = COLORS.border,
                    Filled = false,
                    Size = Vector2.new(42, 24),
                    Thickness = 1,
                    Transparency = 0.72,
                    Visible = true,
                    ZIndex = 203,
                }, { pointerEvents = false }),
            }
            control.hit = self:_capture(control.slider.hit)
            control.track = control.slider.track
            control.fill = control.slider.fill
            control.knob = control.slider.knob
            local activePaint = registerActiveSliderPaint(control.hit, function(painter, point)
                local alpha = math.clamp(
                    (point.X - control.hit.Position.X) / RATE_TRACK_WIDTH,
                    0,
                    1
                )
                local thumbTravel = RATE_TRACK_WIDTH - RATE_THUMB_RADIUS * 2
                local thumbX = control.track.Position.X
                    + RATE_THUMB_RADIUS
                    + thumbTravel * alpha
                paintActiveSlider(
                    painter,
                    control.track,
                    thumbX - control.track.Position.X,
                    thumbX,
                    RATE_THUMB_RADIUS,
                    COLORS.accent
                )
            end)
            local function setRate(point, persist)
                local alpha = math.clamp(
                    (point.X - control.hit.Position.X) / RATE_TRACK_WIDTH,
                    0,
                    1
                )
                self.context.setRate(definition.id, math.round(alpha * 100), persist)
            end
            control.hit:on("pointerdown", function(_node, point)
                setRate(point, false)
                if activePaint then
                    setRetainedSliderVisible(self, control.fill, control.knob, false)
                end
            end)
            control.hit:on("drag", function(_node, point)
                setRate(point, false)
                if activePaint then
                    setRetainedSliderVisible(self, control.fill, control.knob, false)
                end
            end)
            control.hit:on("pointerup", function(_node, point)
                setRate(point, true)
                if activePaint then
                    setRetainedSliderVisible(self, control.fill, control.knob, true)
                end
            end)
            controls.rates[definition.id] = control
        end
    end

    controls.sections = {}
    controls.options = {}
    for _, group in ipairs(OPTION_GROUPS) do
        local hasAvailableOption = false
        for _, optionRow in ipairs(group.rows) do
            for _, optionName in ipairs(optionRow) do
                hasAvailableOption = hasAvailableOption or self.optionAvailable[optionName] == true
            end
        end
        if hasAvailableOption then
            controls.sections[group.id] = {
                label = self:_text({
                    Color = COLORS.accent,
                    Size = 11,
                    Text = group.label,
                    ZIndex = 203,
                }),
                line = surface:create("Square", {
                    Color = COLORS.border,
                    Filled = true,
                    Size = Vector2.new(218, 1),
                    Visible = true,
                    ZIndex = 202,
                }, { pointerEvents = false }),
            }
        end
        for _, optionRow in ipairs(group.rows) do
            for _, optionName in ipairs(optionRow) do
                if self.optionAvailable[optionName] then
        local parent = OPTION_PARENTS[optionName]
        local row = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(134, 30),
            Visible = true,
            ZIndex = 202,
        }))
        local label = self:_text({
            Color = COLORS.text,
            Size = 13,
            Text = self.optionLabels[optionName] or OPTION_LABELS[optionName],
            ZIndex = 203,
        })
        local value = self:_text({
            Center = true,
            Color = COLORS.secondary,
            Size = 12,
            Text = "Off",
            ZIndex = 203,
        })
        local outline = surface:create("Square", {
            Color = COLORS.border,
            Filled = false,
            Size = Vector2.new(134, 30),
            Thickness = 1,
            Transparency = 0.72,
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false })
        local switchShadowTrack = surface:create("Square", {
            Color = COLORS.panelShadow,
            Filled = true,
            Size = Vector2.new(18, 22),
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false })
        local switchShadowLeft = surface:create("Circle", {
            Color = COLORS.panelShadow,
            Filled = true,
            NumSides = 24,
            Radius = 11,
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false })
        local switchShadowRight = surface:create("Circle", {
            Color = COLORS.panelShadow,
            Filled = true,
            NumSides = 24,
            Radius = 11,
            Visible = true,
            ZIndex = 203,
        }, { pointerEvents = false })
        local switchTrack = surface:create("Square", {
            Color = COLORS.border,
            Filled = true,
            Size = Vector2.new(18, 22),
            Visible = true,
            ZIndex = 204,
        }, { pointerEvents = false })
        local switchLeft = surface:create("Circle", {
            Color = COLORS.border,
            Filled = true,
            NumSides = 24,
            Radius = 11,
            Visible = true,
            ZIndex = 204,
        }, { pointerEvents = false })
        local switchRight = surface:create("Circle", {
            Color = COLORS.border,
            Filled = true,
            NumSides = 24,
            Radius = 11,
            Visible = true,
            ZIndex = 204,
        }, { pointerEvents = false })
        local switchFillTrack = surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(18, 18),
            Visible = true,
            ZIndex = 205,
        }, { pointerEvents = false })
        local switchFillLeft = surface:create("Circle", {
            Color = COLORS.elevated,
            Filled = true,
            NumSides = 24,
            Radius = 9,
            Visible = true,
            ZIndex = 205,
        }, { pointerEvents = false })
        local switchFillRight = surface:create("Circle", {
            Color = COLORS.elevated,
            Filled = true,
            NumSides = 24,
            Radius = 9,
            Visible = true,
            ZIndex = 205,
        }, { pointerEvents = false })
        local switchKnobRim = surface:create("Circle", {
            Color = COLORS.border,
            Filled = true,
            NumSides = 24,
            Radius = 9.5,
            Visible = true,
            ZIndex = 206,
        }, { pointerEvents = false })
        local switchKnob = surface:create("Circle", {
            Color = COLORS.text,
            Filled = true,
            NumSides = 24,
            Radius = 8.5,
            Visible = true,
            ZIndex = 207,
        }, { pointerEvents = false })
        local marker
        if parent then
            marker = surface:create("Square", {
                Color = COLORS.border,
                Filled = true,
                Size = Vector2.new(2, 14),
                Visible = true,
                ZIndex = 203,
            }, { pointerEvents = false })
        end
        row:on("click", function()
            if self.optionSupport[optionName] == false then
                return
            end
            local state = self.context.store:Get()
            self.context.setOption(optionName, not state.settings[optionName])
        end)
        controls.options[optionName] = {
            outline = outline,
            row = row,
            label = label,
            marker = marker,
            switch = {
                fillLeft = switchFillLeft,
                fillRight = switchFillRight,
                fillTrack = switchFillTrack,
                knob = switchKnob,
                knobRim = switchKnobRim,
                left = switchLeft,
                right = switchRight,
                shadowLeft = switchShadowLeft,
                shadowRight = switchShadowRight,
                shadowTrack = switchShadowTrack,
                track = switchTrack,
            },
            value = value,
        }
                end
            end
        end
    end

    self:_buildPlotCopy()

    controls.cosmetics = {
        header = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(276, 30),
            Visible = true,
            ZIndex = 202,
        })),
        headerLabel = self:_text({
            Color = COLORS.accent,
            Size = 11,
            Text = "COSMETICS",
            ZIndex = 203,
        }),
        indicator = self:_text({
            Center = true,
            Color = COLORS.secondary,
            Size = 14,
            Text = "+",
            ZIndex = 203,
        }),
        weaponMode = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(134, 24),
            Visible = false,
            ZIndex = 202,
        })),
        weaponModeLabel = self:_text({
            Center = true,
            Color = COLORS.text,
            Size = 12,
            Text = "Weapons",
            Visible = false,
            ZIndex = 203,
        }),
        gloveMode = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(134, 24),
            Visible = false,
            ZIndex = 202,
        })),
        gloveModeLabel = self:_text({
            Center = true,
            Color = COLORS.text,
            Size = 12,
            Text = "Gloves",
            Visible = false,
            ZIndex = 203,
        }),
        weaponBackground = surface:create("Square", {
            Color = COLORS.panel,
            Filled = true,
            Size = Vector2.new(208, 30),
            Visible = false,
            ZIndex = 202,
        }, { pointerEvents = false }),
        weaponName = self:_text({
            Center = true,
            Color = COLORS.text,
            Size = 13,
            Text = "Weapon",
            Visible = false,
            ZIndex = 203,
        }),
        weaponNext = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        })),
        weaponNextLabel = self:_text({
            Center = true,
            Color = COLORS.text,
            Size = 15,
            Text = ">",
            Visible = false,
            ZIndex = 203,
        }),
        weaponPrevious = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        })),
        weaponPreviousLabel = self:_text({
            Center = true,
            Color = COLORS.text,
            Size = 15,
            Text = "<",
            Visible = false,
            ZIndex = 203,
        }),
        next = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        })),
        nextLabel = self:_text({
            Center = true,
            Color = COLORS.text,
            Size = 15,
            Text = ">",
            Visible = false,
            ZIndex = 203,
        }),
        previous = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        })),
        previousLabel = self:_text({
            Center = true,
            Color = COLORS.text,
            Size = 15,
            Text = "<",
            Visible = false,
            ZIndex = 203,
        }),
        reset = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(134, 30),
            Visible = false,
            ZIndex = 202,
        })),
        resetLabel = self:_text({
            Color = COLORS.text,
            Size = 13,
            Text = "Reset Stock",
            Visible = false,
            ZIndex = 203,
        }),
        skinBackground = surface:create("Square", {
            Color = COLORS.panel,
            Filled = true,
            Size = Vector2.new(208, 30),
            Visible = false,
            ZIndex = 202,
        }, { pointerEvents = false }),
        skinName = self:_text({
            Center = true,
            Color = COLORS.text,
            Size = 13,
            Text = "Stock",
            Visible = false,
            ZIndex = 203,
        }),
        statTrak = self:_interactive(surface:create("Square", {
            Color = COLORS.elevated,
            Filled = true,
            Size = Vector2.new(134, 30),
            Visible = false,
            ZIndex = 202,
        })),
        statTrakLabel = self:_text({
            Color = COLORS.text,
            Size = 13,
            Text = "StatTrak",
            Visible = false,
            ZIndex = 203,
        }),
        statTrakValue = self:_text({
            Center = true,
            Color = COLORS.secondary,
            Size = 12,
            Text = "N/A",
            Visible = false,
            ZIndex = 203,
        }),
        wearFill = surface:create("Square", {
            Color = COLORS.accent,
            Filled = true,
            Visible = false,
            ZIndex = 204,
        }, { pointerEvents = false }),
        wearHit = self:_capture(surface:create("Square", {
            Color = COLORS.panel,
            Filled = true,
            Size = Vector2.new(276, 22),
            Transparency = HITBOX_TRANSPARENCY,
            Visible = false,
            ZIndex = 202,
        })),
        wearKnob = surface:create("Circle", {
            Color = COLORS.text,
            Filled = true,
            NumSides = 32,
            Radius = 6,
            Visible = false,
            ZIndex = 205,
        }, { pointerEvents = false }),
        wearLabel = self:_text({
            Color = COLORS.secondary,
            Size = 12,
            Text = "Wear",
            Visible = false,
            ZIndex = 203,
        }),
        wearTrack = surface:create("Square", {
            Color = COLORS.border,
            Filled = true,
            Size = Vector2.new(276, 4),
            Visible = false,
            ZIndex = 203,
        }, { pointerEvents = false }),
        wearValue = self:_text({
            Center = true,
            Color = COLORS.secondary,
            Size = 12,
            Text = "0.00",
            Visible = false,
            ZIndex = 203,
        }),
    }
    controls.cosmetics.colorChannels = {}
    for _, channel in ipairs({
        { id = "r", label = "R", color = Color3.fromRGB(230, 107, 110) },
        { id = "g", label = "G", color = COLORS.accent },
        { id = "b", label = "B", color = Color3.fromRGB(91, 155, 213) },
    }) do
        controls.cosmetics.colorChannels[channel.id] = {
            fill = surface:create("Square", {
                Color = channel.color,
                Filled = true,
                Visible = false,
                ZIndex = 204,
            }, { pointerEvents = false }),
            hit = self:_capture(surface:create("Square", {
                Color = COLORS.panel,
                Filled = true,
                Size = Vector2.new(236, 20),
                Transparency = HITBOX_TRANSPARENCY,
                Visible = false,
                ZIndex = 202,
            })),
            knob = surface:create("Circle", {
                Color = COLORS.text,
                Filled = true,
                NumSides = 32,
                Radius = 5,
                Visible = false,
                ZIndex = 205,
            }, { pointerEvents = false }),
            label = self:_text({
                Color = channel.color,
                Size = 12,
                Text = channel.label,
                Visible = false,
                ZIndex = 203,
            }),
            track = surface:create("Square", {
                Color = COLORS.border,
                Filled = true,
                Size = Vector2.new(236, 4),
                Visible = false,
                ZIndex = 203,
            }, { pointerEvents = false }),
            value = self:_text({
                Center = true,
                Color = COLORS.secondary,
                Size = 11,
                Text = "0",
                Visible = false,
                ZIndex = 203,
            }),
        }
    end
    controls.cosmetics.header:on("click", function()
        self.context.setCosmeticsOpen(not self.context.store:Get().cosmeticsOpen)
    end)
    controls.cosmetics.weaponMode:on("click", function()
        self.context.setCosmeticMode("weapon")
    end)
    controls.cosmetics.gloveMode:on("click", function()
        self.context.setCosmeticMode("gloves")
    end)
    controls.cosmetics.weaponPrevious:on("click", function()
        self.context.cycleCosmeticWeapon(-1)
    end)
    controls.cosmetics.weaponNext:on("click", function()
        self.context.cycleCosmeticWeapon(1)
    end)
    controls.cosmetics.previous:on("click", function()
        if self.context.store:Get().cosmeticMode == "gloves" then
            self.context.cycleGlove(-1)
        else
            self.context.cycleSkin(-1)
        end
    end)
    controls.cosmetics.next:on("click", function()
        if self.context.store:Get().cosmeticMode == "gloves" then
            self.context.cycleGlove(1)
        else
            self.context.cycleSkin(1)
        end
    end)
    controls.cosmetics.statTrak:on("click", function()
        local state = self.context.store:Get()
        if state.cosmeticMode == "gloves" then
            local current = state.settings.gloveColorOverride
            if type(current) == "table" then
                self.context.setGloveColor(false)
            else
                self.context.setGloveColor({
                    b = 0.68,
                    g = 0.84,
                    r = 0.38,
                })
            end
        else
            self.context.toggleStatTrak()
        end
    end)
    controls.cosmetics.reset:on("click", function()
        if self.context.store:Get().cosmeticMode == "gloves" then
            self.context.resetGlove()
        else
            self.context.resetSkin()
        end
    end)

    local function setFov(point, persist)
        local state = self.context.store:Get()
        if state.settings.fullScreenAim then
            return
        end
        local alpha = math.clamp((point.X - self.sliderStartX) / FOV_TRACK_WIDTH, 0, 1)
        local settings = state.settings
        self.context.setFov(
            settings.minimumFov + (settings.maximumFov - settings.minimumFov) * alpha,
            persist
        )
    end
    local function fovSliderEnabled()
        return self.context.store:Get().settings.fullScreenAim ~= true
    end
    local fovActivePaint = registerActiveSliderPaint(controls.sliderHit, function(painter, point)
        if not fovSliderEnabled() then
            return
        end
        local alpha = math.clamp((point.X - self.sliderStartX) / FOV_TRACK_WIDTH, 0, 1)
        local knobX = self.sliderStartX + FOV_TRACK_WIDTH * alpha
        paintActiveSlider(
            painter,
            controls.sliderTrack,
            FOV_TRACK_WIDTH * alpha,
            knobX,
            7,
            COLORS.accent
        )
    end)
    controls.sliderHit:on("pointerdown", function(_node, point)
        setFov(point, false)
        if fovActivePaint and fovSliderEnabled() then
            setRetainedSliderVisible(self, controls.sliderFill, controls.sliderKnob, false)
        end
    end)
    controls.sliderHit:on("drag", function(_node, point)
        setFov(point, false)
        if fovActivePaint and fovSliderEnabled() then
            setRetainedSliderVisible(self, controls.sliderFill, controls.sliderKnob, false)
        end
    end)
    controls.sliderHit:on("pointerup", function(_node, point)
        setFov(point, true)
        if fovActivePaint then
            setRetainedSliderVisible(self, controls.sliderFill, controls.sliderKnob, true)
        end
    end)
    local function setWear(point)
        local alpha = math.clamp((point.X - self.wearStartX) / 276, 0, 1)
        if self.context.store:Get().cosmeticMode == "gloves" then
            self.context.setGloveWear(alpha)
        else
            self.context.setWear(alpha)
        end
    end
    local wearActivePaint = registerActiveSliderPaint(controls.cosmetics.wearHit, function(painter, point)
        local alpha = math.clamp((point.X - self.wearStartX) / 276, 0, 1)
        paintActiveSlider(
            painter,
            controls.cosmetics.wearTrack,
            276 * alpha,
            self.wearStartX + 276 * alpha,
            6,
            COLORS.accent
        )
    end)
    controls.cosmetics.wearHit:on("pointerdown", function(_node, point)
        setWear(point)
        if wearActivePaint then
            setRetainedSliderVisible(
                self,
                controls.cosmetics.wearFill,
                controls.cosmetics.wearKnob,
                false
            )
        end
    end)
    controls.cosmetics.wearHit:on("drag", function(_node, point)
        setWear(point)
        if wearActivePaint then
            setRetainedSliderVisible(
                self,
                controls.cosmetics.wearFill,
                controls.cosmetics.wearKnob,
                false
            )
        end
    end)
    controls.cosmetics.wearHit:on("pointerup", function(_node, point)
        setWear(point)
        if wearActivePaint then
            setRetainedSliderVisible(
                self,
                controls.cosmetics.wearFill,
                controls.cosmetics.wearKnob,
                true
            )
        end
    end)
    for channelName, channel in pairs(controls.cosmetics.colorChannels) do
        local function setColor(point)
            local state = self.context.store:Get()
            local current = state.settings.gloveColorOverride
            if type(current) ~= "table" then
                return
            end
            local color = {
                b = current.b,
                g = current.g,
                r = current.r,
            }
            color[channelName] = math.clamp((point.X - self.colorStartX) / 236, 0, 1)
            self.context.setGloveColor(color)
        end
        local activePaint = registerActiveSliderPaint(channel.hit, function(painter, point)
            local alpha = math.clamp((point.X - self.colorStartX) / 236, 0, 1)
            paintActiveSlider(
                painter,
                channel.track,
                236 * alpha,
                self.colorStartX + 236 * alpha,
                5,
                channel.label.Color
            )
        end)
        channel.hit:on("pointerdown", function(_node, point)
            setColor(point)
            if activePaint then
                setRetainedSliderVisible(self, channel.fill, channel.knob, false)
            end
        end)
        channel.hit:on("drag", function(_node, point)
            setColor(point)
            if activePaint then
                setRetainedSliderVisible(self, channel.fill, channel.knob, false)
            end
        end)
        channel.hit:on("pointerup", function(_node, point)
            setColor(point)
            if activePaint then
                setRetainedSliderVisible(self, channel.fill, channel.knob, true)
            end
        end)
    end
end

function Overlay:_layout()
    local camera = self.context.getCamera()
    if not camera then
        return
    end

    local controls = self.controls
    local panelSize = controls.panel.Size
    local defaultPosition = Vector2.new(math.max(20, camera.ViewportSize.X - 324), 20)
    local requestedPosition = self.panelPosition or defaultPosition
    local x = math.clamp(requestedPosition.X, 0, math.max(0, camera.ViewportSize.X - panelSize.X))
    local y = math.clamp(requestedPosition.Y, 0, math.max(0, camera.ViewportSize.Y - panelSize.Y))
    if self.panelPosition then
        self.panelPosition = Vector2.new(x, y)
    end
    controls.panel.Position = Vector2.new(x, y)
    controls.panelShadow.Position = Vector2.new(x + 5, y + 6)
    controls.panelBorder.Position = Vector2.new(x, y)
    controls.headerSurface.Position = Vector2.new(x, y)
    controls.headerRail.Position = Vector2.new(x, y)
    controls.title.Position = Vector2.new(x + 16, y + 12)
    controls.hideButton.Position = Vector2.new(x + 232, y + 8)
    controls.hideLabel.Position = Vector2.new(x + 261, y + 13)
    controls.status.Position = Vector2.new(x + 16, y + 32)
    controls.statusDot.Position = Vector2.new(x + 284, y + 41)
    controls.weaponSurface.Position = Vector2.new(x + 12, y + 54)
    controls.weaponBorder.Position = controls.weaponSurface.Position
    controls.weaponLabel.Position = Vector2.new(x + 24, y + 64)
    controls.weaponValue.Position = Vector2.new(x + 244, y + 64)
    controls.fovCard.Position = Vector2.new(x + 12, y + 92)
    controls.fovCardBorder.Position = controls.fovCard.Position
    controls.fovLabel.Position = Vector2.new(x + 24, y + 102)
    controls.fovAmount.Position = Vector2.new(x + 248, y + 102)
    controls.fovModeButton.Position = Vector2.new(x + 24, y + 140)
    controls.fovValue.Position = Vector2.new(x + 54, y + 145)

    self.sliderStartX = x + 24
    controls.sliderHit.Position = Vector2.new(self.sliderStartX, y + 114)
    controls.sliderTrack.Position = Vector2.new(self.sliderStartX, y + 127)
    controls.sliderFill.Position = controls.sliderTrack.Position

    local sectionY = y + (self.aimControlsSupported and 184 or 60)
    local aimSection = controls.sections.rage
    if aimSection then
        aimSection.label.Position = Vector2.new(x + 12, sectionY)
        aimSection.line.Position = Vector2.new(x + 64, sectionY + 7)
        sectionY = sectionY + 22
    end
    for _, definition in ipairs(RATE_CONTROLS) do
        local control = controls.rates[definition.id]
        if control then
            control.background.Position = Vector2.new(x + 12, sectionY)
            control.border.Position = control.background.Position
            control.label.Position = Vector2.new(x + 22, sectionY + 8)
            control.valueSurface.Visible = false
            control.valueBorder.Visible = false
            control.value.Position = Vector2.new(x + 258, sectionY + 8)
            control.hit.Position = Vector2.new(x + 22, sectionY + 22)
            control.track.Position = Vector2.new(x + 22, sectionY + 35)
            control.fill.Position = control.track.Position
            sectionY = sectionY + 58
        end
    end
    for _, group in ipairs(OPTION_GROUPS) do
        local section = controls.sections[group.id]
        if section then
        if group.id ~= "rage" then
            section.label.Position = Vector2.new(x + 12, sectionY)
            section.line.Position = Vector2.new(x + 70, sectionY + 7)
            sectionY = sectionY + 22
        end
        for _, optionRow in ipairs(group.rows) do
            local availableCount = 0
            for _, optionName in ipairs(optionRow) do
                if controls.options[optionName] then
                    availableCount = availableCount + 1
                end
            end
            local column = 0
            local rowWidth = availableCount == 1 and CONTENT_WIDTH or 134
            for _, optionName in ipairs(optionRow) do
                local option = controls.options[optionName]
                if option then
                column = column + 1
                local rowX = x + 12 + (column - 1) * 142
                option.row.Position = Vector2.new(rowX, sectionY)
                option.row.Size = Vector2.new(rowWidth, 32)
                option.outline.Position = option.row.Position
                option.outline.Size = option.row.Size
                if option.marker then
                    option.marker.Position = Vector2.new(rowX + 10, sectionY + 9)
                end
                option.label.Position =
                    Vector2.new(rowX + (option.marker and 24 or 12), sectionY + 10)
                option.value.Position = Vector2.new(rowX + rowWidth - 60, sectionY + 10)
                local switchX = rowX + rowWidth - 30
                local switchY = sectionY + 16
                option.switch.shadowTrack.Position = Vector2.new(switchX - 9, switchY - 10)
                option.switch.shadowLeft.Position = Vector2.new(switchX - 9, switchY + 1)
                option.switch.shadowRight.Position = Vector2.new(switchX + 9, switchY + 1)
                option.switch.track.Position = Vector2.new(switchX - 9, switchY - 11)
                option.switch.left.Position = Vector2.new(switchX - 9, switchY)
                option.switch.right.Position = Vector2.new(switchX + 9, switchY)
                option.switch.fillTrack.Position = Vector2.new(switchX - 9, switchY - 9)
                option.switch.fillLeft.Position = Vector2.new(switchX - 9, switchY)
                option.switch.fillRight.Position = Vector2.new(switchX + 9, switchY)
                end
            end
            if column > 0 then
                sectionY = sectionY + 36
            end
        end
        sectionY = sectionY + 6
        end
    end

    local plotCopy = controls.plotCopy
    if plotCopy then
        local section = controls.sections.plotCopy
        section.label.Position = Vector2.new(x + 12, sectionY)
        section.line.Position = Vector2.new(x + 82, sectionY + 7)
        sectionY = sectionY + 22

        plotCopy.ownerButton.Position = Vector2.new(x + 12, sectionY)
        plotCopy.ownerOutline.Position = plotCopy.ownerButton.Position
        plotCopy.ownerLabel.Position = Vector2.new(x + 22, sectionY + 9)
        plotCopy.ownerValue.Position = Vector2.new(x + 106, sectionY + 9)
        plotCopy.ownerIndicator.Position = Vector2.new(x + 275, sectionY + 8)

        plotCopy.saveButton.Position = Vector2.new(x + 12, sectionY + 36)
        plotCopy.saveOutline.Position = plotCopy.saveButton.Position
        plotCopy.saveLabel.Position = Vector2.new(x + 22, sectionY + 45)
        plotCopy.saveValue.Position = Vector2.new(x + 82, sectionY + 45)

        plotCopy.actionButton.Position = Vector2.new(x + 12, sectionY + 72)
        plotCopy.actionLabel.Position = Vector2.new(x + 150, sectionY + 80)
        plotCopy.progressPhase.Position = Vector2.new(x + 14, sectionY + 111)
        plotCopy.progressValue.Position = Vector2.new(x + 274, sectionY + 111)
        plotCopy.progressTrack.Position = Vector2.new(x + 12, sectionY + 130)
        plotCopy.progressFill.Position = plotCopy.progressTrack.Position

        for index, item in ipairs(self.plotDropdownItems) do
            item.row.Position = Vector2.new(x + 12, sectionY + 30 + (index - 1) * 26)
            item.label.Position = Vector2.new(x + 22, sectionY + 37 + (index - 1) * 26)
        end
        sectionY = sectionY + 142
    end

    self.optionsPanelHeight = sectionY - y + 12
    local cosmetics = controls.cosmetics
    cosmetics.header.Position = Vector2.new(x + 12, sectionY)
    cosmetics.headerLabel.Position = Vector2.new(x + 22, sectionY + 9)
    cosmetics.indicator.Position = Vector2.new(x + 270, sectionY + 7)
    cosmetics.weaponMode.Position = Vector2.new(x + 12, sectionY + 30)
    cosmetics.weaponModeLabel.Position = Vector2.new(x + 79, sectionY + 37)
    cosmetics.gloveMode.Position = Vector2.new(x + 154, sectionY + 30)
    cosmetics.gloveModeLabel.Position = Vector2.new(x + 221, sectionY + 37)
    cosmetics.weaponPrevious.Position = Vector2.new(x + 12, sectionY + 58)
    cosmetics.weaponPreviousLabel.Position = Vector2.new(x + 27, sectionY + 65)
    cosmetics.weaponBackground.Position = Vector2.new(x + 46, sectionY + 58)
    cosmetics.weaponName.Position = Vector2.new(x + 150, sectionY + 66)
    cosmetics.weaponNext.Position = Vector2.new(x + 258, sectionY + 58)
    cosmetics.weaponNextLabel.Position = Vector2.new(x + 273, sectionY + 65)
    local weaponOffset = self.cosmeticMode == "weapon" and 34 or 0
    cosmetics.previous.Position = Vector2.new(x + 12, sectionY + 58 + weaponOffset)
    cosmetics.previousLabel.Position = Vector2.new(x + 27, sectionY + 65 + weaponOffset)
    cosmetics.skinBackground.Position = Vector2.new(x + 46, sectionY + 58 + weaponOffset)
    cosmetics.skinName.Position = Vector2.new(x + 150, sectionY + 66 + weaponOffset)
    cosmetics.next.Position = Vector2.new(x + 258, sectionY + 58 + weaponOffset)
    cosmetics.nextLabel.Position = Vector2.new(x + 273, sectionY + 65 + weaponOffset)
    cosmetics.wearLabel.Position = Vector2.new(x + 12, sectionY + 94 + weaponOffset)
    cosmetics.wearValue.Position = Vector2.new(x + 264, sectionY + 94 + weaponOffset)
    self.wearStartX = x + 12
    cosmetics.wearHit.Position = Vector2.new(x + 12, sectionY + 106 + weaponOffset)
    cosmetics.wearTrack.Position = Vector2.new(x + 12, sectionY + 115 + weaponOffset)
    cosmetics.wearFill.Position = cosmetics.wearTrack.Position
    cosmetics.statTrak.Position = Vector2.new(x + 12, sectionY + 132 + weaponOffset)
    cosmetics.statTrakLabel.Position = Vector2.new(x + 21, sectionY + 140 + weaponOffset)
    cosmetics.statTrakValue.Position = Vector2.new(x + 124, sectionY + 140 + weaponOffset)
    cosmetics.reset.Position = Vector2.new(x + 154, sectionY + 132 + weaponOffset)
    cosmetics.resetLabel.Position = Vector2.new(x + 163, sectionY + 140 + weaponOffset)
    self.colorStartX = x + 32
    for index, channelName in ipairs({ "r", "g", "b" }) do
        local channel = cosmetics.colorChannels[channelName]
        local channelY = sectionY + 166 + weaponOffset + (index - 1) * 24
        channel.label.Position = Vector2.new(x + 12, channelY + 4)
        channel.hit.Position = Vector2.new(x + 32, channelY)
        channel.track.Position = Vector2.new(x + 32, channelY + 8)
        channel.fill.Position = channel.track.Position
        channel.value.Position = Vector2.new(x + 280, channelY + 3)
    end
end

function Overlay:_setMenuVisible(visible)
    local controls = self.controls
    for _, name in ipairs({
        "panel",
        "panelShadow",
        "panelBorder",
        "headerSurface",
        "title",
        "hideButton",
        "hideLabel",
        "status",
    }) do
        controls[name].Visible = visible
    end
    local aimVisible = visible and self.aimControlsSupported
    for _, name in ipairs({
        "weaponLabel",
        "weaponSurface",
        "weaponBorder",
        "weaponValue",
        "fovCard",
        "fovCardBorder",
        "fovLabel",
        "fovAmount",
        "fovValue",
        "fovModeButton",
        "sliderHit",
        "sliderTrack",
        "sliderFill",
        "sliderKnob",
    }) do
        controls[name].Visible = aimVisible
    end
    for _, option in pairs(controls.options) do
        setVisible(option, visible)
        option.value.Visible = visible
            and (option.value.Text == "N/A" or option.value.Text == "Standby")
    end
    for _, rate in pairs(controls.rates) do
        setVisible(rate, visible)
    end
    for _, section in pairs(controls.sections) do
        setVisible(section, visible)
    end
    local plotCopy = controls.plotCopy
    if plotCopy then
        for name, node in pairs(plotCopy) do
            if name ~= "inputLayer" and name ~= "saveInput" then
                node.Visible = visible
            end
        end
        for _, item in ipairs(self.plotDropdownItems) do
            setVisible(item, visible and self.plotDropdownOpen)
        end
        if plotCopy.inputLayer then
            plotCopy.inputLayer.Enabled = visible
        end
        if not visible then
            self:_setPlotDropdownOpen(false)
        end
    end
    local cosmeticsVisible = visible and self.cosmeticsSupported
    controls.cosmetics.header.Visible = cosmeticsVisible
    controls.cosmetics.headerLabel.Visible = cosmeticsVisible
    controls.cosmetics.indicator.Visible = cosmeticsVisible
    for name, node in pairs(controls.cosmetics) do
        if name ~= "header" and name ~= "headerLabel" and name ~= "indicator" then
            if name == "colorChannels" then
                for _, channel in pairs(node) do
                    setVisible(
                        channel,
                        cosmeticsVisible and self.cosmeticsOpen == true and self.gloveColorVisible == true
                    )
                end
            elseif COSMETIC_WEAPON_CONTROLS[name] then
                node.Visible = cosmeticsVisible
                    and self.cosmeticsOpen == true
                    and self.cosmeticMode == "weapon"
            else
                node.Visible = cosmeticsVisible and self.cosmeticsOpen == true
            end
        end
    end
    for node in pairs(self.activeSliderVisuals) do
        node.Visible = false
    end

    if self.captured ~= visible then
        self.captured = visible
        if self.context.setInputCaptured then
            self.context.setInputCaptured(visible)
        end
    end
end

function Overlay:_renderState(state)
    if self.destroyed then
        return
    end

    self.cosmeticMode = state.cosmeticMode == "gloves" and "gloves" or "weapon"
    self:_layout()
    local settings = state.settings
    local controls = self.controls
    controls.status.Text = state.status or "Ready"
    controls.status.Color = state.error and COLORS.danger or COLORS.secondary
    controls.statusDot.Color = state.error and COLORS.danger or COLORS.accent
    controls.weaponValue.Text = state.activeWeapon or "Spectating"
    controls.weaponValue.Color = state.activeWeapon and COLORS.accent or COLORS.secondary
    self.cosmeticsOpen = state.cosmeticsOpen == true

    local plotCopy = controls.plotCopy
    if plotCopy then
        local plotCopyState = state.plotCopy or {}
        local progress = math.clamp(plotCopyState.progress or 0, 0, 1)
        local active = plotCopyState.active == true
        plotCopy.progressPhase.Text = compactText(plotCopyState.phase or "Ready", 34)
        plotCopy.progressPhase.Color = state.error and COLORS.danger
            or (active and COLORS.text or COLORS.secondary)
        plotCopy.progressValue.Text = ("%d%%"):format(math.round(progress * 100))
        plotCopy.progressValue.Color = active and COLORS.accent or COLORS.secondary
        plotCopy.progressFill.Size = Vector2.new(CONTENT_WIDTH * progress, 4)
        plotCopy.progressFill.Color = state.error and COLORS.danger or COLORS.accent
        self:_setControlColor(
            plotCopy.actionButton,
            active and COLORS.panel or COLORS.accentSurface
        )
        plotCopy.actionLabel.Text = active and "Copying..." or "Copy & Save"
        plotCopy.actionLabel.Color = active and COLORS.secondary or COLORS.accent
    end

    for optionName, option in pairs(controls.options) do
        local enabled = settings[optionName] == true
        local parent = OPTION_PARENTS[optionName]
        local supported = self.optionSupport[optionName] ~= false
        local available = supported and (not parent or settings[parent] == true)
        self:_setControlColor(
            option.row,
            available and COLORS.elevated or COLORS.panel
        )
        option.label.Color = available and COLORS.text or COLORS.secondary
        option.outline.Color = COLORS.border
        option.outline.Transparency = available and 0.72 or 0.42
        local switchColor = available and enabled and COLORS.toggleActive or COLORS.border
        option.switch.track.Color = switchColor
        option.switch.left.Color = switchColor
        option.switch.right.Color = switchColor
        option.switch.fillTrack.Color = switchColor
        option.switch.fillLeft.Color = switchColor
        option.switch.fillRight.Color = switchColor
        option.switch.knobRim.Color = available and COLORS.border or COLORS.panel
        option.switch.knob.Color = available and COLORS.text or COLORS.secondary
        local switchCenterX = option.switch.track.Position.X + 9
        local switchCenterY = option.switch.left.Position.Y
        local knobPosition = Vector2.new(switchCenterX + (enabled and 9 or -9), switchCenterY)
        option.switch.knobRim.Position = knobPosition
        option.switch.knob.Position = knobPosition
        if option.marker then
            option.marker.Color = available and COLORS.accent or COLORS.border
        end
        option.value.Color = available and enabled and COLORS.accent or COLORS.secondary
        option.value.Text = not supported and "N/A"
            or (not available and enabled and "Standby" or "")
        option.value.Visible = state.menuVisible ~= false
            and (option.value.Text == "N/A" or option.value.Text == "Standby")
    end

    for _, definition in ipairs(RATE_CONTROLS) do
        local control = controls.rates[definition.id]
        if control then
            local value = math.clamp(settings[definition.id] or 0, 0, 100)
            local alpha = value / 100
            local thumbTravel = RATE_TRACK_WIDTH - RATE_THUMB_RADIUS * 2
            local thumbX = control.track.Position.X
                + RATE_THUMB_RADIUS
                + thumbTravel * alpha
            control.fill.Size = Vector2.new(
                math.max(0, thumbX - control.track.Position.X),
                4
            )
            control.knob.Position =
                Vector2.new(
                    thumbX,
                    control.track.Position.Y + 2
                )
            control.value.Text = ("%d%%"):format(math.round(value))
        end
    end

    local alpha = (settings.fov - settings.minimumFov) / (settings.maximumFov - settings.minimumFov)
    controls.sliderFill.Size = Vector2.new(FOV_TRACK_WIDTH * alpha, 4)
    controls.sliderKnob.Position = Vector2.new(
        self.sliderStartX + FOV_TRACK_WIDTH * alpha,
        controls.sliderTrack.Position.Y + 2
    )
    self:_setControlColor(
        controls.fovModeButton,
        settings.fullScreenAim and COLORS.accentSurface or COLORS.elevated
    )
    controls.sliderFill.Color = settings.fullScreenAim and COLORS.border or COLORS.accent
    controls.sliderKnob.Color = settings.fullScreenAim and COLORS.secondary or COLORS.text
    controls.fovValue.Color = settings.fullScreenAim and COLORS.accent or COLORS.secondary
    controls.fovLabel.Text = "FOV"
    controls.fovAmount.Text = ("%d px"):format(math.round(settings.fov))
    controls.fovValue.Text = "Fullscreen"
    controls.fovCircle.Radius = settings.fov
    controls.fovCircle.Visible = self.aimControlsSupported
        and settings.fovCircle ~= false
        and not settings.fullScreenAim

    local cosmeticMode = self.cosmeticMode
    local gloveColor = settings.gloveColorOverride
    self.gloveColorVisible = cosmeticMode == "gloves" and type(gloveColor) == "table"
    local collapsedHeight = (self.optionsPanelHeight or 560) + 36
    controls.panel.Size = Vector2.new(300, if self.cosmeticsSupported
        then (self.cosmeticsOpen
            and (collapsedHeight
                + (cosmeticMode == "weapon" and 162 or (self.gloveColorVisible and 202 or 128)))
            or collapsedHeight)
        else (self.optionsPanelHeight or 596))
    controls.panelShadow.Size = controls.panel.Size
    controls.panelBorder.Size = controls.panel.Size
    local cosmetics = cosmeticMode == "gloves" and (state.gloves or {}) or (state.cosmetics or {})
    local cosmeticControls = controls.cosmetics
    local minimumWear = cosmetics.minimumWear or 0
    local maximumWear = cosmetics.maximumWear or 1
    local wearRange = maximumWear - minimumWear
    local wearAlpha = wearRange > 0 and ((cosmetics.wear or minimumWear) - minimumWear) / wearRange or 0
    cosmeticControls.indicator.Text = self.cosmeticsOpen and "-" or "+"
    self:_setControlColor(
        cosmeticControls.weaponMode,
        cosmeticMode == "weapon" and COLORS.accentSurface or COLORS.elevated
    )
    self:_setControlColor(
        cosmeticControls.gloveMode,
        cosmeticMode == "gloves" and COLORS.accentSurface or COLORS.elevated
    )
    cosmeticControls.weaponModeLabel.Color = cosmeticMode == "weapon" and COLORS.accent or COLORS.text
    cosmeticControls.gloveModeLabel.Color = cosmeticMode == "gloves" and COLORS.accent or COLORS.text
    cosmeticControls.weaponModeLabel.Text =
        cosmeticMode == "weapon" and (cosmetics.weapon or "Weapon") or "Weapons"
    cosmeticControls.gloveModeLabel.Text =
        cosmeticMode == "gloves" and (cosmetics.weapon or "Gloves") or "Gloves"
    cosmeticControls.weaponName.Text = state.cosmeticWeapon or state.activeWeapon or "Select weapon"
    cosmeticControls.skinName.Text = cosmetics.skinLabel or cosmetics.skin or "Stock"
    cosmeticControls.wearValue.Text = ("%.2f"):format(cosmetics.wear or 0)
    cosmeticControls.wearFill.Size = Vector2.new(276 * wearAlpha, 4)
    cosmeticControls.wearKnob.Position =
        Vector2.new(self.wearStartX + 276 * wearAlpha, cosmeticControls.wearTrack.Position.Y + 2)
    local supportsStatTrak = cosmeticMode ~= "gloves" and cosmetics.supportsStatTrak == true
    local solidColor = cosmeticMode == "gloves" and type(gloveColor) == "table"
    self:_setControlColor(cosmeticControls.statTrak,
        solidColor and COLORS.accentSurface
        or (supportsStatTrak and (cosmetics.statTrak and COLORS.accentSurface or COLORS.elevated) or COLORS.elevated))
    cosmeticControls.statTrakLabel.Color =
        (supportsStatTrak or cosmeticMode == "gloves") and COLORS.text or COLORS.secondary
    cosmeticControls.statTrakValue.Color =
        (solidColor or (supportsStatTrak and cosmetics.statTrak)) and COLORS.accent or COLORS.secondary
    cosmeticControls.statTrakLabel.Text = cosmeticMode == "gloves" and "Solid Color" or "StatTrak"
    cosmeticControls.statTrakValue.Text = cosmeticMode == "gloves"
            and (solidColor and "On" or "Off")
        or (not supportsStatTrak and "N/A" or (cosmetics.statTrak and "On" or "Off"))
    if solidColor then
        for _, channelName in ipairs({ "r", "g", "b" }) do
            local channel = cosmeticControls.colorChannels[channelName]
            local value = math.clamp(gloveColor[channelName] or 0, 0, 1)
            channel.fill.Size = Vector2.new(236 * value, 4)
            channel.knob.Position =
                Vector2.new(self.colorStartX + 236 * value, channel.track.Position.Y + 2)
            channel.value.Text = tostring(math.round(value * 255))
        end
    end
    cosmeticControls.resetLabel.Text = cosmeticMode == "gloves" and "Reset Game" or "Reset Stock"
    self:_setMenuVisible(state.menuVisible ~= false)
end

function Overlay:_ensureBombBillboard()
    if self.worldGui or not self.context.uiParent then
        return self.worldGui
    end

    local createInstance = self.context.createInstance or Instance.new
    local billboard = createInstance("BillboardGui")
    billboard.Name = "UniversalHubBombTimer"
    billboard.AlwaysOnTop = false
    billboard.Enabled = false
    billboard.LightInfluence = 0
    billboard.MaxDistance = 350
    billboard.Size = UDim2.fromOffset(64, 22)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
    billboard.Parent = self.context.uiParent

    local panel = createInstance("Frame")
    panel.Name = "Panel"
    panel.BackgroundColor3 = COLORS.panel
    panel.BackgroundTransparency = 0.04
    panel.BorderSizePixel = 0
    panel.Size = UDim2.fromScale(1, 1)
    panel.Parent = billboard

    local corner = createInstance("UICorner")
    corner.CornerRadius = UDim.new(0, 3)
    corner.Parent = panel

    local stroke = createInstance("UIStroke")
    stroke.Color = COLORS.border
    stroke.Thickness = 1
    stroke.Parent = panel

    local accent = createInstance("Frame")
    accent.Name = "Accent"
    accent.BackgroundColor3 = COLORS.accent
    accent.BorderSizePixel = 0
    accent.Position = UDim2.fromOffset(4, 4)
    accent.Size = UDim2.new(0, 3, 1, -8)
    accent.Parent = panel

    local title = createInstance("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.Position = UDim2.new(0, 12, 0, 0)
    title.Size = UDim2.new(0.42, -12, 1, 0)
    title.Text = "BOMB"
    title.TextColor3 = COLORS.secondary
    title.TextSize = 10
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = panel

    local timer = createInstance("TextLabel")
    timer.Name = "Timer"
    timer.BackgroundTransparency = 1
    timer.Font = Enum.Font.Code
    timer.Position = UDim2.new(0.42, 0, 0, 0)
    timer.Size = UDim2.new(0.58, -8, 1, 0)
    timer.Text = "0.0s"
    timer.TextColor3 = COLORS.text
    timer.TextSize = 13
    timer.TextXAlignment = Enum.TextXAlignment.Right
    timer.Parent = panel

    self.worldGui = {
        accent = accent,
        billboard = billboard,
        panel = panel,
        stroke = stroke,
        timer = timer,
        title = title,
    }
    return self.worldGui
end

function Overlay:_renderBomb(observation, settings)
    local visible = settings.bombTimer == true
        and type(observation) == "table"
        and observation.visible == true
        and observation.adornee ~= nil
    if not visible then
        if self.worldGui then
            self.worldGui.billboard.Enabled = false
        end
        return
    end

    local gui = self:_ensureBombBillboard()
    if not gui then
        return
    end
    local presentation = observation.presentation or {}
    gui.billboard.Adornee = observation.adornee
    gui.billboard.AlwaysOnTop = presentation.alwaysOnTop == true
    gui.billboard.Enabled = presentation.visible ~= false
    gui.billboard.Size = UDim2.fromOffset(presentation.width or 64, presentation.height or 22)
    local urgent = (observation.remaining or 0) <= 10
    gui.timer.Text = ("%.1fs"):format(math.max(observation.remaining or 0, 0))
    gui.timer.TextColor3 = urgent and COLORS.danger or COLORS.text
    gui.timer.TextSize = presentation.textSize or 13
    gui.accent.BackgroundColor3 = urgent and COLORS.danger or COLORS.accent
    gui.stroke.Color = urgent and COLORS.danger or COLORS.border
end

function Overlay:_getPlayerNodes(player)
    local nodes = self.playerNodes[player]
    if nodes then
        return nodes
    end

    nodes = {
        bodyParts = {},
        box = self.surface:create("Square", {
            Color = COLORS.danger,
            Filled = false,
            Thickness = 1.5,
            Visible = false,
            ZIndex = WORLD_LAYER.chams,
        }, { pointerEvents = false }),
        name = self:_text({
            Center = true,
            Color = COLORS.text,
            Outline = true,
            Size = 13,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.player,
        }),
        healthTrack = self.surface:create("Square", {
            Color = COLORS.border,
            Filled = true,
            Visible = false,
            ZIndex = WORLD_LAYER.player,
        }, { pointerEvents = false }),
        healthFill = self.surface:create("Square", {
            Color = COLORS.accent,
            Filled = true,
            Visible = false,
            ZIndex = WORLD_LAYER.health,
        }, { pointerEvents = false }),
        healthTip = self.surface:create("Square", {
            Color = COLORS.text,
            Filled = true,
            Visible = false,
            ZIndex = WORLD_LAYER.playerDetail,
        }, { pointerEvents = false }),
        healthValue = self:_text({
            Center = false,
            Color = COLORS.accent,
            Outline = true,
            Size = 14,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.playerDetail,
        }),
        weapon = self:_text({
            Center = true,
            Color = COLORS.secondary,
            Outline = true,
            Size = 12,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.player,
        }),
    }
    self.playerNodes[player] = nodes
    return nodes
end

function Overlay:_syncBodyPartNodes(nodes, count)
    while #nodes.bodyParts < count do
        local cube = {
            faces = {},
        }
        if not self.immediateChams and self.optionSupport.chams ~= false then
            for _faceIndex = 1, #BODY_CUBE_FACES do
                table.insert(
                    cube.faces,
                    self.surface:create("Quad", {
                        Color = COLORS.danger,
                        Filled = true,
                        Transparency = BODY_CUBE_OPACITY,
                        Visible = false,
                        ZIndex = WORLD_LAYER.chams,
                    }, { pointerEvents = false })
                )
            end
        end
        table.insert(nodes.bodyParts, cube)
    end

    for index = count + 1, #nodes.bodyParts do
        setVisible(nodes.bodyParts[index], false)
    end
end

function Overlay:_getUtilityNodes(index)
    local nodes = self.utilityNodes[index]
    if nodes then
        return nodes
    end

    nodes = {
        marker = self.surface:create("Square", {
            Color = COLORS.accent,
            Filled = false,
            Size = Vector2.new(8, 8),
            Thickness = 1.5,
            Visible = false,
            ZIndex = WORLD_LAYER.utility,
        }, { pointerEvents = false }),
        label = self:_text({
            Center = true,
            Color = COLORS.text,
            Outline = true,
            Size = 12,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.utilityText,
        }),
    }
    if not self.immediateUtilityZones and self.primitiveSupport.Quad then
        nodes.zones = {}
    end
    self.utilityNodes[index] = nodes
    return nodes
end

function Overlay:_syncUtilityZones(nodes, count)
    if not nodes.zones then
        return
    end
    while #nodes.zones < count do
        table.insert(nodes.zones, self.surface:create("Quad", {
            Color = COLORS.danger,
            Filled = true,
            Transparency = 0.14,
            Visible = false,
            ZIndex = WORLD_LAYER.utilityZone,
        }, { pointerEvents = false }))
    end
    for index = count + 1, #nodes.zones do
        nodes.zones[index].Visible = false
    end
end

function Overlay:_syncUtilityWireframe(nodes, count)
    if not self.primitiveSupport.Line then
        return
    end
    nodes.wireframe = nodes.wireframe or {}
    while #nodes.wireframe < count do
        table.insert(nodes.wireframe, self.surface:create("Line", {
            Color = COLORS.danger,
            Thickness = 2,
            Visible = false,
            ZIndex = WORLD_LAYER.utility,
        }, { pointerEvents = false }))
    end
    for index = count + 1, #nodes.wireframe do
        nodes.wireframe[index].Visible = false
    end
end

function Overlay:_paintChams(renderer)
    local paint = self.chamPaint
    if not paint.enabled then
        return
    end

    for _, observation in ipairs(paint.observations) do
        if observation.bounds then
            for _, bodyPart in ipairs(observation.bodyParts or {}) do
                local corners = bodyPart.corners
                if type(corners) == "table" and #corners == 8 then
                    local color = bodyPart.visible == true and COLORS.accent or COLORS.danger
                    for _, cornerIndices in ipairs(BODY_CUBE_FACES) do
                        local pointA = corners[cornerIndices[1]]
                        local pointB = corners[cornerIndices[2]]
                        local pointC = corners[cornerIndices[3]]
                        local pointD = corners[cornerIndices[4]]
                        renderer.FilledQuad(pointA, pointB, pointC, pointD, color, BODY_CUBE_OPACITY)
                    end
                end
            end
        end
    end
end

function Overlay:_paintUtilityZones(renderer)
    local paint = self.utilityZonePaint
    if not paint.enabled then
        return
    end

    for _, observation in ipairs(paint.observations) do
        local tone = observation.tone
        local color = tone == "danger" and COLORS.danger
            or (tone == "smoke" and COLORS.secondary or COLORS.accent)
        local opacity = tone == "smoke" and 0.08 or 0.14
        for _, polygon in ipairs(observation.polygons or {}) do
            if type(polygon) == "table" and #polygon == 4 then
                renderer.FilledTriangle(polygon[1], polygon[2], polygon[3], color, opacity)
                renderer.FilledTriangle(polygon[1], polygon[3], polygon[4], color, opacity)
            end
        end
    end
end

function Overlay:_renderUtilities(observations, enabled)
    observations = observations or {}
    self.utilityZonePaint.enabled = enabled == true
    self.utilityZonePaint.observations = observations
    for index, observation in ipairs(observations) do
        local nodes = self:_getUtilityNodes(index)
        local tone = observation.tone
        local color = tone == "danger" and COLORS.danger
            or (tone == "smoke" and COLORS.secondary or COLORS.accent)
        local corners = observation.wireframeCorners
        local wireframeVisible = enabled
            and self.primitiveSupport.Line
            and observation.markerStyle == "wireframeCube"
            and observation.onScreen == true
            and type(corners) == "table"
            and #corners == 8
        local markerVisible = enabled
            and not wireframeVisible
            and observation.onScreen == true
            and observation.screenPosition ~= nil
        local labelPosition
        if markerVisible then
            nodes.marker.Position = observation.screenPosition - Vector2.new(4, 4)
            labelPosition = observation.screenPosition + Vector2.new(0, 8)
        elseif wireframeVisible then
            labelPosition = observation.labelPosition
                or (observation.screenPosition - Vector2.new(0, 16))
        end
        if wireframeVisible then
            self:_syncUtilityWireframe(nodes, #UTILITY_CUBE_EDGES)
            for edgeIndex, cornerIndices in ipairs(UTILITY_CUBE_EDGES) do
                local edge = nodes.wireframe[edgeIndex]
                edge.From = corners[cornerIndices[1]]
                edge.To = corners[cornerIndices[2]]
                edge.Color = color
                edge.Visible = true
            end
        elseif nodes.wireframe then
            for _, edge in ipairs(nodes.wireframe) do
                edge.Visible = false
            end
        end
        nodes.marker.Color = color
        nodes.marker.Visible = markerVisible
        nodes.label.Color = wireframeVisible and COLORS.text or color
        nodes.label.Size = wireframeVisible and 14 or 12
        nodes.label.Text = observation.label or ""
        if wireframeVisible and labelPosition then
            local camera = self.context.getCamera()
            labelPosition = clampCenteredUtilityLabel(
                labelPosition,
                camera and camera.ViewportSize,
                nodes.label.TextBounds
            )
        end
        if labelPosition then
            nodes.label.Position = labelPosition
        end
        nodes.label.Visible = markerVisible or wireframeVisible

        local polygons = enabled and observation.polygons or {}
        if not self.immediateUtilityZones and nodes.zones then
            self:_syncUtilityZones(nodes, #polygons)
            for polygonIndex, polygon in ipairs(polygons) do
                local zone = nodes.zones[polygonIndex]
                local visible = type(polygon) == "table" and #polygon == 4
                if visible then
                    zone.PointA = polygon[1]
                    zone.PointB = polygon[2]
                    zone.PointC = polygon[3]
                    zone.PointD = polygon[4]
                end
                zone.Color = color
                zone.Transparency = tone == "smoke" and 0.08 or 0.14
                zone.Visible = visible
            end
        end
    end

    for index = #observations + 1, #self.utilityNodes do
        setVisible(self.utilityNodes[index], false)
    end
end

function Overlay:render(observations, mousePosition, utilityObservations)
    if self.destroyed or not self.available then
        return
    end

    observations = observations or {}
    self.observations = observations
    local state = self.context.store:Get()
    local settings = state.settings
    self.chamPaint.enabled = self.immediateChams
        and settings.chams == true
        and self.optionSupport.chams ~= false
    self.chamPaint.observations = observations
    self:_renderBomb(state.bombObservation, settings)
    self.controls.fovCircle.Position = mousePosition
    local seen = {}

    for _, observation in ipairs(observations) do
        if observation.bounds then
            local nodes = self:_getPlayerNodes(observation.player)
            local bounds = observation.bounds
            local visible = observation.visible == true
            local color = visible and COLORS.accent or COLORS.danger
            local bodyParts = observation.bodyParts or {}
            seen[observation.player] = true

            self:_syncBodyPartNodes(nodes, #bodyParts)
            for index, bodyPart in ipairs(bodyParts) do
                local cube = nodes.bodyParts[index]
                local corners = bodyPart.corners
                local cubeVisible = settings.chams == true
                    and self.optionSupport.chams ~= false
                    and type(corners) == "table"
                    and #corners == 8
                local cubeColor = bodyPart.visible == true and COLORS.accent or COLORS.danger

                if not self.immediateChams then
                    for faceIndex, cornerIndices in ipairs(BODY_CUBE_FACES) do
                        local face = cube.faces[faceIndex]
                        if face and cubeVisible then
                            face.PointA = corners[cornerIndices[1]]
                            face.PointB = corners[cornerIndices[2]]
                            face.PointC = corners[cornerIndices[3]]
                            face.PointD = corners[cornerIndices[4]]
                        end
                        if face then
                            face.Color = cubeColor
                            face.Visible = cubeVisible
                        end
                    end
                end
            end

            nodes.box.Position = bounds.position
            nodes.box.Size = bounds.size
            nodes.box.Color = color
            nodes.box.Visible = settings.boxes == true

            nodes.name.Position = Vector2.new(bounds.position.X + bounds.size.X * 0.5, bounds.position.Y - 15)
            nodes.name.Color = color
            nodes.name.Text = observation.player.Name
            nodes.name.Visible = settings.names == true

            local maximumHealth = math.max(observation.maxHealth or 100, 1)
            local healthFraction = math.clamp((observation.health or 0) / maximumHealth, 0, 1)
            local innerHeight = math.max(bounds.size.Y - 2, 0)
            local fillHeight = innerHeight * healthFraction
            nodes.healthTrack.Position = Vector2.new(bounds.position.X - 10, bounds.position.Y)
            nodes.healthTrack.Size = Vector2.new(6, bounds.size.Y)
            nodes.healthTrack.Visible = settings.health == true
            nodes.healthFill.Position =
                Vector2.new(bounds.position.X - 9, bounds.position.Y + 1 + innerHeight - fillHeight)
            nodes.healthFill.Size = Vector2.new(4, fillHeight)
            nodes.healthFill.Color = COLORS.danger:Lerp(COLORS.accent, math.sqrt(healthFraction))
            nodes.healthFill.Visible = settings.health == true and fillHeight > 0
            nodes.healthTip.Position = Vector2.new(bounds.position.X - 10, nodes.healthFill.Position.Y - 1)
            nodes.healthTip.Size = Vector2.new(6, 2)
            nodes.healthTip.Visible = settings.health == true and fillHeight > 0
            nodes.healthValue.Position = Vector2.new(
                bounds.position.X,
                bounds.position.Y + bounds.size.Y + 3
            )
            nodes.healthValue.Color = nodes.healthFill.Color
            nodes.healthValue.Text = ("%d HP"):format(math.ceil(observation.health or 0))
            nodes.healthValue.Visible = settings.health == true and fillHeight > 0

            nodes.weapon.Position = Vector2.new(
                bounds.position.X + bounds.size.X * 0.5,
                bounds.position.Y + bounds.size.Y + 18
            )
            nodes.weapon.Text = observation.weapon or ""
            nodes.weapon.Visible = settings.weapon == true and observation.weapon ~= nil
        end
    end

    for player, nodes in pairs(self.playerNodes) do
        if not seen[player] then
            setVisible(nodes, false)
        end
    end
    self:_renderUtilities(utilityObservations, settings.utilityEsp == true)
end

function Overlay:isCaptured()
    return self.captured
end

function Overlay:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true

    if self.context.setInputCaptured then
        self.context.setInputCaptured(false)
    end
    if self.unsubscribe then
        self.unsubscribe()
    end
    if self.worldGui then
        self.worldGui.billboard:Destroy()
        self.worldGui = nil
    end
    if self.chamPaintConnection then
        self.chamPaintConnection:Disconnect()
        self.chamPaintConnection = nil
    end
    if self.utilityPaintConnection then
        self.utilityPaintConnection:Disconnect()
        self.utilityPaintConnection = nil
    end
    self:_clearPlotDropdown()
    for _, connection in ipairs(self.nativeConnections or {}) do
        connection:Disconnect()
    end
    table.clear(self.nativeConnections or {})
    local plotCopy = self.controls.plotCopy
    if plotCopy and plotCopy.inputLayer then
        plotCopy.inputLayer:Destroy()
        plotCopy.inputLayer = nil
        plotCopy.saveInput = nil
    end
    if self.surface then
        self.surface:destroy()
        self.surface = nil
        self.canvas = nil
    end
    table.clear(self.playerNodes)
    table.clear(self.utilityNodes)
end

return Overlay
