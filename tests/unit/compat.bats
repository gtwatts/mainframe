#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/compat.bats - Tests for BSD/GNU Compatibility Layer
# =============================================================================
# Description: Comprehensive unit tests for lib/compat.sh
#              BSD/GNU cross-platform compatibility layer
# Test Count: 95+ test cases
# Categories: OS detection, sed wrappers, date wrappers, grep wrappers,
#             find wrappers, stat wrappers, portable tools (p* namespace),
#             underscore-style wrappers (compat_*)
# =============================================================================

# Setup - load MAINFRAME
setup() {
    # Load BATS helpers if available
    if [[ -f "$BATS_TEST_DIRNAME/../bats-support/load.bash" ]]; then
        load "$BATS_TEST_DIRNAME/../bats-support/load.bash"
    fi
    if [[ -f "$BATS_TEST_DIRNAME/../bats-assert/load.bash" ]]; then
        load "$BATS_TEST_DIRNAME/../bats-assert/load.bash"
    fi

    # Source MAINFRAME
    MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    export MAINFRAME_ROOT
    source "$MAINFRAME_ROOT/lib/common.sh"

    # Create temp directory for test files
    TEST_TMPDIR=$(mktemp -d)
}

# Helper function to run pipe commands with MAINFRAME functions available
# Usage: run_with_mainframe 'echo "hello" | psed "s/hello/world/"'
run_with_mainframe() {
    local cmd="$1"
    # Create a temp script that sources MAINFRAME then runs the command
    local script="$TEST_TMPDIR/run_cmd.sh"
    cat > "$script" <<EOF
#!/usr/bin/env bash
source "$MAINFRAME_ROOT/lib/common.sh"
$cmd
EOF
    chmod +x "$script"
    "$script"
}

teardown() {
    # Clean up temp files
    [[ -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# OS DETECTION TESTS
# =============================================================================

@test "is_mac returns correct value for current platform" {
    # This test validates the function works without error
    run is_mac
    # Exit code should be 0 (true) on macOS, 1 (false) otherwise
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "compat::get_os returns a valid OS name" {
    run compat::get_os
    [[ "$status" -eq 0 ]]
    # Should return one of the known OS values
    [[ "$output" =~ ^(macos|linux|wsl|freebsd|openbsd|netbsd|windows|unknown)$ ]]
}

@test "compat::get_os_family returns bsd or gnu" {
    run compat::get_os_family
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^(bsd|gnu|unknown)$ ]]
}

@test "compat::is_linux returns true on Linux" {
    if [[ "$(uname -s)" == "Linux" ]]; then
        run compat::is_linux
        [[ "$status" -eq 0 ]]
    else
        skip "Not running on Linux"
    fi
}

@test "compat::is_macos returns true on macOS" {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        run compat::is_macos
        [[ "$status" -eq 0 ]]
    else
        skip "Not running on macOS"
    fi
}

@test "has_gnu_coreutils returns true on Linux" {
    if [[ "$(uname -s)" == "Linux" ]]; then
        run has_gnu_coreutils
        [[ "$status" -eq 0 ]]
    else
        skip "Not running on Linux - test depends on platform"
    fi
}

# =============================================================================
# PORTABLE SED TESTS
# =============================================================================

@test "psed performs basic substitution" {
    echo "hello world" > "$TEST_TMPDIR/test.txt"
    run psed 's/world/universe/' "$TEST_TMPDIR/test.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "hello universe" ]]
}

@test "psed works with stdin" {
    run run_with_mainframe 'echo "hello world" | psed "s/world/universe/"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "hello universe" ]]
}

@test "psed handles extended regex with -E" {
    run run_with_mainframe 'echo "foo123bar" | psed -E "s/[0-9]+/_/"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "foo_bar" ]]
}

@test "psed global substitution works" {
    run run_with_mainframe 'echo "aaa" | psed "s/a/b/g"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "bbb" ]]
}

# =============================================================================
# PORTABLE AWK TESTS
# =============================================================================

@test "pawk extracts fields" {
    run run_with_mainframe 'echo "a b c" | pawk "{print \$2}"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "b" ]]
}

@test "pawk handles custom field separator" {
    run run_with_mainframe 'echo "a:b:c" | pawk -F: "{print \$2}"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "b" ]]
}

@test "pawk performs calculations" {
    run run_with_mainframe 'echo -e "1\n2\n3" | pawk "{sum+=\$1} END {print sum}"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "6" ]]
}

# =============================================================================
# PORTABLE GREP TESTS
# =============================================================================

@test "pgrep finds matching lines" {
    echo -e "apple\nbanana\napricot" > "$TEST_TMPDIR/test.txt"
    run pgrep "ap" "$TEST_TMPDIR/test.txt"
    [[ "$status" -eq 0 ]]
    [[ "${lines[0]}" == "apple" ]]
    [[ "${lines[1]}" == "apricot" ]]
}

@test "pgrep with -E extended regex" {
    run run_with_mainframe 'echo -e "cat\ndog\nrat" | pgrep -E "cat|rat"'
    [[ "$status" -eq 0 ]]
    [[ "${lines[0]}" == "cat" ]]
    [[ "${lines[1]}" == "rat" ]]
}

@test "pgrep with -v inverts match" {
    run run_with_mainframe 'echo -e "apple\nbanana\napricot" | pgrep -v "ap"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "banana" ]]
}

@test "pgrep returns 1 when no match" {
    run run_with_mainframe 'echo "hello" | pgrep "xyz"'
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# PORTABLE FIND TESTS
# =============================================================================

@test "pfind locates files by name" {
    mkdir -p "$TEST_TMPDIR/subdir"
    touch "$TEST_TMPDIR/file.txt"
    touch "$TEST_TMPDIR/subdir/other.txt"

    run pfind "$TEST_TMPDIR" -name "*.txt" -type f
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "file.txt" ]]
    [[ "$output" =~ "other.txt" ]]
}

@test "pfind with -type d finds directories" {
    mkdir -p "$TEST_TMPDIR/subdir1" "$TEST_TMPDIR/subdir2"

    run pfind "$TEST_TMPDIR" -type d -name "subdir*"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "subdir1" ]]
    [[ "$output" =~ "subdir2" ]]
}

