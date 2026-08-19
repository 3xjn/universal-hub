#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
old_commit="8e2d4a84ddb4b7ef901af170966a43b3b35fbaa7"
new_commit="cb1e184c27ffc7639b26cefd55e7f25978b9dcf7"
raw_root="https://raw.githubusercontent.com/3xjn/hydroxide"
temporary_base="${TMPDIR:-/tmp}"
dependency_tmp=$(mktemp -d "$temporary_base/universal-hub-hydroxide-pin.XXXXXX")
case "$dependency_tmp" in
    "$temporary_base"/universal-hub-hydroxide-pin.*) ;;
    *)
        printf 'Unsafe Hydroxide validation directory: %s\n' "$dependency_tmp" >&2
        exit 1
        ;;
esac
cleanup() {
    rm -rf -- "$dependency_tmp"
}
trap cleanup EXIT

mkdir -p "$dependency_tmp/old/modules" "$dependency_tmp/old/tests"
mkdir -p "$dependency_tmp/new/modules" "$dependency_tmp/new/tests"

curl --proto '=https' --tlsv1.2 -fsSL \
    "$raw_root/$old_commit/modules/Targeting.lua" \
    -o "$dependency_tmp/old/modules/Targeting.lua"
for path in Helpers Closure Lifecycle Targeting; do
    curl --proto '=https' --tlsv1.2 -fsSL \
        "$raw_root/$new_commit/modules/$path.lua" \
        -o "$dependency_tmp/new/modules/$path.lua"
done
curl --proto '=https' --tlsv1.2 -fsSL \
    "$raw_root/$new_commit/tests/targeting_module_contracts.luau" \
    -o "$dependency_tmp/new/tests/targeting_module_contracts.luau"
cp "$dependency_tmp/new/tests/targeting_module_contracts.luau" \
    "$dependency_tmp/old/tests/targeting_module_contracts.luau"

OLD_TARGETING_PATH="$dependency_tmp/old/modules/Targeting.lua" \
NEW_TARGETING_PATH="$dependency_tmp/new/modules/Targeting.lua" \
    lune run "$repository_root/tests/hydroxide_pin_contracts.luau"

old_contract_log="$dependency_tmp/old-targeting-contract.log"
if (cd "$dependency_tmp/old" && lune run tests/targeting_module_contracts.luau) \
    >"$old_contract_log" 2>&1
then
    printf 'Old Hydroxide pin unexpectedly satisfies raycastIgnore contracts\n' >&2
    exit 1
fi
if ! grep -Fq 'visibility filter must contain only unique exclusions' "$old_contract_log"; then
    printf 'Old Hydroxide pin failed for an unexpected reason\n' >&2
    sed -n '1,80p' "$old_contract_log" >&2
    exit 1
fi

(cd "$dependency_tmp/new" && lune run tests/targeting_module_contracts.luau)
printf 'hydroxide-pin-contracts-ok\n'
