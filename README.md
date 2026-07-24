# Universal Hub

A game-adapter hub powered by Hydroxide's reusable modules. The hub owns shared reactive state, Drawing UI, cleanup, and game selection. Each game adapter owns only the client contracts observed in that game.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/3xjn/universal-hub/main/loader.lua"))()
```

The loader supports Volt and Potassium and fetches the current `main` branch. Press `Right Shift` to hide or restore the menu.

## Local use

The local loader initializes Hydroxide's core without opening the full Hydroxide UI, then starts the matching game adapter:

```lua
return loadstring(readfile("universal-hub/local/local.lua"), "universal-hub/local.lua")()
```

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

Hydroxide remains the generic inspection and helper project. This repository owns the game registry, menu, sessions, and per-game adapters. New games belong under `games/` and register through `modules/Registry.lua`.

## Verification

```bash
bash scripts/check.sh
```