# =============================================================================
# PORTABLE XARGS TESTS
# =============================================================================

@test "pxargs processes input" {
    run run_with_mainframe 'echo -e "a\nb\nc" | pxargs echo'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "a b c" ]]
}

@test "pxargs_null handles null-delimited input" {
    run run_with_mainframe 'printf "a\0b\0c" | pxargs_null echo'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "a b c" ]]
}

# =============================================================================
# PORTABLE DATE TESTS
# =============================================================================

@test "pdate outputs current date" {
    run pdate +%Y-%m-%d
    [[ "$status" -eq 0 ]]
    # Should match YYYY-MM-DD format
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

@test "pdate_from_epoch converts timestamp" {
    # Unix epoch for 2021-01-01 00:00:00 UTC
    run pdate_from_epoch 1609459200 '%Y-%m-%d'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "2021-01-01" ]]
}

# =============================================================================
# PORTABLE STAT TESTS
# =============================================================================

@test "pstat_size returns file size" {
    echo "hello" > "$TEST_TMPDIR/test.txt"
    run pstat_size "$TEST_TMPDIR/test.txt"
    [[ "$status" -eq 0 ]]
    # "hello\n" is 6 bytes
    [[ "$output" == "6" ]]
}

@test "pstat_mtime returns modification time" {
    touch "$TEST_TMPDIR/test.txt"
    run pstat_mtime "$TEST_TMPDIR/test.txt"
    [[ "$status" -eq 0 ]]
    # Should be a valid Unix timestamp (roughly current time)
    [[ "$output" =~ ^[0-9]+$ ]]
    # Timestamp should be recent (within last hour)
    local now=$(date +%s)
    local diff=$((now - output))
    [[ $diff -ge 0 && $diff -lt 3600 ]]
}

@test "pstat_perms returns octal permissions" {
    touch "$TEST_TMPDIR/test.txt"
    chmod 644 "$TEST_TMPDIR/test.txt"
    run pstat_perms "$TEST_TMPDIR/test.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "644" ]]
}

