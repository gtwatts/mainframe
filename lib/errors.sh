#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/errors.sh - Standardized Error Code Registry
# =============================================================================
# Description: Comprehensive error code constants with human-readable messages
#              and actionable recovery suggestions for AI coding assistants.
#              Maps common failure scenarios to structured codes that agents
#              can use for automated debugging and self-correction.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_ERRORS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_ERRORS_LOADED=1

# =============================================================================
# ERROR CODE CONSTANTS
# =============================================================================
# Categories use numeric ranges for fast classification:
#   1-9:   Argument errors (E_ARG_*)
#   10-19: Path errors (E_PATH_*)
#   20-29: Network errors (E_NET_*)
#   30-39: I/O errors (E_IO_*)
#   40-49: Parse errors (E_PARSE_*)
#   50-59: State errors (E_STATE_*)
#   60-69: Execution errors (E_EXEC_*)
#   70-79: Git errors (E_GIT_*)
#   80-89: Docker errors (E_DOCKER_*)
#   90-99: Cache errors (E_CACHE_*)
# =============================================================================

# --- Argument Errors (1-9) ---
readonly E_ARG_MISSING=1
readonly E_ARG_INVALID=2
readonly E_ARG_TYPE=3
readonly E_ARG_COUNT=4
readonly E_ARG_EMPTY=5
readonly E_ARG_RANGE=6
readonly E_ARG_FORMAT=7
readonly E_ARG_CONFLICT=8
readonly E_ARG_DEPRECATED=9

# --- Path Errors (10-19) ---
readonly E_PATH_NOT_FOUND=10
readonly E_PATH_PERMISSION=11
readonly E_PATH_TRAVERSAL=12
readonly E_PATH_SYMLINK=13
readonly E_PATH_NOT_DIR=14
readonly E_PATH_NOT_FILE=15
readonly E_PATH_EXISTS=16
readonly E_PATH_TOO_LONG=17
readonly E_PATH_INVALID_CHARS=18
readonly E_PATH_NOT_WRITABLE=19

# --- Network Errors (20-29) ---
readonly E_NET_TIMEOUT=20
readonly E_NET_REFUSED=21
readonly E_NET_DNS=22
readonly E_NET_UNREACHABLE=23
readonly E_NET_SSL=24
readonly E_NET_AUTH=25
readonly E_NET_RATE_LIMIT=26
readonly E_NET_PROTOCOL=27
readonly E_NET_PORT_IN_USE=28
readonly E_NET_NO_INTERFACE=29

# --- I/O Errors (30-39) ---
readonly E_IO_READ=30
readonly E_IO_WRITE=31
readonly E_IO_FULL=32
readonly E_IO_LOCKED=33
readonly E_IO_BROKEN_PIPE=34
readonly E_IO_EOF=35
readonly E_IO_ENCODING=36
readonly E_IO_TRUNCATED=37
readonly E_IO_DEVICE=38
readonly E_IO_SEEK=39

# --- Parse Errors (40-49) ---
readonly E_PARSE_JSON=40
readonly E_PARSE_CSV=41
readonly E_PARSE_INI=42
readonly E_PARSE_YAML=43
readonly E_PARSE_URL=44
readonly E_PARSE_SEMVER=45
readonly E_PARSE_DATE=46
readonly E_PARSE_NUMBER=47
readonly E_PARSE_REGEX=48
readonly E_PARSE_XML=49

# --- State Errors (50-59) ---
readonly E_STATE_NOT_READY=50
readonly E_STATE_LOCKED=51
readonly E_STATE_STALE=52
readonly E_STATE_CORRUPTED=53
readonly E_STATE_ALREADY_INIT=54
readonly E_STATE_NOT_INIT=55
readonly E_STATE_BUSY=56
readonly E_STATE_SHUTDOWN=57
readonly E_STATE_INCONSISTENT=58
readonly E_STATE_DEPENDENCY=59

# --- Execution Errors (60-69) ---
readonly E_EXEC_FAILED=60
readonly E_EXEC_TIMEOUT=61
readonly E_EXEC_SIGNAL=62
readonly E_EXEC_PERMISSION=63
readonly E_EXEC_NOT_FOUND=64
readonly E_EXEC_LOOP=65
readonly E_EXEC_RESOURCE=66
readonly E_EXEC_CHILD=67
readonly E_EXEC_PIPE=68
readonly E_EXEC_ABORT=69

# --- Git Errors (70-79) ---
readonly E_GIT_NOT_REPO=70
readonly E_GIT_DIRTY=71
readonly E_GIT_CONFLICT=72
readonly E_GIT_NO_REMOTE=73
readonly E_GIT_DETACHED=74
readonly E_GIT_HOOK_FAILED=75
readonly E_GIT_REBASE=76
readonly E_GIT_SUBMODULE=77
readonly E_GIT_LFS=78
readonly E_GIT_AUTH=79

# --- Docker Errors (80-89) ---
readonly E_DOCKER_NOT_RUNNING=80
readonly E_DOCKER_NOT_FOUND=81
readonly E_DOCKER_BUILD_FAILED=82
readonly E_DOCKER_PULL_FAILED=83
readonly E_DOCKER_NETWORK=84
readonly E_DOCKER_VOLUME=85
readonly E_DOCKER_COMPOSE=86
readonly E_DOCKER_RESOURCE=87
readonly E_DOCKER_REGISTRY=88
readonly E_DOCKER_HEALTHCHECK=89

# --- Cache Errors (90-99) ---
readonly E_CACHE_MISS=90
readonly E_CACHE_EXPIRED=91
readonly E_CACHE_CORRUPTED=92
readonly E_CACHE_FULL=93
readonly E_CACHE_EVICTED=94
readonly E_CACHE_KEY_INVALID=95
readonly E_CACHE_SERIALIZE=96
readonly E_CACHE_BACKEND=97
readonly E_CACHE_TTL_INVALID=98
readonly E_CACHE_COLLISION=99

