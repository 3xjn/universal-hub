# RIVALS Elite Task Farming Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the negative task-farming control with a positive Tools-page toggle and make farming locomotion choose safe, weapon-aware, high-skill routes instead of generic target pressure.

**Architecture:** `TaskLocomotion` becomes the sole decision policy for task-combat movement; `Movement` owns native observation, action execution, and cleanup; `Adapter` supplies stable target/hazard observations and no longer computes a second direction. The persisted UI contract becomes `taskAutomationEnabled`, while `TaskFarmRuntime.paused` remains an internal lifecycle detail.

**Tech Stack:** Luau, Roblox native fighter/mechanics controllers, Workspace raycasts/blockcasts, Prism/React presentation catalog, Lune behavioral contracts.

**Quality bar:** Flagship. Decisions must be purposeful, stable, terrain-safe, and testable; randomness may vary equally safe choices but may never bypass safety or weapon policy.

---

## Product decisions

- Place **Task Farming** under `Tools` in a `TASK FARMING` section before `WORLD`.
- Show **Emergency Stop** (`End`) immediately before the positive **Task Farming** toggle.
- Default `taskAutomationEnabled` to `false`.
- Fresh launches start disabled for safety; teleport bootstrap may preserve an active farm.
- Optimize for the current task family: survival/wins hold positional advantage, eliminations take finishable pressure, and generic play balances both.
- High ground is preferred only when a positively verified route preserves weapon range, support, and acceptable exposure.
- Backpedaling and ramp movement keep the camera/aim on the opponent while movement follows a verified supported route.

## Task 1: Specify the positive setting and migration

**Files:**
- Modify: `modules/Config.lua`
- Modify: `games/rivals/Definition.lua`
- Modify: `games/rivals/Presentation.lua`
- Test: `tests/config_contracts.luau`
- Test: `tests/catalog_contracts.luau`
- Test: `tests/presentation_host_contracts.luau`
- Test: `tests/native_catalog_contracts.luau`

**Step 1: Write failing contracts**

Cover:

```lua
-- New key wins when both exist.
-- Legacy taskAutomationPaused=false migrates to taskAutomationEnabled=true.
-- Legacy taskAutomationPaused=true migrates to taskAutomationEnabled=false.
-- Missing/invalid legacy state leaves the default false.
-- RIVALS exposes Task Farming under Tools, not Settings.
-- Emergency Stop precedes the positive toggle.
```

**Step 2: Run the focused contracts and verify failure**

```powershell
lune run tests/config_contracts.luau
lune run tests/catalog_contracts.luau
lune run tests/presentation_host_contracts.luau
lune run tests/native_catalog_contracts.luau
```

Expected: failures reference the old `taskAutomationPaused` schema and Settings placement.

**Step 3: Implement the schema change**

- Add `taskAutomationEnabled = false` to RIVALS defaults/capabilities/labels.
- Remove `taskAutomationPaused` outside Config migration fixtures.
- Mount `taskFarming` on `Tools` before `world`.
- Add a narrow Config load migration:

```lua
if decoded.taskAutomationEnabled == nil
    and type(decoded.taskAutomationPaused) == "boolean"
then
    decoded.taskAutomationEnabled = not decoded.taskAutomationPaused
end
decoded.taskAutomationPaused = nil
```

**Step 4: Run the contracts and verify pass**

Expected: all four print their `-ok` marker.

**Step 5: Commit only the exact files after user approval**

```bash
git add modules/Config.lua games/rivals/Definition.lua games/rivals/Presentation.lua tests/config_contracts.luau tests/catalog_contracts.luau tests/presentation_host_contracts.luau tests/native_catalog_contracts.luau
git commit -m "feat(rivals): expose positive task farming control"
```

## Task 2: Route runtime mutations through Session

**Files:**
- Modify: `init.lua`
- Modify: `games/rivals/Adapter.lua`
- Test: `tests/session_contracts.luau`
- Test: `tests/rivals_adapter_contracts.luau`
- Test: `tests/rivals_frame_lifecycle_contracts.luau`

**Step 1: Write failing contracts**

Prove:

- Toggle on resumes `TaskFarmRuntime`; toggle off pauses it.
- Manual duel and emergency stop request `taskAutomationEnabled=false` through the injected option mutation boundary.
- No task branch directly patches Store and separately calls `settingsChanged`.
- Normal startup normalizes enabled to false before runtime construction; teleport bootstrap may retain true.
- Starting farming closes the menu once, then respects manual reopen.

**Step 2: Run contracts and verify failure**

```powershell
lune run tests/session_contracts.luau
lune run tests/rivals_adapter_contracts.luau
lune run tests/rivals_frame_lifecycle_contracts.luau
```

**Step 3: Implement one mutation boundary**

- Inject `setOption(name, enabled, persist)` into Adapter context.
- Queue construction-time requests until `Session.new` exists, then flush them through `Session:setOption`.
- Convert only at the TaskFarmRuntime boundary:

```lua
paused = settings.taskAutomationEnabled ~= true
```

- Emergency stop and manual duel request `taskAutomationEnabled=false`.
- Preserve listener teardown and owned-input release.

