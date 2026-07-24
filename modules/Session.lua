local Session = {}
Session.__index = Session

function Session.new(options)
    assert(options and options.environment, "Hub session requires an environment")
    assert(options.store, "Hub session requires a store")
    assert(options.overlay, "Hub session requires an overlay")
    assert(options.adapter, "Hub session requires an adapter")

    local previous = options.environment.UniversalHubSession
    if previous and type(previous.stop) == "function" then
        previous:stop()
    end

    local self = setmetatable({
        adapter = options.adapter,
        environment = options.environment,
        overlay = options.overlay,
        resources = {},
        settingsChanged = options.settingsChanged,
        stopped = false,
        store = options.store,
    }, Session)

    self.environment.UniversalHubSession = self
    return self
end

function Session:Add(cleanup)
    assert(type(cleanup) == "function", "Hub cleanup must be a function")
    if self.stopped then
        cleanup()
        return cleanup
    end

    table.insert(self.resources, cleanup)
    return cleanup
end

function Session:patchSettings(patch)
    self.store:Patch({ settings = patch })
    if self.settingsChanged then
        self.settingsChanged(self.store:Get().settings)
    end
end

function Session:setOption(name, enabled)
    local state = self.store:Get()
    assert(state.settings[name] ~= nil, "Unknown hub option: " .. tostring(name))
    self:patchSettings({
        [name] = enabled == true,
    })
end

function Session:setFov(value)
    local state = self.store:Get()
    local settings = state.settings
    self:patchSettings({
        fov = math.clamp(value, settings.minimumFov, settings.maximumFov),
    })
end

function Session:setRate(name, value)
    assert(
        name == "aimSmoothness" or name == "headshotRate" or name == "missRate",
        "Unknown hub rate: " .. tostring(name)
    )
    self:patchSettings({
        [name] = math.clamp(math.round(value), 0, 100),
    })
end

function Session:setCosmeticsOpen(open)
    self.store:Patch({
        cosmeticsOpen = open == true,
    })
end

function Session:setCosmeticMode(mode)
    self.store:Patch({
        cosmeticMode = mode == "gloves" and "gloves" or "weapon",
    })
end

function Session:setMenuVisible(visible)
    self.store:Patch({
        menuVisible = visible == true,
    })
end

function Session:toggleMenu()
    self:setMenuVisible(not self.store:Get().menuVisible)
end

function Session:stop()
    if self.stopped then
        return
    end
    self.stopped = true

    for index = #self.resources, 1, -1 do
        pcall(self.resources[index])
    end
    table.clear(self.resources)

    if self.adapter and type(self.adapter.stop) == "function" then
        pcall(self.adapter.stop, self.adapter)
    end
    if self.overlay and type(self.overlay.destroy) == "function" then
        pcall(self.overlay.destroy, self.overlay)
    end
    if self.store and type(self.store.Destroy) == "function" then
        self.store:Destroy()
    end

    if self.environment.UniversalHubSession == self then
        self.environment.UniversalHubSession = nil
    end
end

Session.Destroy = Session.stop

return Session
