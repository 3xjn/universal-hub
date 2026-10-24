# MM2 Pathfinding

R15 only. Do not add an R6 leg to the foot offset. Murder Mystery 2's
humanoid root sits about `HipHeight + root.Size.Y / 2` above the soles, and
an equipped gear can desync `Humanoid.HipHeight` from those soles.

Read the module for the concern you are changing. `Controller.lua` only
orders those decisions.

## Module map

- `Agent.lua` — R15 foot offset, capsule height from the soles to the head,
  body radius, and equipped-tool collision. The tool never widens the agent.
- `Ladders.lua` — ladder shape, truss placement in front of the mesh,
  object-space proximity, and climb versus dismount from the feet.
- `Slopes.lua` — walkable incline from `Humanoid.MaxSlopeAngle`. A flat lip
  is a box, not a ramp.
- `Jumps.lua` — hop onto a box top the jump can reach, with head clearance.
- `Clearance.lua` — doorway centering from the R15 body width.
- `Route.lua` — path parameters, plan origin, and waypoint acceptance.
- `Controller.lua` — profile cache, tool collision, and the per-step action.

## Invariants

- Keep the last grounded profile while jumping, falling, or climbing.
- Dismount a ladder from the feet. Comparing the root to the lip lets go
  while the feet are still on the rungs.
- Suspend `CanCollide` on the equipped tool for the whole move, and restore
  it on release. Do not fold the handle into agent radius or height.
- Try the body radius before the tight radius. Agent height is the measured
  body, not 5.
- Walk a ramp the humanoid's `MaxSlopeAngle` allows. Jump only when the
  ground ahead is a lip or wall and the box top is the landing.
- Town, Rivals, and Counterblox do not import this folder.

## Verification

```bash
lune run tests/mm2_pathfinding_contracts.luau
HYDROXIDE_ROOT="$HOME/hydroxide" ./scripts/check.sh
```

A green contract does not move a character through a live MM2 map.
