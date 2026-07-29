# Universal Hub

A game-adapter hub that uses Limn for overlays and Hydroxide for targeting and program inspection. The hub owns shared reactive state, UI components, cleanup, and game selection. Each game adapter owns only the client contracts observed in that game.

## Load

```lua
loadstring(
    game:HttpGet(
        "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/main/loader.lua",
        true
    ),
    "universal-hub/loader.lua"
)()
```

The loader supports Volt and Potassium and fetches the current `main` branch. Normal startup downloads Universal Hub's packaged Limn build and Hydroxide's generic targeting module; it does not load the Hydroxide core, drawing, controls, or weapon helpers. No global configuration or local dependency paths are required. Press `Right Shift` to hide or restore the menu.

## Local use

The local loader initializes Hydroxide's generic targeting helper without loading the Hydroxide core or UI, loads Limn, then starts the matching game adapter:

```lua
return loadstring(readfile("universal-hub/local/local.lua"), "universal-hub/local.lua")()
```

Local development defaults to `universal-hub/local`, `hydroxide/local`, and `limn/dist/Limn.lua`. `UniversalHubConfig` path overrides remain available for development, but the normal remote loader intentionally ignores local paths so stale workspace files cannot replace published sources.

Current adapter:

- Counterblox (`GameId` `7633926880`, inspected place `114234929420007`)

Counterblox options:

- Silent aim for gun and in-range melee attacks
- Trigger bot using the equipped weapon component
- Wallbang/penetration validation using the game's own penetration raycast
- No spread
- No recoil
- FOV slider and circle
- Actual character bounds, name, health, and equipped-weapon overlays

All combat options default off. Visual diagnostics default on. Wallbang cannot manufacture penetration the server does not accept; it directs the game's existing penetration packet toward the selected target so the result exposes the real server-side boundary.

## Project boundary

Limn is the generic retained drawing, paint, input, and cleanup runtime. Universal Hub owns every panel, slider, button, theme, and game-specific drawing on consumer-owned Limn canvases. Hydroxide remains limited to targeting and program inspection. New games belong under `games/` and register through `modules/Registry.lua`.

Limn input positions remain in full-screen coordinates because Universal Hub lays out Drawing primitives against `Camera.ViewportSize`. The menu explicitly accepts processed input because its own capture layer sinks pointer actions to prevent clicks from reaching the game. Each overlay and RIVALS trajectory canvas is destroyed with its owning session.

The shared menu disables cleanly if `Square`, `Circle`, or `Text` is unavailable. Optional `Quad` chams, retained utility zones, and `Line` wireframes or trajectories are feature-detected independently.

## Verification

```bash
bash scripts/check.sh
```