# =============================================================================
# ASSOCIATIVE ARRAYS
# =============================================================================

declare -gA ERROR_CODES
declare -gA ERROR_MESSAGES
declare -gA ERROR_SUGGESTIONS

# --- Argument Error Messages & Suggestions ---
ERROR_CODES[E_ARG_MISSING]=$E_ARG_MISSING
ERROR_CODES[E_ARG_INVALID]=$E_ARG_INVALID
ERROR_CODES[E_ARG_TYPE]=$E_ARG_TYPE
ERROR_CODES[E_ARG_COUNT]=$E_ARG_COUNT
ERROR_CODES[E_ARG_EMPTY]=$E_ARG_EMPTY
ERROR_CODES[E_ARG_RANGE]=$E_ARG_RANGE
ERROR_CODES[E_ARG_FORMAT]=$E_ARG_FORMAT
ERROR_CODES[E_ARG_CONFLICT]=$E_ARG_CONFLICT
ERROR_CODES[E_ARG_DEPRECATED]=$E_ARG_DEPRECATED

ERROR_MESSAGES[E_ARG_MISSING]="Required argument is missing"
ERROR_MESSAGES[E_ARG_INVALID]="Argument value is invalid"
ERROR_MESSAGES[E_ARG_TYPE]="Argument type mismatch"
ERROR_MESSAGES[E_ARG_COUNT]="Wrong number of arguments"
ERROR_MESSAGES[E_ARG_EMPTY]="Argument is empty or blank"
ERROR_MESSAGES[E_ARG_RANGE]="Argument is out of allowed range"
ERROR_MESSAGES[E_ARG_FORMAT]="Argument format is incorrect"
ERROR_MESSAGES[E_ARG_CONFLICT]="Arguments conflict with each other"
ERROR_MESSAGES[E_ARG_DEPRECATED]="Argument is deprecated"

ERROR_SUGGESTIONS[E_ARG_MISSING]="Check function signature with 'declare -f FUNC_NAME'. Use contract_require to validate presence before calling."
ERROR_SUGGESTIONS[E_ARG_INVALID]="Use validate_int, validate_email, or validate_url from validation.sh to pre-check values."
ERROR_SUGGESTIONS[E_ARG_TYPE]="Use contract_type_check to verify argument type. Expected types: string, integer, array, file, dir."
ERROR_SUGGESTIONS[E_ARG_COUNT]="Review function signature. Use \$# to check argument count before calling."
ERROR_SUGGESTIONS[E_ARG_EMPTY]="Use [[ -n \"\$var\" ]] or contract_require to guard against empty strings."
ERROR_SUGGESTIONS[E_ARG_RANGE]="Use validate_int with min/max bounds: validate_int \"\$val\" MIN MAX."
ERROR_SUGGESTIONS[E_ARG_FORMAT]="Validate format with validate_email, validate_date, or validate_semver before passing."
ERROR_SUGGESTIONS[E_ARG_CONFLICT]="Review mutually exclusive options. Only one of the conflicting arguments should be provided."
ERROR_SUGGESTIONS[E_ARG_DEPRECATED]="Check CHEATSHEET.md for the replacement function. Update call to use the new API."

# --- Path Error Messages & Suggestions ---
ERROR_CODES[E_PATH_NOT_FOUND]=$E_PATH_NOT_FOUND
ERROR_CODES[E_PATH_PERMISSION]=$E_PATH_PERMISSION
ERROR_CODES[E_PATH_TRAVERSAL]=$E_PATH_TRAVERSAL
ERROR_CODES[E_PATH_SYMLINK]=$E_PATH_SYMLINK
ERROR_CODES[E_PATH_NOT_DIR]=$E_PATH_NOT_DIR
ERROR_CODES[E_PATH_NOT_FILE]=$E_PATH_NOT_FILE
ERROR_CODES[E_PATH_EXISTS]=$E_PATH_EXISTS
ERROR_CODES[E_PATH_TOO_LONG]=$E_PATH_TOO_LONG
ERROR_CODES[E_PATH_INVALID_CHARS]=$E_PATH_INVALID_CHARS
ERROR_CODES[E_PATH_NOT_WRITABLE]=$E_PATH_NOT_WRITABLE

ERROR_MESSAGES[E_PATH_NOT_FOUND]="Path does not exist"
ERROR_MESSAGES[E_PATH_PERMISSION]="Insufficient permissions to access path"
ERROR_MESSAGES[E_PATH_TRAVERSAL]="Path traversal attack detected"
ERROR_MESSAGES[E_PATH_SYMLINK]="Unexpected or broken symbolic link"
ERROR_MESSAGES[E_PATH_NOT_DIR]="Expected a directory but found a file"
ERROR_MESSAGES[E_PATH_NOT_FILE]="Expected a file but found a directory"
ERROR_MESSAGES[E_PATH_EXISTS]="Path already exists"
ERROR_MESSAGES[E_PATH_TOO_LONG]="Path exceeds maximum length"
ERROR_MESSAGES[E_PATH_INVALID_CHARS]="Path contains invalid characters"
ERROR_MESSAGES[E_PATH_NOT_WRITABLE]="Path is not writable"

