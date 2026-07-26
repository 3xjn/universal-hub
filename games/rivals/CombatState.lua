local CombatState = {}

local function value(replica, key)
    if type(replica) ~= "table" then
        return nil
    end

    if type(replica.Get) == "function" then
        return replica:Get(key)
    end

    local data = replica.Data
    return type(data) == "table" and data[key] or nil
end

function CombatState.isCombatEligible(fighter, duel, loadoutOpen)
    if loadoutOpen == true then
        return false
    end

    if value(fighter, "IsInShootingRange") == true then
        return true
    end

    return value(fighter, "IsInDuel") == true
        and value(duel, "Status") == "RoundStarted"
end

return CombatState
