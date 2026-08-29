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

local ColorPolicy = importDependency("ui/esp/ColorPolicy", "../esp/ColorPolicy")
local WhatsNew = importDependency("ui/WhatsNew", "../WhatsNew")
local Catalog = {}
Catalog.__index = Catalog

local PAGE_ORDER = { "Combat", "Rage", "Movement", "Visuals", "Tools", "Settings" }

local function isEphemeral(page, spec)
    return page == "Rage" or (type(spec) == "table" and spec.persist == false)
end

function Catalog.collectEphemeralSettings(presentation)
    assert(
        type(presentation) == "table" and type(presentation.mount) == "function",
        "Ephemeral setting collection requires a game presentation"
    )
    local result = {}
    local sections = {}
    local collector = {}

    function collector:section(page, id, _label, _lineOffset, _includesRates, _columns, spec)
        sections[id] = {
            ephemeral = isEphemeral(page, spec),
            page = page,
        }
    end

    function collector:option(sectionId, _rowIndex, id, _label, parent)
        local section =
            assert(sections[sectionId], "Unknown presentation section: " .. tostring(sectionId))
        if
            section.ephemeral
            or isEphemeral(section.page, type(parent) == "table" and parent or nil)
        then
            result[id] = true
        end
    end

    function collector:slider(sectionId, id, _label, spec)
        local section =
            assert(sections[sectionId], "Unknown presentation section: " .. tostring(sectionId))
        if section.ephemeral or isEphemeral(section.page, spec) then
            result[id] = true
        end
    end

    function collector:button() end

    function collector:keybind(sectionId, id)
        local section =
            assert(sections[sectionId], "Unknown presentation section: " .. tostring(sectionId))
        if section.ephemeral then
            result[id] = true
        end
    end

    function collector:segmented(page, spec)
        if not isEphemeral(page, spec) then
            return
        end
        result[spec.id] = true
        for _, option in ipairs(spec.options or {}) do
            for _, entry in ipairs(option.patch or {}) do
                result[entry[1]] = true
            end
        end
    end

    setmetatable(collector, {
        __index = function()
            return function() end
        end,
    })
    presentation.mount(collector)
    return result
end

local function buildAvailability(capabilities)
    local available = {}
    for key, value in pairs(capabilities or {}) do
        local name = type(key) == "number" and value or key
        if value ~= false then
            available[name] = true
        end
    end
    return available
end

function Catalog.new(context)
    assert(
        type(context) == "table" and context.store,
        "Presentation catalog requires a Store context"
    )
    return setmetatable({
        available = buildAvailability(context.capabilities),
        context = context,
        finalized = false,
        groups = {},
        groupById = {},
        hasAim = false,
        hasContent = {},
        optionSupport = context.optionSupport or {},
        pageMetadata = {},
        ephemeralSettings = {},
        rates = {},
        relatedValues = {},
        segments = {},
        segmentById = {},
        sliderById = {},
    }, Catalog)
end

function Catalog:page(page, metadata)
    assert(type(page) == "string" and page ~= "", "Presentation page metadata requires a page id")
    assert(type(metadata) == "table", "Presentation page metadata requires a descriptor")
    assert(metadata.order == nil or type(metadata.order) == "number", "Page order must be numeric")
    assert(self.pageMetadata[page] == nil, "Duplicate presentation page metadata: " .. page)
    self.pageMetadata[page] = metadata
end

function Catalog:supports(name)
    return self.available[name] == true
end

function Catalog:read()
    return self.context.store:Get()
end

function Catalog:patch(patch)
    return self.context.store:Patch(patch)
end

function Catalog:action(name, ...)
    local callback = self.context[name]
    if type(callback) == "function" then
        return callback(...)
    end
    assert(self.available[name], "Unknown presentation action: " .. tostring(name))
    return self.context.setOption(name, true, true)
end

function Catalog:_markPage(page)
    self.hasContent[page] = true
end

function Catalog:aim()
    local supported = self.available.silentAim
        or self.available.shotAim
        or self.available.triggerBot
        or self.available.aimSmoothness
        or self.available.aimAssistStrength
        or self.available.headshotRate
        or self.available.missRate
    if self.hasAim or not supported then
        return
    end
    self.hasAim = true
    self:_markPage("Combat")
