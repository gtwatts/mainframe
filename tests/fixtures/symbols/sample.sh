#!/usr/bin/env bash
# Sample bash script for symbol extraction tests

SCRIPT_VERSION="1.0.0"

setup_environment() {
    export PATH="/usr/local/bin:$PATH"
}

function process_files {
    local dir="$1"
    find "$dir" -name "*.txt"
}

function cleanup() {
    rm -rf /tmp/test.*
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v) VERBOSE=1 ;;
            *) break ;;
        esac
        shift
    done
}

main() {
    setup_environment
    parse_args "$@"
    process_files "."
    cleanup
}

main "$@"
