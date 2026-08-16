#!/usr/bin/env bats
# Focused regression coverage for public function-name collisions.

load 'test_helper'

@test "default common load keeps delimiter-first array_join behavior" {
    run env MAINFRAME_ROOT="$MAINFRAME_ROOT" bash --noprofile --norc -c '
        source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
        array_join "," "a" "b" "c"
    '

    [ "$status" -eq 0 ]
    [ "$output" = "a,b,c" ]
}

@test "default common load preserves legacy array-reference array_join behavior" {
    run env MAINFRAME_ROOT="$MAINFRAME_ROOT" bash --noprofile --norc -c '
        source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
        values=("one" "two words" "three")
        array_join values " | "
    '

    [ "$status" -eq 0 ]
    [ "$output" = "one | two words | three" ]
}

@test "collection exposes its nameref join without replacing array_join" {
    run env MAINFRAME_ROOT="$MAINFRAME_ROOT" bash --noprofile --norc -c '
        source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
        values=("one" "two" "three")
        printf "public=<%s> collection=<%s>" \
            "$(array_join ":" "${values[@]}")" \
            "$(collection_join values ", ")"
    '

    [ "$status" -eq 0 ]
    [ "$output" = "public=<one:two:three> collection=<one, two, three>" ]
}

@test "direct functional load preserves canonical core string predicates" {
    run env MAINFRAME_ROOT="$MAINFRAME_ROOT" bash --noprofile --norc -c '
        source "$MAINFRAME_ROOT/lib/functional.sh"
        is_empty "" && is_not_empty "value"
    '

    [ "$status" -eq 0 ]
}

@test "direct path load preserves canonical core path predicates" {
    run env MAINFRAME_ROOT="$MAINFRAME_ROOT" bash --noprofile --norc -c '
        source "$MAINFRAME_ROOT/lib/path.sh"
        path_is_absolute "/tmp/example" && path_is_relative "tmp/example"
    '

    [ "$status" -eq 0 ]
}
