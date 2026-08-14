#!/usr/bin/env bats
# Compatibility contract for the resolved public array collision family.

load 'test_helper'

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    BASH_BIN="${MAINFRAME_BASH:-$(command -v bash)}"
}

canonical_array_probe='\
set -euo pipefail
values=("apple" "apple" "banana" "apricot")
left=("a" "b" "c" "b")
right=("b" "c")
mapfile -t filtered < <(array_filter "a*" "apple" "banana" "apricot")
mapfile -t intersected < <(array_intersect left right)
mapfile -t reversed < <(array_reverse "a" "b" "c")
mapfile -t sliced < <(array_slice 1 3 "a" "b" "c" "d" "e")
mapfile -t unique < <(array_unique "a" "b" "a" "c" "b")
[[ "$(array_count "apple" "${values[@]}")" == 2 ]]
[[ "${filtered[*]}" == "apple apricot" ]]
[[ "$(array_first "${values[@]}")" == apple ]]
[[ "$(array_get 2 "${values[@]}")" == banana ]]
[[ "${intersected[*]}" == "b c b" ]]
[[ "$(array_last "${values[@]}")" == apricot ]]
[[ "$(array_length "${values[@]}")" == 4 ]]
[[ "${reversed[*]}" == "c b a" ]]
[[ "${sliced[*]}" == "b c d" ]]
[[ "$(array_sum 1 2 3 4 5)" == 15 ]]
[[ "${unique[*]}" == "a b c" ]]
printf canonical-array-ok
'

run_profile_probe() {
    local profile="$1"
    if [[ "$profile" == default ]]; then
        run env -u MAINFRAME_LIBS -u MAINFRAME_PROFILE -u MAINFRAME_LAZY \
            MAINFRAME_ROOT="$PROJECT_ROOT" \
            MAINFRAME_ARRAY_PROBE="$canonical_array_probe" \
            "$BASH_BIN" --noprofile --norc -c \
            'source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1; eval "$MAINFRAME_ARRAY_PROBE"'
    else
        run env -u MAINFRAME_LIBS -u MAINFRAME_LAZY \
            MAINFRAME_ROOT="$PROJECT_ROOT" \
            MAINFRAME_PROFILE="$profile" \
            MAINFRAME_ARRAY_PROBE="$canonical_array_probe" \
            "$BASH_BIN" --noprofile --norc -c \
            'source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1; eval "$MAINFRAME_ARRAY_PROBE"'
    fi
}

run_library_probe() {
    local libraries="$1"
    run env -u MAINFRAME_PROFILE -u MAINFRAME_LAZY \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        MAINFRAME_LIBS="$libraries" \
        MAINFRAME_ARRAY_PROBE="$canonical_array_probe" \
        "$BASH_BIN" --noprofile --norc -c \
        'source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1; eval "$MAINFRAME_ARRAY_PROBE"'
}

@test "canonical value-list array behavior is stable across every profile" {
    local profile
    for profile in default minimal standard full ai lazy; do
        run_profile_probe "$profile"
        [ "$status" -eq 0 ]
        [ "$output" = canonical-array-ok ]
    done
}

@test "canonical value-list array behavior survives selective and load-all paths" {
    local libraries
    for libraries in \
        pure-array collection safe collection,safe safe,collection \
        pure-array,collection,safe all; do
        run_library_probe "$libraries"
        [ "$status" -eq 0 ]
        [ "$output" = canonical-array-ok ]
    done

    run env -u MAINFRAME_LIBS -u MAINFRAME_LAZY \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        MAINFRAME_PROFILE=minimal \
        MAINFRAME_ARRAY_PROBE="$canonical_array_probe" \
        "$BASH_BIN" --noprofile --norc -c '
            set -euo pipefail
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            eval "$MAINFRAME_ARRAY_PROBE" >/dev/null
            mainframe_load_all >/dev/null 2>&1
            eval "$MAINFRAME_ARRAY_PROBE"
        '
    [ "$status" -eq 0 ]
    [ "$output" = canonical-array-ok ]
}

