local SilentAim = {}
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
