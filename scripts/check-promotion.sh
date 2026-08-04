#!/usr/bin/env bash
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
    printf 'Promotion check requires Bash 4 or newer.\n' >&2
    exit 1
fi

for required_tool in git awk sha256sum; do
    command -v "$required_tool" >/dev/null 2>&1 \
        || { printf 'Promotion check requires %s.\n' "$required_tool" >&2; exit 1; }
done

readonly manifest_path="release/staging-manifest.tsv"
readonly gates_path="release/staging-gates.tsv"
readonly -a required_gates=(
    automated
    performance
    live-rivals
    live-counterblox
    live-town
    cleanup
)

fail() {
    printf 'Promotion check failed: %s\n' "$1" >&2
    exit 1
}

reset_state() {
    schema=""
    channel=""
    build=""
    base=""
    integration=""
    declare -gA candidates=()
    declare -gA gate_status=()
    declare -gA gate_receipt=()
}

set_singleton() {
    local key=$1
    local value=$2
    [[ -z "${!key}" ]] || fail "duplicate $key entry"
    printf -v "$key" '%s' "$value"
}

read_manifest() {
    local file=$1
    [[ -r "$file" ]] || fail "manifest not found: $file"

    local kind field value extra
    local line_number=0
    while IFS=$'\t' read -r kind field value extra || [[ -n "${kind:-}" ]]; do
        line_number=$((line_number + 1))
        [[ -z "${kind:-}" || "$kind" == \#* ]] && continue
        [[ -z "${extra:-}" ]] || fail "manifest line $line_number has too many fields"
        case "$kind" in
            schema|channel|build|base|integration)
                [[ -n "${field:-}" && -z "${value:-}" ]] \
                    || fail "manifest line $line_number has an invalid $kind entry"
                set_singleton "$kind" "$field"
                ;;
            candidate)
                [[ "${field:-}" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] \
                    || fail "manifest line $line_number has an invalid candidate name"
                [[ "${value:-}" =~ ^[0-9a-f]{40}$ ]] \
                    || fail "manifest line $line_number has an invalid candidate SHA"
                [[ -z "${candidates[$field]+set}" ]] || fail "duplicate candidate: $field"
                candidates[$field]=$value
                ;;
            *)
                fail "manifest line $line_number has an unknown entry: $kind"
                ;;
        esac
    done < "$file"

    [[ "$schema" == 1 ]] || fail "schema must be 1"
    [[ "$channel" == staging ]] || fail "channel must be staging"
    [[ "$build" =~ ^staging-[a-z0-9][a-z0-9._-]{0,55}$ ]] || fail "invalid build ID"
    [[ "$base" =~ ^[0-9a-f]{40}$ ]] || fail "invalid base SHA"
    [[ "$integration" =~ ^[0-9a-f]{40}$ ]] || fail "invalid integration SHA"
    (( ${#candidates[@]} == 1 )) || fail "exactly one candidate is required"
}

read_gates() {
    local file=$1
    [[ -r "$file" ]] || fail "gate file not found: $file"

    local kind name status receipt extra
    local line_number=0
    while IFS=$'\t' read -r kind name status receipt extra || [[ -n "${kind:-}" ]]; do
        line_number=$((line_number + 1))
        [[ -z "${kind:-}" || "$kind" == \#* ]] && continue
        [[ "$kind" == gate && -z "${extra:-}" ]] \
            || fail "gate line $line_number has an invalid entry"
        [[ " ${required_gates[*]} " == *" ${name:-} "* ]] \
            || fail "gate line $line_number has an unknown gate"
        [[ "$status" == pass || "$status" == pending || "$status" == blocked ]] \
            || fail "gate line $line_number has an invalid status"
        [[ -n "${receipt:-}" ]] || fail "gate line $line_number has no receipt"
        [[ -z "${gate_status[$name]+set}" ]] || fail "duplicate gate: $name"
        gate_status[$name]=$status
        gate_receipt[$name]=$receipt
    done < "$file"

    local gate
    for gate in "${required_gates[@]}"; do
        [[ -n "${gate_status[$gate]+set}" ]] || fail "missing gate: $gate"
        case "${gate_status[$gate]}" in
            pending)
                [[ "${gate_receipt[$gate]}" == pending ]] \
                    || fail "$gate pending receipt must be 'pending'"
                ;;
            blocked)
                [[ "${gate_receipt[$gate]}" =~ ^blocked:[a-z0-9._-]{1,80}$ ]] \
                    || fail "$gate blocked receipt must name a stable reason"
                ;;
        esac
    done
}

read_evidence() {
    local gate=$1
    local receipt=${gate_receipt[$gate]}
    local expected_path="release/evidence/$gate.tsv"
    [[ "$receipt" =~ ^release/evidence/[a-z-]+\.tsv#sha256=([0-9a-f]{64})$ ]] \
        || fail "$gate pass receipt must be a SHA-256 evidence reference"
    [[ "${receipt%%#*}" == "$expected_path" ]] || fail "$gate receipt path is not canonical"

    local expected_hash=${BASH_REMATCH[1]}
    [[ "$expected_hash" != 0000000000000000000000000000000000000000000000000000000000000000 ]] \
        || fail "$gate receipt uses a placeholder hash"
    local actual_hash
    if [[ "${promotion_committed:-false}" == true ]]; then
        [[ "$(git ls-tree HEAD -- "$expected_path" | awk '{ print $1 }')" == 100644 ]] \
            || fail "$gate evidence must be a committed regular file"
        actual_hash=$(git show "HEAD:$expected_path" | sha256sum | awk '{print $1}')
    else
        [[ -f "$expected_path" && ! -L "$expected_path" ]] || fail "$gate evidence file is missing"
        actual_hash=$(sha256sum -- "$expected_path" | awk '{print $1}')
    fi
    [[ "$actual_hash" == "$expected_hash" ]] || fail "$gate evidence hash does not match"

    declare -gA evidence=()
    parse_evidence_fields() {
        local key value extra
        while IFS=$'\t' read -r key value extra || [[ -n "${key:-}" ]]; do
            [[ -z "${key:-}" || "$key" == \#* ]] && continue
            [[ "$key" =~ ^[a-z][a-z0-9_]*$ && -n "${value:-}" && -z "${extra:-}" ]] \
                || fail "$gate evidence has an invalid field"
            [[ -z "${evidence[$key]+set}" ]] || fail "$gate evidence repeats $key"
            evidence[$key]=$value
        done
    }
    if [[ "${promotion_committed:-false}" == true ]]; then
        parse_evidence_fields < <(git show "HEAD:$expected_path")
    else
        parse_evidence_fields < "$expected_path"
    fi
    unset -f parse_evidence_fields

    [[ "${evidence[build]:-}" == "$build" ]] || fail "$gate evidence build mismatch"
    [[ "${evidence[integration]:-}" == "$integration" ]] || fail "$gate evidence integration mismatch"
    [[ "${evidence[gate]:-}" == "$gate" ]] || fail "$gate evidence gate mismatch"
    [[ "${evidence[result]:-}" == pass ]] || fail "$gate evidence does not report pass"
    [[ "${evidence[artifact_sha256]:-}" =~ ^[0-9a-f]{64}$ ]] \
        || fail "$gate evidence has no artifact digest"
    [[ "${evidence[artifact_sha256]}" != 0000000000000000000000000000000000000000000000000000000000000000 ]] \
        || fail "$gate evidence uses a placeholder artifact digest"
    [[ "${evidence[artifact_path]:-}" =~ ^release/evidence/artifacts/[a-z-]+\.[a-z0-9]+$ ]] \
        || fail "$gate evidence has no canonical artifact path"
    [[ "${evidence[artifact_path]}" == release/evidence/artifacts/"$gate".* ]] \
        || fail "$gate artifact path is not canonical"
    local artifact_hash
    if [[ "${promotion_committed:-false}" == true ]]; then
        [[ "$(git ls-tree HEAD -- "${evidence[artifact_path]}" | awk '{ print $1 }')" == 100644 ]] \
            || fail "$gate artifact must be a committed regular file"
        artifact_hash=$(git show "HEAD:${evidence[artifact_path]}" | sha256sum | awk '{ print $1 }')
    else
        [[ -f "${evidence[artifact_path]}" && ! -L "${evidence[artifact_path]}" ]] \
            || fail "$gate artifact file is missing"
        artifact_hash=$(sha256sum -- "${evidence[artifact_path]}" | awk '{ print $1 }')
    fi
    [[ "$artifact_hash" == "${evidence[artifact_sha256]}" ]] \
        || fail "$gate artifact hash does not match"

    case "$gate" in
        automated)
            [[ "${evidence[exit_code]:-}" == 0 ]] \
                || fail "automated evidence must record a successful command"
            [[ "${evidence[command]:-}" =~ ^(HYDROXIDE_ROOT=[A-Za-z0-9_./:-]+[[:space:]]+)?\./scripts/check\.sh$ ]] \
                || fail "automated evidence must run the full repository check"
            ;;
        performance)
            local number='^[0-9]+([.][0-9]+)?$'
            for key in hub_stopped_fps ui_only_fps adapter_all_off_fps adapter_all_off_ms sample_seconds; do
                [[ "${evidence[$key]:-}" =~ $number ]] || fail "performance evidence has invalid $key"
            done
            for key in observations rays entity_writes geometry; do
                [[ "${evidence[$key]:-}" == 0 ]] || fail "performance evidence requires $key=0"
            done
            awk -v value="${evidence[adapter_all_off_ms]}" 'BEGIN { exit !(value <= 0.25) }' \
                || fail "Adapter all-off cost exceeds 0.25 ms/frame"
            awk -v stopped="${evidence[hub_stopped_fps]}" -v ui="${evidence[ui_only_fps]}" \
                -v idle="${evidence[adapter_all_off_fps]}" \
                'BEGIN { exit !(stopped > 0 && ui / stopped >= 0.95 && idle / stopped >= 0.95) }' \
                || fail "UI-only or Adapter all-off FPS is below 95% of stopped baseline"
            awk -v seconds="${evidence[sample_seconds]}" 'BEGIN { exit !(seconds >= 10) }' \
                || fail "performance sample must be at least 10 seconds"
            [[ -n "${evidence[fixed_scene]:-}" ]] || fail "performance evidence must name the fixed scene"
            ;;
        live-rivals|live-counterblox|live-town)
            for key in zero_actions reload_cleanup final_cleanup production_config_unchanged; do
                [[ "${evidence[$key]:-}" == true ]] || fail "$gate evidence requires $key=true"
            done
            ;;
        cleanup)
            for key in resources canvases connections; do
                [[ "${evidence[$key]:-}" == 0 ]] || fail "cleanup evidence requires $key=0"
            done
            [[ "${evidence[session_cleared]:-}" == true ]] \
                || fail "cleanup evidence requires session_cleared=true"
            ;;
    esac
}

check_gate_mode() {
    local mode=$1
    [[ "$mode" == staging || "$mode" == production ]] || fail "mode must be staging or production"
    [[ "${gate_status[automated]}" == pass ]] || fail "automated gate must pass before staging"

    local gate
    for gate in "${required_gates[@]}"; do
        if [[ "${gate_status[$gate]}" == pass ]]; then
            read_evidence "$gate"
        elif [[ "$mode" == production ]]; then
            fail "$gate gate is ${gate_status[$gate]}"
        fi
    done
}

check_fixed_inputs() {
    [[ -z "$(git status --porcelain --untracked-files=all)" ]] || fail "worktree is not clean"
    local path
    for path in "$manifest_path" "$gates_path"; do
        [[ "$(git ls-tree HEAD -- "$path" | awk '{ print $1 }')" == 100644 ]] \
            || fail "$path must be a committed regular file"
    done
}

check_git_identity() {

    local branch=${PROMOTION_BRANCH:-${GITHUB_HEAD_REF:-$(git branch --show-current)}}
    [[ "$branch" == "codex/$build" ]] || fail "branch must be codex/$build"

    local remote_main
    remote_main=$(git ls-remote --exit-code origin refs/heads/main | awk 'NR == 1 { print $1 }')
    [[ "$remote_main" == "$base" ]] || fail "base is not the current remote main"

    local sha name
    for sha in "$base" "$integration"; do
        git cat-file -e "$sha^{commit}" 2>/dev/null || fail "unknown commit: $sha"
    done
    git merge-base --is-ancestor "$base" "$integration" \
        || fail "integration does not descend from base"
    git merge-base --is-ancestor "$integration" HEAD \
        || fail "current HEAD does not contain integration"

    local -a integration_line=()
    read -r -a integration_line <<< "$(git rev-list --parents -n 1 "$integration")"
    local parent_count=$((${#integration_line[@]} - 1))
    (( parent_count == 2 )) || fail "integration must have exactly two parents"
    [[ "${integration_line[1]}" == "$base" ]] \
        || fail "integration first parent must be the exact base"

    for name in "${!candidates[@]}"; do
        sha=${candidates[$name]}
        git cat-file -e "$sha^{commit}" 2>/dev/null || fail "unknown candidate commit: $name"
        git merge-base "$base" "$sha" >/dev/null 2>&1 \
            || fail "candidate $name has no mainline ancestry"
        git merge-base --is-ancestor "$sha" "$base" \
            && fail "candidate $name is already contained in base"
        [[ "${integration_line[2]}" == "$sha" ]] \
            || fail "integration second parent is not candidate $name"
        local expected_tree
        expected_tree=$(git merge-tree --write-tree --no-messages "$base" "$sha") \
            || fail "candidate does not merge cleanly into base"
        [[ "$expected_tree" == "$(git rev-parse "$integration^{tree}")" ]] \
            || fail "integration tree differs from the automatic candidate merge"
    done

    local -a receipt_commits=()
    mapfile -t receipt_commits < <(git rev-list --reverse "$integration"..HEAD)
    (( ${#receipt_commits[@]} > 0 )) || fail "staging identity commit is missing"
    [[ "$(git rev-parse "${receipt_commits[0]}^1")" == "$integration" ]] \
        || fail "identity commit must directly follow integration"
    [[ -z "$(git rev-list --merges "$integration"..HEAD)" ]] \
        || fail "receipt history must not contain merges"

    local identity_commit=${receipt_commits[0]}
    [[ "$(git rev-parse "$identity_commit:$manifest_path")" == "$(git rev-parse "HEAD:$manifest_path")" ]] \
        || fail "staging identity changed after its first receipt commit"

    local identity_automated head_automated
    identity_automated=$(git show "$identity_commit:$gates_path" \
        | awk -F '\t' '$1 == "gate" && $2 == "automated" { print $0 }')
    head_automated=$(git show "HEAD:$gates_path" \
        | awk -F '\t' '$1 == "gate" && $2 == "automated" { print $0 }')
    [[ "$identity_automated" == "$head_automated" && "$identity_automated" == *$'\tpass\t'* ]] \
        || fail "automated gate must pass and remain unchanged from the identity commit"
    for path in release/evidence/automated.tsv release/evidence/artifacts/automated.*; do
        local -a identity_matches=()
        mapfile -t identity_matches < <(git ls-tree -r --name-only "$identity_commit" -- "$path")
        (( ${#identity_matches[@]} == 1 )) \
            || fail "identity commit must contain one automated $path receipt"
        [[ "$(git ls-tree "$identity_commit" -- "${identity_matches[0]}" | awk '{ print $1 }')" == 100644 ]] \
            || fail "identity automated receipt must be a regular file"
        [[ "$(git rev-parse "$identity_commit:${identity_matches[0]}")" == "$(git rev-parse "HEAD:${identity_matches[0]}")" ]] \
            || fail "automated receipt changed after the identity commit"
    done

    local commit path
    for commit in "${receipt_commits[@]}"; do
        while IFS= read -r path; do
            case "$path" in
                "$manifest_path"|"$gates_path"|release/evidence/*.tsv|release/evidence/artifacts/*) ;;
                *) fail "commit $commit changes code after integration: $path" ;;
            esac
            if [[ "$commit" != "$identity_commit" && "$path" == "$manifest_path" ]]; then
                fail "staging identity changed after integration"
            fi
        done < <(git diff-tree --no-commit-id --name-only -r "$commit")
    done

    local gate
    for gate in "${required_gates[@]}"; do
        if [[ "${gate_status[$gate]}" == pass ]]; then
            git ls-files --error-unmatch "release/evidence/$gate.tsv" >/dev/null 2>&1 \
                || fail "$gate evidence must be tracked"
        fi
    done
}

write_fixture_evidence() {
    local root=$1
    local gate=$2
    local fixture_build=${3:-staging-self-test}
    local fixture_integration=${4:-1111111111111111111111111111111111111111}
    local file="$root/release/evidence/$gate.tsv"
    local artifact="$root/release/evidence/artifacts/$gate.txt"
    mkdir -p "$root/release/evidence/artifacts"
    printf 'fixture artifact for %s\n' "$gate" > "$artifact"
    local artifact_hash
    artifact_hash=$(sha256sum -- "$artifact" | awk '{ print $1 }')
    {
        printf 'build\t%s\n' "$fixture_build"
        printf 'integration\t%s\n' "$fixture_integration"
        printf 'gate\t%s\n' "$gate"
        printf 'result\tpass\n'
        printf 'artifact_path\trelease/evidence/artifacts/%s.txt\n' "$gate"
        printf 'artifact_sha256\t%s\n' "$artifact_hash"
        case "$gate" in
            automated)
                printf 'command\t./scripts/check.sh\nexit_code\t0\n'
                ;;
            performance)
                printf 'hub_stopped_fps\t240\nui_only_fps\t239\nadapter_all_off_fps\t238\n'
                printf 'adapter_all_off_ms\t0.20\nsample_seconds\t10\nfixed_scene\tfixture\n'
                printf 'observations\t0\nrays\t0\nentity_writes\t0\ngeometry\t0\n'
                ;;
            live-rivals|live-counterblox|live-town)
                printf 'zero_actions\ttrue\nreload_cleanup\ttrue\nfinal_cleanup\ttrue\n'
                printf 'production_config_unchanged\ttrue\n'
                ;;
            cleanup)
                printf 'resources\t0\ncanvases\t0\nconnections\t0\nsession_cleared\ttrue\n'
                ;;
        esac
    } > "$file"
    sha256sum -- "$file" | awk '{ print $1 }'
}

test_git_identity() {
    local root=$1
    local origin="$root/origin.git"
    local repository="$root/repository"
    git init --quiet --bare "$origin"
    git init --quiet --initial-branch=main "$repository"
    (
        cd "$repository"
        git config user.name promotion-test
        git config user.email promotion-test@example.invalid
        printf 'base\n' > tracked.txt
        git add tracked.txt
        git commit --quiet -m base
        git remote add origin "$origin"
        git push --quiet --set-upstream origin main
        local fixture_base
        fixture_base=$(git rev-parse HEAD)

        git switch --quiet -c candidate
        printf 'candidate\n' > candidate.txt
        git add candidate.txt
        git commit --quiet -m candidate
        local fixture_candidate
        fixture_candidate=$(git rev-parse HEAD)

        git switch --quiet -c codex/staging-self-test "$fixture_base"
        git merge --quiet --no-ff -m integration "$fixture_candidate"
        local fixture_integration
        fixture_integration=$(git rev-parse HEAD)

        mkdir -p release/evidence
        local automated_hash
        automated_hash=$(write_fixture_evidence \
            "$repository" automated staging-self-test "$fixture_integration")
        {
            printf 'schema\t1\nchannel\tstaging\nbuild\tstaging-self-test\n'
            printf 'base\t%s\nintegration\t%s\n' "$fixture_base" "$fixture_integration"
            printf 'candidate\tfixture\t%s\n' "$fixture_candidate"
        } > "$manifest_path"
        {
            printf 'gate\tautomated\tpass\trelease/evidence/automated.tsv#sha256=%s\n' \
                "$automated_hash"
            printf 'gate\tperformance\tpending\tpending\n'
            printf 'gate\tlive-rivals\tpending\tpending\n'
            printf 'gate\tlive-counterblox\tpending\tpending\n'
            printf 'gate\tlive-town\tpending\tpending\n'
            printf 'gate\tcleanup\tpending\tpending\n'
        } > "$gates_path"
        git add release
        git commit --quiet -m identity

        reset_state
        promotion_committed=true
        read_manifest <(git show "HEAD:$manifest_path")
        read_gates <(git show "HEAD:$gates_path")
        check_fixed_inputs
        check_gate_mode staging
        check_git_identity

        printf 'tamper\n' >> release/evidence/artifacts/automated.txt
        git add release/evidence/artifacts/automated.txt
        git commit --quiet -m tamper
        if (
            reset_state
            promotion_committed=true
            read_manifest <(git show "HEAD:$manifest_path")
            read_gates <(git show "HEAD:$gates_path")
            check_git_identity
        ) >/dev/null 2>&1; then
            fail "automated receipt mutation was accepted"
        fi
    )
}

self_test() {
    self_test_root=$(mktemp -d)
    [[ -n "$self_test_root" && -d "$self_test_root" ]] || fail "could not create self-test directory"
    trap 'if [[ -n "${self_test_root:-}" && -d "$self_test_root" ]]; then rm -rf -- "$self_test_root"; fi' EXIT
    mkdir -p "$self_test_root/release/evidence"

    reset_state
    cat > "$self_test_root/manifest.tsv" <<'EOF'
schema	1
channel	staging
build	staging-self-test
base	0000000000000000000000000000000000000000
integration	1111111111111111111111111111111111111111
candidate	fixture	2222222222222222222222222222222222222222
EOF
    read_manifest "$self_test_root/manifest.tsv"

    local automated_hash
    automated_hash=$(write_fixture_evidence "$self_test_root" automated)
    cat > "$self_test_root/gates.tsv" <<EOF
gate	automated	pass	release/evidence/automated.tsv#sha256=$automated_hash
gate	performance	pending	pending
gate	live-rivals	pending	pending
gate	live-counterblox	pending	pending
gate	live-town	pending	pending
gate	cleanup	pending	pending
EOF
    (
        cd "$self_test_root"
        read_gates gates.tsv
        check_gate_mode staging
    ) || fail "valid staging evidence was rejected"
    if (
        cd "$self_test_root"
        read_gates gates.tsv
        check_gate_mode production
    ) >/dev/null 2>&1; then
        fail "pending gates were not enforced"
    fi

    local gate hash
    : > "$self_test_root/gates.tsv"
    for gate in "${required_gates[@]}"; do
        hash=$(write_fixture_evidence "$self_test_root" "$gate")
        printf 'gate\t%s\tpass\trelease/evidence/%s.tsv#sha256=%s\n' \
            "$gate" "$gate" "$hash" >> "$self_test_root/gates.tsv"
    done
    (
        cd "$self_test_root"
        read_gates gates.tsv
        check_gate_mode production
    ) || fail "valid production evidence was rejected"

    cp "$self_test_root/gates.tsv" "$self_test_root/invalid-gates.tsv"
    printf 'gate\tautomated\tpass\tTODO\n' > "$self_test_root/invalid-gates.tsv"
    for gate in performance live-rivals live-counterblox live-town cleanup; do
        printf 'gate\t%s\tpending\tpending\n' "$gate" >> "$self_test_root/invalid-gates.tsv"
    done
    if (
        cd "$self_test_root"
        read_gates invalid-gates.tsv
        check_gate_mode staging
    ) >/dev/null 2>&1; then
        fail "placeholder pass receipt was accepted"
    fi

    test_git_identity "$self_test_root/git-identity"

    rm -rf -- "$self_test_root"
    self_test_root=""
    trap - EXIT
    printf 'promotion-contracts-ok\n'
}

if [[ "${1:-}" == --self-test ]]; then
    self_test
    exit 0
fi

mode=${1:-staging}
[[ $# -le 1 ]] || fail "custom manifest paths are not supported"
reset_state
check_fixed_inputs
promotion_committed=true
read_manifest <(git show "HEAD:$manifest_path")
read_gates <(git show "HEAD:$gates_path")
check_gate_mode "$mode"
check_git_identity

printf 'promotion-check-ok build=%s mode=%s integration=%s candidates=%s\n' \
    "$build" "$mode" "$integration" "${#candidates[@]}"