**Step 4: Run contracts and verify pass**

Expected: all three print their `-ok` marker.

**Step 5: Commit exact files after approval**

```bash
git add init.lua games/rivals/Adapter.lua tests/session_contracts.luau tests/rivals_adapter_contracts.luau tests/rivals_frame_lifecycle_contracts.luau
git commit -m "refactor(rivals): make task farming an enabled lifecycle"
```

## Task 3: Remove split-brain movement policy

**Files:**
- Modify: `games/rivals/tasks/TaskLocomotion.lua`
- Modify: `games/rivals/libraries/Movement.lua`
- Modify: `games/rivals/Adapter.lua`
- Test: `tests/rivals_task_locomotion_contracts.luau`
- Test: `tests/rivals_task_movement_contracts.luau`
- Test: `tests/rivals_adapter_contracts.luau`

**Step 1: Write a failing production-path contract**

Create an active ranged engagement with a movable root and prove the plan holds/kites at its native range instead of being replaced by generic push direction.

Also prove physical grounding comes from positive fighter/humanoid evidence, not `localFighterIsTaskActive()`.

**Step 2: Run and verify failure**

```powershell
lune run tests/rivals_task_locomotion_contracts.luau
lune run tests/rivals_task_movement_contracts.luau
lune run tests/rivals_adapter_contracts.luau
```

**Step 3: Establish one deep Interface**

Adapter calls:

```lua
movement:updateTaskCombat({
    target = alignedTarget,
    hazards = taskHazards,
    objective = currentTaskFamily,
})
```

`Movement` observes native actor/weapon state, probes candidate routes, calls `TaskLocomotion:plan(snapshot)`, then executes the returned plan. Delete Adapter route planning and delete Movement’s competing direction replacement path.

**Step 4: Implement planner state identity**

`TaskLocomotion` retains decisions by stable engagement/target identity, not exact moving `targetPosition`. Add `reset()` for disable, target replacement, respawn, and stop.

**Step 5: Run contracts and verify pass**

Expected: the production path preserves the policy decision and cleanup remains immediate.

**Step 6: Commit exact files after approval**

```bash
git add games/rivals/tasks/TaskLocomotion.lua games/rivals/libraries/Movement.lua games/rivals/Adapter.lua tests/rivals_task_locomotion_contracts.luau tests/rivals_task_movement_contracts.luau tests/rivals_adapter_contracts.luau
git commit -m "refactor(rivals): unify task locomotion policy"
```

## Task 4: Add terrain-aware candidate observation

**Files:**
- Modify: `games/rivals/libraries/Movement.lua`
- Modify: `games/rivals/Adapter.lua`
- Test: `tests/rivals_task_movement_contracts.luau`

**Step 1: Write failing route-observation contracts**

For hold, forward, retreat, left, right, and useful diagonals, require positive evidence for:

- destination support and support elevation;
- walkable surface normal/slope;
- body/path clearance;
- edge safety and landing footprint;
- LOS/exposure at the destination;
- hazard clearance;
- verified traversal action, if required.

Unknown probes must remove a specialized candidate rather than report clear.

**Step 2: Run and verify failure**

```powershell
lune run tests/rivals_task_movement_contracts.luau
```

**Step 3: Implement native probes**

- Derive footprint from live character/root extents.
- Derive walkable slope from `Humanoid.MaxSlopeAngle` when available.
- Use Workspace raycast/blockcast results as positive authority.
- Preserve the existing verified-landing jump foundation.
- Never infer grounded, clear, supported, or slide-capable from missing APIs.

**Step 4: Run and verify pass**

Acceptance examples:

- unsupported retreat route is rejected;
- backpedal route on a verified ramp remains eligible;
- elevated route is represented only when connected and walkable;
- unknown landing never creates a jump.

**Step 5: Commit exact files after approval**

```bash
git add games/rivals/libraries/Movement.lua games/rivals/Adapter.lua tests/rivals_task_movement_contracts.luau
git commit -m "feat(rivals): observe safe tactical movement routes"
```

## Task 5: Implement elite tactical decisions

**Files:**
- Modify: `games/rivals/tasks/TaskLocomotion.lua`
- Modify: `games/rivals/libraries/WeaponPolicy.lua`
- Test: `tests/rivals_task_locomotion_contracts.luau`
- Test: `tests/rivals_task_movement_contracts.luau`

**Step 1: Write failing behavior contracts**

Cover:

- hazard evasion beats every combat preference;
- low health or positively unready weapon seeks verified cover;
- aimed scoped opponent prefers a covered lateral route;
- melee/native reach pursues;
- native ranged profile holds or kites inside its effective band;
- high ground wins only when route safety, exposure, and weapon range remain acceptable;
- elevated opponent causes a safe rising route to beat flat push;
- close pressure can backpedal up/down a verified ramp while aim remains on target;
- task family changes aggression without bypassing safety.

**Step 2: Run and verify failure**

```powershell
lune run tests/rivals_task_locomotion_contracts.luau
lune run tests/rivals_task_movement_contracts.luau
```

**Step 3: Add native weapon movement profiles**

