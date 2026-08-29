local StandardPanels = {}
StandardPanels.__index = StandardPanels

local LAYOUT = {
    cardContentInset = 12,
    cardInset = 20,
    columnGap = 8,
    contentWidth = 350,
    fovAmountTop = 12,
    fovCardHeight = 58,
    fovCardTop = 24,
    fovCircleInitialRadius = 180,
    fovLabelTop = 0,
    fovRangeLabelTop = 34,
    fovSliderHitTop = 22,
    fovSliderTrackTop = 36,
    fovTrackInset = 58,
    fovTrackWidth = 227,
    groupGap = 22,
    groupHeaderHeight = 32,
    innerControlWidth = 350,
    navigationIndicatorHalfWidth = 30,
    navigationIndicatorHeight = 1,
    navigationIndicatorWidth = 60,
    navigationEdgeInset = 29,
    optionLabelInset = 4,
    optionLabelTop = 13,
    optionMarkerLabelInset = 18,
    optionMarkerHeight = 12,
    optionMarkerLeft = 6,
    optionMarkerTop = 10,
    optionMarkerWidth = 2,
    optionSeparatorInset = 0,
    optionSwitchRightInset = 28,
    optionSwitchTop = 19,
    optionValueRightInset = 48,
    optionValueTop = 13,
    keycapHeight = 32,
    keycapWidth = 86,
    rateRowHeight = 39,
    rateLabelInset = 16,
    rateLabelTop = 13,
    rateSeparatorInset = 0,
    rateSliderHitTop = 5,
    rateSliderLeft = 122,
    rateSliderTrackTop = 17,
    rateTrackWidth = 171,
    rateValueRightInset = 20,
    responseHeaderHeight = 35,
    rowGap = 0,
    rowHeight = 38,
    settingsCardHeight = 76,
    settingsEyebrowTop = 14,
    settingsKeycapTop = 22,
    settingsLabelTop = 38,
    settingsValueTop = 31,
    sectionDividerGap = 16,
    sectionLabelTop = 6,
    sliderHitHeight = 28,
    tabBarHeight = 44,
    tabLabelTop = 14,
    tabsTop = 84,
    targetModeHeight = 34,
    targetModeLabelTop = 10,
    targetModeTitleGap = 30,
    targetModeTitleHeight = 28,
}

local LAYER = {
    activeControl = 206,
    activeLabel = 207,
    background = 201,
    control = 202,
    detail = 204,
    foreground = 203,
    knob = 205,
    worldFov = 50,
}
local CARD_INSET = LAYOUT.cardInset
local CARD_CONTENT_INSET = LAYOUT.cardContentInset
local CONTENT_WIDTH = LAYOUT.contentWidth
local FOV_TRACK_WIDTH = LAYOUT.fovTrackWidth
local FOV_CARD_HEIGHT = LAYOUT.fovCardHeight
local GROUP_GAP = LAYOUT.groupGap
local GROUP_HEADER_HEIGHT = LAYOUT.groupHeaderHeight
local INNER_CONTROL_WIDTH = LAYOUT.innerControlWidth
local KEYCAP_WIDTH = LAYOUT.keycapWidth
local RATE_TRACK_WIDTH = LAYOUT.rateTrackWidth
local RATE_ROW_HEIGHT = LAYOUT.rateRowHeight
local ROW_GAP = LAYOUT.rowGap
local ROW_HEIGHT = LAYOUT.rowHeight
local SETTINGS_CARD_HEIGHT = LAYOUT.settingsCardHeight
local SLIDER_HIT_HEIGHT = LAYOUT.sliderHitHeight
local TAB_BAR_HEIGHT = LAYOUT.tabBarHeight
local PAGE_ORDER = { "Combat", "Rage", "Movement", "Visuals", "Tools", "Settings" }
local SINGLE_PIXEL = 1

local function segmentLayout(index, count, position, size)
    return {
        LabelPosition = Vector2.new(
            position.X + size.X * ((index - 0.5) / count),
            position.Y + LAYOUT.tabLabelTop
        ),
    }
end

local function navigationLayout(index, count, position, size)
    if count <= 2 then
        return segmentLayout(index, count, position, size)
    end
    return {
        LabelPosition = Vector2.new(
            position.X
                + LAYOUT.navigationEdgeInset
                + (size.X - LAYOUT.navigationEdgeInset * 2) * ((index - 1) / (count - 1)),
            position.Y + LAYOUT.tabLabelTop
        ),
    }
end

local function controlStyle(colors)
    local tokens = assert(colors.tokens, "Presentation theme requires shared tokens")
    return {
        Disabled = {},
        Focused = { Color = colors.hover, Transparency = tokens.opacity.focus },
        Frame = { Color = colors.border, Filled = false, Thickness = tokens.control.borderThickness, Transparency = tokens.opacity.edge, Visible = true },
        Hovered = { Color = colors.hover },
        Label = {
            Center = true,
            Color = colors.text,
            Font = tokens.font.control,
            Size = tokens.type.label,
            Visible = true,
        },
        Listening = { Color = colors.accentSurface },
        Option = { Color = colors.panel, Filled = true, Transparency = 1, Visible = true },
        Selected = {
            Color = colors.accent,
            Filled = false,
            Thickness = tokens.control.borderThickness,
            Transparency = tokens.opacity.edge,
        },
        SelectedLabel = {
            Color = colors.accent,
        },
        Value = {
            Center = true,
            Color = colors.accent,
            Font = tokens.font.control,
            Size = tokens.type.label,
            Visible = true,
        },
    }
end

local function navigationStyle(colors)
    local style = controlStyle(colors)
    style.Focused = { Color = colors.panel, Transparency = 1 }
    style.Frame = { Color = colors.panel, Filled = true, Transparency = 1, Visible = true }
    style.Hovered = { Color = colors.panel }
    style.Option = { Color = colors.panel, Filled = true, Transparency = 1, Visible = true }
    style.Selected = { Color = colors.panel }
    style.Label.Color = colors.secondary
    style.Label.Size = colors.tokens.type.primary
    return style
end