ERROR_SUGGESTIONS[E_PATH_NOT_FOUND]="Use ensure_dir or ensure_file from idempotent.sh to create missing paths. Check with [[ -e \"\$path\" ]]."
ERROR_SUGGESTIONS[E_PATH_PERMISSION]="Check permissions with ls -la. Use chmod/chown or run with appropriate user. Try sudo if appropriate."
ERROR_SUGGESTIONS[E_PATH_TRAVERSAL]="Use validate_path_safe \"\$path\" \"\$base_dir\" from validation.sh. Never use unvalidated user paths."
ERROR_SUGGESTIONS[E_PATH_SYMLINK]="Use readlink -f to resolve symlinks. Check with [[ -L \"\$path\" ]] and verify target exists."
ERROR_SUGGESTIONS[E_PATH_NOT_DIR]="Use [[ -d \"\$path\" ]] to verify directory. Use path_dir from path.sh to get parent directory."
ERROR_SUGGESTIONS[E_PATH_NOT_FILE]="Use [[ -f \"\$path\" ]] to verify file. Ensure path does not end with /."
ERROR_SUGGESTIONS[E_PATH_EXISTS]="Use ensure_file or ensure_dir which are idempotent, or check existence before creating."
ERROR_SUGGESTIONS[E_PATH_TOO_LONG]="Shorten path components. Use path_normalize to remove redundant segments. Max is typically 4096 chars."
ERROR_SUGGESTIONS[E_PATH_INVALID_CHARS]="Use sanitize_filename from validation.sh. Remove null bytes, newlines, and control characters."
ERROR_SUGGESTIONS[E_PATH_NOT_WRITABLE]="Check parent directory write permission. Use [[ -w \"\$path\" ]] or [[ -w \"\$(dirname \"\$path\")\" ]]."

# --- Network Error Messages & Suggestions ---
ERROR_CODES[E_NET_TIMEOUT]=$E_NET_TIMEOUT
ERROR_CODES[E_NET_REFUSED]=$E_NET_REFUSED
ERROR_CODES[E_NET_DNS]=$E_NET_DNS
ERROR_CODES[E_NET_UNREACHABLE]=$E_NET_UNREACHABLE
ERROR_CODES[E_NET_SSL]=$E_NET_SSL
ERROR_CODES[E_NET_AUTH]=$E_NET_AUTH
ERROR_CODES[E_NET_RATE_LIMIT]=$E_NET_RATE_LIMIT
ERROR_CODES[E_NET_PROTOCOL]=$E_NET_PROTOCOL
ERROR_CODES[E_NET_PORT_IN_USE]=$E_NET_PORT_IN_USE
ERROR_CODES[E_NET_NO_INTERFACE]=$E_NET_NO_INTERFACE

ERROR_MESSAGES[E_NET_TIMEOUT]="Network connection timed out"
ERROR_MESSAGES[E_NET_REFUSED]="Connection refused by remote host"
ERROR_MESSAGES[E_NET_DNS]="DNS resolution failed"
ERROR_MESSAGES[E_NET_UNREACHABLE]="Network or host is unreachable"
ERROR_MESSAGES[E_NET_SSL]="SSL/TLS handshake or certificate error"
ERROR_MESSAGES[E_NET_AUTH]="Network authentication failed"
ERROR_MESSAGES[E_NET_RATE_LIMIT]="Rate limit exceeded"
ERROR_MESSAGES[E_NET_PROTOCOL]="Protocol-level error in communication"
ERROR_MESSAGES[E_NET_PORT_IN_USE]="Port is already in use"
ERROR_MESSAGES[E_NET_NO_INTERFACE]="No suitable network interface found"

ERROR_SUGGESTIONS[E_NET_TIMEOUT]="Use retry_with_backoff from safe.sh with increased timeout. Check host_alive from netscan.sh first."
ERROR_SUGGESTIONS[E_NET_REFUSED]="Verify service is running with port_check from netscan.sh. Check firewall rules and service status."
ERROR_SUGGESTIONS[E_NET_DNS]="Verify hostname is correct. Try direct IP if available. Check /etc/resolv.conf and network connectivity."
ERROR_SUGGESTIONS[E_NET_UNREACHABLE]="Check network interface is up. Verify routing with ip route. Use host_alive for connectivity test."
ERROR_SUGGESTIONS[E_NET_SSL]="Check certificate validity. Use --insecure for testing only. Verify ca-certificates package is installed."
ERROR_SUGGESTIONS[E_NET_AUTH]="Verify credentials in env vars. Use env_require from environment.sh to check auth tokens are set."
ERROR_SUGGESTIONS[E_NET_RATE_LIMIT]="Implement exponential backoff with retry_with_backoff. Add delay between requests. Check API quota."
ERROR_SUGGESTIONS[E_NET_PROTOCOL]="Check URL scheme (http vs https). Verify API version compatibility. Review response headers."
ERROR_SUGGESTIONS[E_NET_PORT_IN_USE]="Use proc_find_by_port from process.sh to identify the process. Kill it or choose another port."
ERROR_SUGGESTIONS[E_NET_NO_INTERFACE]="Check network interfaces with ip link. Verify NetworkManager or systemd-networkd status."

# --- I/O Error Messages & Suggestions ---
ERROR_CODES[E_IO_READ]=$E_IO_READ
ERROR_CODES[E_IO_WRITE]=$E_IO_WRITE
ERROR_CODES[E_IO_FULL]=$E_IO_FULL
ERROR_CODES[E_IO_LOCKED]=$E_IO_LOCKED
ERROR_CODES[E_IO_BROKEN_PIPE]=$E_IO_BROKEN_PIPE
ERROR_CODES[E_IO_EOF]=$E_IO_EOF
ERROR_CODES[E_IO_ENCODING]=$E_IO_ENCODING
ERROR_CODES[E_IO_TRUNCATED]=$E_IO_TRUNCATED
ERROR_CODES[E_IO_DEVICE]=$E_IO_DEVICE
ERROR_CODES[E_IO_SEEK]=$E_IO_SEEK

