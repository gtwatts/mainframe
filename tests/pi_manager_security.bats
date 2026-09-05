#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(cd "$BATS_TEST_TMPDIR" && pwd -P)/pi-manager-security-$BATS_TEST_NUMBER"
    /bin/mkdir -m 700 "$TEST_ROOT"

    # shellcheck disable=SC1091 # Resolved from PROJECT_ROOT at runtime.
    source "$PROJECT_ROOT/lib/pi.sh"
}

@test "owner and mode consumers drain stat metadata and reject malformed records" {
    local target marker metadata_case capture_count validation_count
    target="$TEST_ROOT/stat-metadata-target"
    marker="$TEST_ROOT/stat-metadata-drained"
    printf 'fixture\n' > "$target"
    /bin/chmod 600 "$target"

    _mainframe_pi_stat_owner_mode() {
        case "$metadata_case" in
            empty) return 0 ;;
            owner-only) printf '%s\n' "$EUID" ;;
            multiline) printf '%s 600\ntrailing-record\n' "$EUID" ;;
            trailing-garbage) printf '%s 600 trailing-garbage\n' "$EUID" ;;
            valid-nonzero) printf '%s 600\n' "$EUID"; return 23 ;;
            delayed-valid)
                printf '%s 600\n' "$EUID"
                /bin/sleep 1
                : > "$marker"
                ;;
            *) return 99 ;;
        esac
    }
    _mainframe_pi_link_count() { printf '1\n'; }

    for metadata_case in \
        empty owner-only multiline trailing-garbage valid-nonzero; do
        run _mainframe_pi_validate_regular_file "$target" root-or-user true
        [[ "$status" -eq 1 ]]
    done

    # A one-line process-substitution consumer can return before its producer
    # exits. Bash 4.4 then races the producer's final printf against the closed
    # pipe. The delayed marker proves validation consumed the scalar producer
    # through EOF before it parsed the owner and mode locally.
    metadata_case=delayed-valid
    _mainframe_pi_validate_regular_file "$target" root-or-user true
    [[ -f "$marker" ]]

    run /usr/bin/grep -Fq '< <(_mainframe_pi_stat_owner_mode' "$PROJECT_ROOT/lib/pi.sh"
    [[ "$status" -eq 1 ]]
    # shellcheck disable=SC2016 # These are literal source-code contracts.
    capture_count="$(/usr/bin/grep -Fc 'metadata="$(_mainframe_pi_stat_owner_mode' \
        "$PROJECT_ROOT/lib/pi.sh")"
    # shellcheck disable=SC2016 # These are literal source-code contracts.
    validation_count="$(/usr/bin/grep -Fc \
        '[[ "$metadata" =~ ^[0-9]+\ [0-7]{3,4}$ ]] || return 1' \
        "$PROJECT_ROOT/lib/pi.sh")"
    [[ "$capture_count" -eq 6 ]]
    [[ "$validation_count" -eq 6 ]]
}

@test "project AWM outer timeout stays above the inner session-lock budget" {
    local extension lock_default outer_ms
    extension="$PROJECT_ROOT/skills/pi/extensions/mainframe.ts"

    # The public durable-kernel route has a larger budget than the old direct
    # AWM helper. Verify the timeout actually passed to that route and preserve
    # the lock margin without pinning the superseded 15-second value.
    outer_ms="$(/usr/bin/sed -nE \
        's/^const MAINFRAME_PROJECT_AWM_TIMEOUT_MS = ([0-9_]+);$/\1/p' "$extension")"
    outer_ms="${outer_ms//_/}"
    [[ "$outer_ms" =~ ^[0-9]+$ ]]
    run /usr/bin/grep -Fq 'timeoutMs: MAINFRAME_PROJECT_AWM_TIMEOUT_MS,' "$extension"
    [[ "$status" -eq 0 ]]

    lock_default="$(/usr/bin/grep -E '^AWM_LOCK_TIMEOUT="\$\{AWM_LOCK_TIMEOUT:-[0-9]+\}"$' \
        "$PROJECT_ROOT/lib/awm.sh" | /usr/bin/sed -E 's/.*:-([0-9]+)\}"$/\1/' | /usr/bin/head -n 1)"
    [[ "$lock_default" =~ ^[0-9]+$ ]]
    [[ $((lock_default * 3000)) -le "$outer_ms" ]]
    [[ "$outer_ms" -le 60000 ]]
}
