#!/usr/bin/env bats

load test_helper

setup() {
    CHECKER="$MAINFRAME_ROOT/scripts/check-function-exports.py"
    FIXTURE_ROOT="$BATS_TEST_TMPDIR/export-policy-$BATS_TEST_NUMBER"
    mkdir -p "$FIXTURE_ROOT/lib" "$FIXTURE_ROOT/config"
}

write_fixture() {
    local relative_path="$1"
    local content="$2"
    mkdir -p "$(dirname "$FIXTURE_ROOT/$relative_path")"
    printf '%s' "$content" > "$FIXTURE_ROOT/$relative_path"
}

write_policy() {
    local entries="$1"
    printf '%s\n' \
        '{' \
        '  "schema_version": 1,' \
        '  "scope": "test fixture",' \
        '  "collisions": {' \
        "    $entries" \
        '  }' \
        '}' > "$FIXTURE_ROOT/config/function-export-policy.json"
}

run_check() {
    run python3 "$CHECKER" --root "$FIXTURE_ROOT" --check
}

@test "exact policy passes and inventory is deterministic and repo-relative" {
    write_fixture "lib/alpha.sh" $'shared() {\n    :\n}\nunique() {\n    :\n}\nns::value() {\n    :\n}\n  indented() {\n    :\n}\n'
    write_fixture "lib/beta.sh" $'shared() {\n    :\n}\n'
    write_fixture "lib/ext/ignored.sh" $'shared() {\n    :\n}\n'
    write_policy '"shared": {"classification": "legacy-unresolved", "definitions": ["lib/alpha.sh", "lib/beta.sh"], "rationale": "fixture collision"}'

    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"check passed: 1 exact collision entries (1 public, 0 private)."* ]]

    run python3 "$CHECKER" --root "$FIXTURE_ROOT" --inventory
    [ "$status" -eq 0 ]
    [[ "$output" == *"Summary: 2 files, 4 definitions, 3 unique names, 1 collisions (1 public, 0 private)"* ]]
    [[ "$output" == *"- shared [public; legacy-unresolved]: lib/alpha.sh:1, lib/beta.sh:1"* ]]
    [[ "$output" != *"$FIXTURE_ROOT"* ]]
    [[ "$output" != *"ext/ignored.sh"* ]]
    [[ "$output" != *"indented"* ]]
}

@test "an unlisted new collision fails" {
    write_fixture "lib/alpha.sh" $'new_export() {\n    :\n}\n'
    write_fixture "lib/beta.sh" $'new_export() {\n    :\n}\n'
    write_policy ''

    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"unlisted collision new_export: lib/alpha.sh:1, lib/beta.sh:1"* ]]
}

@test "moving a definition fails the exact definition-set check" {
    write_fixture "lib/alpha.sh" $'shared() {\n    :\n}\n'
    write_fixture "lib/gamma.sh" $'shared() {\n    :\n}\n'
    write_policy '"shared": {"classification": "legacy-unresolved", "definitions": ["lib/alpha.sh", "lib/beta.sh"], "rationale": "fixture collision"}'

    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"definition set changed for shared: expected [lib/alpha.sh, lib/beta.sh]; found [lib/alpha.sh, lib/gamma.sh]"* ]]
}

@test "resolving a collision requires a deliberate policy refresh" {
    write_fixture "lib/alpha.sh" $'shared() {\n    :\n}\n'
    write_policy '"shared": {"classification": "legacy-unresolved", "definitions": ["lib/alpha.sh", "lib/beta.sh"], "rationale": "fixture collision"}'

    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"listed collision shared no longer has multiple definitions"* ]]
}

@test "same-file duplicates fail unless explicitly classified" {
    write_fixture "lib/alpha.sh" $'same_file() {\n    :\n}\nsame_file() {\n    :\n}\n'
    write_policy '"same_file": {"classification": "legacy-unresolved", "definitions": ["lib/alpha.sh", "lib/alpha.sh"], "rationale": "fixture collision"}'

    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"same-file duplicate same_file in lib/alpha.sh requires legacy-same-file classification"* ]]

    write_policy '"same_file": {"classification": "legacy-same-file", "definitions": ["lib/alpha.sh", "lib/alpha.sh"], "rationale": "explicit fixture exception"}'
    run_check
    [ "$status" -eq 0 ]
}

@test "guarded-equivalent allows private definitions guarded in every file" {
    write_fixture "lib/alpha.sh" $'if ! declare -F _shared &>/dev/null; then\n_shared() {\n    :\n}\nfi\n'
    write_fixture "lib/beta.sh" $'if ! declare -F _shared >/dev/null 2>&1; then\n_shared() {\n    :\n}\nfi\n'
    write_policy '"_shared": {"classification": "guarded-equivalent", "definitions": ["lib/alpha.sh", "lib/beta.sh"], "rationale": "guarded private shim"}'

    run_check
    [ "$status" -eq 0 ]
}

@test "guarded-equivalent rejects a public function" {
    write_fixture "lib/alpha.sh" $'if ! declare -F shared &>/dev/null; then\nshared() {\n    :\n}\nfi\n'
    write_fixture "lib/beta.sh" $'if ! declare -F shared &>/dev/null; then\nshared() {\n    :\n}\nfi\n'
    write_policy '"shared": {"classification": "guarded-equivalent", "definitions": ["lib/alpha.sh", "lib/beta.sh"], "rationale": "invalid public shim"}'

    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"guarded-equivalent collision shared must be private"* ]]
}

@test "guarded-equivalent rejects any unguarded private definition" {
    write_fixture "lib/alpha.sh" $'_shared() {\n    :\n}\n'
    write_fixture "lib/beta.sh" $'if ! declare -F _shared &>/dev/null; then\n_shared() {\n    :\n}\nfi\n'
    write_policy '"_shared": {"classification": "guarded-equivalent", "definitions": ["lib/alpha.sh", "lib/beta.sh"], "rationale": "partially guarded shim"}'

    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"guarded-equivalent collision _shared has unguarded definitions: lib/alpha.sh:1"* ]]
}