ERROR_MESSAGES[E_IO_READ]="Failed to read from file or stream"
ERROR_MESSAGES[E_IO_WRITE]="Failed to write to file or stream"
ERROR_MESSAGES[E_IO_FULL]="Disk or filesystem is full"
ERROR_MESSAGES[E_IO_LOCKED]="File is locked by another process"
ERROR_MESSAGES[E_IO_BROKEN_PIPE]="Pipe was closed by reader"
ERROR_MESSAGES[E_IO_EOF]="Unexpected end of file"
ERROR_MESSAGES[E_IO_ENCODING]="Character encoding error"
ERROR_MESSAGES[E_IO_TRUNCATED]="File was truncated during operation"
ERROR_MESSAGES[E_IO_DEVICE]="Device I/O error"
ERROR_MESSAGES[E_IO_SEEK]="Cannot seek in stream"

ERROR_SUGGESTIONS[E_IO_READ]="Check file exists and is readable: [[ -r \"\$file\" ]]. Verify encoding with file command."
ERROR_SUGGESTIONS[E_IO_WRITE]="Use atomic_write from atomic.sh for safe writes. Check disk space with df -h. Verify write permissions."
ERROR_SUGGESTIONS[E_IO_FULL]="Check disk usage with df -h. Use safe_remove from atomic.sh to clean temp files. Rotate logs."
ERROR_SUGGESTIONS[E_IO_LOCKED]="Use lockfile_acquire/lockfile_release from process.sh. Check lsof for locking process. Wait and retry."
ERROR_SUGGESTIONS[E_IO_BROKEN_PIPE]="Handle SIGPIPE or use set +o pipefail for this pipeline. Check downstream consumer is still alive."
ERROR_SUGGESTIONS[E_IO_EOF]="Verify file integrity. Check if file was being written concurrently. Use file_checkpoint from atomic.sh."
ERROR_SUGGESTIONS[E_IO_ENCODING]="Detect encoding with file command. Convert with iconv. Use LC_ALL=C for binary-safe operations."
ERROR_SUGGESTIONS[E_IO_TRUNCATED]="Verify file size matches expected. Use file_checkpoint/file_rollback from atomic.sh for recovery."
ERROR_SUGGESTIONS[E_IO_DEVICE]="Check device status with dmesg. Verify mount point. Test with dd if=DEVICE of=/dev/null bs=1 count=1."
ERROR_SUGGESTIONS[E_IO_SEEK]="Use temporary file instead of pipe for random access. Redirect to file first, then process."

# --- Parse Error Messages & Suggestions ---
ERROR_CODES[E_PARSE_JSON]=$E_PARSE_JSON
ERROR_CODES[E_PARSE_CSV]=$E_PARSE_CSV
ERROR_CODES[E_PARSE_INI]=$E_PARSE_INI
ERROR_CODES[E_PARSE_YAML]=$E_PARSE_YAML
ERROR_CODES[E_PARSE_URL]=$E_PARSE_URL
ERROR_CODES[E_PARSE_SEMVER]=$E_PARSE_SEMVER
ERROR_CODES[E_PARSE_DATE]=$E_PARSE_DATE
ERROR_CODES[E_PARSE_NUMBER]=$E_PARSE_NUMBER
ERROR_CODES[E_PARSE_REGEX]=$E_PARSE_REGEX
ERROR_CODES[E_PARSE_XML]=$E_PARSE_XML

ERROR_MESSAGES[E_PARSE_JSON]="Invalid JSON syntax"
ERROR_MESSAGES[E_PARSE_CSV]="Malformed CSV data"
ERROR_MESSAGES[E_PARSE_INI]="Invalid INI file format"
ERROR_MESSAGES[E_PARSE_YAML]="Invalid YAML syntax"
ERROR_MESSAGES[E_PARSE_URL]="Malformed URL"
ERROR_MESSAGES[E_PARSE_SEMVER]="Invalid semantic version format"
ERROR_MESSAGES[E_PARSE_DATE]="Invalid date format"
ERROR_MESSAGES[E_PARSE_NUMBER]="Invalid number format"
ERROR_MESSAGES[E_PARSE_REGEX]="Invalid regular expression"
ERROR_MESSAGES[E_PARSE_XML]="Invalid XML syntax"

ERROR_SUGGESTIONS[E_PARSE_JSON]="Validate with json_get from json.sh. Check for trailing commas, unquoted keys, or single quotes."
ERROR_SUGGESTIONS[E_PARSE_CSV]="Use csv_parse_line from csv.sh. Check for unbalanced quotes or incorrect field count."
ERROR_SUGGESTIONS[E_PARSE_INI]="Use parse_ini from parsers.sh. Verify [section] headers and key=value format."
ERROR_SUGGESTIONS[E_PARSE_YAML]="Check indentation consistency (spaces, not tabs). Verify colons have space after them."
ERROR_SUGGESTIONS[E_PARSE_URL]="Use parse_url from parsers.sh. Ensure scheme:// prefix. Encode special characters with url_encode."
ERROR_SUGGESTIONS[E_PARSE_SEMVER]="Use parse_semver from parsers.sh. Format must be MAJOR.MINOR.PATCH with optional pre-release suffix."
ERROR_SUGGESTIONS[E_PARSE_DATE]="Use validate_date from validation.sh. Expected format: YYYY-MM-DD. Check month/day ranges."
ERROR_SUGGESTIONS[E_PARSE_NUMBER]="Use validate_int or validate_float from validation.sh. Remove non-numeric chars first."
ERROR_SUGGESTIONS[E_PARSE_REGEX]="Check for unescaped metacharacters. Test regex with [[ \"\$str\" =~ \$pattern ]] in isolation."
ERROR_SUGGESTIONS[E_PARSE_XML]="Check for unclosed tags, unescaped ampersands (&amp;), and proper nesting."

