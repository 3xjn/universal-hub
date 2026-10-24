# qos-MM2

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/3xjn/qos-mm2/main/qos-mm2.lua"))()
```

Prism on its own:

```lua
local React, ReactRoblox, Prism, PrismPackage, PrismCleanup =
    loadstring(game:HttpGet("https://raw.githubusercontent.com/3xjn/qos-mm2/main/prism.lua"))()
```

`prism.lua` is the executor runtime pinned to `3xjn/prism@1974a8b77f3eeaa05963ac26abc557b16fd6ad8e`. It returns React, ReactRoblox, Prism, the package, and cleanup. Set `getgenv().QOS_MM2_PRISM_URL` before running qos-MM2 to point it at a different copy.

Right Bracket opens the menu. End unloads.
