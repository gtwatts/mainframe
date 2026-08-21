#!/usr/bin/env bats
# Compatibility contract for the resolved AWM facade/advanced-module collisions.

load 'test_helper'

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    BASH_BIN="${MAINFRAME_BASH:-$(command -v bash)}"
    TEST_HOME="$BATS_TEST_TMPDIR/home"
    TEST_AWM_ROOT="$BATS_TEST_TMPDIR/awm"
    TEST_STORAGE_ROOT="$BATS_TEST_TMPDIR/awm-v2"
    mkdir -p "$TEST_HOME" "$TEST_AWM_ROOT" "$TEST_STORAGE_ROOT"
}

canonical_awm_names='awm_compress awm_handoff_prepare awm_handoff_accept'
alternate_awm_names='awm_stream_compress awm_protocol_handoff_prepare awm_protocol_handoff_accept'
all_awm_names="$canonical_awm_names $alternate_awm_names"

awm_body_probe='\
for name in $MAINFRAME_AWM_CONTRACT_NAMES; do
    if declare -F "$name" >/dev/null 2>&1; then
        printf "%s\t%s\n" "$name" "$(declare -f "$name" | cksum)"
    else
        printf "%s\tabsent\n" "$name"
    fi
done
'

# Every subprocess gets private facade and v2 storage roots. MAINFRAME_CONFIG is
# fixed to /dev/null so a developer's real profile can never influence a probe.
isolated_env() {
    env \
        -u MAINFRAME_LIBS \
        -u MAINFRAME_PROFILE \
        -u MAINFRAME_LAZY \
        -u MAINFRAME_DEFAULT_LIBS \
        -u MAINFRAME_SKIP_AUTOLOAD \
        HOME="$TEST_HOME" \
        AWM_ROOT="$TEST_AWM_ROOT" \
        MAINFRAME_AWM_DIR="$TEST_STORAGE_ROOT" \
        MAINFRAME_STORAGE=file \
        MAINFRAME_CONFIG=/dev/null \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        "$@"
}

body_map_for_libraries() {
    local libraries="$1"
    local action="${2:-:}"

    isolated_env \
        MAINFRAME_LIBS="$libraries" \
        MAINFRAME_AWM_CONTRACT_NAMES="$all_awm_names" \
        MAINFRAME_AWM_BODY_PROBE="$awm_body_probe" \
        MAINFRAME_AWM_ACTION="$action" \
        "$BASH_BIN" --noprofile --norc -c '
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            eval "$MAINFRAME_AWM_ACTION"
            eval "$MAINFRAME_AWM_BODY_PROBE"
        '
}

body_map_for_profile() {
    local profile="$1"
    local action="${2:-:}"

    isolated_env \
        MAINFRAME_PROFILE="$profile" \
        MAINFRAME_AWM_CONTRACT_NAMES="$all_awm_names" \
        MAINFRAME_AWM_BODY_PROBE="$awm_body_probe" \
        MAINFRAME_AWM_ACTION="$action" \
        "$BASH_BIN" --noprofile --norc -c '
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            eval "$MAINFRAME_AWM_ACTION"
            eval "$MAINFRAME_AWM_BODY_PROBE"
        '
}

body_map_for_default() {
    isolated_env \
        MAINFRAME_AWM_CONTRACT_NAMES="$all_awm_names" \
        MAINFRAME_AWM_BODY_PROBE="$awm_body_probe" \
        "$BASH_BIN" --noprofile --norc -c '
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            eval "$MAINFRAME_AWM_BODY_PROBE"
        '
}

@test "AWM facade bodies are canonical in eager profiles and opt-in from smaller profiles" {
    local canonical_stream_reference canonical_reference actual profile

    canonical_reference=$(body_map_for_libraries awm)
    canonical_stream_reference=$(body_map_for_libraries awm,awm_stream)

    actual=$(body_map_for_default)
    [ "$actual" = "$canonical_stream_reference" ]

    for profile in full ai; do
        actual=$(body_map_for_profile "$profile")
        [ "$actual" = "$canonical_stream_reference" ]
    done

    for profile in minimal standard; do
        actual=$(body_map_for_profile "$profile")
        [[ "$actual" == *$'awm_compress\tabsent'* ]]
        [[ "$actual" == *$'awm_handoff_prepare\tabsent'* ]]
        [[ "$actual" == *$'awm_handoff_accept\tabsent'* ]]

        actual=$(body_map_for_profile "$profile" 'mainframe_load awm >/dev/null 2>&1')
        [ "$actual" = "$canonical_reference" ]
    done
}

