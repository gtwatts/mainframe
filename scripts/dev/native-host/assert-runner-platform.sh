#!/usr/bin/env bash
# Fail closed when a CI runner does not match its advertised release platform.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLATFORM_CATALOG="$SCRIPT_DIR/release-platforms.json"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

observe_native_platform() {
    local actual_os actual_arch translated arm64_capable cpu_brand
    local translated_status=0 arm64_capable_status=0 cpu_brand_status=0

    actual_os="$(/usr/bin/uname -s)" || fail "Cannot observe runner operating system"
    actual_arch="$(/usr/bin/uname -m)" || fail "Cannot observe runner architecture"
    case "$actual_os" in
    Darwin)
        if translated="$(/usr/sbin/sysctl -n sysctl.proc_translated 2>/dev/null)"; then
            translated_status=0
        else
            translated_status=$?
            translated=""
        fi
        if arm64_capable="$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)"; then
            arm64_capable_status=0
        else
            arm64_capable_status=$?
            arm64_capable=""
        fi
        if [[ "$translated_status" -eq 0 ]]; then
            case "$translated" in
            0) ;;
            1)
                fail "Release runner is translated under Rosetta; native evidence is required"
                ;;
            *)
                fail "Cannot establish native Darwin execution: sysctl.proc_translated=$translated"
                ;;
            esac
        fi
        if [[ "$arm64_capable_status" -eq 0 ]]; then
            case "$arm64_capable" in
            0|1) ;;
            *)
                fail "Cannot establish native Darwin hardware architecture: hw.optional.arm64=$arm64_capable"
                ;;
            esac
        fi
        if [[ "$actual_arch" == "arm64" ]]; then
            if [[ "$translated_status" -ne 0 || "$translated" != "0" ||
                  "$arm64_capable_status" -ne 0 || "$arm64_capable" != "1" ]]; then
                fail "Cannot establish native Darwin arm64 execution"
            fi
        elif [[ "$actual_arch" == "x86_64" ]]; then
            if [[ "$arm64_capable_status" -ne 0 ]]; then
                if cpu_brand="$(/usr/sbin/sysctl -n machdep.cpu.brand_string 2>/dev/null)"; then
                    cpu_brand_status=0
                else
                    cpu_brand_status=$?
                    cpu_brand=""
                fi
                if [[ "$cpu_brand_status" -ne 0 || "$cpu_brand" != Intel* ]]; then
                    fail "Cannot establish native Darwin Intel hardware: machdep.cpu.brand_string=${cpu_brand:-<unavailable>}"
                fi
            fi
            if [[ "$arm64_capable" == "1" ]]; then
                fail "Release runner is an x86_64 process on Apple Silicon; native Intel evidence is required"
            fi
        elif [[ "$actual_arch" != "x86_64" ]]; then
            fail "Unsupported Darwin runner architecture: $actual_arch"
        fi
        ;;
    Linux)
        case "$actual_arch" in
            x86_64) ;;
            aarch64|arm64) actual_arch="aarch64" ;;
            *) fail "Unsupported Linux runner architecture: $actual_arch" ;;
        esac
        ;;
    *)
        fail "Unsupported release runner OS: $actual_os"
        ;;
    esac

    printf '%s\t%s\n' "$actual_os" "$actual_arch"
}

if [[ $# -eq 1 && "$1" == "--observe-native" ]]; then
    observe_native_platform
    exit 0
fi

if [[ $# -ne 4 ]]; then
    printf 'Usage: %s --observe-native\n' "${0##*/}" >&2
    printf '       %s EXPECTED_ID EXPECTED_OS EXPECTED_ARCH EXPECTED_SYSTEM_LIBC\n' \
        "${0##*/}" >&2
    exit 64
fi

expected_id="$1"
expected_os="$2"
expected_arch="$3"
expected_system_libc="$4"

platform_record="$(observe_native_platform)"
IFS=$'\t' read -r actual_os actual_arch extra <<<"$platform_record"
if [[ -z "$actual_os" || -z "$actual_arch" || -n "${extra:-}" ]]; then
    fail "Native platform observation was not one canonical record"
fi

case "$actual_os" in
    Darwin)
        actual_system_libc="none"
        ;;
    Linux)
        libc_report="$(/usr/bin/getconf GNU_LIBC_VERSION 2>/dev/null || true)"
        if [[ "$libc_report" != glibc\ * ]]; then
            fail "Expected a glibc Linux runner, got: ${libc_report:-<unknown>}"
        fi
        actual_system_libc="glibc"
        ;;
esac

actual_id="${actual_os}-${actual_arch}-${actual_system_libc}"
if [[ "$actual_id" != "$expected_id" || \
      "$actual_os" != "$expected_os" || \
      "$actual_arch" != "$expected_arch" || \
      "$actual_system_libc" != "$expected_system_libc" ]]; then
    printf 'Release runner mismatch: expected %s (%s/%s/%s), got %s (%s/%s/%s)\n' \
        "$expected_id" "$expected_os" "$expected_arch" "$expected_system_libc" \
        "$actual_id" "$actual_os" "$actual_arch" "$actual_system_libc" >&2
    exit 1
fi

[[ -f "$PLATFORM_CATALOG" && ! -L "$PLATFORM_CATALOG" ]] ||
    fail "Release platform catalog is missing or unsafe: $PLATFORM_CATALOG"
if ! /usr/bin/jq -e \
    --arg id "$expected_id" \
    --arg os "$expected_os" \
    --arg arch "$expected_arch" \
    --arg system_libc "$expected_system_libc" '
        .platforms | any(
            .id == $id and
            .os == $os and
            .arch == $arch and
            .system_libc == $system_libc
        )
    ' "$PLATFORM_CATALOG" >/dev/null; then
    printf 'Release runner tuple is not advertised: %s\n' "$actual_id" >&2
    exit 1
fi

printf 'Release runner verified: %s\n' "$actual_id"