end

function Catalog:rate(id, label)
    if not self.available[id] then
        return
    end
    table.insert(self.rates, { id = id, label = label })
    self:_markPage("Combat")
end

local function segmentIsSupported(available, spec)
    for _, option in ipairs(spec.options or {}) do
        for id in pairs(option.when or {}) do
            if available[id] then
                return true
            end
        end
    end
    return false
end

function Catalog:segmented(page, spec)
    assert(
        type(spec) == "table" and type(spec.id) == "string",
        "Segmented presentation control requires an id"
    )
    assert(
        type(spec.options) == "table" and #spec.options > 1,
        "Segmented presentation control requires options"
    )
    assert(not self.segmentById[spec.id], "Duplicate segmented presentation control: " .. spec.id)
    if not segmentIsSupported(self.available, spec) then
        return
    end
    spec.page = page
    spec.ephemeral = isEphemeral(page, spec)
    if spec.ephemeral then
        self.ephemeralSettings[spec.id] = true
        for _, option in ipairs(spec.options or {}) do
            for _, entry in ipairs(option.patch or {}) do
                self.ephemeralSettings[entry[1]] = true
            end
        end
    end
    self.segmentById[spec.id] = spec
    table.insert(self.segments, spec)
    self:_markPage(page)
end

function Catalog:section(page, id, label, lineOffset, includesRates, columns, spec)
    assert(not self.groupById[id], "Duplicate presentation section: " .. tostring(id))
    spec = type(spec) == "table" and spec or {}
    local group = {
        id = id,
        page = page,
        label = label,
        lineOffset = lineOffset,
        includesRates = includesRates == true,
        columns = columns or 1,
        ephemeral = isEphemeral(page, spec),
        renderEmpty = spec.renderEmpty == true,
        treatment = spec.treatment,
        actions = {},
        options = {},
        keybinds = {},
        sliders = {},
    }
    self.groupById[id] = group
    table.insert(self.groups, group)
end

function Catalog:button(sectionId, id, label, spec)
    if not self.available[id] then
        return
    end
    local group =
        assert(self.groupById[sectionId], "Unknown presentation section: " .. tostring(sectionId))
    spec = type(spec) == "table" and spec or { variant = spec }
    table.insert(group.actions, {
        action = id,
        confirm = spec.confirm,
        id = id,
        label = label,
        variant = spec.variant,
    })
    self:_markPage(group.page)
end

function Catalog:option(sectionId, rowIndex, id, label, parent, visibility)
    if not self.available[id] then
        return
    end
    local group =
        assert(self.groupById[sectionId], "Unknown presentation section: " .. tostring(sectionId))
    local spec = type(parent) == "table" and parent or nil
    if spec then
        parent = spec.parent
        visibility = spec.visibility or spec.when or visibility
    end
    local placement = spec and spec.placement or nil
    local ephemeral = group.ephemeral or isEphemeral(group.page, spec)
    if placement == nil then
        if parent == "audience" then
            placement = "audience"
        elseif type(parent) == "string" then
            placement = "details"
        else
            placement = "grid"
        end
    end
    if placement == "audience" then
        parent = nil
    end
    table.insert(group.options, {
        ephemeral = ephemeral,
        id = id,
        label = label,
        parent = parent,
        placement = placement,
        row = rowIndex,
        visibility = visibility,
    })
    if ephemeral then
        self.ephemeralSettings[id] = true
    end
    self:_markPage(group.page)
end

function Catalog:slider(sectionId, id, label, spec)
    if not self.available[id] then
        return
    end
    local group =
        assert(self.groupById[sectionId], "Unknown presentation section: " .. tostring(sectionId))
    spec = spec or {}
    local slider = {
        ephemeral = group.ephemeral or isEphemeral(group.page, spec),
        id = id,
        label = label,
        min = spec.min or 0,
        max = spec.max or 100,
        step = spec.step or 1,
        unit = spec.unit or "",
        parent = spec.parent,
    }
    if slider.ephemeral then
        self.ephemeralSettings[id] = true
    end
    table.insert(group.sliders, slider)
    self.sliderById[id] = slider
    self:_markPage(group.page)