# =============================================================================
# PORTABLE READLINK TESTS
# =============================================================================

@test "preadlink_f resolves symlinks" {
    touch "$TEST_TMPDIR/original.txt"
    ln -s "$TEST_TMPDIR/original.txt" "$TEST_TMPDIR/link.txt"
    local expected
    expected="$(cd "$(dirname "$TEST_TMPDIR/original.txt")" && pwd -P)/original.txt"

    run preadlink_f "$TEST_TMPDIR/link.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$expected" ]]
}

@test "preadlink_f handles relative paths" {
    local original_dir="$PWD"
    cd "$TEST_TMPDIR"
    touch "file.txt"
    local expected
    expected="$(pwd -P)/file.txt"

    run preadlink_f "file.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$expected" ]]

    cd "$original_dir"
}

# =============================================================================
# PORTABLE MKTEMP TESTS
# =============================================================================

@test "pmktemp creates temporary file" {
    run pmktemp
    [[ "$status" -eq 0 ]]
    [[ -f "$output" ]]
    rm -f "$output"
}

@test "pmktemp_d creates temporary directory" {
    run pmktemp_d
    [[ "$status" -eq 0 ]]
    [[ -d "$output" ]]
    rmdir "$output"
}

# =============================================================================
# PORTABLE SORT TESTS
# =============================================================================

@test "psort sorts lines alphabetically" {
    run run_with_mainframe 'echo -e "banana\napple\ncherry" | psort'
    [[ "$status" -eq 0 ]]
    [[ "${lines[0]}" == "apple" ]]
    [[ "${lines[1]}" == "banana" ]]
    [[ "${lines[2]}" == "cherry" ]]
}

@test "psort with -n sorts numerically" {
    run run_with_mainframe 'echo -e "10\n2\n1" | psort -n'
    [[ "$status" -eq 0 ]]
    [[ "${lines[0]}" == "1" ]]
    [[ "${lines[1]}" == "2" ]]
    [[ "${lines[2]}" == "10" ]]
}

@test "psort_version sorts version numbers" {
    run run_with_mainframe 'echo -e "1.10\n1.2\n1.1" | psort_version'
    [[ "$status" -eq 0 ]]
    [[ "${lines[0]}" == "1.1" ]]
    [[ "${lines[1]}" == "1.2" ]]
    [[ "${lines[2]}" == "1.10" ]]
}

# =============================================================================
# PORTABLE HEAD/TAIL TESTS
# =============================================================================

@test "phead returns first n lines" {
    run run_with_mainframe 'echo -e "1\n2\n3\n4\n5" | phead -n 3'
    [[ "$status" -eq 0 ]]
    [[ "${#lines[@]}" -eq 3 ]]
    [[ "${lines[0]}" == "1" ]]
    [[ "${lines[2]}" == "3" ]]
}

@test "ptail returns last n lines" {
    run run_with_mainframe 'echo -e "1\n2\n3\n4\n5" | ptail -n 2'
    [[ "$status" -eq 0 ]]
    [[ "${#lines[@]}" -eq 2 ]]
    [[ "${lines[0]}" == "4" ]]
    [[ "${lines[1]}" == "5" ]]
}

# =============================================================================
# PORTABLE BASE64 TESTS
# =============================================================================

@test "pbase64_encode encodes text" {
    run pbase64_encode "hello"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "aGVsbG8=" ]]
}

@test "pbase64_decode decodes text" {
    run pbase64_decode "aGVsbG8="
    [[ "$status" -eq 0 ]]
    [[ "$output" == "hello" ]]
}

@test "pbase64 roundtrip preserves data" {
    local original="Hello, World! 123 @#\$%"
    local encoded=$(pbase64_encode "$original")
    run pbase64_decode "$encoded"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$original" ]]
}

# =============================================================================
# PORTABLE CHECKSUM TESTS
# =============================================================================

@test "pmd5sum produces consistent hash" {
    # Known MD5 hash for "hello"
    run run_with_mainframe 'echo -n "hello" | pmd5sum'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "5d41402abc4b2a76b9719d911017c592" ]]
}

