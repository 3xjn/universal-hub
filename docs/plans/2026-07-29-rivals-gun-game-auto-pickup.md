# RIVALS Gun Game Auto Pickup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an opt-in, Gun Game-only automatic collector for replicated `Health` and `AmmoBalanced` drops.

**Architecture:** Identify the verified direct `Workspace` `_drop` parts by their `Health` or `AmmoBalanced` model child, then synthesize the normal begin/end touch pair against the local character root through an injected executor function. Scan only during an active Gun Game match, collect only when the corresponding resource is useful, and throttle attempts per drop. Expose the toggle only when both the Gun Game place and executor touch support are present.

**Tech Stack:** Luau, Roblox replicated instances, executor `firetouchinterest`, Lune contract tests.

---

### Task 1: Lock pickup identity and eligibility

**Files:**
- Modify: `tests/rivals_adapter_contracts.luau`
- Modify: `games/rivals/Adapter.lua`

**Step 1: Write failing tests**

Cover:

```lua
assert(Rivals.pickupType(healthDrop) == "Health")
assert(Rivals.pickupType(ammoDrop) == "AmmoBalanced")
assert(Rivals.pickupType(unrelatedPart) == nil)
```

Add health eligibility tests for damaged/full fighters and ammo eligibility tests for depleted/full magazine and reserve values.

**Step 2: Run the focused contract**

Run: `lune run tests/rivals_adapter_contracts.luau`

Expected: FAIL because the pickup helpers do not exist.

**Step 3: Implement the helpers**

Add `Rivals.pickupType(instance)` and `Rivals.shouldCollectPickup(kind, fighter)` with exact model-name checks and no fuzzy matching.

**Step 4: Re-run the focused contract**

Expected: the helper tests PASS.

### Task 2: Add throttled automatic collection

**Files:**
- Modify: `games/rivals/Adapter.lua`
- Modify: `tests/rivals_adapter_contracts.luau`
- Modify: `init.lua`

**Step 1: Add an integration harness**

Inject a fake `fireTouchInterest`, enable `autoPickup`, and provide verified health/ammo drop stubs through `Workspace:GetChildren()`. Assert each eligible drop receives exactly:

```lua
fireTouchInterest(characterRoot, drop, 1)
task.wait()
fireTouchInterest(characterRoot, drop, 0)
```

Assert full resources, disabled settings, unsupported executors, and non-Gun-Game places do not dispatch touches.

**Step 2: Implement the scan**

Inside the RIVALS render loop:

- Require Gun Game place `133215910299950`.
- Require `settings.autoPickup == true`.
- Require an active local fighter in combat.
- Scan direct Workspace children no faster than every 0.1 seconds.
- Retry a surviving eligible drop no faster than every 0.5 seconds.
- Use weak Instance keys for attempt timestamps.
- Follow Volt's documented `1 = Touched`, scheduler step, `0 = TouchEnded` sequence.
- Never move the player or pickup and never invoke a RemoteEvent.

**Step 3: Inject executor support**

Pass `getgenv().firetouchinterest` into the adapter as `fireTouchInterest`.

**Step 4: Run the focused contract**

Run: `lune run tests/rivals_adapter_contracts.luau`

Expected: PASS.

### Task 3: Add the Gun Game-only toggle

**Files:**
- Modify: `games/rivals/Adapter.lua`
- Modify: `init.lua`
- Modify: `modules/Overlay.lua`
- Modify: `tests/rivals_adapter_contracts.luau`
- Modify: `tests/overlay_contracts.luau`

**Step 1: Add the setting**

Add `autoPickup = false` to defaults and `"Auto Pickup"` to the WORLD option group.

**Step 2: Filter capability visibility**

Add `Rivals.capabilitiesFor(context)`. Include `autoPickup` only when:

```lua
context.placeId == 133215910299950
    and context.fireTouchInterestAvailable == true
```

Use the filtered capabilities when constructing the overlay. Other games and other RIVALS modes must not show the toggle.

**Step 3: Add UI contracts**

Assert the option is visible for supported Gun Game context and absent for normal RIVALS or unsupported executor context.

**Step 4: Run contracts**

Run:

```text
lune run tests/rivals_adapter_contracts.luau
lune run tests/overlay_contracts.luau
```

Expected: PASS.

### Task 4: Full verification

**Files:**
- Verify all modified files.

**Step 1: Run repository checks**

Run with the configured Hydroxide definitions:

```text
HYDROXIDE_ROOT=C:/git/hydroxide "C:/Program Files/Git/bin/bash.exe" scripts/check.sh
```

Expected: `universal-hub-check-ok`.

**Step 2: Review the diff**

Confirm no movement, teleport, RemoteEvent, loader, or unrelated game changes were introduced. Do not commit unless the user explicitly requests it.
