#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/lazy.sh - Enhanced Lazy Loading Engine
# =============================================================================
# Description: Function-level lazy loading for AI agent efficiency
#              - Stub functions that load on first call
#              - Library manifests for auto-loading
#              - Precompiled bundles for optimized loading
#              - Load profiling for performance analysis
#              - Memory-efficient unloading
# =============================================================================
# "AI agents should only load what they need."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_LAZY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_LAZY_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Enable lazy loading (set before sourcing common.sh)
# MAINFRAME_LAZY=1 enables function-level lazy loading
declare -g MAINFRAME_LAZY="${MAINFRAME_LAZY:-0}"

# Enable load profiling
declare -g MAINFRAME_PROFILE_LOADS="${MAINFRAME_PROFILE_LOADS:-0}"

# Bundle file path (optional)
declare -g MAINFRAME_BUNDLE="${MAINFRAME_BUNDLE:-}"

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Library manifest: function name -> library name
declare -gA _LAZY_MANIFEST=()

# Load times for profiling (library -> milliseconds)
declare -gA _LAZY_LOAD_TIMES=()

# Profiling start timestamp
declare -g _LAZY_LOAD_START=""

# Stub tracking: which functions are currently stubs
declare -gA _LAZY_STUBS=()

# Libraries that have been fully loaded
declare -gA _LAZY_LOADED_LIBS=()

# =============================================================================
# FUNCTION-LEVEL LAZY LOADING
# =============================================================================