@test "psha256sum produces consistent hash" {
    # Known SHA256 hash for "hello"
    run run_with_mainframe 'echo -n "hello" | psha256sum'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" ]]
}

@test "pmd5sum on file matches expected" {
    echo -n "hello" > "$TEST_TMPDIR/test.txt"
    run pmd5sum "$TEST_TMPDIR/test.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "5d41402abc4b2a76b9719d911017c592" ]]
}

# =============================================================================
# PORTABLE UTILITY TESTS
# =============================================================================

@test "pcut extracts fields" {
    run run_with_mainframe 'echo "a:b:c" | pcut -d: -f2'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "b" ]]
}

@test "ptr translates characters" {
    run run_with_mainframe 'echo "HELLO" | ptr "[:upper:]" "[:lower:]"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "hello" ]]
}

@test "pwc counts lines" {
    echo -e "line1\nline2\nline3" > "$TEST_TMPDIR/test.txt"
    run pwc -l "$TEST_TMPDIR/test.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "3" ]]
}

@test "puniq removes duplicates" {
    run run_with_mainframe 'echo -e "a\na\nb\nb\nc" | puniq'
    [[ "$status" -eq 0 ]]
    [[ "${lines[0]}" == "a" ]]
    [[ "${lines[1]}" == "b" ]]
    [[ "${lines[2]}" == "c" ]]
}

@test "pbasename extracts filename" {
    run pbasename "/path/to/file.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "file.txt" ]]
}

@test "pdirname extracts directory" {
    run pdirname "/path/to/file.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "/path/to" ]]
}

# =============================================================================
# COMPAT CHECK TESTS
# =============================================================================

