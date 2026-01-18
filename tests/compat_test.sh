#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: BSD/GNU Compatibility Library Tests
# =============================================================================
# Run with: bash tests/compat_test.sh
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the library
source "$PROJECT_ROOT/lib/compat.sh"

# Test counters
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

# =============================================================================
# TEST FRAMEWORK
# =============================================================================

# Print colored output
_red() { printf '\033[31m%s\033[0m' "$*"; }
_green() { printf '\033[32m%s\033[0m' "$*"; }
_yellow() { printf '\033[33m%s\033[0m' "$*"; }
_blue() { printf '\033[34m%s\033[0m' "$*"; }

# Run a test
test_case() {
    local name="$1"
    local func="$2"
    
    ((TESTS_RUN++))
    
    # Run test in subshell to isolate
    local output
    if output=$(set -e; "$func" 2>&1); then
        ((TESTS_PASSED++))
        printf '  %s %s\n' "$(_green '✓')" "$name"
    else
        ((TESTS_FAILED++))
        printf '  %s %s\n' "$(_red '✗')" "$name"
        if [[ -n "$output" ]]; then
            printf '    %s\n' "$output" | head -3
        fi
    fi
}

# Assert equality
assert_eq() {
    local expected="$1"
    local actual="$2"
    [[ "$expected" == "$actual" ]] || {
        printf 'Expected: "%s"\nActual: "%s"\n' "$expected" "$actual" >&2
        return 1
    }
}

# Assert not empty
assert_not_empty() {
    local value="$1"
    [[ -n "$value" ]] || {
        printf 'Value is empty\n' >&2
        return 1
    }
}

# Assert contains
assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]] || {
        printf 'String does not contain: %s\n' "$needle" >&2
        return 1
    }
}

# Assert numeric
assert_numeric() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] || {
        printf 'Not numeric: %s\n' "$value" >&2
        return 1
    }
}

# Assert return code
assert_returns() {
    local expected="$1"
    shift
    local actual
    "$@" && actual=0 || actual=$?
    [[ "$actual" -eq "$expected" ]] || {
        printf 'Expected return code: %s, got: %s\n' "$expected" "$actual" >&2
        return 1
    }
}

# =============================================================================
# OS DETECTION TESTS
# =============================================================================

test_get_os_returns_valid_value() {
    local os
    os=$(compat::get_os)
    assert_not_empty "$os"
    # Should be one of the known values
    [[ "$os" =~ ^(macos|linux|freebsd|openbsd|netbsd|windows|unknown)$ ]] || {
        printf 'Unknown OS value: %s\n' "$os" >&2
        return 1
    }
}

test_get_os_family_returns_valid_value() {
    local family
    family=$(compat::get_os_family)
    assert_not_empty "$family"
    [[ "$family" =~ ^(bsd|gnu|unknown)$ ]] || {
        printf 'Unknown family value: %s\n' "$family" >&2
        return 1
    }
}

test_is_macos_or_is_linux_true() {
    # At least one platform check should match
    compat::is_macos || compat::is_linux || compat::is_bsd || [[ $(compat::get_os) == "windows" ]] || [[ $(compat::get_os) == "unknown" ]]
}

test_os_detection_is_cached() {
    # First call
    compat::get_os >/dev/null
    local cached="$_COMPAT_OS"
    
    # Should be set now
    assert_not_empty "$cached"
    
    # Second call should return same value
    local os2
    os2=$(compat::get_os)
    assert_eq "$cached" "$os2"
}

test_has_gnu_consistent_with_family() {
    local family
    family=$(compat::get_os_family)
    
    if [[ "$family" == "gnu" ]]; then
        compat::has_gnu || return 1
    elif [[ "$family" == "bsd" ]]; then
        ! compat::has_gnu || return 1
    fi
}

# =============================================================================
# SED WRAPPER TESTS
# =============================================================================

test_sed_inplace_basic() {
    local tmpfile
    tmpfile=$(mktemp)
    echo "hello world" > "$tmpfile"
    
    compat::sed_inplace "$tmpfile" 's/world/universe/'
    local result
    result=$(cat "$tmpfile")
    rm -f "$tmpfile"
    
    assert_eq "hello universe" "$result"
}