# Create a stub function that loads the real implementation on first call
# Usage: lazy_stub "function_name" "library_name"
# Example: lazy_stub "now" "datetime"
lazy_stub() {
    local fn_name="$1"
    local library="$2"

    # Validate inputs
    [[ -z "$fn_name" ]] && return 1
    [[ -z "$library" ]] && return 1

    # Sanitize function name (prevent injection)
    [[ ! "$fn_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && return 1

    # Sanitize library name (prevent path traversal)
    [[ ! "$library" =~ ^[a-zA-Z0-9_-]+$ ]] && return 1

    # Track stub
    _LAZY_STUBS["$fn_name"]=1

    # Register in manifest
    _LAZY_MANIFEST["$fn_name"]="$library"

    # Create stub function using eval (safe due to validation above)
    # The stub loads the library, removes itself, and re-calls the function
    eval "${fn_name}() {
        # Remove stub marker
        unset '_LAZY_STUBS[${fn_name}]'

        # Load the real library
        if ! lazy_load_library '${library}'; then
            printf 'lazy: failed to load library: %s\\n' '${library}' >&2
            return 1
        fi

        # Re-call the now-loaded function with original arguments
        '${fn_name}' \"\$@\"
    }"
}

# Create stub functions for all exported functions in a library
# Usage: lazy_stub_library "library_name" "func1" "func2" ...
# Example: lazy_stub_library "datetime" now now_iso date_add date_diff
lazy_stub_library() {
    local library="$1"
    shift
    local -a functions=("$@")

    for fn in "${functions[@]}"; do
        lazy_stub "$fn" "$library"
    done
}

# Check if a function is currently a stub
# Usage: lazy_is_stub "function_name"
lazy_is_stub() {
    local fn_name="$1"
    [[ -n "${_LAZY_STUBS[$fn_name]:-}" ]]
}

# =============================================================================
# LIBRARY MANIFEST
# =============================================================================

# Register functions that belong to a library (for auto-loading)
# Usage: lazy_register "library" "func1" "func2" ...
lazy_register() {
    local library="$1"
    shift
    for fn in "$@"; do
        _LAZY_MANIFEST["$fn"]="$library"
    done
}

# Get the library name for a function
# Usage: library=$(lazy_library_for "now")
lazy_library_for() {
    local fn_name="$1"
    printf '%s\n' "${_LAZY_MANIFEST[$fn_name]:-}"
}

# Auto-load library when function is called (command_not_found handler)
# Usage: lazy_autoload "function_name"
lazy_autoload() {
    local fn_name="$1"
    local library="${_LAZY_MANIFEST[$fn_name]:-}"

    if [[ -n "$library" ]]; then
        lazy_load_library "$library"
        return $?
    fi
    return 1
}

# List all registered functions
# Usage: lazy_list_functions
lazy_list_functions() {
    local fn
    for fn in "${!_LAZY_MANIFEST[@]}"; do
        printf '%s -> %s\n' "$fn" "${_LAZY_MANIFEST[$fn]}"
    done | sort
}

# List functions for a specific library
# Usage: lazy_functions_in "datetime"
lazy_functions_in() {
    local library="$1"
    local fn
    for fn in "${!_LAZY_MANIFEST[@]}"; do
        [[ "${_LAZY_MANIFEST[$fn]}" == "$library" ]] && printf '%s\n' "$fn"
    done | sort
}

# =============================================================================
# LIBRARY LOADING
# =============================================================================

# Load a library by name (with profiling support)
# Usage: lazy_load_library "datetime"
lazy_load_library() {
    local lib_name="$1"

    # Validate library name
    [[ -z "${lib_name// /}" ]] && return 1
    [[ ! "$lib_name" =~ ^[a-zA-Z0-9_-]+$ ]] && return 1

    # Skip if already loaded
    [[ -n "${_LAZY_LOADED_LIBS[$lib_name]:-}" ]] && return 0

    # Determine library path
    local lib_dir="${MAINFRAME_ROOT:-${BASH_SOURCE[0]%/*}}"
    local lib_path="${lib_dir}/${lib_name}.sh"

    # Handle alternative path
    if [[ ! -f "$lib_path" && -f "${lib_dir}/lib/${lib_name}.sh" ]]; then
        lib_path="${lib_dir}/lib/${lib_name}.sh"
    fi

    # Check file exists
    if [[ ! -f "$lib_path" ]]; then
        return 1
    fi

    # Start profiling
    lazy_profile_start

    # Source the library
    source "$lib_path" || return 1

    # Mark as loaded
    _LAZY_LOADED_LIBS["$lib_name"]=1

    # End profiling
    lazy_profile_end "$lib_name"

    # Remove any stubs for functions in this library
    local fn
    for fn in "${!_LAZY_STUBS[@]}"; do
        if [[ "${_LAZY_MANIFEST[$fn]:-}" == "$lib_name" ]]; then
            unset '_LAZY_STUBS[$fn]'
        fi
    done

    return 0
}

# Check if a library is loaded
# Usage: lazy_is_loaded "datetime"
lazy_is_loaded() {
    local lib_name="$1"
    [[ -n "${_LAZY_LOADED_LIBS[$lib_name]:-}" ]]
}

# List all loaded libraries
# Usage: lazy_loaded_libs
lazy_loaded_libs() {
    local lib
    for lib in "${!_LAZY_LOADED_LIBS[@]}"; do
        printf '%s\n' "$lib"
    done | sort
}

# =============================================================================
# PRECOMPILED BUNDLE SUPPORT
# =============================================================================

# Generate a single-file bundle of selected libraries
# Usage: lazy_bundle_create "output.sh" "datetime" "http" "csv"
lazy_bundle_create() {
    local output="$1"
    shift
    local -a libraries=("$@")

    local lib_dir="${MAINFRAME_ROOT:-${BASH_SOURCE[0]%/*}}"

    # Handle lib subdirectory
    if [[ ! -f "${lib_dir}/datetime.sh" && -d "${lib_dir}/lib" ]]; then
        lib_dir="${lib_dir}/lib"
    fi

    {
        printf '#!/usr/bin/env bash\n'
        printf '# MAINFRAME Bundle - Generated %s\n' "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')"
        printf '# Libraries: %s\n' "${libraries[*]}"
        printf '# Optimized for AI agent loading\n'
        printf '\n'
        printf '# Prevent double-sourcing\n'
        printf '[[ -n "${_MAINFRAME_BUNDLE_LOADED:-}" ]] && return 0\n'
        printf 'readonly _MAINFRAME_BUNDLE_LOADED=1\n'
        printf '\n'

        for lib in "${libraries[@]}"; do
            local lib_path="${lib_dir}/${lib}.sh"
            if [[ -f "$lib_path" ]]; then
                printf '# === %s.sh ===\n' "$lib"
                # Strip shebang, comment-only lines at start, and empty lines
                # Keep inline comments and code
                awk '
                    BEGIN { in_header = 1 }
                    # Skip shebang
                    /^#!/ && NR == 1 { next }
                    # Skip pure comment lines at the start of file
                    in_header && /^[[:space:]]*#/ { next }
                    # Skip empty lines at the start of file
                    in_header && /^[[:space:]]*$/ { next }
                    # Once we hit code, stop skipping
                    { in_header = 0; print }
                ' "$lib_path"
                printf '\n'
            else
                printf '# WARNING: Library not found: %s\n' "$lib"
            fi
        done
    } > "$output"

    # Calculate bundle size
    local size
    size=$(wc -c < "$output" 2>/dev/null || echo "unknown")

    printf 'Bundle created: %s (%s bytes)\n' "$output" "$size"
}

# Load from bundle if available, fall back to individual files
# Usage: lazy_load_smart
lazy_load_smart() {
    local bundle="${MAINFRAME_BUNDLE:-}"

    if [[ -n "$bundle" && -f "$bundle" ]]; then
        lazy_profile_start
        source "$bundle"
        lazy_profile_end "bundle"
        return 0
    fi

    # Fall back to standard loading
    local lib_dir="${MAINFRAME_ROOT:-${BASH_SOURCE[0]%/*}}"
    if [[ -f "${lib_dir}/common.sh" ]]; then
        source "${lib_dir}/common.sh"
    elif [[ -f "${lib_dir}/lib/common.sh" ]]; then
        source "${lib_dir}/lib/common.sh"
    fi
}

# Validate bundle contents (check it's valid bash)
# Usage: lazy_bundle_validate "bundle.sh"
lazy_bundle_validate() {
    local bundle="$1"

    if [[ ! -f "$bundle" ]]; then
        printf 'Bundle not found: %s\n' "$bundle" >&2
        return 1
    fi

    # Check syntax
    if ! bash -n "$bundle" 2>/dev/null; then
        printf 'Bundle has syntax errors: %s\n' "$bundle" >&2
        return 1
    fi

    # Get bundle info
    local libraries
    libraries=$(grep '^# Libraries:' "$bundle" | cut -d: -f2-)
    local size
    size=$(wc -c < "$bundle")

    printf 'Bundle: %s\n' "$bundle"
    printf 'Libraries: %s\n' "$libraries"
    printf 'Size: %s bytes\n' "$size"
    printf 'Status: Valid\n'

    return 0
}

# =============================================================================
# LOAD PROFILING
# =============================================================================

# Start profiling timer
# Usage: lazy_profile_start (internal)
lazy_profile_start() {
    [[ "$MAINFRAME_PROFILE_LOADS" != "1" ]] && return

    # Use EPOCHREALTIME if available (bash 5+), fallback to date
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        _LAZY_LOAD_START="$EPOCHREALTIME"
    else
        _LAZY_LOAD_START=$(date +%s%N 2>/dev/null || date +%s)
    fi
}

# End profiling timer and record
# Usage: lazy_profile_end "library_name" (internal)
lazy_profile_end() {
    local library="$1"
    [[ "$MAINFRAME_PROFILE_LOADS" != "1" ]] && return
    [[ -z "$_LAZY_LOAD_START" ]] && return

    local end_time duration_ms

    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        end_time="$EPOCHREALTIME"
        # Calculate duration in milliseconds using bash arithmetic
        # EPOCHREALTIME is seconds.microseconds
        duration_ms=$(awk "BEGIN {printf \"%.2f\", ($end_time - $_LAZY_LOAD_START) * 1000}")
    else
        end_time=$(date +%s%N 2>/dev/null || date +%s)
        # Nanoseconds to milliseconds
        if [[ ${#end_time} -gt 10 ]]; then
            duration_ms=$(( (end_time - _LAZY_LOAD_START) / 1000000 ))
        else
            # Fallback for systems without nanosecond precision
            duration_ms=$(( (end_time - _LAZY_LOAD_START) * 1000 ))
        fi
    fi

    _LAZY_LOAD_TIMES["$library"]="$duration_ms"
    _LAZY_LOAD_START=""
}

# Generate load profile report
# Usage: lazy_profile_report
lazy_profile_report() {
    printf '=== MAINFRAME Load Profile ===\n'

    if [[ ${#_LAZY_LOAD_TIMES[@]} -eq 0 ]]; then
        printf '  No load times recorded.\n'
        printf '  Set MAINFRAME_PROFILE_LOADS=1 to enable profiling.\n'
        return
    fi

    local total=0
    local lib

    # Sort by load time (descending)
    for lib in $(
        for k in "${!_LAZY_LOAD_TIMES[@]}"; do
            printf '%s %s\n' "${_LAZY_LOAD_TIMES[$k]}" "$k"
        done | sort -rn | awk '{print $2}'
    ); do
        local time="${_LAZY_LOAD_TIMES[$lib]}"
        printf '  %-25s %8s ms\n' "$lib" "$time"
        # Accumulate total (handle decimals)
        total=$(awk "BEGIN {printf \"%.2f\", $total + $time}")
    done

    printf '  %-25s %8s ms\n' "TOTAL" "$total"
    printf '\n'
    printf 'Libraries loaded: %d\n' "${#_LAZY_LOAD_TIMES[@]}"
}

# Clear profiling data
# Usage: lazy_profile_clear
lazy_profile_clear() {
    _LAZY_LOAD_TIMES=()
    _LAZY_LOAD_START=""
}

# Get load time for a specific library
# Usage: time=$(lazy_load_time "datetime")
lazy_load_time() {
    local library="$1"
    printf '%s\n' "${_LAZY_LOAD_TIMES[$library]:-0}"
}

# =============================================================================
# MEMORY-EFFICIENT LOADING
# =============================================================================

# Unload a library to free memory (replaces functions with stubs)
# Usage: lazy_unload "datetime"
lazy_unload() {
    local library="$1"

    # Check if loaded
    if [[ -z "${_LAZY_LOADED_LIBS[$library]:-}" ]]; then
        return 0  # Not loaded, nothing to do
    fi

    # Get functions from manifest and replace with stubs
    local fn
    for fn in "${!_LAZY_MANIFEST[@]}"; do
        if [[ "${_LAZY_MANIFEST[$fn]}" == "$library" ]]; then
            # Only stub if function exists
            if declare -F "$fn" &>/dev/null; then
                lazy_stub "$fn" "$library"
            fi
        fi
    done

    # Clear loaded flag
    unset '_LAZY_LOADED_LIBS[$library]'

    # Clear any library-specific loaded marker
    local flag_var="_MAINFRAME_${library^^}_LOADED"
    flag_var="${flag_var//-/_}"  # Replace hyphens with underscores
    unset "$flag_var" 2>/dev/null || true
}

# Reload a library (unload then load)
# Usage: lazy_reload "datetime"
lazy_reload() {
    local library="$1"
    lazy_unload "$library"
    lazy_load_library "$library"
}

# Report memory usage of loaded functions
# Usage: lazy_memory_report
lazy_memory_report() {
    local total=0
    local count=0

    printf '=== Function Memory Usage ===\n'

    # Get function definitions and their sizes
    local fn size
    while read -r fn; do
        size=$(declare -f "$fn" 2>/dev/null | wc -c)
        if ((size > 0)); then
            ((total += size))
            ((count++))
        fi
    done < <(declare -F | awk '{print $3}')

    printf 'Total functions: %d\n' "$count"
    printf 'Total definition size: %d bytes (%.2f KB)\n' "$total" "$(awk "BEGIN {printf \"%.2f\", $total / 1024}")"

    # Show loaded libraries
    printf '\nLoaded libraries: %d\n' "${#_LAZY_LOADED_LIBS[@]}"
    for lib in "${!_LAZY_LOADED_LIBS[@]}"; do
        printf '  - %s\n' "$lib"
    done

    # Show stub count
    printf '\nActive stubs: %d\n' "${#_LAZY_STUBS[@]}"
}

# Get estimated memory usage in bytes
# Usage: bytes=$(lazy_memory_usage)
lazy_memory_usage() {
    local total=0
    local fn

    while read -r fn; do
        local size
        size=$(declare -f "$fn" 2>/dev/null | wc -c)
        ((total += size))
    done < <(declare -F | awk '{print $3}')

    printf '%d\n' "$total"
}

# =============================================================================
# STANDARD LIBRARY MANIFESTS
# =============================================================================

# Initialize manifests for all standard libraries
# This registers which functions belong to which libraries
# Usage: lazy_init_manifests
lazy_init_manifests() {
    # DateTime functions
    lazy_register "datetime" \
        now now_ms now_iso now_rfc2822 \
        parse_iso parse_date parse_datetime \
        format_epoch format_iso format_date format_time format_datetime format_relative \
        date_add date_subtract date_diff date_diff_human \
        year month day hour minute second day_of_week day_of_year week_of_year \
        is_leap_year is_before is_after is_same_day is_weekend is_weekday \
        start_of_day end_of_day start_of_month end_of_month start_of_year end_of_year \
        days_in_month make_datetime tz_offset tz_name is_dst

    # HTTP functions
    lazy_register "http" \
        http_request http_get http_post http_put http_delete http_head http_patch \
        http_header http_auth_basic http_auth_bearer \
        url_parse url_encode url_decode query_string \
        http_status http_body http_header_get http_headers \
        http_json_get http_json_post http_json_put http_json_patch \
        http_is_success http_is_redirect http_is_client_error http_is_server_error \
        http_set_timeout http_download \
        http_parse_cookie http_cookie \
        http_debug_request http_debug_response

    # CSV functions
    lazy_register "csv" \
        csv_parse_line csv_parse_multiline csv_parse_file csv_field csv_field_count \
        csv_read csv_get csv_column csv_column_index \
        csv_escape csv_row csv_header csv_write csv_append_row \
        csv_filter csv_sort csv_sort_num csv_select csv_to_json csv_from_json \
        csv_row_count csv_has_header csv_validate csv_row_assoc csv_each csv_map csv_reduce \
        csv_sum csv_count csv_group_count csv_join csv_print \
        csv_delimiter csv_quote

    # Git functions
    lazy_register "git" \
        git_is_repo git_root git_branch git_branches git_remote_branches git_default_branch \
        git_is_dirty git_is_clean git_has_staged git_has_unstaged git_has_untracked \
        git_status_short git_files_changed \
        git_commit_hash git_commit_hash_full git_commit_message git_commit_author \
        git_commit_date git_commit_count git_commits_ahead git_commits_behind \
        git_tag_latest git_tags git_tag_exists git_describe \
        git_remote_url git_remote_name git_has_remote git_is_pushed \
        git_user_name git_user_email git_ignore_check git_file_history git_blame_line \
        git_diff_files git_diff_stat git_merge_base \
        git_summary git_log_oneline git_changed_since \
        git_has_stash git_stash_count git_is_worktree git_worktrees \
        git_has_submodules git_submodules \
        git_tracking_branch git_has_upstream git_ahead_behind \
        git_config_get git_config_exists git_version

    # Crypto functions
    lazy_register "crypto" \
        base64_encode base64_decode base64_encode_file base64_decode_file \
        hex_encode hex_decode bytes_to_hex \
        md5 md5_file sha1 sha1_file sha256 sha256_file sha512 sha512_file \
        hmac_sha256 hmac_sha1 \
        random_bytes random_hex random_base64 random_token secure_random \
        checksum checksum_verify crc32 \
        password_hash password_verify generate_password \
        rot13 xor_encrypt xor_decrypt \
        crypto_check constant_time_compare

    # Validation functions
    lazy_register "validation" \
        validate_int validate_float validate_bool validate_uuid validate_hex \
        validate_email validate_url validate_domain validate_ipv4 validate_ipv6 \
        validate_date validate_time validate_semver \
        validate_path validate_path_safe validate_filename validate_path_chars \
        sanitize_shell_arg sanitize_filename sanitize_sql sanitize_html sanitize_json \
        validate_regex validate_length validate_enum validate_all \
        validate_command_safe build_safe_command \
        validate_port validate_mac validate_credit_card validate_phone \
        validate_json validate_alnum validate_slug validate_cidr validate_base64

    # Path functions
    lazy_register "path" \
        path_normalize path_absolute path_relative \
        path_dir path_base path_ext path_ext_full path_stem path_stem_full \
        path_join path_replace_ext path_add_suffix \
        path_to_unix path_to_windows path_style \
        path_quote path_is_safe path_ensure_dir path_sanitize \
        path_expand_tilde path_common_prefix \
        path_is_absolute path_is_relative path_has_parent_ref path_is_hidden \
        path_equals path_depth path_split \
        path_unique path_resolve

    # Environment functions
    lazy_register "env" \
        env_detect_shell env_config_file \
        env_set env_persist env_get env_unset env_remove_persist \
        env_path_prepend env_path_append env_path_remove env_path_list env_path_has \
        env_path_persist_prepend env_path_persist_append env_path_clean \
        env_load_dotenv env_save_dotenv \
        env_is_set env_is_nonempty env_require env_require_all \
        env_list env_export_from env_with env_copy env_swap \
        env_get_int env_get_bool env_get_array env_set_array \
        env_debug env_diff env_expand env_summary env_backup env_restore

    # Docker functions
    lazy_register "docker" \
        docker_running docker_version \
        docker_container_exists docker_container_running docker_container_status \
        docker_container_id docker_container_id_short \
        docker_container_start docker_container_stop docker_container_restart docker_container_remove \
        docker_containers_running docker_containers_all \
        docker_exec docker_exec_it docker_logs docker_logs_follow \
        docker_stats_json docker_cpu docker_memory docker_memory_percent \
        docker_container_ip docker_container_ports docker_container_env docker_container_labels docker_container_image \
        docker_image_exists docker_image_id docker_image_size docker_image_size_human \
        docker_image_pull docker_image_remove docker_images \
        docker_port_used docker_port_container \
        compose_running compose_status compose_exec compose_up compose_down compose_logs compose_services \
        docker_volume_exists docker_volume_create docker_volume_remove docker_volumes \
        docker_network_exists docker_network_create docker_network_remove docker_networks \
        docker_prune_containers docker_prune_images docker_prune_volumes docker_prune_all

    # Process functions
    lazy_register "proc" \
        proc_exists proc_name proc_cmd proc_parent proc_children proc_tree \
        proc_user proc_start_time proc_runtime \
        proc_memory proc_memory_percent proc_cpu proc_threads proc_open_files \
        proc_find_by_name proc_find_by_port proc_find_by_user proc_find_by_cmd \
        pidfile_create pidfile_read pidfile_check pidfile_remove pidfile_kill \
        lockfile_acquire lockfile_release lockfile_check with_lock \
        proc_signal proc_kill proc_kill_force proc_kill_tree \
        proc_wait proc_wait_timeout proc_wait_start \
        proc_count proc_load proc_uptime proc_uptime_human
}

# Initialize all standard library stubs (for lazy loading mode)
# Usage: lazy_init_stubs
lazy_init_stubs() {
    # First, initialize manifests
    lazy_init_manifests

    # Then create stubs for all registered functions
    local fn lib
    for fn in "${!_LAZY_MANIFEST[@]}"; do
        lib="${_LAZY_MANIFEST[$fn]}"
        lazy_stub "$fn" "$lib"
    done
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Initialize lazy loading system
# Usage: lazy_init [mode]
# Modes: "stubs" (create stubs), "manifests" (register only), "full" (load all)
lazy_init() {
    local mode="${1:-manifests}"

    case "$mode" in
        stubs)
            lazy_init_stubs
            ;;
        manifests)
            lazy_init_manifests
            ;;
        full)
            lazy_init_manifests
            # Load all registered libraries
            local lib
            for lib in $(printf '%s\n' "${_LAZY_MANIFEST[@]}" | sort -u); do
                lazy_load_library "$lib"
            done
            ;;
        *)
            printf 'Unknown mode: %s\n' "$mode" >&2
            return 1
            ;;
    esac
}

# Status report
# Usage: lazy_status
lazy_status() {
    printf '=== MAINFRAME Lazy Loading Status ===\n'
    printf 'Lazy loading enabled: %s\n' "$MAINFRAME_LAZY"
    printf 'Profiling enabled: %s\n' "$MAINFRAME_PROFILE_LOADS"
    printf 'Bundle: %s\n' "${MAINFRAME_BUNDLE:-none}"
    printf '\n'
    printf 'Registered functions: %d\n' "${#_LAZY_MANIFEST[@]}"
    printf 'Active stubs: %d\n' "${#_LAZY_STUBS[@]}"
    printf 'Loaded libraries: %d\n' "${#_LAZY_LOADED_LIBS[@]}"

    if [[ ${#_LAZY_LOADED_LIBS[@]} -gt 0 ]]; then
        printf '\nLoaded:\n'
        for lib in "${!_LAZY_LOADED_LIBS[@]}"; do
            printf '  - %s\n' "$lib"
        done
    fi

    if [[ ${#_LAZY_LOAD_TIMES[@]} -gt 0 ]]; then
        printf '\n'
        lazy_profile_report
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

LAZY_EXPORTS=(
    # Stub creation
    lazy_stub lazy_stub_library lazy_is_stub
    # Manifest management
    lazy_register lazy_library_for lazy_autoload
    lazy_list_functions lazy_functions_in
    # Library loading
    lazy_load_library lazy_is_loaded lazy_loaded_libs
    # Bundle support
    lazy_bundle_create lazy_load_smart lazy_bundle_validate
    # Profiling
    lazy_profile_start lazy_profile_end lazy_profile_report
    lazy_profile_clear lazy_load_time
    # Memory management
    lazy_unload lazy_reload lazy_memory_report lazy_memory_usage
    # Initialization
    lazy_init_manifests lazy_init_stubs lazy_init lazy_status
)