@test "compat_check returns valid JSON" {
    run compat_check
    [[ "$status" -eq 0 ]]
    # Should start with { and end with }
    [[ "$output" =~ ^\{.*\}$ ]]
    # Should contain expected keys
    [[ "$output" =~ \"os\": ]]
    [[ "$output" =~ \"tools\": ]]
}

@test "compat_status produces readable output" {
    run compat_status
    [[ "$status" -eq 0 ]]
    # Should contain header
    [[ "$output" =~ "Portable Tools Status" ]]
    # Should list OS
    [[ "$output" =~ "OS:" ]]
    # Should list tools
    [[ "$output" =~ "gsed" ]]
}

# =============================================================================
# COMPAT::SED WRAPPER TESTS (existing functions)
# =============================================================================

@test "compat::sed_inplace modifies file in place" {
    echo "hello world" > "$TEST_TMPDIR/test.txt"
    compat::sed_inplace "$TEST_TMPDIR/test.txt" 's/world/universe/'
    run cat "$TEST_TMPDIR/test.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "hello universe" ]]
}

@test "compat::sed_extended uses ERE" {
    run run_with_mainframe 'echo "foo123bar" | compat::sed_extended "s/[0-9]+/_/"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "foo_bar" ]]
}

# =============================================================================
# COMPAT::DATE WRAPPER TESTS (existing functions)
# =============================================================================

@test "compat::date_format formats timestamp" {
    # Test with known timestamp
    run compat::date_format '%Y' 1609459200
    [[ "$status" -eq 0 ]]
    [[ "$output" == "2021" ]]
}

@test "compat::date_add_days adds days" {
    local base=1609459200  # 2021-01-01
    run compat::date_add_days 1 $base
    [[ "$status" -eq 0 ]]
    # Should be 1609545600 (2021-01-02)
    [[ "$output" == "1609545600" ]]
}

# =============================================================================
# COMPAT::STAT WRAPPER TESTS (existing functions)
# =============================================================================

@test "compat::stat_size matches pstat_size" {
    echo "test content" > "$TEST_TMPDIR/test.txt"
    local size1=$(compat::stat_size "$TEST_TMPDIR/test.txt")
    local size2=$(pstat_size "$TEST_TMPDIR/test.txt")
    [[ "$size1" == "$size2" ]]
}

@test "compat::stat_owner returns username" {
    touch "$TEST_TMPDIR/test.txt"
    run compat::stat_owner "$TEST_TMPDIR/test.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$(whoami)" ]]
}

# =============================================================================
# BASH VERSION DETECTION TESTS
# =============================================================================

@test "BASH_HAS_ASSOC_ARRAYS is set correctly" {
    # Should be 1 since MAINFRAME requires bash 4.0+
    [[ "$BASH_HAS_ASSOC_ARRAYS" == "1" ]]
}

@test "bash version feature flags are consistent" {
    # If we have namerefs (4.3+), we also have assoc arrays (4.0+)
    if [[ "$BASH_HAS_NAMEREFS" == "1" ]]; then
        [[ "$BASH_HAS_ASSOC_ARRAYS" == "1" ]]
    fi

    # If we have EPOCHREALTIME (5.0+), we also have namerefs (4.3+)
    if [[ "$BASH_HAS_EPOCHREALTIME" == "1" ]]; then
        [[ "$BASH_HAS_NAMEREFS" == "1" ]]
    fi
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

@test "psed handles empty input" {
    run run_with_mainframe 'echo "" | psed "s/foo/bar/"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "" ]]
}

@test "pgrep handles special characters in pattern" {
    echo "hello.world" > "$TEST_TMPDIR/test.txt"
    run pgrep -F "hello.world" "$TEST_TMPDIR/test.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "hello.world" ]]
}

@test "pstat functions handle spaces in filenames" {
    touch "$TEST_TMPDIR/file with spaces.txt"
    run pstat_size "$TEST_TMPDIR/file with spaces.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "0" ]]
}

@test "pfind handles spaces in directory names" {
    mkdir -p "$TEST_TMPDIR/dir with spaces"
    touch "$TEST_TMPDIR/dir with spaces/test.txt"

    run pfind "$TEST_TMPDIR/dir with spaces" -name "*.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "test.txt" ]]
}

# =============================================================================
# UNDERSCORE-STYLE WRAPPER TESTS (compat_*)
# =============================================================================

# -----------------------------------------------------------------------------
# DETECTION FUNCTION TESTS
# -----------------------------------------------------------------------------

@test "compat_detect_os returns valid OS name" {
    run compat_detect_os
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^(macos|linux|wsl|freebsd|openbsd|netbsd|windows|unknown)$ ]]
}

@test "compat_has_gnu_coreutils returns boolean" {
    run compat_has_gnu_coreutils
    # Should return 0 or 1
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "compat_prefer_gnu defaults to on" {
    run compat_prefer_gnu status
    [[ "$status" -eq 0 ]]
    [[ "$output" == "on" ]]
}

@test "compat_prefer_gnu can be toggled" {
    compat_prefer_gnu off
    run compat_prefer_gnu status
    [[ "$output" == "off" ]]

    compat_prefer_gnu on
    run compat_prefer_gnu status
    [[ "$output" == "on" ]]
}

@test "compat_get_os_family returns valid family" {
    run compat_get_os_family
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^(bsd|gnu|unknown)$ ]]
}

@test "compat_is_os matches current OS" {
    local current_os=$(compat_detect_os)
    run compat_is_os "$current_os"
    [[ "$status" -eq 0 ]]
}

@test "compat_is_os returns false for wrong OS" {
    run compat_is_os "nonexistent_os"
    [[ "$status" -eq 1 ]]
}

# -----------------------------------------------------------------------------
# SED WRAPPER TESTS
# -----------------------------------------------------------------------------

@test "compat_sed_inplace modifies file" {
    echo "hello world" > "$TEST_TMPDIR/sed_test.txt"
    compat_sed_inplace "$TEST_TMPDIR/sed_test.txt" 's/world/universe/'
    run cat "$TEST_TMPDIR/sed_test.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "hello universe" ]]
}

@test "compat_sed_inplace returns error on missing args" {
    run compat_sed_inplace
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Usage:" ]]
}

@test "compat_sed_extended uses ERE" {
    echo "foo123bar" > "$TEST_TMPDIR/sed_ext.txt"
    compat_sed_extended "$TEST_TMPDIR/sed_ext.txt" 's/[0-9]+/_/'
    run cat "$TEST_TMPDIR/sed_ext.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "foo_bar" ]]
}

