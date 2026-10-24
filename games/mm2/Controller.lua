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

local Agent = importDependency("games/mm2/Agent", "./Agent")
local Clearance = importDependency("games/mm2/Clearance", "./Clearance")
local Jumps = importDependency("games/mm2/Jumps", "./Jumps")
local Ladders = importDependency("games/mm2/Ladders", "./Ladders")
local Route = importDependency("games/mm2/Route", "./Route")
local Slopes = importDependency("games/mm2/Slopes", "./Slopes")

local Controller = {}

Controller.Agent = Agent
Controller.Clearance = Clearance
Controller.Jumps = Jumps
Controller.Ladders = Ladders
Controller.Route = Route
Controller.Slopes = Slopes

function Controller.syncProfile(move, grounded)
    if move.profile and grounded ~= true then
        return move.profile
    end
    move.profile = Agent.profile(move.character, move.humanoid, move.root)
    return move.profile
end

function Controller.syncTool(move)
    local tool = Agent.equippedTool(move.character)
    if move.tool == tool then
        return
    end
    Agent.restoreCollision(move.toolCollision)
    move.tool = tool
    move.toolCollision = tool and Agent.suspendCollision(tool) or nil
end

function Controller.release(move)
    Agent.restoreCollision(move.toolCollision)
    move.tool = nil
    move.toolCollision = nil
end

function Controller.feet(move)
    local profile = move.profile or Controller.syncProfile(move, true)
    return move.root.Position - Vector3.new(0, profile.footOffset, 0)
end

function Controller.parameters(move, goalRaised, costs)
    local profile = move.profile or Controller.syncProfile(move, true)
    return Route.modes(profile, goalRaised, costs)
end

function Controller.decide(state)
    local profile = state.profile
    local desired = typeof(state.desired) == "Vector3" and state.desired or Vector3.zero
    local ladder = state.ladder
    if type(ladder) == "table" and ladder.near == true then
        local intent = Ladders.intent(ladder)
        if intent == "up" or intent == "down" or intent == "dismount" then
            local direction, jump = Ladders.direction(intent, ladder.toward, ladder.exitFlat, ladder.lipHop)
            return {
                direction = direction,
                intent = intent,
                jump = jump,
                kind = "climb",
            }
        end
    end
    local slope = state.slope
    if slope == "ramp" or slope == "stairs" or slope == "flat" then
        local direction = desired
        local passage = state.passage
        if type(passage) == "table" and profile then
            local offset = Clearance.centerOffset(passage.left, passage.right, profile.bodySize.X)
            if offset ~= 0 then
                direction = Clearance.applyOffset(desired, passage.side, offset)
            end
        end
        return {
            direction = direction,
            jump = false,
            kind = "walk",
        }
    end
    if Jumps.accept(state.box) then
        return {
            direction = desired,
            jump = true,
            kind = "jump",
            landing = state.box.landing,
        }
    end
    return {
        direction = desired,
        jump = false,
        kind = "blocked",
    }
end

return Controller