@test "canonical function bodies remain pure-array owned after every eager load" {
    local names profile reference actual
    names='array_count array_filter array_first array_get array_intersect array_last array_length array_reverse array_slice array_sum array_unique'

    reference=$(env -u MAINFRAME_PROFILE -u MAINFRAME_LAZY \
        MAINFRAME_ROOT="$PROJECT_ROOT" MAINFRAME_LIBS=pure-array \
        MAINFRAME_ARRAY_NAMES="$names" \
        "$BASH_BIN" --noprofile --norc -c '
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            for name in $MAINFRAME_ARRAY_NAMES; do
                printf "%s\t%s\n" "$name" "$(declare -f "$name" | cksum)"
            done
        ')

    for profile in minimal standard full ai; do
        actual=$(env -u MAINFRAME_LIBS -u MAINFRAME_LAZY \
            MAINFRAME_ROOT="$PROJECT_ROOT" MAINFRAME_PROFILE="$profile" \
            MAINFRAME_ARRAY_NAMES="$names" \
            "$BASH_BIN" --noprofile --norc -c '
                source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
                for name in $MAINFRAME_ARRAY_NAMES; do
                    printf "%s\t%s\n" "$name" "$(declare -f "$name" | cksum)"
                done
            ')
        [ "$actual" = "$reference" ]
    done

    actual=$(env -u MAINFRAME_LIBS -u MAINFRAME_PROFILE -u MAINFRAME_LAZY \
        MAINFRAME_ROOT="$PROJECT_ROOT" MAINFRAME_ARRAY_NAMES="$names" \
        "$BASH_BIN" --noprofile --norc -c '
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            for name in $MAINFRAME_ARRAY_NAMES; do
                printf "%s\t%s\n" "$name" "$(declare -f "$name" | cksum)"
            done
        ')
    [ "$actual" = "$reference" ]

    actual=$(env -u MAINFRAME_LIBS -u MAINFRAME_LAZY \
        MAINFRAME_ROOT="$PROJECT_ROOT" MAINFRAME_PROFILE=minimal \
        MAINFRAME_ARRAY_NAMES="$names" \
        "$BASH_BIN" --noprofile --norc -c '
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            mainframe_load_all >/dev/null 2>&1
            for name in $MAINFRAME_ARRAY_NAMES; do
                printf "%s\t%s\n" "$name" "$(declare -f "$name" | cksum)"
            done
        ')
    [ "$actual" = "$reference" ]
}

@test "nameref and bounds-safe alternate contracts have explicit names" {
    run env -u MAINFRAME_LIBS -u MAINFRAME_PROFILE -u MAINFRAME_LAZY \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        "$BASH_BIN" --noprofile --norc -c '
            set -euo pipefail
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            is_even() { (( $1 % 2 == 0 )); }
            values=(1 2 3 4)
            other=(2 4 8)
            collection_filter values is_even filtered
            collection_slice 1 3 values sliced
            collection_unique values unique
            collection_intersect values other intersected
            collection_reverse values reversed
            [[ "${filtered[*]}" == "2 4" ]]
            [[ "${sliced[*]}" == "2 3" ]]
            [[ "${unique[*]}" == "1 2 3 4" ]]
            [[ "${intersected[*]}" == "2 4" ]]
            [[ "${reversed[*]}" == "4 3 2 1" ]]
            [[ "$(collection_count values is_even)" == 2 ]]
            [[ "$(collection_sum values)" == 10 ]]
            [[ "$(collection_first values)" == 1 ]]
            [[ "$(collection_last values)" == 4 ]]
            [[ "$(collection_length values)" == 4 ]]
            [[ "$(safe_array_get values 9 fallback)" == fallback ]]
            printf explicit-array-alternates-ok
        '
    [ "$status" -eq 0 ]
    [ "$output" = explicit-array-alternates-ok ]
}

@test "lazy loading exposes canonical and explicit alternate array contracts" {
    run env -u MAINFRAME_LIBS -u MAINFRAME_LAZY \
        MAINFRAME_ROOT="$PROJECT_ROOT" \
        MAINFRAME_PROFILE=lazy \
        "$BASH_BIN" --noprofile --norc -c '
            set -euo pipefail
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            values=(1 2 3)
            [[ "$(array_sum 1 2 3)" == 6 ]]
            [[ "$(collection_sum values)" == 6 ]]
            [[ "$(safe_array_get values 8 fallback)" == fallback ]]
            printf lazy-array-contracts-ok
        '
    [ "$status" -eq 0 ]
    [ "$output" = lazy-array-contracts-ok ]
}

@test "lazy loading keeps canonical and alternate ownership coherent in both orders" {
    run env -u MAINFRAME_LIBS -u MAINFRAME_LAZY \
        MAINFRAME_ROOT="$PROJECT_ROOT" MAINFRAME_PROFILE=lazy \
        "$BASH_BIN" --noprofile --norc -c '
            set -euo pipefail
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            [[ "${_LAZY_MANIFEST[array_sum]}" == pure-array ]]
            [[ "${_LAZY_MANIFEST[collection_sum]}" == collection ]]
            [[ "${_LAZY_MANIFEST[safe_array_get]}" == safe ]]
            lazy_is_stub array_sum
            lazy_is_stub collection_sum
            lazy_is_stub safe_array_get
            values=(1 2 3)
            [[ "$(array_sum 1 2 3)" == 6 ]]
            ! lazy_is_stub array_sum
            lazy_is_stub collection_sum
            [[ "$(collection_sum values)" == 6 ]]
            ! lazy_is_stub collection_sum
            [[ "$(safe_array_get values 9 fallback)" == fallback ]]
            ! lazy_is_stub safe_array_get
            printf canonical-first-ok
        '
    [ "$status" -eq 0 ]
    [ "$output" = canonical-first-ok ]

    run env -u MAINFRAME_LIBS -u MAINFRAME_LAZY \
        MAINFRAME_ROOT="$PROJECT_ROOT" MAINFRAME_PROFILE=lazy \
        "$BASH_BIN" --noprofile --norc -c '
            set -euo pipefail
            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            values=(1 2 3)
            [[ "$(collection_sum values)" == 6 ]]
            ! lazy_is_stub collection_sum
            lazy_is_stub array_sum
            [[ "$(array_sum 1 2 3)" == 6 ]]
            ! lazy_is_stub array_sum
            [[ "$(safe_array_get values 9 fallback)" == fallback ]]
            ! lazy_is_stub safe_array_get
            lazy_is_stub array_get
            [[ "$(array_get 1 x y z)" == y ]]
            ! lazy_is_stub array_get
            printf alternate-first-ok
        '
    [ "$status" -eq 0 ]
    [ "$output" = alternate-first-ok ]
}

@test "the array family has one source owner per public name" {
    run python3 - "$PROJECT_ROOT" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
canonical = {
    'array_count', 'array_filter', 'array_first', 'array_get',
    'array_intersect', 'array_last', 'array_length', 'array_reverse',
    'array_slice', 'array_sum', 'array_unique',
}
alternates = {
    'collection_count', 'collection_filter', 'collection_first',
    'collection_intersect', 'collection_last', 'collection_length',
    'collection_reverse', 'collection_slice', 'collection_sum',
    'collection_unique', 'safe_array_get',
}
definitions = {}
pattern = re.compile(r'^([a-z_][a-z0-9_]*)\(\) \{')
for path in sorted((root / 'lib').glob('*.sh')):
    for line in path.read_text().splitlines():
        match = pattern.match(line)
        if match:
            definitions.setdefault(match.group(1), []).append(path.name)

assert all(definitions.get(name) == ['pure-array.sh'] for name in canonical)
assert all(len(definitions.get(name, [])) == 1 for name in alternates)

policy = json.load(open(root / 'config/function-export-policy.json'))
assert canonical.isdisjoint(policy['collisions'])
public = [name for name in policy['collisions'] if not name.startswith('_')]
assert len(policy['collisions']) <= 79, len(policy['collisions'])
assert len(public) <= 70, len(public)
print('array source ownership and collision ratchet valid')
PY
    [ "$status" -eq 0 ]
    [ "$output" = "array source ownership and collision ratchet valid" ]
}

@test "registry manifest LSP and CLI expose the resolved array owners" {
    run python3 - "$PROJECT_ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
registry = json.load(open(root / 'FUNCTIONS.json'))
manifest = json.load(open(root / 'MANIFEST.json'))
lsp = json.load(open(root / 'FUNCTIONS.lsp.json'))
canonical = {
    'array_count', 'array_filter', 'array_first', 'array_get',
    'array_intersect', 'array_last', 'array_length', 'array_reverse',
    'array_slice', 'array_sum', 'array_unique',
}
alternates = {
    'collection_count', 'collection_filter', 'collection_first',
    'collection_intersect', 'collection_last', 'collection_length',
    'collection_reverse', 'collection_slice', 'collection_sum',
    'collection_unique', 'safe_array_get',
}
expected_owner = {
    **{name: 'pure-array' for name in canonical},
    **{name: 'collection' for name in alternates if name.startswith('collection_')},
    'safe_array_get': 'safe',
}
completion_by_name = {item['label']: item for item in lsp['completions']}
for name in canonical:
    cid = manifest['name_index'][name]
    assert manifest['exports'][cid]['owner'] == 'pure-array', (name, cid)
    owners = [
        module for module, data in registry['libraries'].items()
        if name in data.get('functions', {})
    ]
    assert owners == ['pure-array'], (name, owners)
for name in alternates:
    assert name in manifest['name_index'], name

labels = [item['label'] for item in lsp['completions']]
for name in canonical | alternates:
    assert labels.count(name) == 1, (name, labels.count(name))
    cid = manifest['name_index'][name]
    assert manifest['exports'][cid]['owner'] == expected_owner[name]
    item = completion_by_name[name]
    assert item['data']['library'] == expected_owner[name]
    metadata = registry['libraries'][expected_owner[name]]['functions'][name]
    assert item['data']['signature'] == metadata['signature']
    assert item['data']['description'] == (metadata['description'] or '')
print('array generated surfaces valid')
PY
    [ "$status" -eq 0 ]
    [ "$output" = "array generated surfaces valid" ]

    run "$PROJECT_ROOT/bin/mainframe" help array_count
    [ "$status" -eq 0 ]
    [[ "$output" == *"Library:"*"pure-array"* ]]

    run "$PROJECT_ROOT/bin/mainframe" help collection_count
    [ "$status" -eq 0 ]
    [[ "$output" == *"Library:"*"collection"* ]]

    run "$PROJECT_ROOT/bin/mainframe" help safe_array_get
    [ "$status" -eq 0 ]
    [[ "$output" == *"Library:"*"safe"* ]]

    run "$PROJECT_ROOT/bin/mainframe" search array_count
    [ "$status" -eq 0 ]
    [[ "$output" == *"array_count - pure-array"* ]]

    run "$PROJECT_ROOT/bin/mainframe" search collection_count
    [ "$status" -eq 0 ]
    [[ "$output" == *"collection_count - collection"* ]]

    run "$PROJECT_ROOT/bin/mainframe" search safe_array_get
    [ "$status" -eq 0 ]
    [[ "$output" == *"safe_array_get - safe"* ]]
}
