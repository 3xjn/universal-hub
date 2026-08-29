# RIVALS Unlock All Skins Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a persisted RIVALS Visuals toggle that exposes every released client skin while enabled and restores the previously equipped owned skin for each weapon when disabled.

**Architecture:** Reuse the hub's existing per-game JSON config for the toggle and a private restore snapshot. A small RIVALS feature temporarily overrides the live `CosmeticLibrary:OwnsCosmetic` client predicate only for non-hidden Skin entries, refreshes the native cosmetics UI through `ClientPlayerData:Replicate`, and uses the game's native `EquipCosmetic` remote path to restore the saved owned skin (or none) when the toggle turns off. On legacy enabled configs without a restore snapshot, derive a safe snapshot from currently equipped skins that the original ownership predicate confirms; unowned current skins fall back to none.

**Tech Stack:** Luau, Roblox `CosmeticLibrary`/`PlayerDataController`, existing Universal Hub JSON config, Lune contract tests.

---

### Task 1: Specify the reversible skin ownership runtime

**Files:**
- Create: `tests/rivals_skin_unlock_contracts.luau`
- Create: `games/rivals/features/SkinUnlock.lua`

**Step 1: Write the failing feature contract**

Create fakes for `CosmeticLibrary`, `PlayerDataController`, `CurrentData:Replicate`, and `EquipCosmetic:FireServer`. Cover these exact behaviors:

```lua
local unlock = SkinUnlock.new({
    cosmeticLibrary = cosmeticLibrary,
    playerDataController = playerDataController,
    equipCosmetic = equipCosmetic,
    onRestoreChanged = function(snapshot)
        persisted = snapshot
    end,
})

unlock:update({ unlockAllSkins = true, unlockAllSkinsRestore = {} })
assert(cosmeticLibrary:OwnsCosmetic(inventory, "Visible Skin", "Assault Rifle") == true)
assert(cosmeticLibrary:OwnsCosmetic(inventory, "Hidden Skin", "Assault Rifle") == false)
assert(cosmeticLibrary:OwnsCosmetic(inventory, "Wrap", "Assault Rifle") == false)
assert(persisted["Assault Rifle"] == "Owned Skin")

unlock:update({ unlockAllSkins = false, unlockAllSkinsRestore = persisted })
assert(cosmeticLibrary.OwnsCosmetic == originalOwnsCosmetic)
assert(equips[1].weapon == "Assault Rifle" and equips[1].skin == "Owned Skin")
```

Also assert that an equipped unowned skin is stored as `"NONE_COSMETIC"`, a pre-existing persisted snapshot is not overwritten on hub load, cosmetic inventory replication occurs after enable/disable, and `stop()` restores only the temporary predicate without changing equipment or deleting the snapshot.

**Step 2: Run the test to verify it fails**

Run: `lune run tests/rivals_skin_unlock_contracts.luau`

Expected: FAIL because `games/rivals/features/SkinUnlock.lua` does not exist.

**Step 3: Implement the minimal runtime**

Implement `SkinUnlock.new(options)`, `SkinUnlock:update(settings)`, and `SkinUnlock:stop()` with this state machine:

```lua
local enabled = settings.unlockAllSkins == true
if enabled == self.enabled then
    return
end

if enabled then
    self.enabled = true
    self.restore = next(settings.unlockAllSkinsRestore or {})
            and settings.unlockAllSkinsRestore
        or self:_snapshotOwnedSkins()
    self.cosmeticLibrary.OwnsCosmetic = self.unlockOwnsCosmetic
    self.onRestoreChanged(self.restore)
else
    self.enabled = false
    self.cosmeticLibrary.OwnsCosmetic = self.originalOwnsCosmetic
    self:_restoreSkins(settings.unlockAllSkinsRestore or self.restore)
    self.onRestoreChanged({})
end
self:_refreshCosmetics()
```

The replacement ownership predicate must return true only when `Cosmetics[name]` has `Type == "Skin"` and `Hidden ~= true`; every other query delegates to the captured native predicate. Snapshot only equipped skin names accepted by that native predicate, and record `"NONE_COSMETIC"` for no skin or an unowned skin. Restore only weapons present in the current `WeaponInventory`, skip already-correct selections, and call:

```lua
equipCosmetic:FireServer(weapon.Name, "Skin", savedName, {})
```

`stop()` restores the captured predicate and refreshes the native cosmetics UI, but does not restore equipment because hot reload must preserve an enabled session.

**Step 4: Re-run the focused contract**

Run: `lune run tests/rivals_skin_unlock_contracts.luau`

Expected: PASS and print `rivals-skin-unlock-contracts-ok`.

### Task 2: Register and present the persisted option

**Files:**
- Modify: `games/rivals/Definition.lua:2-15,16-53,88-131`
- Modify: `games/rivals/Presentation.lua:112-131`
- Modify: `tests/presentation_host_contracts.luau:93-137`
- Modify: `tests/rivals_skin_unlock_contracts.luau`

**Step 1: Extend the failing contract**

Assert:

```lua
assert(Definition.defaults.unlockAllSkins == false)
assert(type(Definition.defaults.unlockAllSkinsRestore) == "table")
assert(table.find(Definition.features.capabilities, "unlockAllSkins"))
assert(table.find(Definition.sources, "games/rivals/features/SkinUnlock"))
```