@test "selective AWM module permutations preserve all six owners" {
    local canonical_reference stream_reference protocol_reference
    local canonical_stream_reference all_reference actual libraries expected

    canonical_reference=$(body_map_for_libraries awm)
    stream_reference=$(body_map_for_libraries awm_stream)
    protocol_reference=$(body_map_for_libraries awm_protocol)
    canonical_stream_reference=$(body_map_for_libraries awm,awm_stream)
    all_reference=$(body_map_for_libraries awm,awm_protocol)

    for libraries in \
        awm awm_stream awm_protocol \
        awm,awm_stream awm_stream,awm \
        awm,awm_protocol awm_protocol,awm \
        awm_stream,awm_protocol awm_protocol,awm_stream \
        awm,awm_stream,awm_protocol awm,awm_protocol,awm_stream \
        awm_stream,awm,awm_protocol awm_stream,awm_protocol,awm \
        awm_protocol,awm,awm_stream awm_protocol,awm_stream,awm \
        all; do
        case "$libraries" in
            awm) expected="$canonical_reference" ;;
            awm_stream) expected="$stream_reference" ;;
            awm_protocol|awm_stream,awm_protocol|awm_protocol,awm_stream)
                expected="$protocol_reference"
                ;;
            awm,awm_stream|awm_stream,awm|all)
                expected="$canonical_stream_reference"
                ;;
            awm,awm_protocol|awm_protocol,awm)
                expected="$all_reference"
                ;;
            awm,awm_stream,awm_protocol|awm,awm_protocol,awm_stream|\
            awm_stream,awm,awm_protocol|awm_stream,awm_protocol,awm|\
            awm_protocol,awm,awm_stream|awm_protocol,awm_stream,awm)
                expected="$all_reference"
                ;;
        esac

        actual=$(body_map_for_libraries "$libraries")
        [ "$actual" = "$expected" ]
    done
}

@test "load-all closure and explicit late modules preserve facade bodies" {
    local canonical_stream_reference all_reference actual

    canonical_stream_reference=$(body_map_for_libraries awm,awm_stream)
    all_reference=$(body_map_for_libraries awm,awm_protocol)

    actual=$(body_map_for_profile minimal 'mainframe_load_all >/dev/null 2>&1')
    # The canonical load-all closure intentionally excludes the legacy
    # protocol-v4 compatibility module; it remains an explicit opt-in below.
    [ "$actual" = "$canonical_stream_reference" ]

    actual=$(body_map_for_libraries awm 'mainframe_load awm_stream >/dev/null 2>&1')
    [ "$actual" = "$canonical_stream_reference" ]

    actual=$(body_map_for_libraries awm 'mainframe_load awm_protocol >/dev/null 2>&1')
    [ "$actual" = "$all_reference" ]

    actual=$(body_map_for_libraries awm_protocol 'mainframe_load awm >/dev/null 2>&1')
    [ "$actual" = "$all_reference" ]

    actual=$(body_map_for_libraries awm 'awm_v2_init >/dev/null 2>&1')
    [ "$actual" = "$canonical_stream_reference" ]
}