end

function Catalog:keybind(sectionId, id, label, defaultValue)
    local group =
        assert(self.groupById[sectionId], "Unknown presentation section: " .. tostring(sectionId))
    table.insert(group.keybinds, { id = id, label = label, defaultValue = defaultValue })
    if group.ephemeral then
        self.ephemeralSettings[id] = true
    end
    self:_markPage(group.page)
end

function Catalog:cosmetics()
    if self.context.cosmetics == false then
        return
    end
    self.hasCosmetics = true
    self:_markPage("Visuals")
end

function Catalog:register(panel)
    -- Legacy custom panels are retained by the Drawing presentation until their
    -- game registers an equivalent renderer-neutral catalog descriptor.
    if panel and panel.page then
        self:_markPage(panel.page)
    end
    return panel
end

function Catalog:finalize()
    if self.finalized then
        return
    end
    self.finalized = true
    for _, page in ipairs(PAGE_ORDER) do
        if self.hasContent[page] then
            self:_markPage("Settings")
            break
        end
    end
end

local function append(list, value)
    table.insert(list, value)
    return value
end

local function selectedSegmentValue(segment, settings)
    local selected = segment.options[1].value
    for _, option in ipairs(segment.options) do
        local matches = true
        for id, expected in pairs(option.when or {}) do
            if settings[id] ~= expected then
                matches = false
                break
            end
        end
        if matches then
            return option.value
        end
    end
    return selected
end

local function selectedTargetMode(settings, cameraMode)
    local mode = cameraMode and settings.cameraTargetMode or settings.shotTargetMode
    if mode == "radius" or mode == "fullscreen" or mode == "360" then
        return mode
    end
    local fullScreenAim = cameraMode
            and (settings.cameraFullScreenAim == nil and settings.fullScreenAim or settings.cameraFullScreenAim)
        or not cameraMode
            and (settings.shotFullScreenAim == nil and settings.fullScreenAim or settings.shotFullScreenAim)
    return fullScreenAim == true and "fullscreen" or "radius"
end