local function keybindStyle(colors)
    local tokens = colors.tokens
    local style = controlStyle(colors)
    style.Frame = {
        Color = colors.border,
        Filled = false,
        Thickness = tokens.control.borderThickness,
        Transparency = tokens.opacity.edge,
        Visible = true,
    }
    style.Listening = { Color = colors.accent }
    style.Value = {
        Center = true,
        Color = colors.secondary,
        Size = tokens.type.row,
        Visible = true,
    }
    return style
end

local function setVisible(nodes, visible)
    for _, node in pairs(nodes or {}) do
        if type(node) == "table" and (type(node.set) == "function" or node.Visible ~= nil) then
            node.Visible = visible
        elseif type(node) == "table" then
            setVisible(node, visible)
        end
    end
end

local function registerActiveSliderPaint(hit, layer, draw)
    local connected, connection = pcall(function()
        return hit:paintCaptured(layer, function(painter, event)
            draw(painter, event.position)
        end)
    end)
    return connected and connection ~= nil
end

local function setRetainedSliderVisible(state, fill, knob, visible)
    fill.Visible = visible
    knob.Visible = visible
    if visible then
        state.activeSliderVisuals[fill] = nil
        state.activeSliderVisuals[knob] = nil
        state.bridge.refreshVisibility()
    else
        state.activeSliderVisuals[fill] = true
        state.activeSliderVisuals[knob] = true
    end
end

local function paintActiveSlider(painter, track, fillWidth, knobX, knobRadius, trackHeight, fillColor, knobColor)
    painter.FilledRectangle(
        track.Position,
        Vector2.new(math.max(0, fillWidth), trackHeight),
        fillColor,
        1,
        0
    )
    painter.FilledCircle(
        Vector2.new(knobX, track.Position.Y + track.Size.Y * 0.5),
        knobRadius,
        knobColor,
        1,
        32
    )
end

local function slider(state, options)
    return {
        hit = state.bridge.node("Square", options.hit, true),
        track = state.bridge.node("Square", options.track, false),
        fill = state.bridge.node("Square", options.fill, false),
        knob = state.bridge.node("Circle", options.knob, false),
    }
end

local function card(state, options)
    return {
        background = state.bridge.node("Square", options.background, false),
        border = state.bridge.node("Square", options.border, false),
    }
end

function StandardPanels.new(bridge, available)
    local aimControlsSupported = available.silentAim == true
        or available.shotAim == true
        or available.triggerBot == true
        or available.aimSmoothness == true
        or available.aimAssistStrength == true
        or available.headshotRate == true
        or available.missRate == true
    return setmetatable({
        activeSliderVisuals = bridge.activeSliderVisuals,
        aimControlsSupported = aimControlsSupported,
        available = available,
        bridge = bridge,
        controls = bridge.controls,
        ephemeralSettings = {},
        groups = {},
        groupById = {},
        pages = {},
        activePageName = nil,
        optionSupport = bridge.optionSupport or {},
        parents = {},
        rates = {},
        theme = bridge.theme,
    }, StandardPanels)
end

function StandardPanels:_page(name)
    local page = self.pages[name]
    if not page then
        page = { hasContent = false, name = name }
        self.pages[name] = page
    end
    return page
end

function StandardPanels:_markPage(name)
    self:_page(name).hasContent = true
end

function StandardPanels:includePage(name)
    self:_markPage(name)
end

function StandardPanels:activePage()
    return self.activePageName
end

function StandardPanels:finalize()
    if self.finalized then
        return
    end
    self.finalized = true
    local hasContent = false
    for _, page in pairs(self.pages) do
        if page.hasContent then
            hasContent = true
            break
        end
    end
    if not hasContent then
        return
    end
    self:_markPage("Settings")
    local options = {}
    for _, name in ipairs(PAGE_ORDER) do
        if self:_page(name).hasContent then
            table.insert(options, { Label = name, Value = name })
        end
    end
    self.pageOptions = options
    self.pageIndexByName = {}
    for index, option in ipairs(options) do
        self.pageIndexByName[option.Value] = index
    end
    self.activePageName = options[1].Value
    self.controls.navigation = self.controls.navigation or {}
    local tokens = self.theme.tokens
    self.controls.navigation.tabs = self.bridge.createSegmentedControl({
        CornerRadius = tokens.control.segmentCornerRadius,
        Layout = navigationLayout,
        Options = options,
        Position = Vector2.zero,
        Size = Vector2.new(CONTENT_WIDTH, TAB_BAR_HEIGHT),
        Style = navigationStyle(self.theme),
        Value = self.activePageName,
        ZIndex = LAYER.foreground,
    })
    self.controls.navigation.indicator = self.bridge.node("Square", {
        Color = self.theme.accent,
        Filled = true,
        Size = Vector2.zero,
        Visible = true,
        ZIndex = LAYER.activeControl,
    }, false)
    self.controls.navigation.rule = self.bridge.node("Square", {
        Color = self.theme.border,
        Filled = true,
        Size = Vector2.new(CONTENT_WIDTH, SINGLE_PIXEL),
        Transparency = tokens.opacity.divider,
        Visible = true,
        ZIndex = LAYER.control,
    }, false)
    self.controls.navigation.tabs.Changed:Connect(function(value, _previous, source)
        if source == "programmatic" or self.activePageName == value then
            return
        end
        self.activePageName = value
        self.bridge.refreshVisibility()
        if type(self.bridge.requestRender) == "function" then
            self.bridge.requestRender()
        else
            self.bridge.requestLayout()
        end
    end)
    self.controls.navigation.menuKey = self.bridge.createKeybindControl({
        Disabled = true,
        Position = Vector2.zero,
        Size = Vector2.new(KEYCAP_WIDTH, LAYOUT.keycapHeight),
        Style = keybindStyle(self.theme),
        Value = "RightShift",
        ZIndex = LAYER.foreground,
    })
    self.controls.settings = {
        background = self.bridge.node("Square", {
            Color = self.theme.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, SETTINGS_CARD_HEIGHT),
            Visible = true,
            ZIndex = LAYER.background,
        }, false),
        border = self.bridge.node("Square", {
            Color = self.theme.border,
            Filled = false,
            Size = Vector2.new(CONTENT_WIDTH, SETTINGS_CARD_HEIGHT),
            Thickness = tokens.control.borderThickness,
            Transparency = tokens.opacity.edge,
            Visible = true,
            ZIndex = LAYER.control,
        }, false),
        eyebrow = self.bridge.text({
            Color = self.theme.text,
            Font = tokens.font.heading,
            Size = tokens.type.section,
            Text = "Menu",
            ZIndex = LAYER.foreground,
        }),
        label = self.bridge.text({
            Color = self.theme.secondary,
            Size = tokens.type.row,
            Text = "Fixed keyboard shortcut",
            ZIndex = LAYER.foreground,
        }),
    }