# --- State Error Messages & Suggestions ---
ERROR_CODES[E_STATE_NOT_READY]=$E_STATE_NOT_READY
ERROR_CODES[E_STATE_LOCKED]=$E_STATE_LOCKED
ERROR_CODES[E_STATE_STALE]=$E_STATE_STALE
ERROR_CODES[E_STATE_CORRUPTED]=$E_STATE_CORRUPTED
ERROR_CODES[E_STATE_ALREADY_INIT]=$E_STATE_ALREADY_INIT
ERROR_CODES[E_STATE_NOT_INIT]=$E_STATE_NOT_INIT
ERROR_CODES[E_STATE_BUSY]=$E_STATE_BUSY
ERROR_CODES[E_STATE_SHUTDOWN]=$E_STATE_SHUTDOWN
ERROR_CODES[E_STATE_INCONSISTENT]=$E_STATE_INCONSISTENT
ERROR_CODES[E_STATE_DEPENDENCY]=$E_STATE_DEPENDENCY

ERROR_MESSAGES[E_STATE_NOT_READY]="Resource is not yet ready"
ERROR_MESSAGES[E_STATE_LOCKED]="Resource is currently locked"
ERROR_MESSAGES[E_STATE_STALE]="State data is outdated"
ERROR_MESSAGES[E_STATE_CORRUPTED]="State data is corrupted"
ERROR_MESSAGES[E_STATE_ALREADY_INIT]="Already initialized"
ERROR_MESSAGES[E_STATE_NOT_INIT]="Not yet initialized"
ERROR_MESSAGES[E_STATE_BUSY]="Resource is busy processing"
ERROR_MESSAGES[E_STATE_SHUTDOWN]="System is shutting down"
ERROR_MESSAGES[E_STATE_INCONSISTENT]="State is internally inconsistent"
ERROR_MESSAGES[E_STATE_DEPENDENCY]="Required dependency is unavailable"

ERROR_SUGGESTIONS[E_STATE_NOT_READY]="Use retry_with_backoff from safe.sh to poll readiness. Check initialization prerequisites."
ERROR_SUGGESTIONS[E_STATE_LOCKED]="Use lockfile_acquire with timeout from process.sh. Check who holds the lock with lsof."
ERROR_SUGGESTIONS[E_STATE_STALE]="Refresh state from source of truth. Check file modification time. Clear cache if applicable."
ERROR_SUGGESTIONS[E_STATE_CORRUPTED]="Use file_rollback from atomic.sh if checkpoint exists. Reinitialize from known good state."
ERROR_SUGGESTIONS[E_STATE_ALREADY_INIT]="Guard with initialization check. This is often safe to ignore if operation is idempotent."
ERROR_SUGGESTIONS[E_STATE_NOT_INIT]="Call initialization function first. Check _LOADED guard variables for required modules."
ERROR_SUGGESTIONS[E_STATE_BUSY]="Wait with retry_with_backoff. Check if previous operation timed out and needs cleanup."
ERROR_SUGGESTIONS[E_STATE_SHUTDOWN]="Do not attempt new operations. Allow graceful shutdown to complete. Check trap handlers."
ERROR_SUGGESTIONS[E_STATE_INCONSISTENT]="Compare actual vs expected state. Use file_checkpoint/file_rollback for recovery."
ERROR_SUGGESTIONS[E_STATE_DEPENDENCY]="Use env_require from environment.sh to check. Install missing deps or start required services."

# --- Execution Error Messages & Suggestions ---
ERROR_CODES[E_EXEC_FAILED]=$E_EXEC_FAILED
ERROR_CODES[E_EXEC_TIMEOUT]=$E_EXEC_TIMEOUT
ERROR_CODES[E_EXEC_SIGNAL]=$E_EXEC_SIGNAL
ERROR_CODES[E_EXEC_PERMISSION]=$E_EXEC_PERMISSION
ERROR_CODES[E_EXEC_NOT_FOUND]=$E_EXEC_NOT_FOUND
ERROR_CODES[E_EXEC_LOOP]=$E_EXEC_LOOP
ERROR_CODES[E_EXEC_RESOURCE]=$E_EXEC_RESOURCE
ERROR_CODES[E_EXEC_CHILD]=$E_EXEC_CHILD
ERROR_CODES[E_EXEC_PIPE]=$E_EXEC_PIPE
ERROR_CODES[E_EXEC_ABORT]=$E_EXEC_ABORT

ERROR_MESSAGES[E_EXEC_FAILED]="Command execution failed"
ERROR_MESSAGES[E_EXEC_TIMEOUT]="Command exceeded time limit"
ERROR_MESSAGES[E_EXEC_SIGNAL]="Process terminated by signal"
ERROR_MESSAGES[E_EXEC_PERMISSION]="Permission denied for execution"
ERROR_MESSAGES[E_EXEC_NOT_FOUND]="Command or executable not found"
ERROR_MESSAGES[E_EXEC_LOOP]="Infinite loop or recursion detected"
ERROR_MESSAGES[E_EXEC_RESOURCE]="Resource limit exceeded (memory, CPU, file descriptors)"
ERROR_MESSAGES[E_EXEC_CHILD]="Child process error"
ERROR_MESSAGES[E_EXEC_PIPE]="Pipeline stage failed"
ERROR_MESSAGES[E_EXEC_ABORT]="Execution was aborted"

