# RIVALS Adapter Guide

The root `AGENTS.md` applies here. This guide contains only RIVALS-specific
ownership and behavior. Read it before changing this integration.

## Runtime shape

`Definition.lua` owns registration, capabilities, and the packaged source set.
The loader imports only the selected Adapter and Presentation. RIVALS has no
Composition because it owns no custom startup or menu actions.

`Adapter.lua` is the integration surface: controller discovery, dependency
wiring, frame ordering, and cleanup. Put behavior in `features/`, policy and
native interpretation in `libraries/`, task automation in `tasks/`, and world
observation/render policy in `world/`. Features receive injected dependencies
from Adapter and use relative `require`; do not add `importDependency` shims.

The Adapter receives scoped Hydroxide helpers and a game-owned Limn canvas. It
must not read `environment.oh`, raw `Drawing`, or a Limn filesystem path.

The per-frame order is:

1. Read native controllers and combat state.
2. Publish player and utility observations.
3. Select or retain one target and apply head/miss policy.
4. Solve direct, projectile, ricochet, slingshot, or splash aim.
5. Camera Aim updates logical aim; Silent Aim promotes only a target staged by
   `ShotPresentation`.
6. Trigger Bot evaluates that same target through `WeaponPolicy`.
7. Movement, deflection, and Effects update under the same combat gates.

`Session.lua` is one frame snapshot. Each field has one writer: `aligned` is
the aim-plan target and `presented` is the target promoted for Silent Aim.

## Cross-Module contracts

- `CameraAim` writes `session.aligned`; it never writes `presented`.
- `SilentAim` owns `ShotPresentation` and writes `session.presented` only after
  the matching native camera frame is staged.
- Trigger Bot reads `presented` while Silent Aim is enabled and otherwise reads
  `aligned`; it does not reselect.
- `HookRuntime` owns optional Shot Aim, Always Scoped, and Katana Stop hooks.
  Hook primitives are required only for declared capabilities.
- Warp owns its Heartbeat hold and releases only when disabled or the character
  dies. It must reject ForceFields, invincibility, and blocked/OOB slots without
  Anchoring the root.
- Rapid Fire reversibly changes native cooldowns and repeats normal input for
  held semi-automatic weapons. Restore every patched item when disabled,
  unequipped, replaced, or stopped.
- `TaskFarmRuntime` is signal-driven and owns no frame loop.
- `Effects` owns utility suppression and trajectory drawing cleanup.

## Names that are easy to misread

- `settings.silentAim` is user-facing **Camera Aim**.
- `settings.shotAim` is user-facing **Silent Aim**.
- `settings.alwaysScoped` is user-facing **Always Scoped**; its Implementation
  remains `ScopedAccuracy`.

Use persisted names in code and user-facing names in Presentation copy.

## Invariants

- Do not fire during lobby, map voting, round countdown, or either loadout
  picker. `CanPickWeapons` is permission, not proof that a picker is open.
- Camera Aim, Silent Aim, and Trigger Bot consume the same retained target.
- Trigger Bot fires only on a solved path. On-screen visibility alone is not a
  firing solution.
- Trigger Bot uses the equipped item's native cooldown. Do not add a `0.1`
  floor or latency compensation. Compare `_shoot_cooldown` with `tick`, not
  `os.clock`.
- Native automatic guns may repeat `StartShooting` without a release gap.
  Continuous `InternalUse` weapons keep one held press and may re-press only
  after the native cooldown remains expired for a full fire interval.
- With both aim modes disabled, Trigger Bot uses the native mouse-ray hit; it
  does not substitute nearest-target or screen-radius selection. Release held
  fire when the target is deflecting.
- `triggerDelay` is a first-shot delay only. Do not add it to subsequent native
  cooldowns.
- Silent Aim actions wait for `ShotPresentation:getPresentedTarget()` and never
  reselect inside the action branch.
- Gunblade ignores normal screen FOV only for its closest eligible world target
  while Silent Aim is off. Strike only when `CanQuickAttack()` is positively
  ready; do not infer readiness from visual dash timing.
- Revolver fan-versus-precise selection requires the complete configured cone
  to fit the target. Do not claim spread removal without server-backed
  evidence.
- Bow charge changes damage, not observed projectile speed. Apply
  `ProjectileSpawnOffset` before solving lead and gravity; do not invent
  latency or shooter-velocity compensation.
- Head preference uses live critical hitbox geometry before visual Head and
  accepts only target-descendant critical proxies or explicitly critical parts.
- Always Scoped is opt-in and requires the native `IsFullyAiming` Seam plus a
  positive numeric `AimScopePercent`. Camera FOV is fallback evidence only.
- Auto Katana pre-blocks only from positive native combat evidence; it does not
  wait for a hitscan shot or invent latency compensation.
- Utility classification is tag-first and rejects held, viewmodel, and local
  copies.
- Use normal client input and native controller/item methods. Direct replication
  calls are discovery evidence, not an Implementation shortcut.
- RIVALS internals are volatile. Re-establish live paths, fields, cooldowns,
  return values, and server acceptance before changing behavior around them.

## Live validation

For authorized testing:

1. Confirm the connected client before trusting observations.
2. Prefer read-only status, script inventory, and decompilation for discovery.
3. Stage through the repository tooling with local paths supplied by documented
   environment variables; do not commit personal workspace paths.
4. Exercise state-changing behavior through normal game/client paths against
   practice dummies or consenting players.
5. Restore temporary settings and loadouts. Report blocked live observations
   instead of turning a pure contract into a runtime claim.

Never expose executor or MCP credentials in source, logs, artifacts, or
handoffs.

## Verification

Run the focused contract for the changed behavior. Common integration checks:

```bash
lune run tests/rivals_adapter_contracts.luau
lune run tests/rivals_combat_state_contracts.luau
lune run tests/overlay_contracts.luau
```

Then run the root gate when its declared prerequisites are available:

```bash
bash scripts/check.sh
```

Prefer behavioral contracts for phase gates, target presentation, projectile
math, input ownership, cleanup, and weapon state machines. Pure contracts do
not replace live QA for runtime claims.
