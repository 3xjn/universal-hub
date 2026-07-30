# RIVALS Gun Game Priority and Final Knife Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** In RIVALS Gun Game, prioritize the lowest-health eligible opponent and recognize the mode's special final Knife as the normal backstab-capable Knife for Camera Aim, Silent Aim, and Trigger Bot.

**Architecture:** Add small pure policy helpers for Gun Game target ranking and Knife-family recognition, then route the existing selection and backstab branches through those helpers only in the Gun Game place. Preserve the existing visibility, FOV, immunity, range, damage, and rear-angle validators; only the ordering and final-weapon identity change.

**Tech Stack:** Luau, Lune contract tests, live Volt read-only inspection, existing RIVALS adapter and weapon policy.

---

### Task 1: Lock the target-order contract

**Files:**
- Modify: `tests/rivals_adapter_contracts.luau`
- Modify: `games/rivals/Adapter.lua`

**Step 1: Write the failing test**

Add observations with different health values and assert that the Gun Game selector chooses the lowest-health candidate accepted by the existing eligibility callback. Assert that ties retain the existing nearest/crosshair ordering and that rejected or dead observations are ignored.

**Step 2: Run test to verify it fails**

Run: `lune run tests/rivals_adapter_contracts.luau`

Expected: FAIL because the low-health selector does not exist.

**Step 3: Write minimal implementation**

Add a pure selector that validates each observation through the existing one-candidate selection path, keeps only the lowest positive health tier, and uses the current nearest selector as its tie-breaker. Invoke it only when `Rivals.isGunGamePlace(game.PlaceId)`; keep target-lock selection unchanged elsewhere.

**Step 4: Run test to verify it passes**

Run: `lune run tests/rivals_adapter_contracts.luau`

Expected: `rivals-adapter-contracts-ok`

### Task 2: Recognize the special final Knife

**Files:**
- Modify: `tests/rivals_adapter_contracts.luau`
- Modify: `games/rivals/WeaponPolicy.lua`
- Modify: `games/rivals/Adapter.lua`

**Step 1: Write the failing test**

Add a final-weapon fixture using the live Gun Game identity and assert that Gun Game routes it through Knife Camera Aim, Silent Aim, rear-position planning, and the right-click Trigger Bot action. Assert the alias does not change unrelated RIVALS weapons.

**Step 2: Run test to verify it fails**

Run: `lune run tests/rivals_adapter_contracts.luau`

Expected: FAIL because the live final-weapon identity is not recognized as Knife.

**Step 3: Write minimal implementation**

Add a Gun Game-only Knife-family predicate based on the verified live item identity. Replace literal `itemName == "Knife"` branches in aiming, triggering, and Knife movement suppression with the predicate while retaining `backstabTriggerReady` as the final right-click validator.

**Step 4: Run test to verify it passes**

Run: `lune run tests/rivals_adapter_contracts.luau`

Expected: `rivals-adapter-contracts-ok`

### Task 3: Verify and reload

**Files:**
- Test: `tests/rivals_adapter_contracts.luau`
- Test: `tests/overlay_contracts.luau`

**Step 1: Run focused and full checks**

Run: `lune run tests/rivals_adapter_contracts.luau`

Run: `HYDROXIDE_ROOT=C:/git/hydroxide scripts/check.sh`

Expected: all contracts end in `-ok`.

**Step 2: Sync live source**

Copy only the changed runtime files into Volt's `universal-hub/local` workspace and verify source/target hashes match.

**Step 3: Reload and inspect**

Reload the Hub, verify the Gun Game adapter is active, confirm the low-health selector and final-Knife predicate are present, and inspect current settings. Do not synthesize an attack during verification.