ERROR_SUGGESTIONS[E_EXEC_FAILED]="Check exit code with \$?. Use observe_command from observe.sh for detailed failure context."
ERROR_SUGGESTIONS[E_EXEC_TIMEOUT]="Increase timeout value or use with_timeout from process.sh with a longer duration."
ERROR_SUGGESTIONS[E_EXEC_SIGNAL]="Check signal with kill -l \$((exit_code - 128)). Common: SIGTERM=15, SIGKILL=9, SIGSEGV=11."
ERROR_SUGGESTIONS[E_EXEC_PERMISSION]="Check executable bit: chmod +x file. Verify shebang line. Check SELinux/AppArmor policies."
ERROR_SUGGESTIONS[E_EXEC_NOT_FOUND]="Use ensure_command from idempotent.sh to verify. Check PATH with env_path_has from environment.sh."
ERROR_SUGGESTIONS[E_EXEC_LOOP]="Add recursion depth counter. Use MAINFRAME_MAX_DEPTH variable. Check for circular dependencies."
ERROR_SUGGESTIONS[E_EXEC_RESOURCE]="Check ulimit -a for limits. Monitor with /proc/PID/status. Reduce parallel operations."
ERROR_SUGGESTIONS[E_EXEC_CHILD]="Check child exit code. Use wait \$pid; echo \$? for async processes. Verify child environment."
ERROR_SUGGESTIONS[E_EXEC_PIPE]="Use set -o pipefail and check PIPESTATUS array. Identify which stage failed."
ERROR_SUGGESTIONS[E_EXEC_ABORT]="Check trap handlers. Verify SIGINT/SIGTERM handling. Review abort conditions in logic."

# --- Git Error Messages & Suggestions ---
ERROR_CODES[E_GIT_NOT_REPO]=$E_GIT_NOT_REPO
ERROR_CODES[E_GIT_DIRTY]=$E_GIT_DIRTY
ERROR_CODES[E_GIT_CONFLICT]=$E_GIT_CONFLICT
ERROR_CODES[E_GIT_NO_REMOTE]=$E_GIT_NO_REMOTE
ERROR_CODES[E_GIT_DETACHED]=$E_GIT_DETACHED
ERROR_CODES[E_GIT_HOOK_FAILED]=$E_GIT_HOOK_FAILED
ERROR_CODES[E_GIT_REBASE]=$E_GIT_REBASE
ERROR_CODES[E_GIT_SUBMODULE]=$E_GIT_SUBMODULE
ERROR_CODES[E_GIT_LFS]=$E_GIT_LFS
ERROR_CODES[E_GIT_AUTH]=$E_GIT_AUTH

ERROR_MESSAGES[E_GIT_NOT_REPO]="Not a git repository"
ERROR_MESSAGES[E_GIT_DIRTY]="Working tree has uncommitted changes"
ERROR_MESSAGES[E_GIT_CONFLICT]="Merge conflict detected"
ERROR_MESSAGES[E_GIT_NO_REMOTE]="No remote repository configured"
ERROR_MESSAGES[E_GIT_DETACHED]="HEAD is detached from any branch"
ERROR_MESSAGES[E_GIT_HOOK_FAILED]="Git hook rejected the operation"
ERROR_MESSAGES[E_GIT_REBASE]="Rebase in progress or failed"
ERROR_MESSAGES[E_GIT_SUBMODULE]="Submodule error"
ERROR_MESSAGES[E_GIT_LFS]="Git LFS error"
ERROR_MESSAGES[E_GIT_AUTH]="Git authentication failed"

ERROR_SUGGESTIONS[E_GIT_NOT_REPO]="Use git init or cd to repository root. Check with git_branch from git.sh."
ERROR_SUGGESTIONS[E_GIT_DIRTY]="Use git_is_dirty from git.sh to check. Commit, stash, or reset changes first."
ERROR_SUGGESTIONS[E_GIT_CONFLICT]="Run git status to see conflicted files. Edit conflict markers, then git add and continue."
ERROR_SUGGESTIONS[E_GIT_NO_REMOTE]="Add remote with git remote add origin URL. Verify with git remote -v."
ERROR_SUGGESTIONS[E_GIT_DETACHED]="Use git checkout BRANCH_NAME to reattach. Create branch with git checkout -b new-branch."
ERROR_SUGGESTIONS[E_GIT_HOOK_FAILED]="Check .git/hooks/ for the failing hook. Use --no-verify to bypass (not recommended)."
ERROR_SUGGESTIONS[E_GIT_REBASE]="Use git rebase --abort to cancel, or resolve conflicts and git rebase --continue."
ERROR_SUGGESTIONS[E_GIT_SUBMODULE]="Run git submodule update --init --recursive. Check .gitmodules configuration."
ERROR_SUGGESTIONS[E_GIT_LFS]="Install git-lfs and run git lfs install. Pull LFS objects with git lfs pull."
ERROR_SUGGESTIONS[E_GIT_AUTH]="Check SSH key with ssh -T git@github.com. Verify credential helper. Update token if expired."

# --- Docker Error Messages & Suggestions ---
ERROR_CODES[E_DOCKER_NOT_RUNNING]=$E_DOCKER_NOT_RUNNING
ERROR_CODES[E_DOCKER_NOT_FOUND]=$E_DOCKER_NOT_FOUND
ERROR_CODES[E_DOCKER_BUILD_FAILED]=$E_DOCKER_BUILD_FAILED
ERROR_CODES[E_DOCKER_PULL_FAILED]=$E_DOCKER_PULL_FAILED
ERROR_CODES[E_DOCKER_NETWORK]=$E_DOCKER_NETWORK
ERROR_CODES[E_DOCKER_VOLUME]=$E_DOCKER_VOLUME
ERROR_CODES[E_DOCKER_COMPOSE]=$E_DOCKER_COMPOSE
ERROR_CODES[E_DOCKER_RESOURCE]=$E_DOCKER_RESOURCE
ERROR_CODES[E_DOCKER_REGISTRY]=$E_DOCKER_REGISTRY
ERROR_CODES[E_DOCKER_HEALTHCHECK]=$E_DOCKER_HEALTHCHECK

