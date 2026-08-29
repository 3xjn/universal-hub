local ScopedAccuracy = require("../features/ScopedAccuracy")
local ShotPresentation = require("../features/ShotPresentation")
local SkipBlocks = require("../features/SkipBlocks")
local HookRuntime = {}
HookRuntime.__index = HookRuntime

local function supports(capabilities, capability)
    return table.find(capabilities or {}, capability) ~= nil
end

local NullPresentation = {}
function NullPresentation:refreshHook() end
function NullPresentation:clear() end
function NullPresentation:setPassthrough() end
function NullPresentation:update()
    return false
end
function NullPresentation:stageFlick()
    return false
end
function NullPresentation:getPresentedTarget()
    return nil
end
function NullPresentation:stop() end

local NullScoped = {}
function NullScoped:refreshHook() end
function NullScoped:stop() end

local NullSkip = {}
function NullSkip:refreshHook() end
function NullSkip:stop() end

function HookRuntime.new(options)
    local wantsShotAim = supports(options.capabilities, "shotAim")
        or supports(options.capabilities, "flickProjectiles")
    local wantsScoped = supports(options.capabilities, "alwaysScoped")
    local wantsSkip = supports(options.capabilities, "skipDeflect")
    if wantsShotAim or wantsScoped or wantsSkip then
        assert(options.hookFunction, "enabled RIVALS hook features require hookfunction")
        assert(options.restoreFunction, "enabled RIVALS hook features require restorefunction")
    end
    local presentation = NullPresentation
    if wantsShotAim then
        presentation = ShotPresentation.new(options.shotPresentation)
    end
    local scoped = NullScoped
    if wantsScoped then
        scoped = ScopedAccuracy.new(options.scopedAccuracy)
    end
    local skip = NullSkip
    if wantsSkip then
        skip = SkipBlocks.new(options.skipBlocks)
    end
    return setmetatable({ presentation = presentation, scoped = scoped, skip = skip }, HookRuntime)
end

function HookRuntime:refresh()
    self.presentation:refreshHook()
    self.scoped:refreshHook()
    self.skip:refreshHook()
end

function HookRuntime:stop()
    self.presentation:stop()
    self.scoped:stop()
    self.skip:stop()
end

return HookRuntime
