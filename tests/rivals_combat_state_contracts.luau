local CombatState = require("../games/rivals/CombatState")

local function replica(data)
    return {
        Data = data,
        Get = function(self, key)
            return self.Data[key]
        end,
    }
end

assert(
    CombatState.isCombatEligible(nil, nil) == false,
    "A missing local fighter must never be combat eligible"
)
assert(
    CombatState.isCombatEligible(replica({}), nil) == false,
    "A healthy lobby fighter must not be treated as combat"
)
assert(
    CombatState.isCombatEligible(
        replica({ IsInDuel = true, CanPickWeapons = false }),
        replica({ Status = "Voting", VoteOptions = { "MapA", "MapB" } })
    ) == false,
    "Map voting must not enable combat automation"
)
assert(
    CombatState.isCombatEligible(
        replica({ IsInDuel = true, CanPickWeapons = false }),
        replica({ Status = "RoundStarting" })
    ) == false,
    "The pre-round countdown must not enable combat automation"
)
assert(
    CombatState.isCombatEligible(
        replica({ IsInDuel = true, CanPickWeapons = false }),
        replica({ Status = "RoundStarted" })
    ) == true,
    "A started duel round must enable combat automation"
)
assert(
    CombatState.isCombatEligible(
        replica({ IsInDuel = true, CanPickWeapons = true }),
        replica({ Status = "RoundStarted" }),
        true
    ) == false,
    "Generic match loadout selection must suspend combat automation"
)
assert(
    CombatState.isCombatEligible(
        replica({ IsInShootingRange = true, CanPickWeapons = false }),
        nil
    ) == true,
    "The practice range must remain combat eligible without a duel object"
)
assert(
    CombatState.isCombatEligible(
        replica({ IsInShootingRange = true, CanPickWeapons = true }),
        nil,
        true
    ) == false,
    "Practice-range loadout selection must suspend combat automation"
)
assert(
    CombatState.isCombatEligible(
        replica({ IsInShootingRange = true, CanPickWeapons = true }),
        nil,
        false
    ) == true,
    "Practice-range weapon-pick permission must not suspend combat after the page closes"
)

print("rivals-combat-state-contracts-ok")
