# RIVALS Gun Game Targeting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Gun Game aim automation ignore replicated spawn invincibility and treat its final Knife as the existing backstab weapon without changing other RIVALS modes.

**Architecture:** Add a small, testable Gun Game place predicate and an entity-replica invincibility predicate to the RIVALS adapter. Compose those predicates into the adapter's shared target eligibility callback so Camera Aim, Silent Aim, Trigger Bot, and knife acquisition all receive the same exclusion. Run the existing end-to-end Knife backstab contract under the Gun Game place so the final weapon remains on the established path without duplicating or regressing normal Knife behavior.

**Tech Stack:** Luau, Roblox client replicas, Lune contract tests.

---

### Task 1: Lock the mode and immunity contracts

**Files:**
- Modify: `tests/rivals_adapter_contracts.luau`

**Step 1: Write failing unit contracts**

Add assertions covering:

```lua
assert(Rivals.isGunGamePlace(133215910299950) == true)
assert(Rivals.isGunGamePlace(17625359962) == false)
assert(Rivals.entityIsInvincible({ Data = { IsInvincible = true } }) == true)
assert(Rivals.entityIsInvincible({ Data = { IsInvincible = false } }) == false)
```

Also cover replicas exposing `Get("IsInvincible")`, including a failed getter.

**Step 2: Run the focused contract**

Run: `lune run tests/rivals_adapter_contracts.luau`

Expected: FAIL because the exported predicates do not exist.

### Task 2: Implement shared Gun Game target eligibility

**Files:**
- Modify: `games/rivals/Adapter.lua`
- Test: `tests/rivals_adapter_contracts.luau`

**Step 1: Add minimal predicates**

Implement:

```lua
local GUN_GAME_PLACE_ID = 133215910299950

function Rivals.isGunGamePlace(placeId)
    return placeId == GUN_GAME_PLACE_ID
end

function Rivals.entityIsInvincible(entity)
    if type(entity) ~= "table" then
        return false
    end
    if type(entity.Get) == "function" then
        local ok, value = pcall(entity.Get, entity, "IsInvincible")
        if ok then
            return value == true
        end
    end
    local data = entity.Data
    return type(data) == "table" and data.IsInvincible == true
end
```

**Step 2: Compose eligibility inside the adapter**

In the adapter-local `isTargetable`, retain normal opponent/ForceField checks and, only when `Rivals.isGunGamePlace(game.PlaceId)` is true, reject a player whose `fighterFor(player).Entity` is invincible.

This one callback must remain the eligibility source for Camera Aim, Silent Aim, Trigger Bot, Gunblade, and Knife/backstab selection.

**Step 3: Add integration assertions**

In the adapter harness, set the enemy entity's replicated `IsInvincible` field to true in Gun Game, render a frame, and assert that neither aim rotation nor trigger input occurs. Clear it and assert targeting resumes. Run the same state outside the Gun Game place and assert the new mode-specific check is inactive.

**Step 4: Run the focused contract**

Run: `lune run tests/rivals_adapter_contracts.luau`

Expected: PASS.

### Task 3: Lock the Gun Game final Knife behavior

**Files:**
- Test: `tests/rivals_adapter_contracts.luau`

**Step 1: Put the adapter harness in Gun Game**

Set the harness `game.PlaceId` to `133215910299950` and assert that the Knife portion is running under that verified place.

**Step 2: Preserve the existing integration assertions**

- Camera Aim chooses the backstab approach point.
- Silent Aim publishes that same backstab target.
- Trigger Bot dispatches secondary attack only when the backstab plan is ready.
- Knife approach suppresses Bunny Hop jumps while the backstab path is active.

The adapter already recognizes `WeaponPolicy.itemName(item) == "Knife"` and shares that branch across all three aim systems, so no second Gun Game-specific Knife implementation is needed.

**Step 3: Run verification**

Run: `lune run tests/rivals_adapter_contracts.luau`

Expected: PASS.

### Task 4: Full verification

**Files:**
- Verify: `games/rivals/Adapter.lua`
- Verify: `tests/rivals_adapter_contracts.luau`

**Step 1: Run repository checks**

Run: `bash scripts/check.sh`

Expected: formatting, static analysis, and all contracts PASS.

**Step 2: Review the diff**

Confirm the change is limited to the RIVALS adapter, its contracts, and this plan. Do not commit unless the user explicitly requests it.