end

function StandardPanels:aim()
    if self.aimBuilt or not self.aimControlsSupported then
        return
    end
    self.aimBuilt = true
    self:_markPage("Combat")
    local state = self
    local controls = state.controls
    local colors = state.theme
    local tokens = colors.tokens

    local fovCard = card(state, {
        background = {
            Color = colors.elevated, Filled = true, Size = Vector2.new(CONTENT_WIDTH, FOV_CARD_HEIGHT), Visible = true, ZIndex = LAYER.background,
        },
        border = {
            Color = colors.border, Filled = false, Size = Vector2.new(CONTENT_WIDTH, FOV_CARD_HEIGHT), Thickness = tokens.control.borderThickness, Transparency = tokens.opacity.edge, Visible = true, ZIndex = LAYER.control,
        },
    })
    controls.fovCard = fovCard.background
    controls.fovCardBorder = fovCard.border
    controls.fovTopHighlight = state.bridge.node("Square", {
        Color = colors.border,
        Filled = true,
        Size = Vector2.zero,
        Transparency = tokens.opacity.edge,
        Visible = false,
        ZIndex = LAYER.foreground,
    }, false)
    controls.targetingLabel = state.bridge.text({
        Color = colors.tertiary,
        Size = tokens.type.eyebrow,
        Text = "",
        Visible = false,
        ZIndex = LAYER.foreground,
    })
    controls.fovLabel = state.bridge.text({
        Color = colors.text,
        Font = tokens.font.heading,
        Size = tokens.type.section,
        Text = "FOV",
        ZIndex = LAYER.control,
    })
    controls.fovValue = state.bridge.text({
        Center = true,
        Color = colors.secondary,
        Size = tokens.type.primary,
        Text = "",
        ZIndex = LAYER.control,
    })
    controls.fovAmount = state.bridge.text({
        Center = true,
        Color = colors.accent,
        Size = tokens.type.display,
        Text = "500 px",
        ZIndex = LAYER.foreground,
    })
    controls.targetModeLabel = state.bridge.text({
        Color = colors.text,
        Font = tokens.font.heading,
        Size = tokens.type.section,
        Text = "Target Mode",
        ZIndex = LAYER.foreground,
    })
    controls.fovMinimum = state.bridge.text({
        Color = colors.tertiary or colors.secondary,
        Size = tokens.type.meta,
        Text = "",
        ZIndex = LAYER.foreground,
    })
    controls.fovMaximum = state.bridge.text({
        Center = true,
        Color = colors.tertiary or colors.secondary,
        Size = tokens.type.meta,
        Text = "",
        ZIndex = LAYER.foreground,
    })
    controls.targetMode = state.bridge.createSegmentedControl({
        CornerRadius = tokens.control.segmentCornerRadius,
        Layout = segmentLayout,
        Options = {
            { Label = "Radius", Value = "radius" },
            { Label = "Fullscreen", Value = "fullscreen" },
        },
        Position = Vector2.zero,
        Size = Vector2.new(INNER_CONTROL_WIDTH, LAYOUT.targetModeHeight),
        Style = controlStyle(colors),
        Value = "radius",
        ZIndex = LAYER.foreground,
    })
    controls.targetMode.Changed:Connect(function(value, _previous, source)
        if source ~= "programmatic" then
            state.bridge.context.setOption("fullScreenAim", value == "fullscreen")
        end
    end)
    local fovSlider = slider(state, {
        hit = { Color = colors.panel, Filled = true, Size = Vector2.new(FOV_TRACK_WIDTH, SLIDER_HIT_HEIGHT), Transparency = tokens.opacity.hitbox, Visible = true, ZIndex = LAYER.control },
        track = { Color = colors.track, Filled = true, Size = Vector2.new(FOV_TRACK_WIDTH, tokens.control.sliderTrackHeight), Visible = true, ZIndex = LAYER.foreground },
        fill = { Color = colors.accent, Filled = true, Visible = true, ZIndex = LAYER.detail },
        knob = { Color = colors.accent, Filled = true, NumSides = tokens.control.sliderCircleSides, Radius = tokens.control.fovThumbRadius, Visible = true, ZIndex = LAYER.knob },
    })
    controls.sliderHit = fovSlider.hit
    controls.sliderTrack = fovSlider.track
    controls.sliderFill = fovSlider.fill
    controls.sliderKnob = fovSlider.knob
    controls.fovCircle = state.bridge.node("Circle", {
        Color = colors.accent,
        Filled = false,
        NumSides = tokens.control.fovCircleSides,
        Radius = LAYOUT.fovCircleInitialRadius,
        Thickness = tokens.control.fovCircleThickness,
        Transparency = tokens.opacity.fovCircle,
        Visible = true,
        ZIndex = LAYER.worldFov,
    }, false)

    local function setFov(point, persist)
        local current = state.bridge.context.store:Get()
        if current.settings.fullScreenAim then
            return
        end
        local alpha = math.clamp((point.X - state.sliderStartX) / FOV_TRACK_WIDTH, 0, 1)
        local settings = current.settings
        state.bridge.context.setFov(
            settings.minimumFov + (settings.maximumFov - settings.minimumFov) * alpha,
            persist
        )
    end
    local function fovSliderEnabled()
        return state.bridge.context.store:Get().settings.fullScreenAim ~= true
    end
    local fovActivePaint = registerActiveSliderPaint(controls.sliderHit, LAYER.activeControl, function(painter, point)
        if not fovSliderEnabled() then
            return
        end
        local alpha = math.clamp((point.X - state.sliderStartX) / FOV_TRACK_WIDTH, 0, 1)
        local knobX = state.sliderStartX + FOV_TRACK_WIDTH * alpha
        paintActiveSlider(
            painter,
            controls.sliderTrack,
            FOV_TRACK_WIDTH * alpha,
            knobX,
            tokens.control.fovThumbRadius,
            tokens.control.sliderTrackHeight,
            colors.accent,
            colors.accent
        )
    end)
    controls.sliderHit:on("pointerdown", function(_node, point)
        setFov(point, false)
        if fovActivePaint and fovSliderEnabled() then
            setRetainedSliderVisible(state, controls.sliderFill, controls.sliderKnob, false)
        end
    end)
    controls.sliderHit:on("drag", function(_node, point)
        setFov(point, false)
        if fovActivePaint and fovSliderEnabled() then
            setRetainedSliderVisible(state, controls.sliderFill, controls.sliderKnob, false)
        end
    end)
    controls.sliderHit:on("pointerup", function(_node, point)
        setFov(point, true)
        if fovActivePaint then
            setRetainedSliderVisible(state, controls.sliderFill, controls.sliderKnob, true)
        end
    end)