ERROR_MESSAGES[E_DOCKER_NOT_RUNNING]="Docker daemon is not running"
ERROR_MESSAGES[E_DOCKER_NOT_FOUND]="Docker image or container not found"
ERROR_MESSAGES[E_DOCKER_BUILD_FAILED]="Docker image build failed"
ERROR_MESSAGES[E_DOCKER_PULL_FAILED]="Failed to pull Docker image"
ERROR_MESSAGES[E_DOCKER_NETWORK]="Docker networking error"
ERROR_MESSAGES[E_DOCKER_VOLUME]="Docker volume error"
ERROR_MESSAGES[E_DOCKER_COMPOSE]="Docker Compose operation failed"
ERROR_MESSAGES[E_DOCKER_RESOURCE]="Docker resource limits exceeded"
ERROR_MESSAGES[E_DOCKER_REGISTRY]="Docker registry communication error"
ERROR_MESSAGES[E_DOCKER_HEALTHCHECK]="Container health check failed"

ERROR_SUGGESTIONS[E_DOCKER_NOT_RUNNING]="Use docker_running from docker.sh to check. Start with: sudo systemctl start docker."
ERROR_SUGGESTIONS[E_DOCKER_NOT_FOUND]="List images with docker images. List containers with docker ps -a. Pull if missing."
ERROR_SUGGESTIONS[E_DOCKER_BUILD_FAILED]="Check Dockerfile syntax. Review build output for the failing step. Use --no-cache to rebuild."
ERROR_SUGGESTIONS[E_DOCKER_PULL_FAILED]="Verify image name and tag. Check registry connectivity. Authenticate with docker login if private."
ERROR_SUGGESTIONS[E_DOCKER_NETWORK]="List networks with docker network ls. Recreate with docker network create. Check port conflicts."
ERROR_SUGGESTIONS[E_DOCKER_VOLUME]="Check volume with docker volume inspect. Verify mount path permissions. Remove stale volumes."
ERROR_SUGGESTIONS[E_DOCKER_COMPOSE]="Validate compose file: docker compose config. Check service dependencies and healthchecks."
ERROR_SUGGESTIONS[E_DOCKER_RESOURCE]="Check docker stats for resource usage. Increase Docker memory/CPU limits in daemon settings."
ERROR_SUGGESTIONS[E_DOCKER_REGISTRY]="Check registry URL. Verify authentication. Test with curl to registry /v2/ endpoint."
ERROR_SUGGESTIONS[E_DOCKER_HEALTHCHECK]="Check docker logs CONTAINER. Review healthcheck command in Dockerfile. Increase health interval."

# --- Cache Error Messages & Suggestions ---
ERROR_CODES[E_CACHE_MISS]=$E_CACHE_MISS
ERROR_CODES[E_CACHE_EXPIRED]=$E_CACHE_EXPIRED
ERROR_CODES[E_CACHE_CORRUPTED]=$E_CACHE_CORRUPTED
ERROR_CODES[E_CACHE_FULL]=$E_CACHE_FULL
ERROR_CODES[E_CACHE_EVICTED]=$E_CACHE_EVICTED
ERROR_CODES[E_CACHE_KEY_INVALID]=$E_CACHE_KEY_INVALID
ERROR_CODES[E_CACHE_SERIALIZE]=$E_CACHE_SERIALIZE
ERROR_CODES[E_CACHE_BACKEND]=$E_CACHE_BACKEND
ERROR_CODES[E_CACHE_TTL_INVALID]=$E_CACHE_TTL_INVALID
ERROR_CODES[E_CACHE_COLLISION]=$E_CACHE_COLLISION

ERROR_MESSAGES[E_CACHE_MISS]="Cache entry not found"
ERROR_MESSAGES[E_CACHE_EXPIRED]="Cache entry has expired"
ERROR_MESSAGES[E_CACHE_CORRUPTED]="Cache data is corrupted"
ERROR_MESSAGES[E_CACHE_FULL]="Cache storage is full"
ERROR_MESSAGES[E_CACHE_EVICTED]="Cache entry was evicted"
ERROR_MESSAGES[E_CACHE_KEY_INVALID]="Cache key is invalid"
ERROR_MESSAGES[E_CACHE_SERIALIZE]="Failed to serialize/deserialize cache data"
ERROR_MESSAGES[E_CACHE_BACKEND]="Cache backend is unavailable"
ERROR_MESSAGES[E_CACHE_TTL_INVALID]="Invalid TTL value for cache entry"
ERROR_MESSAGES[E_CACHE_COLLISION]="Cache key hash collision detected"

ERROR_SUGGESTIONS[E_CACHE_MISS]="This is normal for first access. Populate cache with the computed value and retry."
ERROR_SUGGESTIONS[E_CACHE_EXPIRED]="Refresh from source and update cache. Consider increasing TTL if data changes infrequently."
ERROR_SUGGESTIONS[E_CACHE_CORRUPTED]="Clear the corrupted entry and regenerate. Use atomic_write from atomic.sh for cache writes."
ERROR_SUGGESTIONS[E_CACHE_FULL]="Evict old entries or increase cache size. Implement LRU eviction. Check disk space with df -h."
ERROR_SUGGESTIONS[E_CACHE_EVICTED]="Re-fetch from source. This is normal under memory pressure. Consider increasing cache capacity."
ERROR_SUGGESTIONS[E_CACHE_KEY_INVALID]="Sanitize cache key: remove special chars, limit length. Use sha256 from crypto.sh for long keys."
ERROR_SUGGESTIONS[E_CACHE_SERIALIZE]="Check data encoding. Ensure no binary data in text cache. Use base64_encode from crypto.sh."
ERROR_SUGGESTIONS[E_CACHE_BACKEND]="Check cache service status (Redis, filesystem). Verify connectivity and permissions."
ERROR_SUGGESTIONS[E_CACHE_TTL_INVALID]="TTL must be a positive integer (seconds). Use validate_int from validation.sh to check."
ERROR_SUGGESTIONS[E_CACHE_COLLISION]="Use a longer hash or composite key. Verify key uniqueness. Consider namespace prefixes."

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Resolve an error name from a numeric code
# Usage: _error_name_from_code 10
# Returns: E_PATH_NOT_FOUND
_error_name_from_code() {
    local code="$1"
    local name
    for name in "${!ERROR_CODES[@]}"; do
        if [[ "${ERROR_CODES[$name]}" == "$code" ]]; then
            printf '%s' "$name"
            return 0
        fi
    done
    return 1
}

