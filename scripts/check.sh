#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repository_root"

for required_tool in luau-lsp lune; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        printf 'Missing required tool: %s\n' "$required_tool" >&2
        exit 1
    fi
done

roblox_types_commit="cfa5c378c6370f0eca852910e6fbdf8e4d8921c6"
roblox_types="${LOCALAPPDATA:-${TMPDIR:-/tmp}}/hydroxide/typecheck/globalTypes-$roblox_types_commit.d.luau"
hydroxide_root="${HYDROXIDE_ROOT:-../hydroxide}"

if [ ! -f "$roblox_types" ]; then
    printf 'Missing Roblox definitions. Run the Hydroxide check once first.\n' >&2
    exit 1
fi

luau-lsp analyze \
    --platform roblox \
    --definitions "@roblox=$roblox_types" \
    --definitions "@volt=$hydroxide_root/_Index/volt/volt.d.luau" \
    loader.lua \
    init.lua \
    local.lua \
    hub.lua \
    modules/Store.lua \
    modules/Config.lua \
    modules/InputCapture.lua \
    modules/MenuToggle.lua \
    modules/Registry.lua \
    modules/Session.lua \
    modules/Overlay.lua \
    games/town/Canonical.lua \
    games/town/CheckpointStore.lua \
    games/town/CopyEngine.lua \
    games/town/CopyPlan.lua \
    games/town/ExecutionPlan.lua \
    games/Counterblox.lua \
    games/Town.lua \
    games/rivals/Adapter.lua \
    games/rivals/Targeting.lua \
    games/rivals/ProjectileAim.lua \
    games/rivals/ShotPresentation.lua \
    games/rivals/ScopedAccuracy.lua \
    games/rivals/WeaponPolicy.lua \
    games/rivals/Effects.lua \
    games/rivals/Movement.lua \
    games/rivals/CombatState.lua

lune run tests/store_contracts.luau
lune run tests/remote_loader_contracts.luau
lune run tests/hub_loader_contracts.luau
lune run tests/local_loader_contracts.luau
lune run tests/config_contracts.luau
lune run tests/input_capture_contracts.luau
lune run tests/menu_toggle_contracts.luau
lune run tests/registry_contracts.luau
lune run tests/session_contracts.luau
lune run tests/overlay_contracts.luau
lune run tests/town_canonical_contracts.luau
lune run tests/town_checkpoint_contracts.luau
lune run tests/town_copy_engine_contracts.luau
lune run tests/town_copy_plan_contracts.luau
TOWN_TEST_COUNT=256 lune run tests/town_large_copy_integration_contracts.luau
lune run tests/town_large_copy_integration_contracts.luau
lune run tests/town_second_review_contracts.luau
lune run tests/counterblox_adapter_contracts.luau
lune run tests/town_adapter_contracts.luau
lune run tests/rivals_combat_state_contracts.luau
lune run tests/rivals_adapter_contracts.luau
lune run tests/shot_presentation_binding_contracts.luau
lune run tests/scoped_accuracy_contracts.luau
printf 'universal-hub-check-ok\n'
