<p align="center">
  <img src="site/assets/icon.png" alt="Universal Hub" width="112" />
</p>

<h1 align="center">Universal Hub</h1>

<p align="center">
  <strong>One hub. Tuned for every game it supports.</strong>
</p>

<p align="center">
  <a href="https://3xjn.github.io/universal-hub/"><strong>Games &amp; features →</strong></a>
</p>

## Load

Stable:

```lua
loadstring(game:HttpGet("https://3xjn.github.io/universal-hub/bootstrap.lua?v="..tick()))()
```

Beta testing:

```lua
loadstring(game:HttpGet("https://3xjn.github.io/universal-hub/beta/bootstrap.lua?v="..tick()))()
```

Works with Volt and Potassium; press `Right Shift` to toggle the menu.

Remote startup downloads a generated shared runtime, the selected game bundle, and the menu artifact instead of every source file. CI refreshes `dist/runtime.lua` and `dist/games/*.lua`; reproduce it locally with `HYDROXIDE_ROOT=../hydroxide lune run scripts/build_runtime_bundles.luau`.

Limn is the hub's sole drawing and input runtime. Universal Hub owns its panels, state, persistence, and game adapters; scoped Hydroxide `Targeting`, `Closure`, and `Lifecycle` helpers are loaded independently without starting or replacing the Hydroxide application.
