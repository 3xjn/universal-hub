# RIVALS Adapter Guide

This directory owns Universal Hub's RIVALS integration. Read this file before
opening the implementation. Start with the module named for the behavior you
need; read `Adapter.lua` only when changing orchestration or a cross-module
flow.

## Runtime shape

`init.lua` imports these modules and injects them into `Adapter.new(context)`.
`hub.lua` must also list every remotely loaded source. Keep both import lists
in sync when adding, renaming, or removing a module.

The per-frame flow is:

1. `Adapter` reads the live RIVALS controllers and combat state.
2. It publishes player and utility observations to the shared store/overlay.
3. `Targeting` selects or retains a target and applies head/miss policy.
4. `ProjectileAim` optionally replaces the direct aim point with a trajectory.
5. Camera Aim updates the logical camera immediately. Silent Aim promotes the
   target only after `ShotPresentation` has staged the matching native camera
   frame.
6. `ScopedAccuracy` optionally reports eligible native Gun shots as scoped
   without changing the user's ADS/FOV state.
7. Trigger Bot evaluates that same target, then `WeaponPolicy` decides whether
   and how the equipped weapon may act.
8. `Movement` and `Effects` update independently under the same combat gates.

## Module map

- `Adapter.lua`
  - RIVALS manifest and capabilities.
  - Live controller discovery and dependency wiring.
  - Observation refresh, target retention, per-frame orchestration, input
    dispatch, and weapon-specific coordination.
  - This is the integration layer, not the home for reusable ballistics,
    targeting, effects, movement, or weapon policy.
- `CombatState.lua`
  - The single reusable combat-eligibility rule.
  - Practice range is eligible only while its loadout picker is closed.
  - Duels are eligible only at `Status == "RoundStarted"`.
- `Targeting.lua`
  - Nearest/retained observation selection.
  - Humanized rotation, hit/miss rates, and visible critical head points.
- `ProjectileAim.lua`
  - Direct projectile lead/gravity, launch offsets, splash impacts, ricochet,
    and Slingshot trajectory helpers.
  - Treat each projectile family as a policy seam; do not assume Bow,
    Slingshot, splash weapons, and raycast guns share one launch model.
- `ShotPresentation.lua`
  - Silent Aim's native `GetCameraData` presentation handshake.
  - Separates logical shot rotation from the rendered camera and restores the
    visible view around the native camera render step.
- `ScopedAccuracy.lua`
  - Opt-in native `IsFullyAiming` policy for equipped Guns with a positive
    `AimScopePercent`.
  - Does not mutate `IsAiming`, viewmodel progress, FOV, or persistent item
    state, and restores its hook on weapon changes and reload.
- `WeaponPolicy.lua`
  - Pure or mostly pure item rules: labels, damage/falloff, ADS readiness,
    hold-to-fire, Bow charge, Revolver action choice, Knife backstab, and
    Gunblade combo state.
- `Effects.lua`
  - Throwable/utility discovery, classification, visibility suppression, and
    trajectory drawing.
  - Subspace Tripmine uses projected oriented bounds for its wireframe cube.
- `Movement.lua`
  - Bunny hop and slide behavior behind active/combat/input-capture gates.

## Names that are easy to misread

The persisted setting names predate the current UI labels:

- `settings.silentAim` is user-facing **Camera Aim**.
- `settings.shotAim` is user-facing **Silent Aim**.

Use the setting names in code and the user-facing names in UI copy. Never
infer behavior from the setting name alone.

## Invariants

- Do not fire during lobby, map voting, round countdown, or either loadout
  picker. `CanPickWeapons` is permission, not proof that the picker is open;
  use the live Pick Weapons page through `CombatState`.
- Camera Aim, Silent Aim, and Trigger Bot must consume the same selected
  target. Retain a valid target rather than switching every frame.
- Silent Aim actions must wait for `ShotPresentation:getPresentedTarget()`.
  Never reselect inside a Silent Aim trigger branch; that bypasses the
  presentation-before-action guarantee.
- Gunblade may use its closest eligible world-space target and ignore normal
  screen FOV only when Silent Aim is off. With Silent Aim on, it uses the
  presented target. Slice on the first frame inside `BladeReach` for which
  `CanQuickAttack()` is true; do not wait for the visual dash duration.
- Revolver spread is nondeterministic client-side. Choose fan versus precise
  only when the complete configured cone fits the selected target. Do not
  claim spread removal or inverse compensation without new server-backed
  evidence.
- Bow charge changes damage, not its observed projectile speed. Direct
  projectile solving must apply the weapon's `ProjectileSpawnOffset` before
  iterating lead and gravity. Do not add speculative latency or
  shooter-velocity inheritance.
- Head preference must use live critical `HitboxHead`/`HitboxHeadSmall`
  geometry before the smaller visual Head, then test center and bounded crown
  points. A body part in front of the point is not a head hit; accept only
  target-descendant native head proxies or parts explicitly marked
  `IsCritical`.
- Always Scoped is opt-in and may only override the equipped item when it
  exposes the common native `IsFullyAiming` seam and a positive numeric
  `AimScopePercent`. Keep normal ADS readiness on the native predicate; camera
  FOV is fallback evidence only. The stored setting and capability key is
  `alwaysScoped`; the internal implementation module remains `ScopedAccuracy`.
- Utility ESP classification is tag-first and must reject held/viewmodel/local
  copies. Tripmine renders as a 12-edge wireframe cube; generic utilities keep
  their compact marker.
- Use normal client input and native controller/item methods for actions.
  Direct replication calls are discovery evidence, not an implementation
  shortcut.
- RIVALS client internals are volatile. Re-establish live paths, fields,
  cooldowns, and server acceptance before changing behavior based on them.

## Live validation

For authorized RIVALS testing:

1. Confirm the connected Roblox client before trusting runtime observations.
2. Prefer read-only status, evaluation, script inventory, and decompilation for
   discovery.
3. Load the local tree with:

   ```lua
   loadstring(readfile("universal-hub/local/local.lua"), "universal-hub/local.lua")()
   ```

4. Validate state-changing behavior through normal game/client paths against
   practice dummies or consenting players.
5. Restore temporary settings and loadouts after QA. If the live client blocks
   the observation, report the gap instead of converting a contract test into
   a live claim.

Never expose executor or MCP credentials in source, logs, artifacts, or
handoffs.

## Verification

Focused contracts:

```bash
HYDROXIDE_ROOT='C:/git/hydroxide' lune run tests/rivals_adapter_contracts.luau
HYDROXIDE_ROOT='C:/git/hydroxide' lune run tests/rivals_combat_state_contracts.luau
HYDROXIDE_ROOT='C:/git/hydroxide' lune run tests/overlay_contracts.luau
```

Full repository gate:

```bash
HYDROXIDE_ROOT='C:/git/hydroxide' ./scripts/check.sh
```

Add a behavioral contract for subtle cross-module boundaries, especially
phase gates, target presentation, projectile launch math, and weapon state
machines. A green pure contract does not replace live QA when runtime behavior
is the claim.
