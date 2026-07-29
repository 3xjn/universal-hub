# Universal Hub design

The menu preserves the established generated-code and tooling identity while remaining a separate game-adapter surface. Limn owns the generic retained drawing, paint, and input runtime; Universal Hub owns every panel, control, theme, and game-specific overlay component.

## Runtime packaging

- The normal remote loader always uses Universal Hub's canonical published source root. It does not inspect local workspace paths or require global configuration.
- Remote startup fetches the generated `vendor/Limn.lua` artifact with the matching Universal Hub sources and loads only Hydroxide's generic `modules/Targeting.lua`.
- Local development is an explicit `local.lua` entry with conventional workspace defaults and optional path overrides. It never changes how the normal remote loader selects sources.

## Visual language

- Panel: `Color3.fromRGB(17, 23, 29)` at 97% opacity
- Elevated controls: `Color3.fromRGB(21, 28, 35)`
- Hovered controls: `Color3.fromRGB(28, 37, 45)`
- Border: `Color3.fromRGB(41, 50, 58)`
- Primary text: `Color3.fromRGB(243, 246, 247)`
- Secondary text: `Color3.fromRGB(167, 176, 184)`
- Active/visible: `Color3.fromRGB(98, 214, 173)`
- Toggle active fill: `Color3.fromRGB(74, 166, 139)` across the whole pill
- Blocked/error: `Color3.fromRGB(230, 107, 110)`
- Typeface: Drawing Plex
- Depth is built from Drawing primitives: a low-opacity offset shadow, one-pixel frame, elevated title surface, and a 3 px semantic accent rail. Roblox GUI effects and rounded-corner assumptions are not part of the shared shell.

## Layout contract

- 300 × 596 px collapsed panel, anchored 20 px from the upper-right viewport edge
- The FOV row shows the current radius on the left and an explicit `Fullscreen On/Off` toggle on the right; full-screen mode disables the radius slider and hides the FOV circle without disabling Silent Aim
- Game name and live adapter status first
- Equipped weapon and FOV are shared state for aim-capable adapters, not game tabs. Adapters without an aim capability omit both cards and the world-space FOV circle.
- Compact two-column controls grouped by `RAGE`, `MELEE`, `MOVEMENT`, and `VISUALS`
- `No Weapon Slow` sits with the combat modifiers; `No Flash` and `No Smoke` sit with visual suppression
- Capability modifiers are visibly nested under their parent: `Wallbang` inherits `Silent Aim`, while `Micro Step` inherits `Knife Aura`
- Game adapters expose only capabilities they implement. Adapter-unsupported controls and empty groups are omitted entirely; `N/A` is reserved for a supported capability whose required Drawing primitive is unavailable on the active executor.
- Town exposes a `PLOT COPY` action group instead of a toggle. It contains a live plot-owner dropdown, an editable save-name field, one full-width `Copy & Save` action, and a phase-labeled loading bar driven by completed copy work. Opening the dropdown refreshes the list from the current server, excludes the local player's plot, and overlays the remaining fields without shifting the panel.
- Configured child controls show `Standby` while their parent is disabled instead of pretending to be active
- Compact `RSHIFT` control in the title row hides the menu; the same key restores it
- Pointer capture prevents menu interaction from firing the weapon
- Interactive Drawing controls implement their own hover/resting state. State changes update the resting color so leaving a control never paints stale state back over it.
- FOV follows the pointer
- `COSMETICS` is a full-width collapsed disclosure at the bottom of the panel. Opening it reveals an explicit two-option `Weapons` / `Gloves` segmented selector, a separate previous/current/next weapon row in Weapons mode, skin picker, schema-constrained wear slider, conditional StatTrak toggle, and contextual reset. The selected weapon is independent of the equipped weapon so an override can be prepared before that weapon is equipped. In Gloves mode, the weapon row collapses, the StatTrak slot becomes a `Solid Color` control, and enabling it reveals three direct RGB sliders that color only the local viewmodel's glove parts.
- The selected cosmetics segment uses the accent surface while the inactive segment stays elevated. Both labels remain visible at all times; the active segment may show the selected weapon or glove family so mode switching is never hidden behind unrelated copy.
- Cosmetic controls reuse the elevated control surface, accent active state, 4 px spacing rhythm, and Drawing Plex typography. The collapsed state consumes only one 30 px row.
- `Hitboxes` and `Chams` are independent visual controls. Hitboxes use each observed body part's projected bounds as a 1.5 px outline; Chams use six filled `Quad` faces per body part to produce a translucent projected cuboid
- A visual control whose Drawing primitive is unavailable on the active executor remains visible but reads `N/A` and cannot publish a misleading enabled state
- The shared menu requires Limn `Square`, `Circle`, and `Text` primitives. If any are unavailable, the menu disables cleanly without blocking the game adapter. Optional `Quad` and `Line` features degrade independently.
- Cuboid faces use 0.18 Drawing opacity. Each body part uses the same five-point visibility sample as targeting: green means at least one sampled point is on-screen and directly shootable, red means every sampled point is blocked
- Health is a 4 px vertical track anchored 7 px left of the projected character bounds. Its 2 px inner fill rises from the bottom, interpolating from blocked/error red at zero health to active/visible green at full health.
- World utility observations reuse the existing palette and overlay surface. Moving throwables receive a compact marker and label; replicated fire and smoke voxels are projected into one immediate Drawing triangle mesh per paint pass, avoiding a retained object per tile while preserving the exact server-authored affected area rather than estimating a radius. Executors without immediate paint support fall back to retained translucent quads.
- A planted-bomb marker is a small distance-scaled `BillboardGui` anchored above the replicated bomb. Its dark panel uses the standard border, a 3 px semantic accent rail, a secondary `BOMB` eyebrow, and a separate high-contrast countdown; the final ten seconds turn only the rail, border, and countdown red. It uses the server-time plant payload, stays hidden beyond its configured range, becomes through-wall readable only at useful nearby distances, and is lifecycle-owned by the overlay so it cannot survive a reload or round cleanup.
- The legacy projected-bounds rectangle is only a compatibility fallback when an adapter cannot publish body-part observations

