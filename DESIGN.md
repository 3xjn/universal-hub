# Universal Hub design

The menu inherits Hydroxide's generated-code and tooling identity while remaining a separate game-adapter surface.

## Visual language

- Panel: `Color3.fromRGB(17, 23, 29)` at 97% opacity
- Elevated controls: `Color3.fromRGB(21, 28, 35)`
- Border: `Color3.fromRGB(41, 50, 58)`
- Primary text: `Color3.fromRGB(243, 246, 247)`
- Secondary text: `Color3.fromRGB(167, 176, 184)`
- Active/visible: `Color3.fromRGB(98, 214, 173)`
- Blocked/error: `Color3.fromRGB(230, 107, 110)`
- Typeface: Drawing Plex

## Layout contract

- 300 × 562 px collapsed panel, anchored 20 px from the upper-right viewport edge
- The FOV row shows the current radius on the left and an explicit `Fullscreen On/Off` toggle on the right; full-screen mode disables the radius slider and hides the FOV circle without disabling Silent Aim
- Game name and live adapter status first
- Equipped weapon and FOV are shared state, not game tabs
- Compact two-column controls grouped by `RAGE`, `MELEE`, `MOVEMENT`, and `VISUALS`
- `No Weapon Slow` sits with the combat modifiers; `No Flash` and `No Smoke` sit with visual suppression
- Capability modifiers are visibly nested under their parent: `Wallbang` inherits `Silent Aim`, while `Micro Step` inherits `Knife Aura`
- Configured child controls show `Standby` while their parent is disabled instead of pretending to be active
- Compact `RSHIFT` control in the title row hides the menu; the same key restores it
- Pointer capture prevents menu interaction from firing the weapon
- FOV follows the pointer
- `COSMETICS` is a full-width collapsed disclosure at the bottom of the panel. Opening it expands the panel to 690 px and reveals an explicit two-option `Weapons` / `Gloves` segmented selector, skin picker, schema-constrained wear slider, conditional StatTrak toggle, and contextual reset. In Gloves mode, the StatTrak slot becomes a `Solid Color` control; enabling it expands three direct RGB sliders and colors only the local viewmodel's glove parts.
- The selected cosmetics segment uses the accent surface while the inactive segment stays elevated. Both labels remain visible at all times; the active segment may show the selected weapon or glove family so mode switching is never hidden behind unrelated copy.
- Cosmetic controls reuse the elevated control surface, accent active state, 4 px spacing rhythm, and Drawing Plex typography. The collapsed state consumes only one 30 px row.
- Character overlays use projected character bounds for label placement and six filled `Quad` faces per body part, producing a translucent projected cuboid instead of axis-aligned mini-boxes or one coarse player rectangle
- Cuboid faces use 0.18 Drawing opacity. Each body part uses the same five-point visibility sample as targeting: green means at least one sampled point is on-screen and directly shootable, red means every sampled point is blocked
- Health is a 4 px vertical track anchored 7 px left of the projected character bounds. Its 2 px inner fill rises from the bottom, interpolating from blocked/error red at zero health to active/visible green at full health.
- The legacy projected-bounds rectangle is only a compatibility fallback when an adapter cannot publish body-part observations

## State contract

`modules/Store.lua` is the single reactive seam. The adapter publishes live weapon, status, target, and observations. The overlay subscribes to that state and sends option changes back through the session. No game adapter reaches into Drawing controls directly.

Menu visibility is live UI state, not a combat setting. Hiding the menu releases pointer capture and affects only panel controls; enabled FOV and character overlays continue rendering.

Wallbang is active only while Silent Aim is active, and a redirected shot is published only when the penetration trace reaches the selected character. Knife Aura only attacks inside the game's measured melee range and aligns the game's synchronous melee direction with the selected target before immediately restoring the camera. Micro Step is active only while Knife Aura is active and remains bounded by the adapter's extra reach budget. Bunny Hop requires the player to hold Space. Spin Bot forces a reversible third-person view and rotates only the visible root joint; it never owns the Humanoid's physical root, movement velocities, or `AutoRotate`.

Visual suppression is transition-based. Enabling `No Flash` cancels the active flash once and blocks future flash effects. Enabling `No Smoke` clears active voxel smoke once and blocks future creation. Disabling either restores the game's original effect function for subsequent events. `No Weapon Slow` preserves game states that intentionally stop movement, while lifting a positive movement result to the normal unencumbered speed for the current stance.

Full-screen aim removes only the screen-distance constraint. Team, alive, on-screen, visibility, and wall-penetration checks remain unchanged.

Character observations publish `bodyParts` as projected per-part bounds and eight ordered cuboid corners with `visible` and normalized `visibility` values. The overlay owns only their retained Drawing nodes; targeting remains the single source of truth for geometry and line-of-sight.

Cosmetic overrides are local presentation state keyed by weapon name. They never call inventory remotes. The Counterblox adapter applies the selected skin, wear, and optional StatTrak value when a weapon component is created, refreshes a tracked equipped viewmodel when safe, and re-applies the override after respawn or re-equip. Glove substitution and solid-color application are scoped to local-player viewmodel construction so they cannot alter another player's gloves. Selected knife family/skin/wear, glove family/skin/wear, and optional glove color are stored per adapter in the executor workspace and restored on reload; menu disclosure state and live observations are not persisted.
