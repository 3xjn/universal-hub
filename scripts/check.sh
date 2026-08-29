#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repository_root"

for required_tool in curl luau-lsp lune stylua; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        printf 'Missing required tool: %s\n' "$required_tool" >&2
        exit 1
    fi
done

mapfile -t rivals_contracts < <(git ls-files 'tests/rivals_*_contracts.luau')
stylua --check games/rivals "${rivals_contracts[@]}" \
    tests/shot_presentation_binding_contracts.luau \
    tests/scoped_accuracy_contracts.luau \
    tests/runtime_bundle_contracts.luau \
    scripts/build_runtime_bundles.luau \
    hub.lua init.lua loader.lua

roblox_types_commit="cfa5c378c6370f0eca852910e6fbdf8e4d8921c6"
roblox_types="${LOCALAPPDATA:-${TMPDIR:-/tmp}}/hydroxide/typecheck/globalTypes-$roblox_types_commit.d.luau"
hydroxide_root="${HYDROXIDE_ROOT:-../hydroxide}"

if [ ! -f "$roblox_types" ]; then
    printf 'Missing Roblox definitions. Run the Hydroxide check once first.\n' >&2
    exit 1
fi

mapfile -t luau_sources < <(git ls-files '*.lua' | grep -Ev '^(dist|site|vendor|ui/dist)/')

luau-lsp analyze \
    --platform roblox \
    --definitions "@roblox=$roblox_types" \
    --definitions "@volt=$hydroxide_root/_Index/volt/volt.d.luau" \
    "${luau_sources[@]}"

./scripts/check-hydroxide-pin.sh
lune run tests/store_contracts.luau
lune run tests/remote_loader_contracts.luau
lune run tests/request_transport_contracts.luau
lune run tests/runtime_bundle_contracts.luau
lune run tests/hub_loader_contracts.luau
lune run tests/local_loader_contracts.luau
lune run tests/menu_artifact_contracts.luau
lune run tests/config_contracts.luau
lune run tests/changelog_contracts.luau
lune run tests/whats_new_contracts.luau
lune run scripts/changelog.luau -- --check
lune run tests/input_capture_contracts.luau
lune run tests/menu_toggle_contracts.luau
lune run tests/registry_contracts.luau
lune run tests/catalog_contracts.luau
lune run tests/game_composition_contracts.luau
lune run tests/sources_contracts.luau
lune run tests/presentation_host_contracts.luau
for onboarding_contract in tests/game_onboarding/*.luau; do
    lune run "$onboarding_contract"
done
lune run tests/session_contracts.luau
lune run tests/overlay_contracts.luau
lune run tests/limn_consumer_contracts.luau
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
lune run tests/rivals_auto_counter_runtime_contracts.luau
lune run tests/rivals_auto_counter_test_simulator_contracts.luau
lune run tests/rivals_auto_counter_integration_contracts.luau
lune run tests/rivals_adapter_contracts.luau
lune run tests/rivals_camera_aim_contracts.luau
lune run tests/rivals_silent_aim_contracts.luau
lune run tests/rivals_teleport_behind_contracts.luau
lune run tests/rivals_trigger_bot_contracts.luau
lune run tests/rivals_skip_blocks_contracts.luau
lune run tests/rivals_auto_deflect_contracts.luau
lune run tests/rivals_item_input_contracts.luau
lune run tests/rivals_melee_reach_contracts.luau
lune run tests/rivals_noscope_pickup_contracts.luau
lune run tests/rivals_skin_unlock_contracts.luau
lune run tests/rivals_loadout_picker_contracts.luau
lune run tests/rivals_task_counter_policy_contracts.luau
lune run tests/rivals_task_farm_runtime_contracts.luau
lune run tests/rivals_task_locomotion_contracts.luau
lune run tests/rivals_task_movement_contracts.luau
lune run tests/rivals_task_targeting_contracts.luau
lune run tests/rivals_task_weapon_swap_contracts.luau
lune run tests/rivals_frame_lifecycle_contracts.luau
lune run tests/shot_presentation_binding_contracts.luau
lune run tests/scoped_accuracy_contracts.luau
if [ -n "${LIMN_ROOT:-}" ]; then
    cmp "$LIMN_ROOT/dist/Limn.lua" vendor/Limn.lua
fi
printf 'universal-hub-check-ok\n'