test_sed_inplace_extended() {
    local tmpfile
    tmpfile=$(mktemp)
    echo "foo bar baz" > "$tmpfile"
    
    compat::sed_inplace_extended "$tmpfile" 's/(foo|bar)/X/g'
    local result
    result=$(cat "$tmpfile")
    rm -f "$tmpfile"
    
    assert_eq "X X baz" "$result"
}

test_sed_extended_pipe() {
    local result
    result=$(echo "foobar" | compat::sed_extended 's/(foo)(bar)/\2-\1/')
    assert_eq "bar-foo" "$result"
}

test_sed_inplace_backup() {
    local tmpfile
    tmpfile=$(mktemp)
    echo "original" > "$tmpfile"
    
    compat::sed_inplace_backup "$tmpfile" 's/original/modified/' '.bak'
    
    local modified_content backup_content
    modified_content=$(cat "$tmpfile")
    backup_content=$(cat "${tmpfile}.bak")
    
    rm -f "$tmpfile" "${tmpfile}.bak"
    
    assert_eq "modified" "$modified_content"
    assert_eq "original" "$backup_content"
}

# =============================================================================
# GREP WRAPPER TESTS
# =============================================================================

test_grep_extended_basic() {
    local result
    result=$(echo -e "foo\nbar\nbaz" | compat::grep_extended '(foo|bar)')
    assert_contains "$result" "foo"
    assert_contains "$result" "bar"
}

test_grep_quiet_found() {
    echo "hello world" | compat::grep_quiet "hello"
}

test_grep_quiet_not_found() {
    ! (echo "hello world" | compat::grep_quiet "xyz")
}

test_grep_count_basic() {
    local count
    count=$(echo -e "foo\nfoo\nbar" | compat::grep_count "foo")
    assert_eq "2" "$count"
}

test_grep_count_no_match() {
    local count
    count=$(echo "hello" | compat::grep_count "xyz" | head -1)
    assert_eq "0" "$count"
}

test_has_grep_perl_returns_status() {
    # Just check that it returns a status without error
    compat::has_grep_perl || true
}

# =============================================================================
# DATE WRAPPER TESTS
# =============================================================================

test_date_now_basic() {
    local result
    result=$(compat::date_now '%Y-%m-%d')
    # Should match YYYY-MM-DD format
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
        printf 'Invalid date format: %s\n' "$result" >&2
        return 1
    }
}

test_date_format_timestamp() {
    local result
    # Use a mid-year timestamp to avoid timezone edge cases
    # July 1, 2020 12:00:00 UTC = 1593604800
    result=$(compat::date_format '%Y' 1593604800)
    assert_eq "2020" "$result"
}