Update the RIVALS presentation sequence to expect:

```lua
"option:visuals:6:unlockAllSkins:Unlock All Skins"
```

before Utility ESP, moving Utility ESP to row 7.

**Step 2: Run tests to verify they fail**

Run:

```text
lune run tests/rivals_skin_unlock_contracts.luau
lune run tests/presentation_host_contracts.luau
```

Expected: FAIL because the definition and presentation do not expose the setting.

**Step 3: Add the setting and option**

Add these defaults:

```lua
unlockAllSkins = false,
unlockAllSkinsRestore = {},
```

Add `"unlockAllSkins"` to capabilities, add `"games/rivals/features/SkinUnlock"` to the closed source list, and mount this under the existing Visuals grid:

```lua
host:option("visuals", 6, "unlockAllSkins", "Unlock All Skins")
host:option("visuals", 7, "utilityEsp", "Utility ESP")
```

Do not enable the generic cosmetics panel; this feature operates the native RIVALS equipment UI.

**Step 4: Re-run the contracts**

Expected: both contracts PASS.

### Task 3: Wire the feature into the RIVALS adapter and config lifecycle

**Files:**
- Modify: `games/rivals/Adapter.lua:1-35,219-235,287-312,2185-2229,2264-2304`
- Modify: `tests/rivals_skin_unlock_contracts.luau`

**Step 1: Add adapter lifecycle assertions**

Use source-level assertions to verify the adapter imports `SkinUnlock`, calls `skinUnlock:update(settings)` from the store reconciliation path, and calls `skinUnlock:stop()` during adapter shutdown. Keep runtime behavior in the pure feature contract rather than expanding the already-large adapter harness.

**Step 2: Run the focused contract to verify it fails**

Run: `lune run tests/rivals_skin_unlock_contracts.luau`

Expected: FAIL because Adapter does not wire the feature.

**Step 3: Inject live native dependencies**

Import `SkinUnlock` at the adapter boundary. In the existing live-only dependency block, reuse the already loaded `ReplicatedStorage.Modules` and load `CosmeticLibrary`. Construct the feature when both `CosmeticLibrary` and `PlayerDataController` exist:

```lua
local skinUnlock = SkinUnlock.new({
    cosmeticLibrary = CosmeticLibrary,
    playerDataController = PlayerDataController,
    equipCosmetic = game:GetService("ReplicatedStorage").Remotes.Data.EquipCosmetic,
    onRestoreChanged = function(snapshot)
        local state = store:Get()
        local updated = table.clone(state.settings)
        updated.unlockAllSkinsRestore = snapshot
        store:Patch({ settings = updated })
        if type(context.settingsChanged) == "function" then
            context.settingsChanged(updated)
        end
    end,
})
```

Call `skinUnlock:update(settings)` near the start of `reconcileFrameLifecycle`, before deciding whether frame work is needed. The option must not force a render-step connection. Call `skinUnlock:stop()` in `self.stop()`.

For injected adapter contracts that intentionally omit live player-data dependencies, leave `skinUnlock` nil; the standalone feature contract owns the behavior seam.

**Step 4: Re-run the focused contract**

Run: `lune run tests/rivals_skin_unlock_contracts.luau`

Expected: PASS.

### Task 4: Verify compatibility and repository health

**Files:**
- Verify: `games/rivals/features/SkinUnlock.lua`
- Verify: `games/rivals/Adapter.lua`
- Verify: `games/rivals/Definition.lua`
- Verify: `games/rivals/Presentation.lua`
- Verify: `tests/rivals_skin_unlock_contracts.luau`
- Verify: `tests/presentation_host_contracts.luau`

**Step 1: Format changed Luau files**

Run:

```text
stylua games/rivals/features/SkinUnlock.lua games/rivals/Adapter.lua games/rivals/Definition.lua games/rivals/Presentation.lua tests/rivals_skin_unlock_contracts.luau tests/presentation_host_contracts.luau
```

Expected: exit code 0.

**Step 2: Run focused contracts**

Run:

```text
lune run tests/rivals_skin_unlock_contracts.luau
lune run tests/presentation_host_contracts.luau
lune run tests/rivals_adapter_contracts.luau
lune run tests/store_contracts.luau
lune run tests/config_contracts.luau
```

Expected: every command exits 0 with its `*-ok` marker.

**Step 3: Run the full repository gate**

Run:

```text
$env:HYDROXIDE_ROOT='C:/git/hydroxide'; & 'C:/Program Files/Git/bin/bash.exe' scripts/check.sh
```

Expected: `universal-hub-check-ok`.

**Step 4: Perform read-only live validation**

In the connected authorized RIVALS client, verify the discovered seams still exist: `CosmeticLibrary.OwnsCosmetic`, `PlayerDataController.CurrentData:Replicate`, and `ReplicatedStorage.Remotes.Data.EquipCosmetic`. Do not toggle or equip a skin during automated validation; report state-changing QA as a manual follow-up.

**Step 5: Review the diff without committing**

Confirm only the planned RIVALS feature, registration, presentation, contract, and plan files changed by this work. Preserve all pre-existing dirty worktree changes. Do not commit unless the user explicitly requests it.