# @pre: code is a valid error name (E_*) or numeric code (1-99)
# @post: prints human-readable error message to stdout
# @returns: 0 on success, 1 if code not found
#
# Get the human-readable message for an error code.
#
# Usage: mainframe_error_msg E_PATH_NOT_FOUND
# Usage: mainframe_error_msg 10
# Example: msg=$(mainframe_error_msg E_ARG_MISSING)
mainframe_error_msg() {
    local code="$1"

    # If numeric, resolve to name first
    if [[ "$code" =~ ^[0-9]+$ ]]; then
        code=$(_error_name_from_code "$code") || {
            printf 'Unknown error code: %s' "$1"
            return 1
        }
    fi

    local msg="${ERROR_MESSAGES[$code]:-}"
    if [[ -z "$msg" ]]; then
        printf 'Unknown error: %s' "$code"
        return 1
    fi

    printf '%s' "$msg"
    return 0
}

# @pre: code is a valid error name (E_*) or numeric code (1-99)
# @post: prints actionable recovery suggestion to stdout
# @returns: 0 on success, 1 if code not found
#
# Get the recovery suggestion for an error code.
# Suggestions are actionable - they tell the AI agent exactly what to call.
#
# Usage: mainframe_error_suggest E_PATH_NOT_FOUND
# Usage: mainframe_error_suggest 10
# Example: hint=$(mainframe_error_suggest E_NET_TIMEOUT)
mainframe_error_suggest() {
    local code="$1"

    # If numeric, resolve to name first
    if [[ "$code" =~ ^[0-9]+$ ]]; then
        code=$(_error_name_from_code "$code") || {
            printf 'No suggestion available for unknown code: %s' "$1"
            return 1
        }
    fi

    local suggestion="${ERROR_SUGGESTIONS[$code]:-}"
    if [[ -z "$suggestion" ]]; then
        printf 'No suggestion available for: %s' "$code"
        return 1
    fi

    printf '%s' "$suggestion"
    return 0
}

# @pre: code is a valid error name (E_*) or numeric code (1-99)
# @post: prints category name to stdout (arg, path, net, io, parse, state, exec, git, docker, cache)
# @returns: 0 on success, 1 if code not found
#
# Get the category for an error code based on its numeric range.
#
# Usage: mainframe_error_category E_PATH_NOT_FOUND
# Usage: mainframe_error_category 10
# Example: cat=$(mainframe_error_category 25)  # "net"
mainframe_error_category() {
    local code="$1"
    local num

    # If named, resolve to numeric
    if [[ "$code" =~ ^E_ ]]; then
        num="${ERROR_CODES[$code]:-}"
        if [[ -z "$num" ]]; then
            printf 'unknown'
            return 1
        fi
    elif [[ "$code" =~ ^[0-9]+$ ]]; then
        num="$code"
    else
        printf 'unknown'
        return 1
    fi

    if (( num >= 1 && num <= 9 )); then
        printf 'arg'
    elif (( num >= 10 && num <= 19 )); then
        printf 'path'
    elif (( num >= 20 && num <= 29 )); then
        printf 'net'
    elif (( num >= 30 && num <= 39 )); then
        printf 'io'
    elif (( num >= 40 && num <= 49 )); then
        printf 'parse'
    elif (( num >= 50 && num <= 59 )); then
        printf 'state'
    elif (( num >= 60 && num <= 69 )); then
        printf 'exec'
    elif (( num >= 70 && num <= 79 )); then
        printf 'git'
    elif (( num >= 80 && num <= 89 )); then
        printf 'docker'
    elif (( num >= 90 && num <= 99 )); then
        printf 'cache'
    else
        printf 'unknown'
        return 1
    fi
    return 0
}

# @pre: none (category filter is optional)
# @post: prints formatted error code listing to stdout
# @returns: 0 always
#
# List all error codes, optionally filtered by category.
# Output format: CODE  NAME  MESSAGE
#
# Usage: mainframe_error_list
# Usage: mainframe_error_list net
# Usage: mainframe_error_list docker
# Example: mainframe_error_list path | while read -r code name msg; do ...; done
mainframe_error_list() {
    local filter="${1:-}"
    local name num category

    # Collect and sort by numeric code
    local -a entries=()
    for name in "${!ERROR_CODES[@]}"; do
        num="${ERROR_CODES[$name]}"
        category=$(mainframe_error_category "$num" 2>/dev/null)
        if [[ -z "$filter" || "$category" == "$filter" ]]; then
            entries+=("$(printf '%03d\t%s\t%s' "$num" "$name" "${ERROR_MESSAGES[$name]:-}")")
        fi
    done

    # Sort by numeric code and print
    local entry
    printf '%s\n' "${entries[@]}" | sort -t$'\t' -k1,1n | while IFS=$'\t' read -r num name msg; do
        # Strip leading zeros for display
        num=$(( 10#$num ))
        printf '%-4d  %-24s  %s\n' "$num" "$name" "$msg"
    done

    return 0
}