@test "explicit streaming and protocol-v4 names retain their distinct behavior" {
    run isolated_env \
        MAINFRAME_LIBS=awm,awm_protocol \
        "$BASH_BIN" --noprofile --norc -c '
            set -euo pipefail
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1

            normalized=$(awm_stream_compress "  lots   of    spaces   " 1)
            [[ "$normalized" == "lots of spaces" ]]
            summary=$(awm_stream_compress $'"'"'Line 1\nLine 2\nLine 3'"'"' 5)
            [[ "$summary" == *"Compressed:"* ]]
            [[ "$summary" == *"3 lines"* ]]
            [[ "$summary" == *"6 words"* ]]
            [[ "$summary" == *"20 chars"* ]]

            awm_storage_init >/dev/null
            awm_agent_register parent_agent orchestrate >/dev/null
            awm_budget_init >/dev/null
            awm_store_push "session:parent_agent:discoveries" '"'"'"important finding"'"'"' >/dev/null

            handoff=$(awm_protocol_handoff_prepare child_agent 32000)
            jq -e ".type == \"handoff\" and
                .parent_agent == \"parent_agent\" and
                .target_agent == \"child_agent\" and
                (.contextId | startswith(\"ctx_\")) and
                .budget_remaining > 0 and
                (has(\"parent_session\") | not)" \
                <<< "$handoff" >/dev/null
            context_id=$(jq -r .contextId <<< "$handoff")

            awm_agent_register child_agent execute >/dev/null
            awm_protocol_handoff_accept "$handoff" >/dev/null
            [[ "$(awm_context_get)" == "$context_id" ]]
            [[ "$(awm_store_len session:child_agent:inherited_discoveries)" == 1 ]]
            [[ "$(awm_store_get session:child_agent:handoff)" == "$handoff" ]]

            declare -f awm_compress | grep -q _awm_compress_log
            declare -f awm_handoff_prepare | grep -q _awm_locked_atomic_write
            declare -f awm_handoff_accept | grep -q parent_session
            printf explicit-awm-alternates-ok
        '
    [ "$status" -eq 0 ]
    [ "$output" = explicit-awm-alternates-ok ]
}

@test "lazy calls load canonical and alternate AWM owners in either order" {
    run isolated_env \
        MAINFRAME_PROFILE=lazy \
        MAINFRAME_AWM_DIR="$TEST_STORAGE_ROOT/canonical-first" \
        "$BASH_BIN" --noprofile --norc -c '
            set -euo pipefail
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1

            [[ "${_LAZY_MANIFEST[awm_compress]}" == awm ]]
            [[ "${_LAZY_MANIFEST[awm_handoff_prepare]}" == awm ]]
            [[ "${_LAZY_MANIFEST[awm_handoff_accept]}" == awm ]]
            [[ "${_LAZY_MANIFEST[awm_stream_compress]}" == awm_stream ]]
            [[ "${_LAZY_MANIFEST[awm_protocol_handoff_prepare]}" == awm_protocol ]]
            [[ "${_LAZY_MANIFEST[awm_protocol_handoff_accept]}" == awm_protocol ]]
            for name in \
                awm_compress awm_handoff_prepare awm_handoff_accept \
                awm_stream_compress \
                awm_protocol_handoff_prepare awm_protocol_handoff_accept; do
                lazy_is_stub "$name"
            done

            if awm_compress >/dev/null 2>&1; then
                exit 1
            fi
            if lazy_is_stub awm_compress ||
               lazy_is_stub awm_handoff_prepare ||
               lazy_is_stub awm_handoff_accept; then
                exit 1
            fi
            declare -f awm_compress | grep -q _awm_compress_log
            declare -f awm_handoff_prepare | grep -q _awm_locked_atomic_write
            declare -f awm_handoff_accept | grep -q parent_session

            # Run the first lazy call in this shell. Command substitution would
            # correctly isolate the lazy-loader state in a subshell, which
            # cannot prove that the parent-shell marker was reconciled.
            stream_output="$HOME/canonical-first-stream.txt"
            awm_stream_compress "  alpha   beta  " 1 > "$stream_output"
            [[ "$(<"$stream_output")" == "alpha beta" ]]
            if lazy_is_stub awm_stream_compress; then
                exit 1
            fi

            handoff_output="$HOME/canonical-first-handoff.json"
            awm_protocol_handoff_prepare child_agent 32000 > "$handoff_output"
            handoff=$(<"$handoff_output")
            jq -e ".type == \"handoff\" and .target_agent == \"child_agent\"" \
                <<< "$handoff" >/dev/null
            if lazy_is_stub awm_protocol_handoff_prepare ||
               lazy_is_stub awm_protocol_handoff_accept; then
                exit 1
            fi
            declare -f awm_compress | grep -q _awm_compress_log
            printf canonical-first-ok
        '
    [ "$status" -eq 0 ]
    [ "$output" = canonical-first-ok ]

    run isolated_env \
        MAINFRAME_PROFILE=lazy \
        MAINFRAME_AWM_DIR="$TEST_STORAGE_ROOT/alternate-first" \
        "$BASH_BIN" --noprofile --norc -c '
            set -euo pipefail
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1

            handoff='"'"'{"contextId":"ctx_lazy_accept","budget_remaining":32000,"discoveries":[],"parent_agent":null}'"'"'
            awm_protocol_handoff_accept "$handoff" >/dev/null
            [[ "$(awm_context_get)" == ctx_lazy_accept ]]
            if lazy_is_stub awm_protocol_handoff_prepare ||
               lazy_is_stub awm_protocol_handoff_accept; then
                exit 1
            fi
            # awm_protocol sources awm_stream as a dependency; lazy bookkeeping
            # must agree that the real streaming body is already present.
            if lazy_is_stub awm_stream_compress; then
                exit 1
            fi
            [[ "$(awm_stream_compress "  alternate   first  " 1)" == "alternate first" ]]

            if awm_compress >/dev/null 2>&1; then
                exit 1
            fi
            if lazy_is_stub awm_compress ||
               lazy_is_stub awm_handoff_prepare ||
               lazy_is_stub awm_handoff_accept; then
                exit 1
            fi
            declare -f awm_compress | grep -q _awm_compress_log
            declare -f awm_handoff_prepare | grep -q _awm_locked_atomic_write
            declare -f awm_handoff_accept | grep -q parent_session
            declare -f awm_stream_compress | grep -q "local content"
            declare -f awm_protocol_handoff_prepare | grep -q contextId
            declare -f awm_protocol_handoff_accept | grep -q awm_context_set
            printf alternate-first-ok
        '
    [ "$status" -eq 0 ]
    [ "$output" = alternate-first-ok ]
}

@test "failed lazy AWM dependency loads remain retryable in the same shell" {
    local module function retry_root

    for module in awm_stream awm_protocol awm_tiers; do
        retry_root="$BATS_TEST_TMPDIR/retry-$module"
        mkdir -p "$retry_root"
        cp "$PROJECT_ROOT/lib/$module.sh" "$retry_root/$module.sh"
        case "$module" in
            awm_stream)
                function=awm_stream_compress
                ;;
            awm_protocol)
                function=awm_protocol_handoff_prepare
                cp "$PROJECT_ROOT/lib/awm_stream.sh" "$retry_root/awm_stream.sh"
                ;;
            awm_tiers)
                function=awm_tier_init
                cp "$PROJECT_ROOT/lib/awm_stream.sh" "$retry_root/awm_stream.sh"
                ;;
        esac

        run isolated_env \
            MAINFRAME_ROOT="$retry_root" \
            MAINFRAME_SOURCE_ROOT="$PROJECT_ROOT" \
            MAINFRAME_RETRY_MODULE="$module" \
            MAINFRAME_RETRY_FUNCTION="$function" \
            "$BASH_BIN" --noprofile --norc -c '
                set -euo pipefail
                source "$MAINFRAME_SOURCE_ROOT/lib/lazy.sh"
                lazy_stub "$MAINFRAME_RETRY_FUNCTION" "$MAINFRAME_RETRY_MODULE"

                case "$MAINFRAME_RETRY_MODULE" in
                    awm_stream)
                        if awm_stream_compress "first attempt" 1 >/dev/null 2>&1; then
                            exit 1
                        fi
                        guard=_AWM_STREAM_LOADED
                        ;;
                    awm_protocol)
                        if awm_protocol_handoff_prepare child_agent 32000 >/dev/null 2>&1; then
                            exit 1
                        fi
                        guard=_AWM_PROTOCOL_LOADED
                        ;;
                    awm_tiers)
                        if awm_tier_init >/dev/null 2>&1; then
                            exit 1
                        fi
                        guard=_AWM_TIERS_LOADED
                        ;;
                esac

                # The first source failed before the module was complete. It
                # must not commit either loaded indicator, and the callable is
                # still the original lazy stub rather than a partial body.
                [[ -z "${!guard:-}" ]]
                [[ -z "${_LAZY_LOADED_LIBS[$MAINFRAME_RETRY_MODULE]:-}" ]]
                declare -f "$MAINFRAME_RETRY_FUNCTION" |
                    grep -q "lazy_load_library '\''$MAINFRAME_RETRY_MODULE'\''"

                cp "$MAINFRAME_SOURCE_ROOT/lib/awm_storage.sh" \
                    "$MAINFRAME_ROOT/awm_storage.sh"

                case "$MAINFRAME_RETRY_MODULE" in
                    awm_stream)
                        retry_output="$HOME/retry-stream.txt"
                        awm_stream_compress "  retry   succeeded  " 1 > "$retry_output"
                        [[ "$(<"$retry_output")" == "retry succeeded" ]]
                        ;;
                    awm_protocol)
                        retry_output="$HOME/retry-protocol.json"
                        awm_protocol_handoff_prepare child_agent 32000 > "$retry_output"
                        jq -e ".type == \"handoff\" and .target_agent == \"child_agent\"" \
                            "$retry_output" >/dev/null
                        ;;
                    awm_tiers)
                        awm_tier_init
                        [[ -d "$MAINFRAME_AWM_DIR/warm" ]]
                        [[ -d "$MAINFRAME_AWM_DIR/cold" ]]
                        ;;
                esac

                [[ "${!guard}" == 1 ]]
                [[ "${_LAZY_LOADED_LIBS[$MAINFRAME_RETRY_MODULE]}" == 1 ]]
                if declare -f "$MAINFRAME_RETRY_FUNCTION" |
                    grep -q "lazy_load_library '\''$MAINFRAME_RETRY_MODULE'\''"; then
                    exit 1
                fi
                printf "%s-retry-ok" "$MAINFRAME_RETRY_MODULE"
            '
        [ "$status" -eq 0 ]
        [ "$output" = "$module-retry-ok" ]
    done
}