Extend `WeaponPolicy` with a capability-based `movementProfile(item)` using live reach/falloff/readiness evidence. Display names never choose behavior. Unknown range evidence yields a neutral profile rather than guessed specialization.

**Step 4: Implement ordered decision modes**

Priority:

1. continue verified traversal commitment;
2. evade positively observed hazard;
3. recover support or hold;
4. seek cover when vulnerable;
5. pursue/hold/kite for weapon range and task objective;
6. prefer reachable high ground when it improves the valid position;
7. attach mobility only to an already safe traversal plan.

Compare eligible routes lexicographically: safety gate → mode fit → native range error → exposure → useful elevation → progress → reversal cost → deterministic tie order.

**Step 5: Add bounded unpredictability**

Use engagement identity and decision revision only to choose among equally valid left/right routes. Keep the choice until route invalidation, target replacement, objective change, or measured failure. Time alone must not flip direction.

**Step 6: Run and verify pass**

Expected: deterministic snapshots produce stable plans, while a new engagement may choose the opposite equally safe flank.

**Step 7: Commit exact files after approval**

```bash
git add games/rivals/tasks/TaskLocomotion.lua games/rivals/libraries/WeaponPolicy.lua tests/rivals_task_locomotion_contracts.luau tests/rivals_task_movement_contracts.luau
git commit -m "feat(rivals): add adaptive elite movement policy"
```

## Task 6: Make slide-jump and parkour state-driven

**Files:**
- Modify: `games/rivals/libraries/Movement.lua`
- Test: `tests/rivals_task_movement_contracts.luau`

**Step 1: Write failing action-state contracts**

Prove:

- `Slide` is requested once;
- `HighJump` occurs only after native sliding is positively confirmed;
- airborne and landing states advance from native state;
- pause, capture, respawn, actor replacement, rejection, or stop aborts and releases owned slide/crouch/input;
- gap jumps retain their exact verified landing;
- double jump occurs once, only while descending and natively supported.

**Step 2: Run and verify failure**

```powershell
lune run tests/rivals_task_movement_contracts.luau
```

**Step 3: Implement the executor state machine**

```text
idle → slide requested → native sliding confirmed → high jump requested
→ native airborne → native grounded → complete
```

No arbitrary elapsed delay may stand in for native state. If a positive capability or bounded native transition is unavailable, fall back to walking the same safe route.

**Step 4: Run and verify pass**

Expected: actions occur once and every lifecycle exit restores owned state.

**Step 5: Commit exact files after approval**

```bash
git add games/rivals/libraries/Movement.lua tests/rivals_task_movement_contracts.luau
git commit -m "feat(rivals): execute native-confirmed mobility chains"
```

## Task 7: Rebuild UI and run repository verification

**Files:**
- Regenerate: `ui/dist/Menu.lua`
- Regenerate: `ui/dist/Menu.provenance`

**Step 1: Build UI**

```powershell
npm run build
```

Run from `C:\git\universal-hub\ui`.

Expected: TypeScript compile checks pass and both generated artifacts update.

**Step 2: Run focused and related contracts**

```powershell
lune run tests/config_contracts.luau
lune run tests/catalog_contracts.luau
lune run tests/presentation_host_contracts.luau
lune run tests/native_catalog_contracts.luau
lune run tests/session_contracts.luau
lune run tests/rivals_task_locomotion_contracts.luau
lune run tests/rivals_task_movement_contracts.luau
lune run tests/rivals_adapter_contracts.luau
lune run tests/rivals_frame_lifecycle_contracts.luau
lune run tests/menu_artifact_contracts.luau
```

**Step 3: Check the patch**

```powershell
git diff --check
bash scripts/check.sh
```

Report a missing external prerequisite such as `luau-lsp`; do not call an unexecuted gate passing.

## Task 8: Live discovery and QA

**Files:** No source edits until observations are recorded.

**Step 1: Reconnect an authenticated RIVALS client**

Confirm the active session, local fighter, current duel, and task runtime before trusting observations.

**Step 2: Read native movement authority**

Verify live fields/methods and transitions for:

- physical grounding and support;
- `CanSlide`, `Slide`, `IsSliding`, `StopSliding`;
- normal/high/double jump requests and return values;
- root velocity and ramp support normals;
- character footprint and native weapon range/readiness evidence.

**Step 3: Stage only changed files through the local workspace**

Do not expose local paths in committed code.

**Step 4: Exercise consenting/practice scenarios**

- flat ranged duel: hold range and stable strafe commitment;
- close pressure: supported backpedal without edge walking;
- ramp: retreat while facing/aiming at the opponent;
- elevated opponent: take a verified rising route;
- scoped opponent: use cover/lateral close;
- traversal lane: slide confirmed before high jump;
- hazard: immediate safe-route override;
- hide/disable/emergency stop: zero movement and restore all owned states.

**Step 5: Tune policy, not safety gates**

Adjust only ordering/tie behavior after observed outcomes. Never replace missing native evidence with guessed success.

**Step 6: Restore temporary settings/loadout and record final evidence**

Only then claim live movement behavior.