test_date_add_days_positive() {
    local base result expected
    base=1577836800  # Jan 1, 2020
    expected=1578441600  # Jan 8, 2020 (7 days later)
    
    result=$(compat::date_add_days 7 "$base")
    assert_numeric "$result"
    
    # Allow 1 day tolerance for timezone differences
    local diff=$((result - expected))
    [[ ${diff#-} -lt 86400 ]] || {
        printf 'Date add off by more than 1 day: expected ~%s, got %s\n' "$expected" "$result" >&2
        return 1
    }
}

test_date_sub_days() {
    local base result
    base=$(date +%s)
    
    result=$(compat::date_sub_days 1 "$base")
    assert_numeric "$result"
    
    # Result should be approximately 86400 seconds less
    local diff=$((base - result))
    [[ $diff -gt 80000 && $diff -lt 90000 ]] || {
        printf 'Date sub unexpected diff: %s\n' "$diff" >&2
        return 1
    }
}

test_date_add_hours() {
    local base result
    base=$(date +%s)
    
    result=$(compat::date_add_hours 24 "$base")
    assert_numeric "$result"
    
    # Should be approximately 86400 seconds more
    local diff=$((result - base))
    [[ $diff -gt 80000 && $diff -lt 90000 ]] || {
        printf 'Date add hours unexpected diff: %s\n' "$diff" >&2
        return 1
    }
}

test_date_dow_valid() {
    local dow
    dow=$(compat::date_dow)
    assert_numeric "$dow"
    [[ $dow -ge 0 && $dow -le 6 ]] || {
        printf 'Invalid day of week: %s\n' "$dow" >&2
        return 1
    }
}

test_date_week_valid() {
    local week
    week=$(compat::date_week)
    assert_numeric "$week"
    [[ $week -ge 1 && $week -le 53 ]] || {
        printf 'Invalid week number: %s\n' "$week" >&2
        return 1
    }
}

# =============================================================================
# STAT WRAPPER TESTS
# =============================================================================

test_stat_size_basic() {
    local tmpfile size
    tmpfile=$(mktemp)
    echo -n "hello" > "$tmpfile"  # 5 bytes
    
    size=$(compat::stat_size "$tmpfile")
    rm -f "$tmpfile"
    
    assert_eq "5" "$size"
}

test_stat_mtime_numeric() {
    local tmpfile mtime
    tmpfile=$(mktemp)
    echo "test" > "$tmpfile"
    
    mtime=$(compat::stat_mtime "$tmpfile")
    rm -f "$tmpfile"
    
    assert_numeric "$mtime"
}

test_stat_atime_numeric() {
    local tmpfile atime
    tmpfile=$(mktemp)
    echo "test" > "$tmpfile"
    cat "$tmpfile" > /dev/null  # Access the file
    
    atime=$(compat::stat_atime "$tmpfile")
    rm -f "$tmpfile"
    
    assert_numeric "$atime"
}

test_stat_perms_format() {
    local tmpfile perms
    tmpfile=$(mktemp)
    chmod 644 "$tmpfile"
    
    perms=$(compat::stat_perms "$tmpfile")
    rm -f "$tmpfile"
    
    assert_eq "644" "$perms"
}

test_stat_owner_not_empty() {
    local tmpfile owner
    tmpfile=$(mktemp)
    
    owner=$(compat::stat_owner "$tmpfile")
    rm -f "$tmpfile"
    
    assert_not_empty "$owner"
}

test_stat_group_not_empty() {
    local tmpfile group
    tmpfile=$(mktemp)
    
    group=$(compat::stat_group "$tmpfile")
    rm -f "$tmpfile"
    
    assert_not_empty "$group"
}

test_stat_inode_numeric() {
    local tmpfile inode
    tmpfile=$(mktemp)
    
    inode=$(compat::stat_inode "$tmpfile")
    rm -f "$tmpfile"
    
    assert_numeric "$inode"
}

test_stat_links_numeric() {
    local tmpfile links
    tmpfile=$(mktemp)
    
    links=$(compat::stat_links "$tmpfile")
    rm -f "$tmpfile"
    
    assert_numeric "$links"
}

# =============================================================================
# REALPATH WRAPPER TESTS
# =============================================================================

test_realpath_basic() {
    local tmpdir tmpfile result
    tmpdir=$(mktemp -d)
    tmpfile="$tmpdir/test.txt"
    echo "test" > "$tmpfile"
    
    result=$(compat::realpath "$tmpfile")
    rm -rf "$tmpdir"
    
    # Result should be absolute path
    [[ "$result" == /* ]] || {
        printf 'Not an absolute path: %s\n' "$result" >&2
        return 1
    }
}

test_readlink_symlink() {
    local tmpdir target link result
    tmpdir=$(mktemp -d)
    target="$tmpdir/target.txt"
    link="$tmpdir/link.txt"
    
    echo "test" > "$target"
    ln -s "$target" "$link"
    
    result=$(compat::readlink "$link")
    rm -rf "$tmpdir"
    
    assert_eq "$target" "$result"
}

# =============================================================================
# MKTEMP WRAPPER TESTS
# =============================================================================

test_mktemp_creates_file() {
    local tmpfile
    tmpfile=$(compat::mktemp "test")
    
    [[ -f "$tmpfile" ]] || {
        printf 'Temp file not created\n' >&2
        return 1
    }
    
    rm -f "$tmpfile"
}

test_mktemp_dir_creates_directory() {
    local tmpdir
    tmpdir=$(compat::mktemp_dir "test")
    
    [[ -d "$tmpdir" ]] || {
        printf 'Temp dir not created\n' >&2
        return 1
    }
    
    rm -rf "$tmpdir"
}

# =============================================================================
# TAR WRAPPER TESTS
# =============================================================================

test_tar_create_and_extract() {
    local tmpdir archive extracted
    tmpdir=$(mktemp -d)
    archive="$tmpdir/test.tar.gz"
    
    # Create a test file
    echo "hello" > "$tmpdir/hello.txt"
    
    # Create archive
    compat::tar_create "$archive" -C "$tmpdir" "hello.txt"
    
    [[ -f "$archive" ]] || {
        rm -rf "$tmpdir"
        printf 'Archive not created\n' >&2
        return 1
    }
    
    # Extract to new location
    mkdir "$tmpdir/extracted"
    compat::tar_extract "$archive" "$tmpdir/extracted"
    
    extracted=$(cat "$tmpdir/extracted/hello.txt")
    rm -rf "$tmpdir"
    
    assert_eq "hello" "$extracted"
}

# =============================================================================
# BASE64 WRAPPER TESTS
# =============================================================================

test_base64_encode_decode() {
    local original encoded decoded
    original="hello world"
    
    encoded=$(compat::base64_encode "$original")
    decoded=$(compat::base64_decode "$encoded")
    
    assert_eq "$original" "$decoded"
}

test_base64_pipe() {
    local result
    result=$(echo -n "test" | compat::base64_encode | compat::base64_decode)
    assert_eq "test" "$result"
}

# =============================================================================
# CHECKSUM WRAPPER TESTS
# =============================================================================

test_sha256_consistent() {
    local tmpfile hash1 hash2
    tmpfile=$(mktemp)
    echo "test content" > "$tmpfile"
    
    hash1=$(compat::sha256 "$tmpfile")
    hash2=$(compat::sha256 "$tmpfile")
    
    rm -f "$tmpfile"
    
    assert_not_empty "$hash1"
    assert_eq "$hash1" "$hash2"
}

test_md5_consistent() {
    local tmpfile hash1 hash2
    tmpfile=$(mktemp)
    echo "test content" > "$tmpfile"
    
    hash1=$(compat::md5 "$tmpfile")
    hash2=$(compat::md5 "$tmpfile")
    
    rm -f "$tmpfile"
    
    assert_not_empty "$hash1"
    assert_eq "$hash1" "$hash2"
}

# =============================================================================
# UTILITY TESTS
# =============================================================================

test_info_runs_without_error() {
    local output
    output=$(compat::info)
    assert_contains "$output" "OS:"
    assert_contains "$output" "Family:"
}

test_gnu_prefer_falls_back() {
    # This should work even if gecho doesn't exist
    local result
    result=$(compat::gnu_prefer echo "hello")
    assert_eq "hello" "$result"
}

# =============================================================================
# MAIN TEST RUNNER
# =============================================================================

main() {
    printf '\n%s\n' "$(_blue '═══════════════════════════════════════════════════════════════')"
    printf '%s\n' "$(_blue '  MAINFRAME: BSD/GNU Compatibility Library Tests')"
    printf '%s\n\n' "$(_blue '═══════════════════════════════════════════════════════════════')"
    
    printf 'Detected OS: %s (%s family)\n\n' "$(compat::get_os)" "$(compat::get_os_family)"
    
    # OS Detection Tests
    printf '%s\n' "$(_yellow '▸ OS Detection Tests')"
    test_case "compat::get_os returns valid value" test_get_os_returns_valid_value
    test_case "compat::get_os_family returns valid value" test_get_os_family_returns_valid_value
    test_case "At least one platform check matches" test_is_macos_or_is_linux_true
    test_case "OS detection is cached" test_os_detection_is_cached
    test_case "has_gnu consistent with family" test_has_gnu_consistent_with_family
    
    # Sed Tests
    printf '\n%s\n' "$(_yellow '▸ Sed Wrapper Tests')"
    test_case "sed_inplace basic substitution" test_sed_inplace_basic
    test_case "sed_inplace_extended with ERE" test_sed_inplace_extended
    test_case "sed_extended with pipe" test_sed_extended_pipe
    test_case "sed_inplace_backup creates backup" test_sed_inplace_backup
    
    # Grep Tests
    printf '\n%s\n' "$(_yellow '▸ Grep Wrapper Tests')"
    test_case "grep_extended basic pattern" test_grep_extended_basic
    test_case "grep_quiet returns 0 on match" test_grep_quiet_found
    test_case "grep_quiet returns non-zero on no match" test_grep_quiet_not_found
    test_case "grep_count counts matches" test_grep_count_basic
    test_case "grep_count returns 0 for no match" test_grep_count_no_match
    test_case "has_grep_perl returns status" test_has_grep_perl_returns_status
    
    # Date Tests
    printf '\n%s\n' "$(_yellow '▸ Date Wrapper Tests')"
    test_case "date_now returns valid format" test_date_now_basic
    test_case "date_format with timestamp" test_date_format_timestamp
    test_case "date_add_days adds days" test_date_add_days_positive
    test_case "date_sub_days subtracts days" test_date_sub_days
    test_case "date_add_hours adds hours" test_date_add_hours
    test_case "date_dow returns valid day" test_date_dow_valid
    test_case "date_week returns valid week" test_date_week_valid
    
    # Stat Tests
    printf '\n%s\n' "$(_yellow '▸ Stat Wrapper Tests')"
    test_case "stat_size returns correct size" test_stat_size_basic
    test_case "stat_mtime returns numeric timestamp" test_stat_mtime_numeric
    test_case "stat_atime returns numeric timestamp" test_stat_atime_numeric
    test_case "stat_perms returns octal permissions" test_stat_perms_format
    test_case "stat_owner returns username" test_stat_owner_not_empty
    test_case "stat_group returns group name" test_stat_group_not_empty
    test_case "stat_inode returns numeric inode" test_stat_inode_numeric
    test_case "stat_links returns numeric count" test_stat_links_numeric
    
    # Realpath Tests
    printf '\n%s\n' "$(_yellow '▸ Realpath Wrapper Tests')"
    test_case "realpath returns absolute path" test_realpath_basic
    test_case "readlink follows symlink" test_readlink_symlink
    
    # Mktemp Tests
    printf '\n%s\n' "$(_yellow '▸ Mktemp Wrapper Tests')"
    test_case "mktemp creates file" test_mktemp_creates_file
    test_case "mktemp_dir creates directory" test_mktemp_dir_creates_directory
    
    # Tar Tests
    printf '\n%s\n' "$(_yellow '▸ Tar Wrapper Tests')"
    test_case "tar create and extract" test_tar_create_and_extract
    
    # Base64 Tests
    printf '\n%s\n' "$(_yellow '▸ Base64 Wrapper Tests')"
    test_case "base64 encode/decode roundtrip" test_base64_encode_decode
    test_case "base64 works with pipes" test_base64_pipe
    
    # Checksum Tests
    printf '\n%s\n' "$(_yellow '▸ Checksum Wrapper Tests')"
    test_case "sha256 produces consistent hash" test_sha256_consistent
    test_case "md5 produces consistent hash" test_md5_consistent
    
    # Utility Tests
    printf '\n%s\n' "$(_yellow '▸ Utility Tests')"
    test_case "compat::info runs without error" test_info_runs_without_error
    test_case "gnu_prefer falls back correctly" test_gnu_prefer_falls_back
    
    # Summary
    printf '\n%s\n' "$(_blue '═══════════════════════════════════════════════════════════════')"
    printf '  Results: '
    if ((TESTS_FAILED == 0)); then
        printf '%s\n' "$(_green "All $TESTS_PASSED tests passed!")"
    else
        printf '%s passed, %s\n' "$(_green "$TESTS_PASSED")" "$(_red "$TESTS_FAILED failed")"
    fi
    printf '%s\n\n' "$(_blue '═══════════════════════════════════════════════════════════════')"
    
    return $((TESTS_FAILED > 0 ? 1 : 0))
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