@test "the six AWM names have one source owner and ratchet collision debt" {
    run python3 - "$PROJECT_ROOT" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
expected = {
    'awm_compress': 'awm.sh',
    'awm_handoff_prepare': 'awm.sh',
    'awm_handoff_accept': 'awm.sh',
    'awm_stream_compress': 'awm_stream.sh',
    'awm_protocol_handoff_prepare': 'awm_protocol.sh',
    'awm_protocol_handoff_accept': 'awm_protocol.sh',
}
definitions = {}
pattern = re.compile(r'^([a-z_][a-z0-9_]*)\(\) \{')
for path in sorted((root / 'lib').glob('*.sh')):
    for line in path.read_text().splitlines():
        match = pattern.match(line)
        if match:
            definitions.setdefault(match.group(1), []).append(path.name)

for name, owner in expected.items():
    assert definitions.get(name) == [owner], (name, definitions.get(name))

policy = json.load(open(root / 'config/function-export-policy.json'))
assert set(expected).isdisjoint(policy['collisions'])
public = [name for name in policy['collisions'] if not name.startswith('_')]
assert len(policy['collisions']) <= 76, len(policy['collisions'])
assert len(public) <= 67, len(public)
print('AWM source ownership and collision ratchet valid')
PY
    [ "$status" -eq 0 ]
    [ "$output" = "AWM source ownership and collision ratchet valid" ]
}