## Shared Drawing primitives

- `Panel`: shadow, opaque body, one-pixel frame, elevated title surface, and accent rail; the full stack moves and resizes as one draggable window.
- `Status cue`: title-row status copy plus a semantic live/error dot.
- `Value surface`: compact elevated backing for right-aligned live values such as the equipped weapon.
- `Toggle card`: framed two-column control with label, disabled treatment, and hover feedback. The card surface remains neutral in every state. State is carried by a 40 × 22 px switch with one muted fill across the whole pill, a dark offset shadow, and an inset rimmed thumb. Normal states do not repeat `On` or `Off`; exceptional `Standby` and `N/A` states may use text.
- `Slider`: transparent 28 px hit target over a 4 px track, semantic fill, and high-contrast circular thumb. Rate-slider thumb travel is inset by its radius so the zero and 100 percent states stay inside the track; each live percentage sits in an aligned one-pixel framed value surface.
- `Section divider`: compact accent eyebrow and one-pixel continuation rule.
- `Dropdown field`: full-width elevated surface with a left-aligned field label, right-aligned selected value, disclosure indicator, border, hover feedback, and an elevated option list above following content. States are empty, closed, open, hover, and selected.
- `Text entry field`: full-width elevated Drawing surface with label, mirrored value or placeholder, border, hover, and accent focus treatment. Keyboard capture is delegated to an off-screen native Roblox `TextBox`; the native object owns no visible layout.
- `Primary action`: full-width accent surface with centered high-contrast label. It is used for explicit one-shot work and never represented as a persistent toggle.
- `Progress bar`: a compact phase label, exact percentage, muted track, and semantic fill. Progress reflects completed server-replicated work across snapshot, part creation, geometry, appearance, details, collision, anchoring, and save phases; it never runs on a decorative timer.
- These primitives are shared by every game adapter. Adapters choose capabilities and labels; they do not fork presentation.
- Each overlay and game-specific drawing surface owns a separate Limn canvas and destroys it on unload or reload.

## State contract

`modules/Store.lua` is the single reactive seam. The adapter publishes live weapon, status, target, character observations, bomb state, and utility observations. The overlay subscribes to that state and sends option changes back through the session. No game adapter reaches into Drawing controls directly.

Menu visibility is live UI state, not a combat setting. Hiding the menu releases pointer capture and affects only panel controls; enabled FOV and character overlays continue rendering.

Wallbang is active only while Silent Aim is active, and a redirected shot is published only when the penetration trace reaches the selected character. Knife Aura only attacks inside the game's measured melee range and aligns the game's synchronous melee direction with the selected target before immediately restoring the camera. Micro Step is active only while Knife Aura is active and remains bounded by the adapter's extra reach budget. Bunny Hop requires the player to hold Space. Spin Bot forces a reversible third-person view and rotates only the visible root joint; it never owns the Humanoid's physical root, movement velocities, or `AutoRotate`.

Visual suppression is transition-based. Enabling `No Flash` cancels the active flash once and blocks future flash effects. Enabling `No Smoke` clears active voxel smoke once and blocks future creation. Disabling either restores the game's original effect function for subsequent events. `No Weapon Slow` preserves game states that intentionally stop movement, while lifting a positive movement result to the normal unencumbered speed for the current stance.

Full-screen aim removes only the screen-distance constraint. Team, alive, on-screen, visibility, and wall-penetration checks remain unchanged.

Character observations publish `bodyParts` as projected per-part bounds and eight ordered cuboid corners with `visible` and normalized `visibility` values. The overlay owns separate retained Limn `Square` outlines and `Quad` faces; targeting remains the single source of truth for geometry and line-of-sight.

Cosmetic overrides are local presentation state keyed by weapon name. They never call inventory remotes. The Counterblox adapter applies the selected skin, wear, and optional StatTrak value when a weapon component is created, refreshes a tracked equipped viewmodel when safe, and re-applies the override after respawn or re-equip. Glove substitution and solid-color application are scoped to local-player viewmodel construction so they cannot alter another player's gloves. Selected knife family/skin/wear, glove family/skin/wear, and optional glove color are stored per adapter in the executor workspace and restored on reload; menu disclosure state and live observations are not persisted.

Town plot selection and save-name entry are live plot-copy form state, not persistent combat settings. The overlay asks the Town adapter for current plot owners whenever the dropdown opens, then sends the selected owner and exact validated save name through one action callback. The adapter owns progress, replication, failure cleanup, and the final server save command. Its replicated appearance pass includes F3X meshes, textures, and lights. For wired plots it also preserves the hidden texture values and nested F3X model hierarchy. Any moving group observed at its active endpoint is normalized to its Start Position before Town's normal `!wireconnections` compiler runs, preventing a copied open door from becoming the new closed origin. The adapter waits for the replicated `Wired` state and only then autosaves through a save GUI prepared before the wire-command cooldown.
