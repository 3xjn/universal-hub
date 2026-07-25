local Overlay = {}
Overlay.__index = Overlay

local OPTION_GROUPS = {
    {
        id = "rage",
        label = "RAGE",
        rows = {
            { "silentAim", "wallbang" },
            { "humanAim" },
            { "triggerBot", "noSpread" },
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
            { "noSmoke" },
        },
    },
}

local OPTION_LABELS = {
    bhop = "Bunny Hop",
    silentAim = "Silent Aim",
    triggerBot = "Trigger Bot",
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
    panel = Color3.fromRGB(17, 23, 29),
    secondary = Color3.fromRGB(167, 176, 184),
    text = Color3.fromRGB(243, 246, 247),
}

local BODY_CUBE_FACES = {
    { 1, 2, 3, 4 },
    { 5, 8, 7, 6 },
    { 1, 5, 6, 2 },
    { 4, 3, 7, 8 },
    { 1, 4, 8, 5 },
    { 2, 6, 7, 3 },
}

local BODY_CUBE_OPACITY = 0.18

local function setVisible(nodes, visible)
    for _, node in pairs(nodes) do
        if type(node) == "table" and node.Visible == nil then
            setVisible(node, visible)
        else
            node.Visible = visible
        end
    end
end

function Overlay.new(context)
    assert(context and context.drawing, "Hub overlay requires Hydroxide drawing helpers")
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
    local optionSupport = {
        chams = type(context.drawing.supports) ~= "function" or context.drawing.supports("Quad"),
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
    local self = setmetatable({
        captured = false,
        cosmeticsSupported = context.cosmetics ~= false,
        context = context,
        controls = {},
        destroyed = false,
        observations = {},
        optionAvailable = optionAvailable,
        optionSupport = optionSupport,
        optionLabels = context.optionLabels or {},
        rateAvailable = rateAvailable,
        playerNodes = {},
        surface = context.drawing.createSurface({
            acceptProcessedInput = true,
        }),
    }, Overlay)

    self:_build()
    self.unsubscribe = context.store:Subscribe(function(state)
        self:_renderState(state)
    end)
    return self
end

function Overlay:_capture(node)
    return node
end

function Overlay:_text(properties, pointerEvents)
    properties.Font = properties.Font or Drawing.Fonts.Plex
    properties.Visible = properties.Visible ~= false
    return self.surface:create("Text", properties, {
        pointerEvents = pointerEvents == true,
    })
end

function Overlay:_build()
    local surface = self.surface
    local controls = self.controls

    controls.panel = self:_capture(surface:create("Square", {
        Color = COLORS.panel,
        Filled = true,
        Size = Vector2.new(300, 596),
        Transparency = 0.97,
        Visible = true,
        ZIndex = 200,
    }))
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
    controls.hideButton = self:_capture(surface:create("Square", {
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
    controls.fovModeButton = self:_capture(surface:create("Square", {
        Color = COLORS.elevated,
        Filled = true,
        Size = Vector2.new(112, 22),
        Visible = true,
        ZIndex = 201,
    }))
    controls.fovModeButton:on("click", function()
        local settings = self.context.store:Get().settings
        self.context.setOption("fullScreenAim", not settings.fullScreenAim)
    end)
    controls.sliderHit = self:_capture(surface:create("Square", {
        Color = COLORS.panel,
        Filled = true,
        Size = Vector2.new(276, 28),
        Transparency = 0,
        Visible = true,
        ZIndex = 202,
    }))
    controls.sliderTrack = surface:create("Square", {
        Color = COLORS.border,
        Filled = true,
        Size = Vector2.new(276, 4),
        Visible = true,
        ZIndex = 203,
    }, { pointerEvents = false })
    controls.sliderFill = surface:create("Square", {
        Color = COLORS.accent,
        Filled = true,
        Visible = true,
        ZIndex = 204,
    }, { pointerEvents = false })
    controls.sliderKnob = surface:create("Circle", {
        Color = COLORS.text,
        Filled = true,
        NumSides = 32,
        Radius = 7,
        Visible = true,
        ZIndex = 205,
    }, { pointerEvents = false })
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
                fill = surface:create("Square", {
                    Color = COLORS.accent,
                    Filled = true,
                    Visible = true,
                    ZIndex = 204,
                }, { pointerEvents = false }),
                hit = self:_capture(surface:create("Square", {
                    Color = COLORS.panel,
                    Filled = true,
                    Size = Vector2.new(276, 24),
                    Transparency = 0,
                    Visible = true,
                    ZIndex = 202,
                })),
                knob = surface:create("Circle", {
                    Color = COLORS.text,
                    Filled = true,
                    NumSides = 32,
                    Radius = 6,
                    Visible = true,
                    ZIndex = 205,
                }, { pointerEvents = false }),
                label = self:_text({
                    Color = COLORS.text,
                    Size = 13,
                    Text = definition.label,
                    ZIndex = 203,
                }),
                track = surface:create("Square", {
                    Color = COLORS.border,
                    Filled = true,
                    Size = Vector2.new(276, 4),
                    Visible = true,
                    ZIndex = 203,
                }, { pointerEvents = false }),
                value = self:_text({
                    Center = true,
                    Color = COLORS.secondary,
                    Size = 12,
                    Text = "0%",
                    ZIndex = 203,
                }),
            }
            local function setRate(point)
                local alpha = math.clamp((point.X - control.hit.Position.X) / 276, 0, 1)
                self.context.setRate(definition.id, math.round(alpha * 100))
            end
            control.hit:on("pointerdown", function(_node, point)
                setRate(point)
            end)
            control.hit:on("drag", function(_node, point)
                setRate(point)
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
        local row = self:_capture(surface:create("Square", {
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
            row = row,
            label = label,
            marker = marker,
            value = value,
        }
                end
            end
        end
    end

    controls.cosmetics = {
        header = self:_capture(surface:create("Square", {
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
        weaponMode = self:_capture(surface:create("Square", {
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
        gloveMode = self:_capture(surface:create("Square", {
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
        next = self:_capture(surface:create("Square", {
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
        previous = self:_capture(surface:create("Square", {
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
        reset = self:_capture(surface:create("Square", {
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
        statTrak = self:_capture(surface:create("Square", {
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
            Transparency = 0,
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
                Transparency = 0,
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

    local function setFov(point)
        local state = self.context.store:Get()
        if state.settings.fullScreenAim then
            return
        end
        local alpha = math.clamp((point.X - self.sliderStartX) / 276, 0, 1)
        local settings = state.settings
        self.context.setFov(settings.minimumFov + (settings.maximumFov - settings.minimumFov) * alpha)
    end
    controls.sliderHit:on("pointerdown", function(_node, point)
        setFov(point)
    end)
    controls.sliderHit:on("drag", function(_node, point)
        setFov(point)
    end)
    local function setWear(point)
        local alpha = math.clamp((point.X - self.wearStartX) / 276, 0, 1)
        if self.context.store:Get().cosmeticMode == "gloves" then
            self.context.setGloveWear(alpha)
        else
            self.context.setWear(alpha)
        end
    end
    controls.cosmetics.wearHit:on("pointerdown", function(_node, point)
        setWear(point)
    end)
    controls.cosmetics.wearHit:on("drag", function(_node, point)
        setWear(point)
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
        channel.hit:on("pointerdown", function(_node, point)
            setColor(point)
        end)
        channel.hit:on("drag", function(_node, point)
            setColor(point)
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
    controls.title.Position = Vector2.new(x + 12, y + 12)
    controls.hideButton.Position = Vector2.new(x + 230, y + 7)
    controls.hideLabel.Position = Vector2.new(x + 259, y + 12)
    controls.status.Position = Vector2.new(x + 12, y + 34)
    controls.weaponLabel.Position = Vector2.new(x + 12, y + 58)
    controls.weaponValue.Position = Vector2.new(x + 240, y + 58)
    controls.fovLabel.Position = Vector2.new(x + 12, y + 84)
    controls.fovValue.Position = Vector2.new(x + 232, y + 84)
    controls.fovModeButton.Position = Vector2.new(x + 176, y + 78)

    self.sliderStartX = x + 12
    controls.sliderHit.Position = Vector2.new(x + 12, y + 100)
    controls.sliderTrack.Position = Vector2.new(x + 12, y + 112)
    controls.sliderFill.Position = controls.sliderTrack.Position

    local sectionY = y + 138
    for _, definition in ipairs(RATE_CONTROLS) do
        local control = controls.rates[definition.id]
        if control then
            control.label.Position = Vector2.new(x + 12, sectionY)
            control.value.Position = Vector2.new(x + 264, sectionY)
            control.hit.Position = Vector2.new(x + 12, sectionY + 12)
            control.track.Position = Vector2.new(x + 12, sectionY + 21)
            control.fill.Position = control.track.Position
            sectionY = sectionY + 34
        end
    end
    for _, group in ipairs(OPTION_GROUPS) do
        local section = controls.sections[group.id]
        if section then
        section.label.Position = Vector2.new(x + 12, sectionY)
        section.line.Position = Vector2.new(x + 70, sectionY + 7)
        sectionY = sectionY + 20
        for _, optionRow in ipairs(group.rows) do
            local column = 0
            for _, optionName in ipairs(optionRow) do
                local option = controls.options[optionName]
                if option then
                column = column + 1
                local rowX = x + 12 + (column - 1) * 142
                option.row.Position = Vector2.new(rowX, sectionY)
                if option.marker then
                    option.marker.Position = Vector2.new(rowX + 8, sectionY + 8)
                end
                option.label.Position =
                    Vector2.new(rowX + (option.marker and 15 or 9), sectionY + 8)
                option.value.Position = Vector2.new(rowX + 112, sectionY + 8)
                end
            end
            if column > 0 then
                sectionY = sectionY + 34
            end
        end
        sectionY = sectionY + 6
        end
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
    cosmetics.previous.Position = Vector2.new(x + 12, sectionY + 58)
    cosmetics.previousLabel.Position = Vector2.new(x + 27, sectionY + 65)
    cosmetics.skinBackground.Position = Vector2.new(x + 46, sectionY + 58)
    cosmetics.skinName.Position = Vector2.new(x + 150, sectionY + 66)
    cosmetics.next.Position = Vector2.new(x + 258, sectionY + 58)
    cosmetics.nextLabel.Position = Vector2.new(x + 273, sectionY + 65)
    cosmetics.wearLabel.Position = Vector2.new(x + 12, sectionY + 94)
    cosmetics.wearValue.Position = Vector2.new(x + 264, sectionY + 94)
    self.wearStartX = x + 12
    cosmetics.wearHit.Position = Vector2.new(x + 12, sectionY + 106)
    cosmetics.wearTrack.Position = Vector2.new(x + 12, sectionY + 115)
    cosmetics.wearFill.Position = cosmetics.wearTrack.Position
    cosmetics.statTrak.Position = Vector2.new(x + 12, sectionY + 132)
    cosmetics.statTrakLabel.Position = Vector2.new(x + 21, sectionY + 140)
    cosmetics.statTrakValue.Position = Vector2.new(x + 124, sectionY + 140)
    cosmetics.reset.Position = Vector2.new(x + 154, sectionY + 132)
    cosmetics.resetLabel.Position = Vector2.new(x + 163, sectionY + 140)
    self.colorStartX = x + 32
    for index, channelName in ipairs({ "r", "g", "b" }) do
        local channel = cosmetics.colorChannels[channelName]
        local channelY = sectionY + 166 + (index - 1) * 24
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
        "title",
        "hideButton",
        "hideLabel",
        "status",
        "weaponLabel",
        "weaponValue",
        "fovLabel",
        "fovValue",
        "fovModeButton",
        "sliderHit",
        "sliderTrack",
        "sliderFill",
        "sliderKnob",
    }) do
        controls[name].Visible = visible
    end
    for _, option in pairs(controls.options) do
        setVisible(option, visible)
    end
    for _, rate in pairs(controls.rates) do
        setVisible(rate, visible)
    end
    for _, section in pairs(controls.sections) do
        setVisible(section, visible)
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
            else
                node.Visible = cosmeticsVisible and self.cosmeticsOpen == true
            end
        end
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

    self:_layout()
    local settings = state.settings
    local controls = self.controls
    controls.status.Text = state.status or "Ready"
    controls.status.Color = state.error and COLORS.danger or COLORS.secondary
    controls.weaponValue.Text = state.activeWeapon or "Spectating"
    controls.weaponValue.Color = state.activeWeapon and COLORS.accent or COLORS.secondary
    self.cosmeticsOpen = state.cosmeticsOpen == true

    for optionName, option in pairs(controls.options) do
        local enabled = settings[optionName] == true
        local parent = OPTION_PARENTS[optionName]
        local supported = self.optionSupport[optionName] ~= false
        local available = supported and (not parent or settings[parent] == true)
        option.row.Color = available and (enabled and COLORS.accentSurface or COLORS.elevated) or COLORS.panel
        option.label.Color = available and COLORS.text or COLORS.secondary
        if option.marker then
            option.marker.Color = available and COLORS.accent or COLORS.border
        end
        option.value.Color = available and enabled and COLORS.accent or COLORS.secondary
        option.value.Text = not supported and "N/A"
            or (not available and enabled and "Standby" or (enabled and "On" or "Off"))
    end

    for _, definition in ipairs(RATE_CONTROLS) do
        local control = controls.rates[definition.id]
        if control then
            local value = math.clamp(settings[definition.id] or 0, 0, 100)
            local alpha = value / 100
            control.fill.Size = Vector2.new(276 * alpha, 4)
            control.knob.Position =
                Vector2.new(control.track.Position.X + 276 * alpha, control.track.Position.Y + 2)
            control.value.Text = ("%d%%"):format(math.round(value))
        end
    end

    local alpha = (settings.fov - settings.minimumFov) / (settings.maximumFov - settings.minimumFov)
    controls.sliderFill.Size = Vector2.new(276 * alpha, 4)
    controls.sliderKnob.Position = Vector2.new(self.sliderStartX + 276 * alpha, controls.sliderTrack.Position.Y + 2)
    controls.fovModeButton.Color = settings.fullScreenAim and COLORS.accentSurface or COLORS.elevated
    controls.sliderFill.Color = settings.fullScreenAim and COLORS.border or COLORS.accent
    controls.sliderKnob.Color = settings.fullScreenAim and COLORS.secondary or COLORS.text
    controls.fovValue.Color = settings.fullScreenAim and COLORS.accent or COLORS.secondary
    controls.fovLabel.Text = ("FOV · %d px"):format(math.round(settings.fov))
    controls.fovValue.Text = settings.fullScreenAim and "Fullscreen On" or "Fullscreen Off"
    controls.fovCircle.Radius = settings.fov
    controls.fovCircle.Visible = settings.fovCircle ~= false and not settings.fullScreenAim

    local cosmeticMode = state.cosmeticMode == "gloves" and "gloves" or "weapon"
    local gloveColor = settings.gloveColorOverride
    self.gloveColorVisible = cosmeticMode == "gloves" and type(gloveColor) == "table"
    local collapsedHeight = (self.optionsPanelHeight or 560) + 36
    controls.panel.Size = Vector2.new(300, if self.cosmeticsSupported
        then (self.cosmeticsOpen
            and (collapsedHeight + (self.gloveColorVisible and 202 or 128))
            or collapsedHeight)
        else (self.optionsPanelHeight or 596))
    local cosmetics = cosmeticMode == "gloves" and (state.gloves or {}) or (state.cosmetics or {})
    local cosmeticControls = controls.cosmetics
    local minimumWear = cosmetics.minimumWear or 0
    local maximumWear = cosmetics.maximumWear or 1
    local wearRange = maximumWear - minimumWear
    local wearAlpha = wearRange > 0 and ((cosmetics.wear or minimumWear) - minimumWear) / wearRange or 0
    cosmeticControls.indicator.Text = self.cosmeticsOpen and "-" or "+"
    cosmeticControls.weaponMode.Color = cosmeticMode == "weapon" and COLORS.accentSurface or COLORS.elevated
    cosmeticControls.gloveMode.Color = cosmeticMode == "gloves" and COLORS.accentSurface or COLORS.elevated
    cosmeticControls.weaponModeLabel.Color = cosmeticMode == "weapon" and COLORS.accent or COLORS.text
    cosmeticControls.gloveModeLabel.Color = cosmeticMode == "gloves" and COLORS.accent or COLORS.text
    cosmeticControls.weaponModeLabel.Text =
        cosmeticMode == "weapon" and (cosmetics.weapon or "Weapon") or "Weapons"
    cosmeticControls.gloveModeLabel.Text =
        cosmeticMode == "gloves" and (cosmetics.weapon or "Gloves") or "Gloves"
    cosmeticControls.skinName.Text = cosmetics.skinLabel or cosmetics.skin or "Stock"
    cosmeticControls.wearValue.Text = ("%.2f"):format(cosmetics.wear or 0)
    cosmeticControls.wearFill.Size = Vector2.new(276 * wearAlpha, 4)
    cosmeticControls.wearKnob.Position =
        Vector2.new(self.wearStartX + 276 * wearAlpha, cosmeticControls.wearTrack.Position.Y + 2)
    local supportsStatTrak = cosmeticMode ~= "gloves" and cosmetics.supportsStatTrak == true
    local solidColor = cosmeticMode == "gloves" and type(gloveColor) == "table"
    cosmeticControls.statTrak.Color =
        solidColor and COLORS.accentSurface
        or (supportsStatTrak and (cosmetics.statTrak and COLORS.accentSurface or COLORS.elevated) or COLORS.elevated)
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
            ZIndex = 60,
        }, { pointerEvents = false }),
        name = self:_text({
            Center = true,
            Color = COLORS.text,
            Outline = true,
            Size = 13,
            Text = "",
            Visible = false,
            ZIndex = 61,
        }),
        healthTrack = self.surface:create("Square", {
            Color = COLORS.border,
            Filled = true,
            Visible = false,
            ZIndex = 61,
        }, { pointerEvents = false }),
        healthFill = self.surface:create("Square", {
            Color = COLORS.accent,
            Filled = true,
            Visible = false,
            ZIndex = 62,
        }, { pointerEvents = false }),
        weapon = self:_text({
            Center = true,
            Color = COLORS.secondary,
            Outline = true,
            Size = 12,
            Text = "",
            Visible = false,
            ZIndex = 61,
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
        if self.optionSupport.chams ~= false then
            for _faceIndex = 1, #BODY_CUBE_FACES do
                table.insert(
                    cube.faces,
                    self.surface:create("Quad", {
                        Color = COLORS.danger,
                        Filled = true,
                        Transparency = BODY_CUBE_OPACITY,
                        Visible = false,
                        ZIndex = 60,
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

function Overlay:render(observations, mousePosition)
    if self.destroyed then
        return
    end

    self.observations = observations
    local settings = self.context.store:Get().settings
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

            nodes.box.Position = bounds.position
            nodes.box.Size = bounds.size
            nodes.box.Color = color
            nodes.box.Visible = settings.boxes == true

            nodes.name.Position = Vector2.new(bounds.position.X + bounds.size.X * 0.5, bounds.position.Y - 15)
            nodes.name.Text = observation.player.Name
            nodes.name.Visible = settings.names == true

            local maximumHealth = math.max(observation.maxHealth or 100, 1)
            local healthFraction = math.clamp((observation.health or 0) / maximumHealth, 0, 1)
            local innerHeight = math.max(bounds.size.Y - 2, 0)
            local fillHeight = innerHeight * healthFraction
            nodes.healthTrack.Position = Vector2.new(bounds.position.X - 7, bounds.position.Y)
            nodes.healthTrack.Size = Vector2.new(4, bounds.size.Y)
            nodes.healthTrack.Visible = settings.health == true
            nodes.healthFill.Position =
                Vector2.new(bounds.position.X - 6, bounds.position.Y + 1 + innerHeight - fillHeight)
            nodes.healthFill.Size = Vector2.new(2, fillHeight)
            nodes.healthFill.Color = COLORS.danger:Lerp(COLORS.accent, healthFraction)
            nodes.healthFill.Visible = settings.health == true and fillHeight > 0

            nodes.weapon.Position = Vector2.new(
                bounds.position.X + bounds.size.X * 0.5,
                bounds.position.Y + bounds.size.Y + 3
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
    self.surface:destroy()
    table.clear(self.playerNodes)
end

return Overlay