end

function StandardPanels:slider(_sectionId, _id, _label, _spec)
end

function StandardPanels:rate(id, label)
    if not self.available[id] or self.controls.rates[id] then
        return
    end
    local state = self
    state:_markPage("Combat")
    local colors = state.theme
    local tokens = colors.tokens
    local thumbRadius = tokens.control.rateThumbRadius
    local control = {
        slider = slider(state, {
            hit = { Color = colors.panel, Filled = true, Size = Vector2.new(RATE_TRACK_WIDTH, SLIDER_HIT_HEIGHT), Transparency = tokens.opacity.hitbox, Visible = true, ZIndex = LAYER.control },
            track = { Color = colors.track, Filled = true, Size = Vector2.new(RATE_TRACK_WIDTH, tokens.control.sliderTrackHeight), Visible = true, ZIndex = LAYER.foreground },
            fill = { Color = colors.accent, Filled = true, Visible = true, ZIndex = LAYER.detail },
            knob = { Color = colors.accent, Filled = true, NumSides = tokens.control.sliderCircleSides, Radius = thumbRadius, Visible = true, ZIndex = LAYER.knob },
        }),
        label = state.bridge.text({
            Color = colors.text,
            Size = tokens.type.row,
            Text = label,
            ZIndex = LAYER.foreground,
        }),
        value = state.bridge.text({
            Center = true,
            Color = colors.accent,
            Size = tokens.type.rateValue,
            Text = "0%",
            ZIndex = LAYER.foreground,
        }),
        separator = state.bridge.node("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(INNER_CONTROL_WIDTH - LAYOUT.rateSeparatorInset * 2, SINGLE_PIXEL),
            Transparency = tokens.opacity.subDivider,
            Visible = true,
            ZIndex = LAYER.control,
        }, false),
    }
    control.hit = control.slider.hit
    control.track = control.slider.track
    control.fill = control.slider.fill
    control.knob = control.slider.knob
    local activePaint = registerActiveSliderPaint(control.hit, LAYER.activeControl, function(painter, point)
        local alpha = math.clamp((point.X - control.hit.Position.X) / RATE_TRACK_WIDTH, 0, 1)
        local thumbTravel = RATE_TRACK_WIDTH - thumbRadius * 2
        local thumbX = control.track.Position.X + thumbRadius + thumbTravel * alpha
        paintActiveSlider(
            painter,
            control.track,
            thumbX - control.track.Position.X,
            thumbX,
            thumbRadius,
            tokens.control.sliderTrackHeight,
            colors.accent,
            colors.accent
        )
    end)
    local function setRate(point, persist)
        local alpha = math.clamp((point.X - control.hit.Position.X) / RATE_TRACK_WIDTH, 0, 1)
        state.bridge.context.setRate(id, math.round(alpha * 100), persist)
    end
    control.hit:on("pointerdown", function(_node, point)
        setRate(point, false)
        if activePaint then
            setRetainedSliderVisible(state, control.fill, control.knob, false)
        end
    end)
    control.hit:on("drag", function(_node, point)
        setRate(point, false)
        if activePaint then
            setRetainedSliderVisible(state, control.fill, control.knob, false)
        end
    end)
    control.hit:on("pointerup", function(_node, point)
        setRate(point, true)
        if activePaint then
            setRetainedSliderVisible(state, control.fill, control.knob, true)
        end
    end)
    state.controls.rates[id] = control
    table.insert(state.rates, id)
end

function StandardPanels:section(page, id, label, lineOffset, includesRates, columns, spec)
    assert(not self.groupById[id], "Duplicate presentation section: " .. id)
    assert(type(page) == "string" and page ~= "", "Presentation sections require a game-owned page")
    local group = {
        id = id,
        page = page,
        label = label,
        lineOffset = lineOffset or 70,
        includesRates = includesRates == true,
        columns = columns or 1,
        ephemeral = page == "Rage" or (type(spec) == "table" and spec.persist == false),
        maxRow = 0,
        rows = {},
    }
    self.groupById[id] = group
    self:_page(group.page)
    table.insert(self.groups, group)
end

local function buildSection(state, group)
    if state.controls.sections[group.id] then
        return
    end
    local tokens = state.theme.tokens
    local rateCount = #state.rates
    state.controls.sections[group.id] = {
        divider = state.bridge.node("Square", {
            Color = state.theme.border,
            Filled = true,
            Size = Vector2.new(INNER_CONTROL_WIDTH, SINGLE_PIXEL),
            Transparency = tokens.opacity.divider,
            Visible = true,
            ZIndex = LAYER.control,
        }, false),
        label = state.bridge.text({
            Color = state.theme.text,
            Font = tokens.font.heading,
            Size = tokens.type.section,
            Text = group.label,
            ZIndex = LAYER.foreground,
        }),
        responseLabel = group.includesRates and state.bridge.text({
            Color = state.theme.text,
            Font = tokens.font.heading,
            Size = tokens.type.section,
            Text = "Response",
            ZIndex = LAYER.foreground,
        }) or nil,
        responseBackground = group.includesRates and state.bridge.node("Square", {
            Color = state.theme.elevated,
            Filled = true,
            Size = Vector2.new(INNER_CONTROL_WIDTH, math.max(1, rateCount) * RATE_ROW_HEIGHT),
            Visible = true,
            ZIndex = LAYER.background,
        }, false) or nil,
        responseBorder = group.includesRates and state.bridge.node("Square", {
            Color = state.theme.border,
            Filled = false,
            Size = Vector2.new(INNER_CONTROL_WIDTH, math.max(1, rateCount) * RATE_ROW_HEIGHT),
            Thickness = tokens.control.borderThickness,
            Transparency = tokens.opacity.edge,
            Visible = true,
            ZIndex = LAYER.control,
        }, false) or nil,
    }
