#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Cross-loader public export contracts
# =============================================================================

load 'test_helper'

assert_common_export_contracts() {
    local loader_mode="$1"

    run env MAINFRAME_ROOT="$MAINFRAME_ROOT" MAINFRAME_QUIET=1 \
        bash --noprofile --norc -c '
            set -e
            loader_mode="$1"
            unset MAINFRAME_LIBS MAINFRAME_PROFILE

            case "$loader_mode" in
                default)
                    ;;
                full)
                    export MAINFRAME_PROFILE=full
                    ;;
                load_all)
                    export MAINFRAME_LIBS=core
                    ;;
                *)
                    printf "unknown loader mode: %s\n" "$loader_mode" >&2
                    exit 2
                    ;;
            esac

            source "$MAINFRAME_ROOT/lib/common.sh" >/dev/null 2>&1
            if [[ "$loader_mode" == "load_all" ]]; then
                mainframe_load_all >/dev/null 2>&1
            fi

            local_response=$'"'"'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nX-Test: yes\r\n\r\nbody'"'"'
            raw_headers=$(http_headers "$local_response")
            expected_headers=$'"'"'Content-Type: text/plain\nX-Test: yes'"'"'
            [[ "$raw_headers" == "$expected_headers" ]] || {
                printf "raw header contract failed: %q\n" "$raw_headers" >&2
                exit 1
            }

            netscan_http_headers() {
                printf "network:%s:%s" "$1" "${2:-}"
            }
            network_headers=$(http_headers "https://example.test/health" 7)
            [[ "$network_headers" == "network:https://example.test/health:7" ]] || {
                printf "URL dispatch contract failed: %q\n" "$network_headers" >&2
                exit 1
            }

            epoch_date=$(TZ=UTC format_date 0)
            [[ "$epoch_date" == "1970-01-01" ]] || {
                printf "epoch date contract failed: %q\n" "$epoch_date" >&2
                exit 1
            }

            formatted_year=$(format_date "%Y")
            [[ "$formatted_year" =~ ^[0-9]{4}$ ]] || {
                printf "format date contract failed: %q\n" "$formatted_year" >&2
                exit 1
            }

            explicit_year=$(format_current_date "%Y")
            [[ "$explicit_year" =~ ^[0-9]{4}$ ]] || {
                printf "explicit date contract failed: %q\n" "$explicit_year" >&2
                exit 1
            }
        ' _ "$loader_mode"

    if [[ "$status" -ne 0 ]]; then
        printf '%s\n' "$output" >&2
    fi
    [[ "$status" -eq 0 ]]
}

@test "default loader preserves canonical HTTP and date contracts" {
    assert_common_export_contracts default
}

@test "full profile preserves canonical HTTP and date contracts" {
    assert_common_export_contracts full
}

@test "mainframe_load_all preserves canonical HTTP and date contracts" {
    assert_common_export_contracts load_all
}