@test "compat_sed with -i flag" {
    echo "test line" > "$TEST_TMPDIR/sed_i.txt"
    compat_sed -i 's/test/modified/' "$TEST_TMPDIR/sed_i.txt"
    run cat "$TEST_TMPDIR/sed_i.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "modified line" ]]
}

@test "compat_sed with -E flag" {
    run run_with_mainframe 'echo "abc123def" | compat_sed -E "s/[0-9]+/_/"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "abc_def" ]]
}

# -----------------------------------------------------------------------------
# DATE WRAPPER TESTS
# -----------------------------------------------------------------------------

@test "compat_date_parse parses YYYY-MM-DD" {
    run compat_date_parse "2021-01-01" "%Y-%m-%d"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "1609459200" ]]
}

@test "compat_date_parse returns error on missing args" {
    run compat_date_parse
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Usage:" ]]
}

@test "compat_date_add adds days correctly" {
    local base=1609459200  # 2021-01-01
    run compat_date_add 7 $base
    [[ "$status" -eq 0 ]]
    # 7 days = 604800 seconds
    [[ "$output" == "1610064000" ]]
}

@test "compat_date_add defaults to current time" {
    local now=$(date +%s)
    run compat_date_add 1
    [[ "$status" -eq 0 ]]
    # Result should be roughly now + 86400
    local expected=$((now + 86400))
    local diff=$((output - expected))
    # Allow 5 second variance for test execution time
    [[ ${diff#-} -lt 5 ]]
}

@test "compat_date_diff calculates positive difference" {
    # 2021-01-01 to 2021-01-08 = 7 days
    run compat_date_diff "2021-01-01" "2021-01-08"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "7" ]]
}

@test "compat_date_diff calculates negative difference" {
    # 2021-01-08 to 2021-01-01 = -7 days
    run compat_date_diff "2021-01-08" "2021-01-01"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "-7" ]]
}

@test "compat_date_diff accepts timestamps" {
    # Timestamps 7 days apart
    run compat_date_diff 1609459200 1610064000
    [[ "$status" -eq 0 ]]
    [[ "$output" == "7" ]]
}

@test "compat_date_sub subtracts days" {
    local base=1609459200  # 2021-01-01
    run compat_date_sub 7 $base
    [[ "$status" -eq 0 ]]
    # 7 days before = 604800 seconds less
    [[ "$output" == "1608854400" ]]
}

@test "compat_date_format formats timestamp" {
    run compat_date_format '%Y-%m-%d' 1609459200
    [[ "$status" -eq 0 ]]
    [[ "$output" == "2021-01-01" ]]
}

@test "compat_now returns current timestamp" {
    local before=$(date +%s)
    run compat_now
    local after=$(date +%s)
    [[ "$status" -eq 0 ]]
    [[ "$output" -ge "$before" && "$output" -le "$after" ]]
}

# -----------------------------------------------------------------------------
# GREP WRAPPER TESTS
# -----------------------------------------------------------------------------

@test "compat_grep_extended matches ERE pattern" {
    echo -e "cat\ndog\nrat" > "$TEST_TMPDIR/grep_test.txt"
    run compat_grep_extended "cat|rat" "$TEST_TMPDIR/grep_test.txt"
    [[ "$status" -eq 0 ]]
    [[ "${lines[0]}" == "cat" ]]
    [[ "${lines[1]}" == "rat" ]]
}

@test "compat_grep_extended returns error on no args" {
    run compat_grep_extended
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Usage:" ]]
}

@test "compat_grep_perl falls back gracefully" {
    echo "hello world" > "$TEST_TMPDIR/grep_perl.txt"
    run compat_grep_perl "hello" "$TEST_TMPDIR/grep_perl.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "hello world" ]]
}

# -----------------------------------------------------------------------------
# FIND WRAPPER TESTS
# -----------------------------------------------------------------------------