function Catalog:model(state)
    self:finalize()
    state = state or self.context.store:Get()
    local settings = state.settings
    local sectionsByPage = {}
    for _, page in ipairs(PAGE_ORDER) do
        sectionsByPage[page] = {}
    end

    for _, segment in ipairs(self.segments) do
        local selected = selectedSegmentValue(segment, settings)
        local controls = {
            {
                id = segment.id,
                kind = "segmented",
                label = segment.label,
                value = selected,
                emphasis = segment.emphasis,
                options = segment.options,
            },
        }
        for _, related in ipairs(segment.related or {}) do
            local kind = related.kind or "toggle"
            local parentActive = not related.parent or settings[related.parent] == true
            if related.when == selected and self.available[related.id] and parentActive then
                local value = settings[related.id]
                append(controls, {
                    id = related.id,
                    kind = kind,
                    label = related.label,
                    max = kind == "slider" and (related.max or 100) or nil,
                    min = kind == "slider" and (related.min or 0) or nil,
                    parent = related.parent,
                    step = kind == "slider" and (related.step or 1) or nil,
                    unit = kind == "slider" and related.unit or nil,
                    value = kind == "slider" and value or value == true,
                    status = self.optionSupport[related.id] == false and "unavailable"
                        or "available",
                })
            end
        end
        append(sectionsByPage[segment.page], {
            id = segment.id,
            label = segment.sectionLabel or segment.label,
            treatment = segment.treatment or (segment.id == "worldRenderer" and "style" or "card"),
            controls = controls,
        })
    end

    if self.hasAim then
        local cameraMode = settings.shotAim ~= true
        local targetMode = selectedTargetMode(settings, cameraMode)
        local targetOptions = {
            { value = "radius", label = "Radius" },
            { value = "fullscreen", label = "Fullscreen" },
        }
        if self.available.target360 then
            table.insert(targetOptions, { value = "360", label = "360" })
        end
        local controls = {
            {
                id = "fullScreenAim",
                kind = "segmented",
                label = "Target Mode",
                value = targetMode,
                emphasis = "prominent",
                options = targetOptions,
            },
        }
        if targetMode == "radius" then
            append(controls, {
                id = "fov",
                kind = "slider",
                label = "FOV",
                value = (cameraMode and settings.cameraFov or settings.shotFov) or settings.fov,
                min = settings.minimumFov,
                max = settings.maximumFov,
                step = 1,
                unit = "px",
                emphasis = "row",
            })
        end
        append(sectionsByPage.Combat, {
            id = "targeting",
            label = "Targeting",
            treatment = "card",
            controls = controls,
        })
    end

    if #self.rates > 0 then
        local controls = {}
        for _, rate in ipairs(self.rates) do
            append(controls, {
                id = rate.id,
                kind = "slider",
                label = rate.label,
                value = math.clamp(settings[rate.id] or 0, 0, 100),
                min = 0,
                max = 100,
                step = 1,
                unit = "%",
                emphasis = "row",
            })
        end
        append(sectionsByPage.Combat, {
            id = "response",
            label = "Response",
            treatment = "card",
            controls = controls,
        })
    end

    for _, group in ipairs(self.groups) do
        if
            #group.actions > 0
            or #group.options > 0
            or #group.keybinds > 0
            or #group.sliders > 0
            or group.renderEmpty
        then
            local controls = {}
            for _, action in ipairs(group.actions) do
                append(controls, {
                    action = action.action,
                    confirm = action.confirm,
                    id = action.id,
                    kind = "action",
                    label = action.label,
                    variant = action.variant,
                })
            end
            for _, keybind in ipairs(group.keybinds) do
                local value = settings[keybind.id]
                append(controls, {
                    id = keybind.id,
                    kind = "keybind",
                    label = keybind.label,
                    value = type(value) == "string" and Enum.KeyCode[value]
                        or Enum.KeyCode[keybind.defaultValue or "End"],
                    readOnly = false,
                })
            end
            for _, option in ipairs(group.options) do
                local parentActive = not option.parent
                    or option.parent == "audience"
                    or settings[option.parent] == true
                local visible = option.visibility ~= "when-parent" or parentActive
                if type(option.visibility) == "table" then
                    local expected = option.visibility.equals
                    visible = settings[option.visibility.setting] == expected
                        and (option.visibility.whenParent ~= true or parentActive)
                end
                if visible then
                    local status = "available"
                    if self.optionSupport[option.id] == false then
                        status = "unavailable"
                    elseif not parentActive then
                        status = "standby"
                    end
                    append(controls, {
                        id = option.id,
                        kind = "toggle",
                        label = option.label,
                        parent = option.parent,
                        placement = option.placement,
                        value = settings[option.id] == true,
                        status = status,
                    })
                    for _, slider in ipairs(group.sliders) do
                        if slider.parent == option.id and settings[option.id] == true then
                            local value = settings[slider.id]
                            if type(value) ~= "number" then
                                value = slider.min
                            end
                            append(controls, {
                                id = slider.id,
                                kind = "slider",
                                label = slider.label,
                                parent = slider.parent,
                                value = math.clamp(value, slider.min, slider.max),
                                min = slider.min,
                                max = slider.max,
                                step = slider.step,
                                unit = slider.unit,
                                emphasis = "nested",
                            })
                        end
                    end
                end
            end
            for _, slider in ipairs(group.sliders) do
                if slider.parent then
                    continue
                end
                local value = settings[slider.id]
                if type(value) ~= "number" then
                    value = slider.min
                end
                append(controls, {
                    id = slider.id,
                    kind = "slider",
                    label = slider.label,
                    value = math.clamp(value, slider.min, slider.max),
                    min = slider.min,
                    max = slider.max,
                    step = slider.step,
                    unit = slider.unit,
                    emphasis = "row",
                })
            end
            if #controls > 0 or group.renderEmpty then
                local treatment = group.treatment
                if treatment == nil then
                    local metadata = self.pageMetadata[group.page] or {}
                    if metadata.layout == "toggle-grid" then
                        for _, option in ipairs(group.options) do
                            if option.placement == "grid" then
                                treatment = "grid"
                                break
                            end
                        end
                    end
                end
                append(sectionsByPage[group.page], {
                    id = group.id,
                    label = group.label,
                    treatment = treatment or "list",
                    controls = controls,
                })
            end
        end
    end

    if self.hasCosmetics then
        local cosmetics = state.cosmetics or {}
        local gloves = state.gloves or {}
        local minimumWear = cosmetics.minimumWear or 0
        local maximumWear = cosmetics.maximumWear or 1
        local minimumGloveWear = gloves.minimumWear or 0
        local maximumGloveWear = gloves.maximumWear or 1
        append(sectionsByPage.Visuals, {
            id = "skin-changer",
            label = "Skin changer",
            treatment = "plain",
            controls = {
                {
                    id = "cosmeticModelViewer",
                    kind = "model-viewer",
                    label = "Weapon preview",
                    height = 230,
                    key = type(self.context.getWeaponPreviewKey) == "function"
                            and self.context.getWeaponPreviewKey(state)
                        or tostring(state.previewRevision or 0),
                    resolve = type(self.context.getWeaponPreviewSubject) == "function"
                            and function()
                                return self.context.getWeaponPreviewSubject(state)
                            end
                        or nil,
                },
                {
                    id = "previousCosmeticWeapon",
                    kind = "action",
                    action = "previousCosmeticWeapon",
                    label = "Previous weapon",
                },
                {
                    id = "nextCosmeticWeapon",
                    kind = "action",
                    action = "nextCosmeticWeapon",
                    label = "Next weapon · " .. tostring(cosmetics.weapon or "Weapon"),
                },
                {
                    id = "previousSkin",
                    kind = "action",
                    action = "previousSkin",
                    label = "Previous skin",
                },
                {
                    id = "nextSkin",
                    kind = "action",
                    action = "nextSkin",
                    label = "Next skin · "
                        .. tostring(cosmetics.skinLabel or cosmetics.skin or "Stock"),
                },
                {
                    id = "cosmeticWear",
                    kind = "slider",
                    label = "Knife wear",
                    value = math.clamp(cosmetics.wear or minimumWear, minimumWear, maximumWear),
                    min = minimumWear,
                    max = maximumWear,
                    step = 0.01,
                },
                {
                    id = "cosmeticStatTrak",
                    kind = "toggle",
                    label = "StatTrak",
                    value = cosmetics.statTrak == true,
                    disabled = cosmetics.supportsStatTrak ~= true,
                },
                {
                    id = "resetSkin",
                    kind = "action",
                    action = "resetSkin",
                    label = "Reset knife",
                },
            },
        })
        append(sectionsByPage.Visuals, {
            id = "glove-changer",
            label = "Gloves",
            treatment = "plain",
            controls = {
                {
                    id = "previousGlove",
                    kind = "action",
                    action = "previousGlove",
                    label = "Previous gloves",
                },
                {
                    id = "nextGlove",
                    kind = "action",
                    action = "nextGlove",
                    label = "Next gloves · " .. tostring(gloves.skin or "Game equipped"),
                },
                {
                    id = "gloveWear",
                    kind = "slider",
                    label = "Glove wear",
                    value = math.clamp(
                        gloves.wear or minimumGloveWear,
                        minimumGloveWear,
                        maximumGloveWear
                    ),
                    min = minimumGloveWear,
                    max = maximumGloveWear,
                    step = 0.01,
                },
                {
                    id = "resetGlove",
                    kind = "action",
                    action = "resetGlove",
                    label = "Use game-equipped gloves",
                },
            },
        })
    end

    append(sectionsByPage.Settings, {
        id = "menu",
        label = "Menu",
        treatment = "card",
        controls = {
            {
                id = "menuKey",
                kind = "keybind",
                label = "Toggle interface",
                value = type(settings.menuKey) == "string" and Enum.KeyCode[settings.menuKey]
                    or Enum.KeyCode.RightShift,
                readOnly = false,
            },
        },
    })

    local pages = {}
    local pageRanks = {}
    for defaultOrder, page in ipairs(PAGE_ORDER) do
        if self.hasContent[page] then
            local metadata = self.pageMetadata[page] or {}
            pageRanks[page] = metadata.order or defaultOrder
            local preview
            if metadata.preview then
                preview = {}
                for key, value in pairs(metadata.preview) do
                    preview[key] = value
                end
                preview.worldRenderer = settings.worldRenderer
                preview.tone = "enemy"
                local visualPolicy = self.context.visualPolicy
                local defaultAlpha = preview.worldRenderer == "native"
                        and (1 - (visualPolicy and visualPolicy.FILL_TRANSPARENCY or 0.42))
                    or 0.18
                local defaults = {
                    enemy = Color3.fromRGB(255, 118, 87),
                    teammate = Color3.fromRGB(101, 157, 214),
                    weapon = Color3.fromRGB(177, 188, 199),
                    healthLow = Color3.fromRGB(255, 118, 87),
                    healthHigh = Color3.fromRGB(98, 214, 173),
                }
                local function relationshipPalette(relationship, label)
                    local primary = defaults[relationship]
                    local fillAlpha = ColorPolicy.fillAlpha(settings, defaultAlpha, relationship)
                    return {
                        id = relationship,
                        label = label,
                        fillAlpha = fillAlpha,
                        targets = {
                            {
                                id = "outline",
                                label = "Outline",
                                color = ColorPolicy.color(
                                    settings,
                                    "outline",
                                    primary,
                                    relationship
                                ),
                                defaultColor = primary,
                            },
                            {
                                id = "fill",
                                label = "Fill",
                                color = ColorPolicy.color(settings, "fill", primary, relationship),
                                alpha = fillAlpha,
                                defaultColor = primary,
                                defaultAlpha = defaultAlpha,
                            },
                            {
                                id = "name",
                                label = "Name",
                                color = ColorPolicy.color(settings, "name", primary, relationship),
                                defaultColor = primary,
                            },
                            {
                                id = "weapon",
                                label = "Weapon",
                                color = ColorPolicy.color(
                                    settings,
                                    "weapon",
                                    defaults.weapon,
                                    relationship
                                ),
                                defaultColor = defaults.weapon,
                            },
                            {
                                id = "healthLow",
                                label = "Health Low",
                                color = ColorPolicy.color(
                                    settings,
                                    "healthLow",
                                    defaults.healthLow,
                                    relationship
                                ),
                                defaultColor = defaults.healthLow,
                            },
                            {
                                id = "healthHigh",
                                label = "Health High",
                                color = ColorPolicy.color(
                                    settings,
                                    "healthHigh",
                                    defaults.healthHigh,
                                    relationship
                                ),
                                defaultColor = defaults.healthHigh,
                            },
                        },
                    }
                end
                local enemyPalette = relationshipPalette("enemy", "Enemies")
                preview.chamsColor = enemyPalette.targets[2].color
                preview.chamsTransparency = 1 - enemyPalette.fillAlpha
                preview.outlineColor = enemyPalette.targets[1].color
                preview.palette = {
                    checkerboardImage = self.context.alphaCheckerboard,
                    relationships = {
                        enemyPalette,
                        relationshipPalette("teammate", "Teammates"),
                    },
                }
                preview.nameLabel = self.context.localPlayer and self.context.localPlayer.Name
                    or "Preview Player"
                preview.weaponLabel = preview.weaponLabel or "Assault Rifle"
                preview.boxes = settings.boxes == true
                preview.chams = settings.chams == true
                preview.names = settings.names == true
                preview.health = settings.health == true
                preview.weapon = settings.weapon == true
                preview.chamsExcludeAccessories = settings.chamsExcludeAccessories == true
                preview.chamsPerPart = settings.chamsPerPart == true
                if type(self.context.publishPreviewObservation) == "function" then
                    preview.publish = self.context.publishPreviewObservation
                end
                if type(self.context.reportPreviewStatus) == "function" then
                    preview.report = self.context.reportPreviewStatus
                end
                if type(self.context.getPreviewSubject) == "function" then
                    preview.key = type(self.context.getPreviewKey) == "function"
                            and self.context.getPreviewKey(state)
                        or tostring(state.previewRevision or 0)
                    preview.resolve = function()
                        return self.context.getPreviewSubject(state)
                    end
                end
            end
            local views = metadata.views
            if views == nil and preview and preview.palette then
                views = {
                    { id = "preview", label = "Preview" },
                    { id = "colors", label = "ESP Colors" },
                }
            end
            append(pages, {
                id = page,
                label = page,
                icon = self.context.pageIcons and self.context.pageIcons[page] or nil,
                layout = metadata.layout,
                views = views,
                preview = preview,
                sections = sectionsByPage[page],
            })
        end
    end
    table.sort(pages, function(left, right)
        return pageRanks[left.id] < pageRanks[right.id]
    end)
    local footer = {}
    for _, metric in ipairs(state.footerMetrics or {}) do
        local tone = "neutral"
        local icon
        local value = tostring(metric.value)
        if metric.kind == "latency" and type(metric.value) == "number" then
            icon = "signal"
            tone = metric.value <= 80 and "positive"
                or metric.value <= 150 and "warning"
                or "negative"
            value ..= " ms"
        end
        table.insert(footer, {
            icon = icon,
            id = metric.id,
            label = metric.label,
            tone = tone,
            value = value,
        })
    end

    return {
        brandLabel = "universal-hub",
        brandIcon = self.context.brandIcon,
        gameLabel = self.context.gameLabel or "Universal",
        gameIcon = self.context.gameIcon,
        floatingMonitor = type(state.floatingMonitor) == "table" and state.floatingMonitor or nil,
        notification = type(state.notification) == "table" and state.notification or nil,
        enemyAudienceIcon = self.context.enemyAudienceIcon,
        allyAudienceIcon = self.context.allyAudienceIcon,
        visible = state.menuVisible ~= false,
        whatsNew = WhatsNew.model(state.whatsNew),
        pages = pages,
        footer = footer,
        onDismissNotification = function()
            self.context.store:Patch({ notification = false })
        end,
        onValueChange = function(id, value, persist)
            local segment = self.segmentById[id]
            if segment then
                local shouldPersist = not segment.ephemeral
                local currentSettings = self.context.store:Get().settings
                local currentValue = selectedSegmentValue(segment, currentSettings)
                for _, related in ipairs(segment.related or {}) do
                    if related.when == currentValue and self.available[related.id] then
                        self.relatedValues[related.id] = currentSettings[related.id]
                    end
                end
                for _, option in ipairs(segment.options) do
                    if option.value == value then
                        for _, entry in ipairs(option.patch or {}) do
                            if
                                type(entry[2]) == "boolean"
                                or type(self.context.setSetting) ~= "function"
                            then
                                self.context.setOption(entry[1], entry[2], shouldPersist)
                            else
                                self.context.setSetting(entry[1], entry[2], shouldPersist)
                            end
                        end
                        for _, related in ipairs(segment.related or {}) do
                            local retained = self.relatedValues[related.id]
                            if related.when == value and retained ~= nil then
                                if type(retained) == "boolean" then
                                    self.context.setOption(related.id, retained, shouldPersist)
                                else
                                    self.context.setRate(related.id, retained, shouldPersist)
                                end
                            end
                        end
                        if id == "aimMode" then
                            local settings = self.context.store:Get().settings
                            local shotOnly = settings.shotAim == true
                            local targetMode = selectedTargetMode(settings, not shotOnly)
                            self.context.setFov(
                                (shotOnly and settings.shotFov or settings.cameraFov)
                                    or settings.fov,
                                shouldPersist
                            )
                            self.context.setOption(
                                "fullScreenAim",
                                targetMode ~= "radius",
                                shouldPersist
                            )
                        end
                        return
                    end
                end
            end
            if id == "menuKey" and self.context.setMenuKey then
                self.context.setMenuKey(value)
            elseif id == "taskAutomationEmergencyKey" and value ~= nil then
                self.context.setSetting(id, value.Name, persist == true)
            elseif id == "fov" then
                self.context.setFov(value, persist == true)
            elseif id:sub(1, 9) == "espColor:" then
                local relationship, target = id:match("^espColor:([^:]+):([^:]+)$")
                local setting = relationship and ColorPolicy.settingName(relationship, target)
                if setting then
                    self.context.setSetting(setting, value, persist == true)
                end
            elseif id:sub(1, 9) == "espAlpha:" then
                local relationship = id:match("^espAlpha:([^:]+)$")
                local setting = relationship and ColorPolicy.settingName(relationship, "fillAlpha")
                if setting then
                    local nextValue = value == -1 and -1 or math.clamp(value, 0, 1)
                    self.context.setSetting(setting, nextValue, persist == true)
                end
            elseif id:sub(1, 21) == "resetEspRelationship:" then
                local relationship = id:match("^resetEspRelationship:([^:]+)$")
                for _, target in ipairs(ColorPolicy.TARGETS) do
                    self.context.setSetting(
                        ColorPolicy.settingName(relationship, target),
                        "",
                        persist == true
                    )
                end
                self.context.setSetting(
                    ColorPolicy.settingName(relationship, "fillAlpha"),
                    -1,
                    persist == true
                )
            elseif id == "resetEspAll" then
                for _, relationship in ipairs(ColorPolicy.RELATIONSHIPS) do
                    for _, target in ipairs(ColorPolicy.TARGETS) do
                        self.context.setSetting(
                            ColorPolicy.settingName(relationship, target),
                            "",
                            persist == true
                        )
                    end
                    self.context.setSetting(
                        ColorPolicy.settingName(relationship, "fillAlpha"),
                        -1,
                        persist == true
                    )
                end
            elseif id == "fullScreenAim" then
                local settings = self.context.store:Get().settings
                local modeName = settings.shotAim == true and "shotTargetMode" or "cameraTargetMode"
                if settings[modeName] ~= nil then
                    self.context.setSetting(modeName, value, persist == true)
                end
                local fullScreenName = settings.shotAim == true and "shotFullScreenAim"
                    or "cameraFullScreenAim"
                if settings[fullScreenName] == nil then
                    fullScreenName = "fullScreenAim"
                end
                self.context.setOption(fullScreenName, value ~= "radius", persist == true)
                if fullScreenName ~= "fullScreenAim" then
                    self.context.setOption("fullScreenAim", value ~= "radius", persist == true)
                end
            elseif id == "cosmeticWear" and self.context.setWear then
                local cosmetics = self.context.store:Get().cosmetics or {}
                local minimum = cosmetics.minimumWear or 0
                local maximum = cosmetics.maximumWear or 1
                self.context.setWear(
                    maximum > minimum and (value - minimum) / (maximum - minimum) or 0
                )
            elseif id == "gloveWear" and self.context.setGloveWear then
                local gloves = self.context.store:Get().gloves or {}
                local minimum = gloves.minimumWear or 0
                local maximum = gloves.maximumWear or 1
                self.context.setGloveWear(
                    maximum > minimum and (value - minimum) / (maximum - minimum) or 0
                )
            elseif id == "cosmeticStatTrak" and self.context.toggleStatTrak then
                local cosmetics = self.context.store:Get().cosmetics or {}
                if (cosmetics.statTrak == true) ~= (value == true) then
                    self.context.toggleStatTrak()
                end
            elseif self.sliderById[id] then
                local slider = self.sliderById[id]
                local nextValue = math.clamp(math.round(value), slider.min, slider.max)
                self.context.setSetting(id, nextValue, persist == true and not slider.ephemeral)
            elseif self.groupById[id] or self.available[id] then
                if type(value) == "boolean" then
                    self.context.setOption(id, value, not self.ephemeralSettings[id])
                else
                    self.context.setRate(id, value, persist == true)
                end
            elseif id == "cosmeticsOpen" and self.context.setCosmeticsOpen then
                self.context.setCosmeticsOpen(value == true)
            end
        end,
        onAction = function(name)
            return self:action(name)
        end,
    }
end

return Catalog