end

function StandardPanels:option(sectionId, rowIndex, id, label, parent)
    if not self.available[id] then
        return
    end
    local state = self
    local group = assert(state.groupById[sectionId], "Unknown presentation section: " .. sectionId)
    local optionSpec = type(parent) == "table" and parent or nil
    local ephemeral = group.ephemeral or (optionSpec and optionSpec.persist == false)
    if ephemeral then
        state.ephemeralSettings[id] = true
    end
    buildSection(state, group)
    group.rows[rowIndex] = group.rows[rowIndex] or {}
    table.insert(group.rows[rowIndex], id)
    group.maxRow = math.max(group.maxRow, rowIndex)
    state.parents[id] = parent
    state:_markPage(group.page)

    local colors = state.theme
    local tokens = colors.tokens
    local controlTokens = tokens.control
    local row = state.bridge.interactive(state.bridge.node("Square", {
        Color = colors.panel,
        Filled = true,
        Size = Vector2.new(INNER_CONTROL_WIDTH, ROW_HEIGHT),
        Visible = true,
        ZIndex = LAYER.control,
    }, true))
    local labelNode = state.bridge.text({
        Color = colors.text,
        Size = tokens.type.row,
        Text = label,
        ZIndex = LAYER.foreground,
    })
    local value = state.bridge.text({
        Center = true,
        Color = colors.secondary,
        Size = tokens.type.meta,
        Text = "Off",
        ZIndex = LAYER.foreground,
    })
    local separator = state.bridge.node("Square", {
        Color = colors.border,
        Filled = true,
        Size = Vector2.new(INNER_CONTROL_WIDTH - LAYOUT.optionSeparatorInset * 2, SINGLE_PIXEL),
        Transparency = tokens.opacity.subDivider,
        Visible = true,
        ZIndex = LAYER.control,
    }, false)
    local function switchNode(kind, properties)
        return state.bridge.node(kind, properties, false)
    end
    local switchShadowTrack = switchNode("Square", {
        Color = colors.panelShadow, Filled = true, Size = Vector2.new(controlTokens.switchTrackWidth, controlTokens.switchOuterTrackHeight), Visible = true, ZIndex = LAYER.foreground,
    })
    local switchShadowLeft = switchNode("Circle", {
        Color = colors.panelShadow, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchOuterRadius, Visible = true, ZIndex = LAYER.foreground,
    })
    local switchShadowRight = switchNode("Circle", {
        Color = colors.panelShadow, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchOuterRadius, Visible = true, ZIndex = LAYER.foreground,
    })
    local switchTrack = switchNode("Square", {
        Color = colors.border, Filled = true, Size = Vector2.new(controlTokens.switchTrackWidth, controlTokens.switchOuterTrackHeight), Visible = true, ZIndex = LAYER.detail,
    })
    local switchLeft = switchNode("Circle", {
        Color = colors.border, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchOuterRadius, Visible = true, ZIndex = LAYER.detail,
    })
    local switchRight = switchNode("Circle", {
        Color = colors.border, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchOuterRadius, Visible = true, ZIndex = LAYER.detail,
    })
    local switchFillTrack = switchNode("Square", {
        Color = colors.elevated, Filled = true, Size = Vector2.new(controlTokens.switchTrackWidth, controlTokens.switchInnerTrackHeight), Visible = true, ZIndex = LAYER.knob,
    })
    local switchFillLeft = switchNode("Circle", {
        Color = colors.elevated, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchInnerRadius, Visible = true, ZIndex = LAYER.knob,
    })
    local switchFillRight = switchNode("Circle", {
        Color = colors.elevated, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchInnerRadius, Visible = true, ZIndex = LAYER.knob,
    })
    local switchKnobRim = switchNode("Circle", {
        Color = colors.border, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchKnobRimRadius, Visible = true, ZIndex = LAYER.activeControl,
    })
    local switchKnob = switchNode("Circle", {
        Color = colors.text, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchKnobRadius, Visible = true, ZIndex = LAYER.activeLabel,
    })
    local marker
    if parent then
        marker = switchNode("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(LAYOUT.optionMarkerWidth, LAYOUT.optionMarkerHeight),
            Visible = true,
            ZIndex = LAYER.foreground,
        })
    end
    row:on("click", function()
        if state.optionSupport[id] == false then
            return
        end
        local current = state.bridge.context.store:Get()
        state.bridge.context.setOption(id, not current.settings[id], not ephemeral)
    end)
    state.controls.options[id] = {
        row = row,
        separator = separator,
        sectionId = sectionId,
        label = labelNode,
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

function StandardPanels:layout(x, y, cursor)
    local controls = self.controls
    local controlTokens = self.theme.tokens.control
    local settings = self.bridge.context.store:Get().settings
    if controls.navigation then
        controls.navigation.tabs:setLayout({
            Layout = navigationLayout,
            Position = Vector2.new(x + CARD_INSET, y + LAYOUT.tabsTop),
            Size = Vector2.new(CONTENT_WIDTH, TAB_BAR_HEIGHT),
        })
        local activeIndex = self.pageIndexByName[self.activePageName]
        local activeTabLayout = navigationLayout(
            activeIndex,
            #self.pageOptions,
            Vector2.new(x + CARD_INSET, y + LAYOUT.tabsTop),
            Vector2.new(CONTENT_WIDTH, TAB_BAR_HEIGHT)
        )
        controls.navigation.rule.Position = Vector2.new(
            x + CARD_INSET,
            y + LAYOUT.tabsTop + TAB_BAR_HEIGHT - SINGLE_PIXEL
        )
        controls.navigation.indicator.Position = Vector2.new(
            activeTabLayout.LabelPosition.X - LAYOUT.navigationIndicatorHalfWidth,
            y + LAYOUT.tabsTop + TAB_BAR_HEIGHT - LAYOUT.navigationIndicatorHeight
        )
        controls.navigation.indicator.Size = Vector2.new(
            LAYOUT.navigationIndicatorWidth,
            LAYOUT.navigationIndicatorHeight
        )
    end
    if self.aimBuilt and self.activePageName == "Combat" then
        local fovCardX = x + CARD_INSET
        local fovCardY = cursor + LAYOUT.fovCardTop
        controls.fovLabel.Position = Vector2.new(fovCardX, cursor + LAYOUT.fovLabelTop)
        controls.fovCard.Position = Vector2.new(fovCardX, fovCardY)
        controls.fovCardBorder.Position = controls.fovCard.Position
        controls.fovTopHighlight.Position = controls.fovCard.Position
        self.sliderStartX = fovCardX + LAYOUT.fovTrackInset
        controls.sliderHit.Position = Vector2.new(self.sliderStartX, fovCardY + LAYOUT.fovSliderHitTop)
        controls.sliderTrack.Position = Vector2.new(self.sliderStartX, fovCardY + LAYOUT.fovSliderTrackTop)
        controls.sliderFill.Position = controls.sliderTrack.Position
        local fovAlpha = (settings.fov - settings.minimumFov)
            / (settings.maximumFov - settings.minimumFov)
        local fovThumbX = self.sliderStartX + FOV_TRACK_WIDTH * fovAlpha
        controls.sliderKnob.Position = Vector2.new(
            fovThumbX,
            controls.sliderTrack.Position.Y + controlTokens.sliderTrackHeight * 0.5
        )
        controls.fovAmount.Position = Vector2.new(fovThumbX, fovCardY + LAYOUT.fovAmountTop)
        controls.fovMinimum.Position = Vector2.new(fovCardX + CARD_CONTENT_INSET, fovCardY + LAYOUT.fovRangeLabelTop)
        controls.fovMaximum.Position = Vector2.new(
            fovCardX + CONTENT_WIDTH - CARD_CONTENT_INSET - 12,
            fovCardY + LAYOUT.fovRangeLabelTop
        )

        local targetModeLabelY = fovCardY + FOV_CARD_HEIGHT + LAYOUT.targetModeTitleGap
        local targetModeY = targetModeLabelY + LAYOUT.targetModeTitleHeight
        controls.targetModeLabel.Position = Vector2.new(fovCardX, targetModeLabelY)
        controls.targetMode:setLayout({
            Layout = segmentLayout,
            Position = Vector2.new(fovCardX, targetModeY),
            Size = Vector2.new(INNER_CONTROL_WIDTH, LAYOUT.targetModeHeight),
        })
        cursor = targetModeY + LAYOUT.targetModeHeight + GROUP_GAP
    end

    if self.activePageName == "Settings" and controls.navigation then
        local settings = controls.settings
        settings.background.Position = Vector2.new(x + CARD_INSET, cursor)
        settings.border.Position = settings.background.Position
        settings.eyebrow.Position = Vector2.new(x + CARD_INSET + CARD_CONTENT_INSET, cursor + LAYOUT.settingsEyebrowTop)
        settings.label.Position = Vector2.new(x + CARD_INSET + CARD_CONTENT_INSET, cursor + LAYOUT.settingsLabelTop)
        controls.navigation.menuKey:setLayout({
            Position = Vector2.new(x + CARD_INSET + CONTENT_WIDTH - CARD_CONTENT_INSET - KEYCAP_WIDTH, cursor + LAYOUT.settingsKeycapTop),
            Size = Vector2.new(KEYCAP_WIDTH, LAYOUT.keycapHeight),
            Layout = {
                ValuePosition = Vector2.new(x + CARD_INSET + CONTENT_WIDTH - CARD_CONTENT_INSET - KEYCAP_WIDTH * 0.5, cursor + LAYOUT.settingsValueTop),
            },
        })
        return cursor + SETTINGS_CARD_HEIGHT + GROUP_GAP
    end

    for _, group in ipairs(self.groups) do
        if group.page == self.activePageName then
            local section = controls.sections[group.id]
            if section then
                local innerX = x + CARD_INSET
                if group.includesRates then
                    section.responseLabel.Position = Vector2.new(
                        innerX,
                        cursor + LAYOUT.sectionLabelTop
                    )
                    cursor = cursor + LAYOUT.responseHeaderHeight
                    local responseHeight = #self.rates * RATE_ROW_HEIGHT
                    section.responseBackground.Position = Vector2.new(innerX, cursor)
                    section.responseBackground.Size = Vector2.new(INNER_CONTROL_WIDTH, responseHeight)
                    section.responseBorder.Position = section.responseBackground.Position
                    section.responseBorder.Size = section.responseBackground.Size
                    for rateIndex, id in ipairs(self.rates) do
                        local control = controls.rates[id]
                        local rateY = cursor + (rateIndex - 1) * RATE_ROW_HEIGHT
                        control.label.Position = Vector2.new(
                            innerX + LAYOUT.rateLabelInset,
                            rateY + LAYOUT.rateLabelTop
                        )
                        control.value.Position = Vector2.new(
                            innerX + INNER_CONTROL_WIDTH - LAYOUT.rateValueRightInset,
                            rateY + LAYOUT.rateLabelTop
                        )
                        control.hit.Position = Vector2.new(
                            innerX + LAYOUT.rateSliderLeft,
                            rateY + LAYOUT.rateSliderHitTop
                        )
                        control.track.Position = Vector2.new(
                            innerX + LAYOUT.rateSliderLeft,
                            rateY + LAYOUT.rateSliderTrackTop
                        )
                        control.fill.Position = control.track.Position
                        control.separator.Position = Vector2.new(
                            innerX + LAYOUT.rateSeparatorInset,
                            rateY + RATE_ROW_HEIGHT - SINGLE_PIXEL
                        )
                        local rateValue = math.clamp(settings[id] or 0, 0, 100)
                        local rateThumbRadius = controlTokens.rateThumbRadius
                        local rateThumbTravel = RATE_TRACK_WIDTH - rateThumbRadius * 2
                        local rateThumbX = control.track.Position.X
                            + rateThumbRadius
                            + rateThumbTravel * (rateValue / 100)
                        control.knob.Position = Vector2.new(
                            rateThumbX,
                            control.track.Position.Y + controlTokens.sliderTrackHeight * 0.5
                        )
                    end
                    cursor = cursor + responseHeight + GROUP_GAP
                end

                section.divider.Position = Vector2.new(innerX, cursor)
                cursor = cursor + LAYOUT.sectionDividerGap

                section.label.Position = Vector2.new(
                    innerX,
                    cursor + LAYOUT.sectionLabelTop
                )
                cursor = cursor + GROUP_HEADER_HEIGHT

                local optionRowCount = 0
                for rowIndex = 1, group.maxRow do
                    local rowOptions = group.rows[rowIndex] or {}
                    local columns = math.max(1, group.columns)
                    local visualRows = math.ceil(#rowOptions / columns)
                    optionRowCount = optionRowCount + visualRows
                    local columnWidth = (INNER_CONTROL_WIDTH - LAYOUT.columnGap * (columns - 1)) / columns
                    for optionIndex, optionName in ipairs(rowOptions) do
                        local option = controls.options[optionName]
                        if option then
                            local columnIndex = (optionIndex - 1) % columns
                            local visualRowIndex = math.floor((optionIndex - 1) / columns)
                            local rowX = innerX
                                + columnIndex * (columnWidth + LAYOUT.columnGap)
                            local rowY = cursor + visualRowIndex * (ROW_HEIGHT + ROW_GAP)
                            option.row.Position = Vector2.new(rowX, rowY)
                            option.row.Size = Vector2.new(columnWidth, ROW_HEIGHT)
                            option.separator.Position = Vector2.new(
                                rowX + LAYOUT.optionSeparatorInset,
                                rowY + ROW_HEIGHT - SINGLE_PIXEL
                            )
                            option.separator.Size = Vector2.new(
                                columnWidth - LAYOUT.optionSeparatorInset * 2,
                                SINGLE_PIXEL
                            )
                            if option.marker then
                                option.marker.Position = Vector2.new(
                                    rowX + LAYOUT.optionMarkerLeft,
                                    rowY + LAYOUT.optionMarkerTop
                                )
                            end
                            local parentAvailable = not option.marker
                                or settings[self.parents[optionName]] == true
                            option.label.Position = Vector2.new(
                                rowX
                                    + (option.marker and parentAvailable and LAYOUT.optionMarkerLabelInset
                                        or LAYOUT.optionLabelInset),
                                rowY + LAYOUT.optionLabelTop
                            )
                            option.value.Position = Vector2.new(
                                rowX + columnWidth - LAYOUT.optionValueRightInset,
                                rowY + LAYOUT.optionValueTop
                            )
                            local switchX = rowX + columnWidth - LAYOUT.optionSwitchRightInset
                            local switchY = rowY + LAYOUT.optionSwitchTop
                            local halfTrackWidth = controlTokens.switchTrackWidth * 0.5
                            local outerHalfHeight = controlTokens.switchOuterTrackHeight * 0.5
                            local innerHalfHeight = controlTokens.switchInnerTrackHeight * 0.5
                            local shadowOffset = SINGLE_PIXEL
                            option.switch.shadowTrack.Position = Vector2.new(
                                switchX - halfTrackWidth,
                                switchY - outerHalfHeight + shadowOffset
                            )
                            option.switch.shadowLeft.Position = Vector2.new(
                                switchX - halfTrackWidth,
                                switchY + shadowOffset
                            )
                            option.switch.shadowRight.Position = Vector2.new(
                                switchX + halfTrackWidth,
                                switchY + shadowOffset
                            )
                            option.switch.track.Position = Vector2.new(
                                switchX - halfTrackWidth,
                                switchY - outerHalfHeight
                            )
                            option.switch.left.Position = Vector2.new(switchX - halfTrackWidth, switchY)
                            option.switch.right.Position = Vector2.new(switchX + halfTrackWidth, switchY)
                            option.switch.fillTrack.Position = Vector2.new(
                                switchX - halfTrackWidth,
                                switchY - innerHalfHeight
                            )
                            option.switch.fillLeft.Position = Vector2.new(switchX - halfTrackWidth, switchY)
                            option.switch.fillRight.Position = Vector2.new(switchX + halfTrackWidth, switchY)
                            local knobPosition = Vector2.new(
                                switchX + (settings[optionName] == true and halfTrackWidth or -halfTrackWidth),
                                switchY
                            )
                            option.switch.knobRim.Position = knobPosition
                            option.switch.knob.Position = knobPosition
                        end
                    end
                    if visualRows > 0 then
                        cursor = cursor + visualRows * (ROW_HEIGHT + ROW_GAP)
                    end
                end
                if optionRowCount > 0 then
                    cursor = cursor - ROW_GAP
                end
                cursor = cursor + GROUP_GAP
            end
        end
    end
    return cursor
end

function StandardPanels:setVisible(visible)
    local controls = self.controls
    local combatVisible = visible and self.activePageName == "Combat"
    if controls.navigation then
        controls.navigation.tabs:setVisible(visible)
        controls.navigation.indicator.Visible = visible
        controls.navigation.rule.Visible = visible
        controls.navigation.menuKey:setVisible(visible and self.activePageName == "Settings")
        setVisible(controls.settings, visible and self.activePageName == "Settings")
    end
    if self.aimBuilt then
        for _, name in ipairs({
            "fovCard",
            "fovCardBorder",
            "fovLabel",
            "fovAmount",
            "fovMinimum",
            "fovMaximum",
            "targetModeLabel",
            "sliderHit",
            "sliderTrack",
            "sliderFill",
            "sliderKnob",
        }) do
            controls[name].Visible = combatVisible
        end
        controls.targetMode:setVisible(combatVisible)
        controls.fovValue.Visible = false
        controls.fovTopHighlight.Visible = false
        controls.targetingLabel.Visible = false
    end
    for _, option in pairs(controls.options) do
        local optionVisible = visible and self.groupById[option.sectionId].page == self.activePageName
        setVisible(option, optionVisible)
        option.value.Visible = optionVisible
            and (option.value.Text == "N/A" or option.value.Text == "Standby")
    end
    for _, rate in pairs(controls.rates) do
        setVisible(rate, combatVisible)
    end
    for _, group in ipairs(self.groups) do
        if controls.sections[group.id] then
            setVisible(controls.sections[group.id], visible and group.page == self.activePageName)
        end
    end
end

function StandardPanels:render(current)
    local settings = current.settings
    local controls = self.controls
    local colors = self.theme
    local tokens = colors.tokens
    local rateThumbRadius = tokens.control.rateThumbRadius

    for optionName, option in pairs(controls.options) do
        if self.groupById[option.sectionId].page == self.activePageName then
            local enabled = settings[optionName] == true
            local parent = self.parents[optionName]
            local supported = self.optionSupport[optionName] ~= false
            local available = supported and (not parent or settings[parent] == true)
            self.bridge.setControlColor(option.row, colors.panel)
            option.label.Color = available and colors.text or (colors.tertiary or colors.secondary)
            local trackColor = available and (enabled and colors.accent or colors.track) or colors.elevated
            local fillColor = available and (enabled and colors.accent or colors.elevated) or colors.elevated
            option.switch.track.Color = trackColor
            option.switch.left.Color = trackColor
            option.switch.right.Color = trackColor
            option.switch.fillTrack.Color = fillColor
            option.switch.fillLeft.Color = fillColor
            option.switch.fillRight.Color = fillColor
            option.switch.knobRim.Color = available and (enabled and colors.accent or colors.border) or colors.panel
            option.switch.knob.Color = available
                and (enabled and colors.text or colors.secondary)
                or colors.tertiary
            if option.marker then
                option.marker.Visible = available
            end
            local knobTravel = tokens.control.switchTrackWidth * 0.5
            local switchCenterX = option.switch.track.Position.X + knobTravel
            local switchCenterY = option.switch.left.Position.Y
            local knobPosition = Vector2.new(
                switchCenterX + (enabled and knobTravel or -knobTravel),
                switchCenterY
            )
            option.switch.knobRim.Position = knobPosition
            option.switch.knob.Position = knobPosition
            if option.marker then
                option.marker.Color = available and colors.accent or colors.border
            end
            option.value.Color = available and enabled and colors.accent or colors.secondary
            option.value.Text = not supported and "N/A"
                or (not available and enabled and "Standby" or "")
            option.value.Visible = current.menuVisible ~= false
                and (option.value.Text == "N/A" or option.value.Text == "Standby")
        end
    end

    if self.activePageName == "Combat" then
        for _, id in ipairs(self.rates) do
            local control = controls.rates[id]
            if not control or not control.track or not control.track.Position then
                continue
            end
            local value = math.clamp(settings[id] or 0, 0, 100)
            local alpha = value / 100
            local thumbTravel = RATE_TRACK_WIDTH - rateThumbRadius * 2
            local thumbX = control.track.Position.X + rateThumbRadius + thumbTravel * alpha
            control.fill.Size = Vector2.new(
                math.max(0, thumbX - control.track.Position.X),
                tokens.control.sliderTrackHeight
            )
            control.knob.Position = Vector2.new(
                thumbX,
                control.track.Position.Y + tokens.control.sliderTrackHeight * 0.5
            )
            control.value.Text = ("%d%%"):format(math.round(value))
            control.value.Color = colors.accent
        end
    end

    if self.aimBuilt and self.activePageName == "Combat" then
        local alpha = (settings.fov - settings.minimumFov) / (settings.maximumFov - settings.minimumFov)
        controls.sliderFill.Size = Vector2.new(
            FOV_TRACK_WIDTH * alpha,
            tokens.control.sliderTrackHeight
        )
        controls.sliderKnob.Position = Vector2.new(
            self.sliderStartX + FOV_TRACK_WIDTH * alpha,
            controls.sliderTrack.Position.Y + tokens.control.sliderTrackHeight * 0.5
        )
        controls.targetMode:setValue(settings.fullScreenAim and "fullscreen" or "radius")
        controls.sliderFill.Color = settings.fullScreenAim and colors.border or colors.accent
        controls.sliderKnob.Color = settings.fullScreenAim and colors.secondary or colors.accent
        controls.fovValue.Color = settings.fullScreenAim and colors.accent or colors.secondary
        controls.fovLabel.Text = "FOV"
        controls.fovAmount.Text = settings.fullScreenAim and "Fullscreen" or ("%d px"):format(math.round(settings.fov))
        controls.fovAmount.Position = Vector2.new(
            settings.fullScreenAim and (self.sliderStartX + FOV_TRACK_WIDTH * 0.5)
                or (self.sliderStartX + FOV_TRACK_WIDTH * alpha),
            controls.fovCard.Position.Y + LAYOUT.fovAmountTop
        )
        controls.fovMinimum.Text = ("%d px"):format(math.round(settings.minimumFov))
        controls.fovMaximum.Text = ("%d px"):format(math.round(settings.maximumFov))
        controls.fovValue.Text = "Fullscreen"
        controls.fovCircle.Radius = settings.fov
        controls.fovCircle.Visible = self.aimControlsSupported
            and settings.fovCircle ~= false
            and not settings.fullScreenAim
    end
end

function StandardPanels:setMousePosition(position)
    if self.controls.fovCircle then
        self.controls.fovCircle.Position = position
    end
end

function StandardPanels:destroy()
    if self.controls.navigation then
        self.controls.navigation.tabs:destroy()
        self.controls.navigation.menuKey:destroy()
    end
    if self.controls.targetMode then
        self.controls.targetMode:destroy()
    end
end

return StandardPanels