@test "registry manifest and LSP expose exactly the six resolved AWM owners" {
    run python3 - "$PROJECT_ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
registry = json.load(open(root / 'FUNCTIONS.json'))
manifest = json.load(open(root / 'MANIFEST.json'))
lsp = json.load(open(root / 'FUNCTIONS.lsp.json'))
expected = {
    'awm_compress': 'awm',
    'awm_handoff_prepare': 'awm',
    'awm_handoff_accept': 'awm',
    'awm_stream_compress': 'awm_stream',
    'awm_protocol_handoff_prepare': 'awm_protocol',
    'awm_protocol_handoff_accept': 'awm_protocol',
}

labels = [item['label'] for item in lsp['completions']]
completion_by_name = {item['label']: item for item in lsp['completions']}
for name, owner in expected.items():
    owners = sorted(
        module for module, data in registry['libraries'].items()
        if name in data.get('functions', {})
    )
    assert owners == [owner], (name, owners)

    registrations = [
        item['module'] for item in manifest['registrations']
        if item['name'] == name
    ]
    assert registrations == [owner], (name, registrations)

    cid = manifest['name_index'][name]
    export = manifest['exports'][cid]
    assert export['name'] == name, (name, export)
    assert export['owner'] == owner, (name, export['owner'])

    assert labels.count(name) == 1, (name, labels.count(name))
    completion = completion_by_name[name]
    metadata = registry['libraries'][owner]['functions'][name]
    assert completion['data']['library'] == owner, (name, completion['data']['library'])
    assert completion['data']['signature'] == metadata['signature'], name
    assert completion['data']['description'] == (metadata['description'] or ''), name
    assert export['signature'] == metadata['signature'], name

print('AWM generated surfaces valid')
PY
    [ "$status" -eq 0 ]
    [ "$output" = "AWM generated surfaces valid" ]
}

@test "CLI help and search report the resolved owner for each AWM name" {
    local name owner
    while read -r name owner; do
        run isolated_env "$PROJECT_ROOT/bin/mainframe" help "$name"
        [ "$status" -eq 0 ]
        grep -Fqx "Library:     $owner (lib/$owner.sh)" <<< "$output"

        run isolated_env "$PROJECT_ROOT/bin/mainframe" search "$name"
        [ "$status" -eq 0 ]
        grep -Eq "^${name} - ${owner} \\[risk=[^]]+\\]$" <<< "$output"
    done <<'EOF'
awm_compress awm
awm_handoff_prepare awm
awm_handoff_accept awm
awm_stream_compress awm_stream
awm_protocol_handoff_prepare awm_protocol
awm_protocol_handoff_accept awm_protocol
EOF
}
