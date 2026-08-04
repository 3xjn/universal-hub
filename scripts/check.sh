#!/usr/bin/env bash
set -euo pipefail

repository_root=${REPOSITORY_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
cd "$repository_root"

for required_tool in curl sha256sum luau-lsp lune; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        printf 'Missing required tool: %s\n' "$required_tool" >&2
        exit 1
    fi
done

roblox_types_commit="cfa5c378c6370f0eca852910e6fbdf8e4d8921c6"
roblox_types_sha256="3e504a7248e26614fed5a3e4206d11ef86dfcec14d3775098b1e18e4a1d8b1e1"
cache_root="${XDG_CACHE_HOME:-${LOCALAPPDATA:-${TMPDIR:-/tmp}}}/hydroxide/typecheck"
roblox_types="$cache_root/globalTypes-$roblox_types_commit.d.luau"
hydroxide_root="${HYDROXIDE_ROOT:-../hydroxide}"
promotion_check_script=${PROMOTION_CHECK_SCRIPT:-./scripts/check-promotion.sh}

mkdir -p "$cache_root"

if [ ! -f "$roblox_types" ] \
    || ! printf '%s  %s\n' "$roblox_types_sha256" "$roblox_types" | sha256sum --check --status; then
    curl --fail --location --silent --show-error \
        "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$roblox_types_commit/scripts/globalTypes.d.luau" \
        --output "$roblox_types"
fi

printf '%s  %s\n' "$roblox_types_sha256" "$roblox_types" | sha256sum --check --status

"$promotion_check_script" --self-test

mapfile -t luau_sources < <(git ls-files '*.lua' | grep -Ev '^(site|vendor)/')

luau-lsp analyze \
    --platform roblox \
    --definitions "@roblox=$roblox_types" \
    --definitions "@volt=$hydroxide_root/_Index/volt/volt.d.luau" \
    "${luau_sources[@]}"

mapfile -t candidate_contract_tests < <(
    git ls-files 'tests/*.luau' 'tests/**/*.luau' \
        | grep '_contracts\.luau$' \
        | sort -u
)
contract_tests=("${candidate_contract_tests[@]}")
if [[ -n "${TRUSTED_BASE_SHA:-}" ]]; then
    git cat-file -e "$TRUSTED_BASE_SHA^{commit}" 2>/dev/null \
        || { printf 'Unknown trusted base SHA: %s\n' "$TRUSTED_BASE_SHA" >&2; exit 1; }
    mapfile -t trusted_contract_tests < <(
        git ls-tree -r --name-only "$TRUSTED_BASE_SHA" -- tests \
            | grep '_contracts\.luau$' \
            | sort -u
    )
    trusted_test_root=$(mktemp -d)
    [[ -n "$trusted_test_root" && -d "$trusted_test_root" ]] \
        || { printf 'Could not create trusted test worktree.\n' >&2; exit 1; }
    rmdir "$trusted_test_root"
    git worktree add --quiet --detach "$trusted_test_root" HEAD
    trap 'git worktree remove --force "${trusted_test_root:-}" >/dev/null 2>&1 || true' EXIT
    for contract_test in "${trusted_contract_tests[@]}"; do
        [[ "$(git ls-tree HEAD -- "$contract_test" | awk '{ print $1 }')" == 100644 ]] \
            || { printf 'Candidate removed or replaced required contract: %s\n' "$contract_test" >&2; exit 1; }
        [[ "$(git ls-tree "$TRUSTED_BASE_SHA" -- "$contract_test" | awk '{ print $1 }')" == 100644 ]] \
            || { printf 'Trusted contract is not a regular file: %s\n' "$contract_test" >&2; exit 1; }
        git -C "$trusted_test_root" reset --quiet --hard HEAD
        rm -f -- "$trusted_test_root/$contract_test"
        git show "$TRUSTED_BASE_SHA:$contract_test" > "$trusted_test_root/$contract_test"
        if [[ "$contract_test" == tests/town_large_copy_integration_contracts.luau ]]; then
            (cd "$trusted_test_root" && TOWN_TEST_COUNT=256 lune run "$contract_test")
        fi
        (cd "$trusted_test_root" && lune run "$contract_test")
    done
    mapfile -t contract_tests < <(
        for contract_test in "${candidate_contract_tests[@]}"; do
            if git cat-file -e "$TRUSTED_BASE_SHA:$contract_test" 2>/dev/null \
                && [[ "$(git rev-parse "$TRUSTED_BASE_SHA:$contract_test")" == \
                    "$(git rev-parse "HEAD:$contract_test")" ]]; then
                continue
            fi
            printf '%s\n' "$contract_test"
        done
    )
    git worktree remove --force "$trusted_test_root"
    trusted_test_root=""
    trap - EXIT
fi
for contract_test in "${contract_tests[@]}"; do
    if [[ "$contract_test" == tests/town_large_copy_integration_contracts.luau ]]; then
        TOWN_TEST_COUNT=256 lune run "$contract_test"
    fi
    lune run "$contract_test"
done
printf 'universal-hub-check-ok\n'