@test "compat_find_mtime finds recent files" {
    mkdir -p "$TEST_TMPDIR/findtest"
    touch "$TEST_TMPDIR/findtest/recent.txt"

    run compat_find_mtime "$TEST_TMPDIR/findtest" 1
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "recent.txt" ]]
}

@test "compat_find_mtime returns error on missing args" {
    run compat_find_mtime
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "Usage:" ]]
}

@test "compat_find_exec executes command on matches" {
    mkdir -p "$TEST_TMPDIR/exectest"
    echo "content1" > "$TEST_TMPDIR/exectest/file1.txt"
    echo "content2" > "$TEST_TMPDIR/exectest/file2.txt"

    # Create a marker file for each found file
    compat_find_exec "$TEST_TMPDIR/exectest" "*.txt" "touch {}.marker"

    # Check markers were created
    [[ -f "$TEST_TMPDIR/exectest/file1.txt.marker" ]]
    [[ -f "$TEST_TMPDIR/exectest/file2.txt.marker" ]]
}

# -----------------------------------------------------------------------------
# STAT WRAPPER TESTS
# -----------------------------------------------------------------------------

@test "compat_stat_size returns file size" {
    echo "hello" > "$TEST_TMPDIR/stat_test.txt"
    run compat_stat_size "$TEST_TMPDIR/stat_test.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "6" ]]  # "hello\n" = 6 bytes
}

@test "compat_stat_size returns error for missing file" {
    run compat_stat_size "$TEST_TMPDIR/nonexistent.txt"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "not found" ]]
}

@test "compat_stat_mtime returns timestamp" {
    touch "$TEST_TMPDIR/mtime_test.txt"
    run compat_stat_mtime "$TEST_TMPDIR/mtime_test.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9]+$ ]]
    # Should be recent
    local now=$(date +%s)
    local diff=$((now - output))
    [[ $diff -ge 0 && $diff -lt 60 ]]
}

@test "compat_stat_mtime returns error for missing file" {
    run compat_stat_mtime "$TEST_TMPDIR/nonexistent.txt"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "not found" ]]
}

# -----------------------------------------------------------------------------
# UTILITY FUNCTION TESTS
# -----------------------------------------------------------------------------

@test "compat_cmd_has_flag detects grep -E" {
    run compat_cmd_has_flag grep -E
    [[ "$status" -eq 0 ]]
}

@test "compat_info_json returns valid JSON" {
    run compat_info_json
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^\{.*\}$ ]]
    [[ "$output" =~ \"os\": ]]
}

@test "compat_summary produces readable output" {
    run compat_summary
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Platform:" ]]
    [[ "$output" =~ "Bash:" ]]
    [[ "$output" =~ "GNU Coreutils:" ]]
}

# -----------------------------------------------------------------------------
# INTEGRATION TESTS
# -----------------------------------------------------------------------------

@test "compat functions work together in pipeline" {
    # Create test data
    mkdir -p "$TEST_TMPDIR/integration"
    echo "2021-01-01: event1" > "$TEST_TMPDIR/integration/log1.txt"
    echo "2021-01-02: event2" >> "$TEST_TMPDIR/integration/log1.txt"
    echo "2021-01-03: event3" > "$TEST_TMPDIR/integration/log2.txt"

    # Find, grep, and count
    local count=$(compat_find_mtime "$TEST_TMPDIR/integration" 1 | \
        while read -r f; do compat_grep_extended "event" "$f" 2>/dev/null; done | wc -l)

    [[ "$count" -eq 3 ]]
}

@test "compat date functions roundtrip correctly" {
    local original="2021-06-15"
    local ts=$(compat_date_parse "$original" "%Y-%m-%d")
    run compat_date_format "%Y-%m-%d" "$ts"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$original" ]]
}

@test "compat stat and date functions work together" {
    touch "$TEST_TMPDIR/combo_test.txt"
    local mtime=$(compat_stat_mtime "$TEST_TMPDIR/combo_test.txt")
    run compat_date_format "%Y-%m-%d" "$mtime"
    [[ "$status" -eq 0 ]]
    # compat_date_format uses UTC formatting
    local today=$(TZ=UTC date +%Y-%m-%d)
    [[ "$output" == "$today" ]]
}
