#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/hints.sh - Function Hint Database
# =============================================================================
# Description: Suggests what function to call next based on workflow patterns.
#              Provides contextual hints for AI coding assistants and developers
#              to discover optimal function chains across MAINFRAME libraries.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_HINTS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_HINTS_LOADED=1

# =============================================================================
# HINT DATABASE
# =============================================================================

# Associative array mapping function names to suggested next functions.
# Format: FUNCTION_HINTS[function_name]="next_function_1,next_function_2,..."
declare -gA FUNCTION_HINTS

# =============================================================================
# FILE OPERATIONS
# =============================================================================

FUNCTION_HINTS[file_exists]="read_file,file_size,file_lines,require_file"
FUNCTION_HINTS[file_size]="format_bytes,file_lines,read_file"
FUNCTION_HINTS[file_lines]="file_head,file_tail,file_range"
FUNCTION_HINTS[read_file]="trim_string,split_string,json_get"
FUNCTION_HINTS[read_file_lines]="array_length,array_filter,fp_map"
FUNCTION_HINTS[file_head]="trim_string,split_string,file_tail"
FUNCTION_HINTS[file_tail]="trim_string,split_string,file_head"
FUNCTION_HINTS[file_range]="trim_string,array_join,file_lines"
FUNCTION_HINTS[file_line]="trim_string,split_string"
FUNCTION_HINTS[file_ext]="path_replace_ext,to_lower"
FUNCTION_HINTS[file_name]="path_join,file_ext"
FUNCTION_HINTS[write_file]="file_exists,read_file,file_checkpoint"
FUNCTION_HINTS[temp_file]="write_file,read_file,on_exit"
FUNCTION_HINTS[temp_dir]="ensure_dir,on_exit"
FUNCTION_HINTS[abs_path]="path_normalize,file_exists"
FUNCTION_HINTS[require_file]="read_file,file_lines,json_read"
FUNCTION_HINTS[require_dir]="ensure_dir,abs_path"

# =============================================================================
# GIT OPERATIONS
# =============================================================================

FUNCTION_HINTS[git_is_repo]="git_root,git_branch,git_summary"
FUNCTION_HINTS[git_root]="abs_path,path_join"
FUNCTION_HINTS[git_branch]="git_commit_hash,git_is_dirty,git_log_oneline"
FUNCTION_HINTS[git_branches]="array_contains,array_filter"
FUNCTION_HINTS[git_default_branch]="git_branch,git_commits_ahead"
FUNCTION_HINTS[git_is_dirty]="git_changed_files,git_status_short,git_has_staged"
FUNCTION_HINTS[git_is_clean]="git_commit_hash,git_branch"
FUNCTION_HINTS[git_has_staged]="git_commit_hash,git_diff_files"
FUNCTION_HINTS[git_has_unstaged]="git_changed_files,git_diff_stat"
FUNCTION_HINTS[git_has_untracked]="git_files_changed,git_status_short"
FUNCTION_HINTS[git_status_short]="git_is_dirty,git_changed_files"
FUNCTION_HINTS[git_files_changed]="array_length,array_contains,git_diff_files"
FUNCTION_HINTS[git_commit_hash]="git_commit_message,git_commit_author,git_log_oneline"
FUNCTION_HINTS[git_commit_hash_full]="git_commit_hash,git_describe"
FUNCTION_HINTS[git_commit_message]="trim_string,json_object"
FUNCTION_HINTS[git_commit_author]="git_commit_date,git_user_email"
FUNCTION_HINTS[git_commit_date]="format_relative,format_iso"
FUNCTION_HINTS[git_commit_count]="format_number,json_object"
FUNCTION_HINTS[git_commits_ahead]="git_commits_behind,git_is_pushed"
FUNCTION_HINTS[git_commits_behind]="git_commits_ahead,git_merge_base"
FUNCTION_HINTS[git_tag_latest]="git_tags,version_compare"
FUNCTION_HINTS[git_tags]="array_sort,git_tag_exists"
FUNCTION_HINTS[git_tag_exists]="git_describe,git_tag_latest"
FUNCTION_HINTS[git_describe]="git_tag_latest,version_compare"
FUNCTION_HINTS[git_remote_url]="url_parse,git_remote_name"
FUNCTION_HINTS[git_remote_name]="git_remote_url,git_has_remote"
FUNCTION_HINTS[git_has_remote]="git_remote_url,git_is_pushed"
FUNCTION_HINTS[git_is_pushed]="git_commits_ahead,git_remote_url"
FUNCTION_HINTS[git_user_name]="git_user_email,json_object"
FUNCTION_HINTS[git_user_email]="git_user_name,validate_email"
FUNCTION_HINTS[git_diff_files]="array_length,git_diff_stat"
FUNCTION_HINTS[git_diff_stat]="format_bytes,git_diff_files"
FUNCTION_HINTS[git_merge_base]="git_commits_ahead,git_commits_behind"
FUNCTION_HINTS[git_summary]="json_pretty,log_info"
FUNCTION_HINTS[git_log_oneline]="git_commit_hash,git_changed_since"
FUNCTION_HINTS[git_changed_since]="array_length,git_diff_files"
FUNCTION_HINTS[git_blame_line]="git_commit_author,git_commit_date"
FUNCTION_HINTS[git_file_history]="git_blame_line,git_log_oneline"

# =============================================================================
# TIME / DATETIME OPERATIONS
# =============================================================================

FUNCTION_HINTS[now]="format_iso,format_relative,date_add"
FUNCTION_HINTS[now_ms]="format_duration,date_diff"
FUNCTION_HINTS[now_iso]="date_add,parse_iso"
FUNCTION_HINTS[now_rfc2822]="parse_datetime,now_iso"
FUNCTION_HINTS[parse_iso]="date_diff,format_relative"
FUNCTION_HINTS[parse_date]="date_add,date_subtract,is_before"
FUNCTION_HINTS[parse_datetime]="date_diff,format_relative"
FUNCTION_HINTS[format_epoch]="format_relative,date_diff"
FUNCTION_HINTS[format_iso]="json_object,parse_iso"
FUNCTION_HINTS[format_date]="format_time,format_datetime"
FUNCTION_HINTS[format_time]="format_date,format_datetime"
FUNCTION_HINTS[format_datetime]="json_object,log_info"
FUNCTION_HINTS[format_relative]="log_info,json_object"
FUNCTION_HINTS[date_add]="format_iso,date_diff,is_before"
FUNCTION_HINTS[date_subtract]="format_iso,date_diff,is_after"
FUNCTION_HINTS[date_diff]="format_duration,date_diff_human"
FUNCTION_HINTS[date_diff_human]="log_info,json_object"
FUNCTION_HINTS[is_before]="date_diff,is_after"
FUNCTION_HINTS[is_after]="date_diff,is_before"
FUNCTION_HINTS[is_same_day]="is_weekend,is_weekday"
FUNCTION_HINTS[is_weekend]="is_weekday,day_of_week"
FUNCTION_HINTS[is_weekday]="is_weekend,day_of_week"
FUNCTION_HINTS[start_of_day]="end_of_day,date_diff"
FUNCTION_HINTS[end_of_day]="start_of_day,is_before"
FUNCTION_HINTS[start_of_month]="end_of_month,days_in_month"
FUNCTION_HINTS[end_of_month]="start_of_month,date_add"
FUNCTION_HINTS[days_in_month]="start_of_month,end_of_month"
FUNCTION_HINTS[timestamp]="log_info,json_object"
FUNCTION_HINTS[timestamp_iso]="json_object,format_relative"
FUNCTION_HINTS[epoch]="format_duration,date_diff"

# =============================================================================
# HTTP OPERATIONS
# =============================================================================

FUNCTION_HINTS[http_get]="json_get,json_pretty,log_info"
FUNCTION_HINTS[http_post]="json_get,json_object,log_info"
FUNCTION_HINTS[http_download]="file_exists,file_size,sha256"
FUNCTION_HINTS[url_parse]="http_get,validate_url"
FUNCTION_HINTS[query_string]="url_parse,http_get"
FUNCTION_HINTS[validate_url]="url_parse,http_get"

# =============================================================================
# DOCKER OPERATIONS
# =============================================================================

FUNCTION_HINTS[docker_running]="docker_containers_running,docker_version"
FUNCTION_HINTS[docker_version]="version_compare,json_get"
FUNCTION_HINTS[docker_container_exists]="docker_container_running,docker_container_status"
FUNCTION_HINTS[docker_container_running]="docker_logs,docker_exec,docker_stats_json"
FUNCTION_HINTS[docker_container_status]="docker_container_start,docker_container_restart"
FUNCTION_HINTS[docker_container_id]="docker_container_running,docker_logs"
FUNCTION_HINTS[docker_container_start]="docker_container_running,docker_logs"
FUNCTION_HINTS[docker_container_stop]="docker_container_status,docker_container_remove"
FUNCTION_HINTS[docker_container_restart]="docker_container_running,docker_logs"
FUNCTION_HINTS[docker_container_remove]="docker_container_exists,docker_prune_containers"
FUNCTION_HINTS[docker_containers_running]="array_length,docker_container_status"
FUNCTION_HINTS[docker_containers_all]="docker_containers_running,docker_prune_containers"
FUNCTION_HINTS[docker_exec]="trim_string,json_get,log_info"
FUNCTION_HINTS[docker_logs]="trim_string,file_tail,log_info"
FUNCTION_HINTS[docker_stats_json]="json_get,docker_cpu,docker_memory"
FUNCTION_HINTS[docker_cpu]="format_percent,json_object"
FUNCTION_HINTS[docker_memory]="format_bytes,docker_memory_percent"
FUNCTION_HINTS[docker_memory_percent]="format_percent,log_warn"
FUNCTION_HINTS[docker_container_ip]="port_check,http_get"
FUNCTION_HINTS[docker_container_ports]="port_check,docker_port_used"
FUNCTION_HINTS[docker_container_env]="json_object,env_get"
FUNCTION_HINTS[docker_container_image]="docker_image_exists,docker_image_size"
FUNCTION_HINTS[docker_image_exists]="docker_image_pull,docker_image_size"
FUNCTION_HINTS[docker_image_size]="format_bytes,docker_image_size_human"
FUNCTION_HINTS[docker_image_size_human]="log_info,json_object"
FUNCTION_HINTS[docker_image_pull]="docker_image_exists,docker_container_start"
FUNCTION_HINTS[docker_port_used]="docker_port_container,port_check"
FUNCTION_HINTS[docker_port_container]="docker_container_running,docker_logs"
FUNCTION_HINTS[compose_running]="compose_status,compose_logs"
FUNCTION_HINTS[compose_status]="compose_up,compose_down"
FUNCTION_HINTS[compose_exec]="trim_string,log_info"
FUNCTION_HINTS[compose_up]="compose_running,compose_logs"
FUNCTION_HINTS[compose_down]="compose_status,docker_prune_containers"
FUNCTION_HINTS[compose_logs]="trim_string,file_tail"
FUNCTION_HINTS[compose_services]="array_contains,compose_running"
FUNCTION_HINTS[docker_volume_exists]="docker_volume_create,docker_volumes"
FUNCTION_HINTS[docker_volume_create]="docker_volume_exists,docker_container_start"
FUNCTION_HINTS[docker_network_exists]="docker_network_create,docker_networks"
FUNCTION_HINTS[docker_network_create]="docker_network_exists,docker_container_start"
FUNCTION_HINTS[docker_prune_all]="docker_running,log_info"

# =============================================================================
# JSON OPERATIONS
# =============================================================================

FUNCTION_HINTS[json_object]="json_write,json_pretty,json_merge"
FUNCTION_HINTS[json_array]="json_object,json_write,json_pretty"
FUNCTION_HINTS[json_string]="json_object,json_array"
FUNCTION_HINTS[json_number]="json_object,json_array"
FUNCTION_HINTS[json_bool]="json_object,json_array"
FUNCTION_HINTS[json_value]="json_object,json_array"
FUNCTION_HINTS[json_get]="json_object,trim_string,log_info"
FUNCTION_HINTS[json_keys]="array_contains,array_length,json_get"
FUNCTION_HINTS[json_merge]="json_write,json_pretty,json_get"
FUNCTION_HINTS[json_pretty]="json_write_pretty,log_info"
FUNCTION_HINTS[json_valid]="json_get,json_keys,log_error"
FUNCTION_HINTS[json_escape]="json_string,json_object"
FUNCTION_HINTS[json_read]="json_get,json_valid,json_keys"
FUNCTION_HINTS[json_write]="json_read,file_exists"
FUNCTION_HINTS[json_write_pretty]="json_read,file_exists"
FUNCTION_HINTS[json_from_assoc]="json_write,json_pretty"
FUNCTION_HINTS[json_nested]="json_merge,json_write"
FUNCTION_HINTS[json_array_from_lines]="json_write,json_pretty"
FUNCTION_HINTS[json_array_typed]="json_object,json_write"

# =============================================================================
# VALIDATION OPERATIONS
# =============================================================================

FUNCTION_HINTS[validate_email]="sanitize_shell_arg,log_info,json_object"
FUNCTION_HINTS[validate_url]="url_parse,http_get"
FUNCTION_HINTS[validate_int]="json_number,format_number"
FUNCTION_HINTS[validate_float]="json_number,format_percent"
FUNCTION_HINTS[validate_bool]="json_bool,env_get_bool"
FUNCTION_HINTS[validate_uuid]="log_info,json_object"
FUNCTION_HINTS[validate_ipv4]="port_check,host_alive"
FUNCTION_HINTS[validate_ipv6]="port_check,host_alive"
FUNCTION_HINTS[validate_date]="parse_date,date_add"
FUNCTION_HINTS[validate_time]="parse_datetime,format_time"
FUNCTION_HINTS[validate_semver]="version_compare,version_at_least"
FUNCTION_HINTS[validate_path_safe]="read_file,path_normalize,require_file"
FUNCTION_HINTS[validate_filename]="sanitize_filename,path_join"
FUNCTION_HINTS[validate_path_chars]="path_normalize,validate_path_safe"
FUNCTION_HINTS[validate_domain]="validate_url,http_get"
FUNCTION_HINTS[validate_port]="port_check,docker_port_used"
FUNCTION_HINTS[validate_json]="json_get,json_keys"
FUNCTION_HINTS[validate_slug]="to_lower,sanitize_filename"
FUNCTION_HINTS[validate_cidr]="validate_ipv4,scan_range"
FUNCTION_HINTS[validate_base64]="base64_decode,sha256"
FUNCTION_HINTS[validate_command_safe]="build_safe_command,sanitize_shell_arg"
FUNCTION_HINTS[validate_all]="log_info,json_object"
FUNCTION_HINTS[sanitize_shell_arg]="build_safe_command,validate_command_safe"
FUNCTION_HINTS[sanitize_filename]="path_join,validate_filename"
FUNCTION_HINTS[sanitize_sql]="log_info,json_string"
FUNCTION_HINTS[sanitize_html]="json_string,log_info"
FUNCTION_HINTS[sanitize_json]="json_valid,json_get"
FUNCTION_HINTS[build_safe_command]="sanitize_shell_arg,log_debug"

# =============================================================================
# ARRAY OPERATIONS
# =============================================================================

FUNCTION_HINTS[array_sort]="array_unique,array_join,array_reverse"
FUNCTION_HINTS[array_unique]="array_sort,array_length,array_join"
FUNCTION_HINTS[array_filter]="array_length,array_join,array_unique"
FUNCTION_HINTS[array_join]="log_info,json_array,trim_string"
FUNCTION_HINTS[array_contains]="array_filter,array_find"
FUNCTION_HINTS[array_length]="format_number,json_number,log_info"
FUNCTION_HINTS[array_first]="array_last,array_get"
FUNCTION_HINTS[array_last]="array_first,array_get"
FUNCTION_HINTS[array_get]="array_length,array_contains"
FUNCTION_HINTS[array_slice]="array_length,array_join"
FUNCTION_HINTS[array_reverse]="array_join,array_first"
FUNCTION_HINTS[array_push]="array_length,array_last"
FUNCTION_HINTS[array_pop]="array_length,array_last"
FUNCTION_HINTS[array_shift]="array_length,array_first"
FUNCTION_HINTS[array_map]="array_join,array_filter"
FUNCTION_HINTS[array_find]="array_contains,array_filter"
FUNCTION_HINTS[array_flatten]="array_unique,array_length"

# =============================================================================
# STRING OPERATIONS
# =============================================================================

FUNCTION_HINTS[trim_string]="to_lower,to_upper,split_string"
FUNCTION_HINTS[trim_left]="trim_right,trim_string"
FUNCTION_HINTS[trim_right]="trim_left,trim_string"
FUNCTION_HINTS[to_lower]="to_upper,trim_string,validate_slug"
FUNCTION_HINTS[to_upper]="to_lower,trim_string"
FUNCTION_HINTS[split_string]="array_join,array_length,array_filter"
FUNCTION_HINTS[replace_all]="trim_string,to_lower"
FUNCTION_HINTS[string_length]="trim_string,validate_length"
FUNCTION_HINTS[string_repeat]="log_info,printf"
FUNCTION_HINTS[string_reverse]="trim_string,to_lower"
FUNCTION_HINTS[starts_with]="ends_with,contains,trim_string"
FUNCTION_HINTS[ends_with]="starts_with,contains,file_ext"
FUNCTION_HINTS[contains]="starts_with,ends_with,split_string"
FUNCTION_HINTS[capitalize]="to_lower,to_upper"
FUNCTION_HINTS[camel_case]="snake_case,to_lower"
FUNCTION_HINTS[snake_case]="camel_case,to_lower"
FUNCTION_HINTS[pad_left]="pad_right,string_length"
FUNCTION_HINTS[pad_right]="pad_left,string_length"
FUNCTION_HINTS[random_string]="sha256,uuid"

# =============================================================================
# PATH OPERATIONS
# =============================================================================

FUNCTION_HINTS[path_normalize]="path_absolute,file_exists,path_is_safe"
FUNCTION_HINTS[path_absolute]="path_normalize,file_exists,require_file"
FUNCTION_HINTS[path_relative]="path_join,path_normalize"
FUNCTION_HINTS[path_join]="file_exists,path_normalize,require_file"
FUNCTION_HINTS[path_dir]="path_base,path_join,ensure_dir"
FUNCTION_HINTS[path_base]="path_ext,path_stem,file_name"
FUNCTION_HINTS[path_ext]="path_replace_ext,to_lower,file_ext"
FUNCTION_HINTS[path_ext_full]="path_replace_ext,path_stem_full"
FUNCTION_HINTS[path_stem]="path_ext,path_replace_ext"
FUNCTION_HINTS[path_stem_full]="path_ext_full,path_replace_ext"
FUNCTION_HINTS[path_replace_ext]="file_exists,path_ext"
FUNCTION_HINTS[path_add_suffix]="file_exists,path_base"
FUNCTION_HINTS[path_to_unix]="path_normalize,path_join"
FUNCTION_HINTS[path_to_windows]="path_to_unix,path_normalize"
FUNCTION_HINTS[path_quote]="sanitize_shell_arg,build_safe_command"
FUNCTION_HINTS[path_is_safe]="validate_path_safe,read_file,path_normalize"
FUNCTION_HINTS[path_ensure_dir]="ensure_dir,path_dir"
FUNCTION_HINTS[path_sanitize]="path_normalize,validate_path_chars"
FUNCTION_HINTS[path_expand_tilde]="path_normalize,path_absolute"
FUNCTION_HINTS[path_common_prefix]="path_relative,path_normalize"
FUNCTION_HINTS[path_is_absolute]="path_is_relative,path_normalize"
FUNCTION_HINTS[path_is_relative]="path_absolute,path_is_absolute"
FUNCTION_HINTS[path_has_parent_ref]="path_normalize,validate_path_safe"
FUNCTION_HINTS[path_depth]="path_split,path_normalize"
FUNCTION_HINTS[path_split]="array_length,path_join"
FUNCTION_HINTS[path_unique]="array_unique,path_normalize"
FUNCTION_HINTS[path_resolve]="path_absolute,file_exists"
FUNCTION_HINTS[path_equals]="path_normalize,path_absolute"
FUNCTION_HINTS[path_style]="path_to_unix,path_to_windows"

# =============================================================================
# CRYPTO OPERATIONS
# =============================================================================

FUNCTION_HINTS[sha256]="base64_encode,json_object,log_info"
FUNCTION_HINTS[md5]="sha256,base64_encode"
FUNCTION_HINTS[base64_encode]="base64_decode,json_string"
FUNCTION_HINTS[base64_decode]="json_get,read_file"
FUNCTION_HINTS[random_token]="sha256,json_object,log_info"
FUNCTION_HINTS[uuid]="json_object,log_info,random_token"

# =============================================================================
# CSV OPERATIONS
# =============================================================================

FUNCTION_HINTS[csv_row]="csv_parse_line,write_file"
FUNCTION_HINTS[csv_parse_line]="csv_get,array_length,array_join"
FUNCTION_HINTS[csv_get]="trim_string,json_object,validate_int"
FUNCTION_HINTS[csv_to_json]="json_pretty,json_write"
FUNCTION_HINTS[csv_headers]="csv_parse_line,array_contains"
FUNCTION_HINTS[csv_from_json]="csv_row,write_file"

# =============================================================================
# PROCESS OPERATIONS
# =============================================================================

FUNCTION_HINTS[proc_exists]="proc_name,proc_find_by_port,proc_kill"
FUNCTION_HINTS[proc_name]="proc_cmd,proc_user"
FUNCTION_HINTS[proc_cmd]="proc_name,proc_find_by_cmd"
FUNCTION_HINTS[proc_parent]="proc_children,proc_tree"
FUNCTION_HINTS[proc_children]="proc_tree,proc_kill_tree"
FUNCTION_HINTS[proc_tree]="proc_kill_tree,json_object"
FUNCTION_HINTS[proc_user]="proc_name,proc_find_by_user"
FUNCTION_HINTS[proc_start_time]="proc_runtime,format_relative"
FUNCTION_HINTS[proc_runtime]="format_duration,proc_start_time"
FUNCTION_HINTS[proc_memory]="format_bytes,proc_memory_percent"
FUNCTION_HINTS[proc_memory_percent]="format_percent,log_warn"
FUNCTION_HINTS[proc_cpu]="format_percent,log_warn"
FUNCTION_HINTS[proc_threads]="format_number,json_object"
FUNCTION_HINTS[proc_open_files]="format_number,log_warn"
FUNCTION_HINTS[proc_find_by_name]="proc_exists,proc_kill"
FUNCTION_HINTS[proc_find_by_port]="port_check,proc_kill,docker_port_used"
FUNCTION_HINTS[proc_find_by_user]="proc_find_by_name,proc_kill"
FUNCTION_HINTS[proc_find_by_cmd]="proc_exists,proc_kill"
FUNCTION_HINTS[pidfile_create]="pidfile_check,pidfile_read"
FUNCTION_HINTS[pidfile_read]="proc_exists,pidfile_check"
FUNCTION_HINTS[pidfile_check]="pidfile_kill,pidfile_remove"
FUNCTION_HINTS[pidfile_remove]="pidfile_create,log_info"
FUNCTION_HINTS[pidfile_kill]="pidfile_remove,log_info"
FUNCTION_HINTS[lockfile_acquire]="lockfile_release,with_lock"
FUNCTION_HINTS[lockfile_release]="lockfile_acquire,log_info"
FUNCTION_HINTS[lockfile_check]="lockfile_acquire,log_warn"
FUNCTION_HINTS[with_lock]="lockfile_acquire,lockfile_release"
FUNCTION_HINTS[with_timeout]="retry,log_warn,proc_wait_timeout"
FUNCTION_HINTS[proc_signal]="proc_exists,proc_kill"
FUNCTION_HINTS[proc_kill]="proc_exists,pidfile_remove"
FUNCTION_HINTS[proc_kill_force]="proc_exists,pidfile_remove"
FUNCTION_HINTS[proc_kill_tree]="proc_children,log_info"
FUNCTION_HINTS[proc_wait]="proc_exists,log_info"
FUNCTION_HINTS[proc_wait_timeout]="with_timeout,log_warn"
FUNCTION_HINTS[proc_wait_start]="proc_exists,port_check"
FUNCTION_HINTS[proc_count]="format_number,log_info"
FUNCTION_HINTS[proc_load]="format_percent,log_warn"
FUNCTION_HINTS[proc_uptime]="format_duration,proc_uptime_human"
FUNCTION_HINTS[proc_uptime_human]="log_info,json_object"

# =============================================================================
# OBSERVE OPERATIONS
# =============================================================================

FUNCTION_HINTS[trace_start]="trace_step,trace_end,observe_command"
FUNCTION_HINTS[trace_step]="trace_end,trace_start,observe_command"
FUNCTION_HINTS[trace_end]="trace_start,log_info,json_object"
FUNCTION_HINTS[observe_command]="trace_step,trace_end,log_info"
FUNCTION_HINTS[stack_trace]="log_error,trace_end,json_object"

# =============================================================================
# CONTRACT OPERATIONS
# =============================================================================

FUNCTION_HINTS[contract_require]="contract_ensure,mainframe_error,log_error"
FUNCTION_HINTS[contract_ensure]="contract_require,log_info,json_object"
FUNCTION_HINTS[contract_type_check]="contract_require,validate_int,validate_float"
FUNCTION_HINTS[mainframe_error]="log_error,trace_end,stack_trace"

# =============================================================================
# ATOMIC OPERATIONS
# =============================================================================

FUNCTION_HINTS[atomic_write]="file_checkpoint,file_exists,read_file"
FUNCTION_HINTS[atomic_replace]="file_checkpoint,atomic_write"
FUNCTION_HINTS[safe_remove]="file_exists,log_info"
FUNCTION_HINTS[file_checkpoint]="file_rollback,atomic_write"
FUNCTION_HINTS[file_rollback]="file_checkpoint,read_file,log_warn"

# =============================================================================
# IDEMPOTENT OPERATIONS
# =============================================================================

FUNCTION_HINTS[ensure_dir]="ensure_file,path_join,file_exists"
FUNCTION_HINTS[ensure_file]="ensure_dir,ensure_line,read_file"
FUNCTION_HINTS[ensure_line]="ensure_file,read_file,grep"
FUNCTION_HINTS[ensure_symlink]="ensure_dir,file_exists,path_resolve"
FUNCTION_HINTS[ensure_command]="ensure_dir,require_command,log_info"

# =============================================================================
# PERF / FEATURE GATE OPERATIONS
# =============================================================================

FUNCTION_HINTS[bash_version]="bash_version_at_least,version_compare"
FUNCTION_HINTS[bash_version_at_least]="bash_has_feature,bash_version"
FUNCTION_HINTS[bash_has_feature]="bash_version_at_least,log_info"
FUNCTION_HINTS[perf_timer_start]="perf_timer_stop,perf_benchmark"
FUNCTION_HINTS[perf_timer_stop]="format_duration,log_info,perf_timer_start"
FUNCTION_HINTS[perf_benchmark]="perf_timer_start,format_duration,json_object"

# =============================================================================
# NETSCAN OPERATIONS
# =============================================================================

FUNCTION_HINTS[port_check]="host_alive,banner_grab,proc_find_by_port"
FUNCTION_HINTS[host_alive]="port_check,scan_range"
FUNCTION_HINTS[banner_grab]="port_check,json_object"
FUNCTION_HINTS[http_headers]="json_object,http_get"
FUNCTION_HINTS[scan_range]="port_check,json_array,host_alive"

# =============================================================================
# PARSERS OPERATIONS
# =============================================================================

FUNCTION_HINTS[parse_csv_line]="csv_get,array_length"
FUNCTION_HINTS[parse_key_value]="json_object,env_set"
FUNCTION_HINTS[parse_ini]="json_object,env_load_dotenv"
FUNCTION_HINTS[parse_url]="http_get,validate_url"
FUNCTION_HINTS[parse_semver]="version_compare,validate_semver"

# =============================================================================
# ENVIRONMENT OPERATIONS
# =============================================================================

FUNCTION_HINTS[env_set]="env_get,env_persist,env_is_set"
FUNCTION_HINTS[env_get]="env_set,env_require,env_is_nonempty"
FUNCTION_HINTS[env_persist]="env_set,env_config_file"
FUNCTION_HINTS[env_unset]="env_is_set,env_remove_persist"
FUNCTION_HINTS[env_path_prepend]="env_path_has,env_path_list"
FUNCTION_HINTS[env_path_append]="env_path_has,env_path_list"
FUNCTION_HINTS[env_path_remove]="env_path_list,env_path_has"
FUNCTION_HINTS[env_path_has]="env_path_prepend,env_path_append"
FUNCTION_HINTS[env_path_list]="array_contains,env_path_clean"
FUNCTION_HINTS[env_path_clean]="env_path_list,log_info"
FUNCTION_HINTS[env_load_dotenv]="env_get,env_require_all"
FUNCTION_HINTS[env_save_dotenv]="env_load_dotenv,env_get"
FUNCTION_HINTS[env_is_set]="env_is_nonempty,env_require"
FUNCTION_HINTS[env_is_nonempty]="env_require,env_get"
FUNCTION_HINTS[env_require]="env_get,die,log_error"
FUNCTION_HINTS[env_require_all]="env_require,log_error"
FUNCTION_HINTS[env_detect_shell]="env_config_file,env_summary"
FUNCTION_HINTS[env_config_file]="env_persist,env_detect_shell"
FUNCTION_HINTS[env_with]="env_set,env_unset"
FUNCTION_HINTS[env_get_int]="validate_int,env_get"
FUNCTION_HINTS[env_get_bool]="validate_bool,env_get"
FUNCTION_HINTS[env_summary]="json_object,log_info"
FUNCTION_HINTS[env_backup]="env_restore,json_write"
FUNCTION_HINTS[env_restore]="env_backup,env_set"
FUNCTION_HINTS[env_copy]="env_set,env_get"
FUNCTION_HINTS[env_swap]="env_copy,env_set"
FUNCTION_HINTS[env_diff]="json_object,log_info"
FUNCTION_HINTS[env_list]="array_filter,json_array"

# =============================================================================
# LOGGING / OUTPUT OPERATIONS
# =============================================================================

FUNCTION_HINTS[log_info]="log_debug,success,json_object"
FUNCTION_HINTS[log_warn]="log_error,log_info"
FUNCTION_HINTS[log_error]="log_fatal,die,stack_trace"
FUNCTION_HINTS[log_fatal]="die,stack_trace"
FUNCTION_HINTS[log_debug]="log_info,trace_step"
FUNCTION_HINTS[success]="log_info,json_object"
FUNCTION_HINTS[failure]="log_error,die"
FUNCTION_HINTS[header]="subheader,log_info"
FUNCTION_HINTS[subheader]="header,log_info"
FUNCTION_HINTS[progress_bar]="log_info,format_percent"
FUNCTION_HINTS[spinner]="log_info,proc_wait"

# =============================================================================
# FORMATTING OPERATIONS
# =============================================================================

FUNCTION_HINTS[format_bytes]="file_size,json_object,log_info"
FUNCTION_HINTS[format_duration]="date_diff,proc_runtime,log_info"
FUNCTION_HINTS[format_percent]="json_object,log_info,progress_bar"
FUNCTION_HINTS[format_number]="json_number,log_info"

# =============================================================================
# FUNCTIONAL PROGRAMMING OPERATIONS
# =============================================================================

FUNCTION_HINTS[fp_map]="fp_filter,fp_reduce,array_join"
FUNCTION_HINTS[fp_filter]="fp_map,array_length,fp_reduce"
FUNCTION_HINTS[fp_reduce]="fp_map,fp_filter,json_number"
FUNCTION_HINTS[fp_find]="fp_filter,fp_any"
FUNCTION_HINTS[fp_any]="fp_all,fp_none,fp_find"
FUNCTION_HINTS[fp_all]="fp_any,fp_none"
FUNCTION_HINTS[fp_none]="fp_any,fp_all"
FUNCTION_HINTS[fp_compose]="fp_pipe,fp_apply"
FUNCTION_HINTS[fp_pipe]="fp_compose,fp_apply"
FUNCTION_HINTS[fp_partition_v]="fp_filter,fp_map"
FUNCTION_HINTS[fp_take]="fp_drop,fp_take_while"
FUNCTION_HINTS[fp_drop]="fp_take,fp_drop_while"
FUNCTION_HINTS[fp_zip]="fp_zip_with,array_join"
FUNCTION_HINTS[fp_count]="format_number,json_number"
FUNCTION_HINTS[fp_group_by]="json_object,fp_filter"

# =============================================================================
# GUARD OPERATIONS
# =============================================================================

FUNCTION_HINTS[guard_path_exists]="guard_path_safe,read_file"
FUNCTION_HINTS[guard_path_safe]="guard_path_chars,validate_path_safe"
FUNCTION_HINTS[guard_path_chars]="guard_path_safe,path_normalize"
FUNCTION_HINTS[guard_var_set]="guard_var_safe,env_require"
FUNCTION_HINTS[guard_var_safe]="guard_var_set,sanitize_shell_arg"
FUNCTION_HINTS[guard_command]="guard_commands,require_command"
FUNCTION_HINTS[guard_commands]="guard_command,require_commands"
FUNCTION_HINTS[guard_lock]="guard_unlock,guard_with_lock"
FUNCTION_HINTS[guard_unlock]="guard_lock,log_info"
FUNCTION_HINTS[guard_with_lock]="guard_lock,guard_unlock"
FUNCTION_HINTS[guard_disk_space]="format_bytes,log_warn"
FUNCTION_HINTS[guard_memory]="format_bytes,log_warn"
FUNCTION_HINTS[guard_integer]="validate_int,json_number"
FUNCTION_HINTS[guard_filename]="sanitize_filename,validate_filename"
FUNCTION_HINTS[guard_file_op]="guard_path_exists,guard_path_safe"
FUNCTION_HINTS[guard_destructive_path]="guard_path_safe,log_warn"
FUNCTION_HINTS[guard_symlink]="ensure_symlink,path_resolve"

# =============================================================================
# SAFE EXECUTION OPERATIONS
# =============================================================================

FUNCTION_HINTS[enable_strict_mode]="disable_strict_mode,log_debug"
FUNCTION_HINTS[disable_strict_mode]="enable_strict_mode,unsafe_run"
FUNCTION_HINTS[unsafe_run]="safe_exit_code,log_warn"
FUNCTION_HINTS[safe_exit_code]="log_info,retry"
FUNCTION_HINTS[safe_source]="safe_source_all,source_if_exists"
FUNCTION_HINTS[safe_source_all]="safe_source,log_info"
FUNCTION_HINTS[source_if_exists]="safe_source,file_exists"
FUNCTION_HINTS[retry_backoff]="retry_backoff_jitter,log_warn"
FUNCTION_HINTS[retry_backoff_jitter]="retry_backoff,retry_with_callback"
FUNCTION_HINTS[retry_with_callback]="retry_backoff,log_info"
FUNCTION_HINTS[run_with_timeout]="timeout_cmd,log_warn"
FUNCTION_HINTS[capture_both]="capture_stdout,capture_stderr"
FUNCTION_HINTS[capture_stdout]="capture_stderr,capture_both"
FUNCTION_HINTS[capture_stderr]="capture_stdout,capture_both"
FUNCTION_HINTS[require_var]="env_require,guard_var_set"
FUNCTION_HINTS[default]="env_get,require_var"

# =============================================================================
# PROJECT DETECTION OPERATIONS
# =============================================================================

FUNCTION_HINTS[project_detect]="project_commands,project_entry,project_deps"
FUNCTION_HINTS[project_commands]="project_detect,log_info"
FUNCTION_HINTS[project_entry]="project_detect,file_exists"
FUNCTION_HINTS[project_deps]="project_detect,json_get"

# =============================================================================
# CATEGORY INDEX
# =============================================================================

# Maps category names to function lists for mainframe_hints_for
declare -gA _HINTS_CATEGORIES

_HINTS_CATEGORIES[file]="file_exists,file_size,file_lines,read_file,read_file_lines,file_head,file_tail,file_range,file_line,file_ext,file_name,write_file,temp_file,temp_dir,abs_path,require_file,require_dir"
_HINTS_CATEGORIES[git]="git_is_repo,git_root,git_branch,git_branches,git_default_branch,git_is_dirty,git_is_clean,git_has_staged,git_has_unstaged,git_has_untracked,git_status_short,git_files_changed,git_commit_hash,git_commit_hash_full,git_commit_message,git_commit_author,git_commit_date,git_commit_count,git_commits_ahead,git_commits_behind,git_tag_latest,git_tags,git_tag_exists,git_describe,git_remote_url,git_remote_name,git_has_remote,git_is_pushed,git_user_name,git_user_email,git_diff_files,git_diff_stat,git_merge_base,git_summary,git_log_oneline,git_changed_since,git_blame_line,git_file_history"
_HINTS_CATEGORIES[time]="now,now_ms,now_iso,now_rfc2822,parse_iso,parse_date,parse_datetime,format_epoch,format_iso,format_date,format_time,format_datetime,format_relative,date_add,date_subtract,date_diff,date_diff_human,is_before,is_after,is_same_day,is_weekend,is_weekday,start_of_day,end_of_day,start_of_month,end_of_month,days_in_month,timestamp,timestamp_iso,epoch"
_HINTS_CATEGORIES[http]="http_get,http_post,http_download,url_parse,query_string,validate_url"
_HINTS_CATEGORIES[docker]="docker_running,docker_version,docker_container_exists,docker_container_running,docker_container_status,docker_container_id,docker_container_start,docker_container_stop,docker_container_restart,docker_container_remove,docker_containers_running,docker_containers_all,docker_exec,docker_logs,docker_stats_json,docker_cpu,docker_memory,docker_memory_percent,docker_container_ip,docker_container_ports,docker_container_env,docker_container_image,docker_image_exists,docker_image_size,docker_image_size_human,docker_image_pull,docker_port_used,docker_port_container,compose_running,compose_status,compose_exec,compose_up,compose_down,compose_logs,compose_services,docker_volume_exists,docker_volume_create,docker_network_exists,docker_network_create,docker_prune_all"
_HINTS_CATEGORIES[json]="json_object,json_array,json_string,json_number,json_bool,json_value,json_get,json_keys,json_merge,json_pretty,json_valid,json_escape,json_read,json_write,json_write_pretty,json_from_assoc,json_nested,json_array_from_lines,json_array_typed"
_HINTS_CATEGORIES[validation]="validate_email,validate_url,validate_int,validate_float,validate_bool,validate_uuid,validate_ipv4,validate_ipv6,validate_date,validate_time,validate_semver,validate_path_safe,validate_filename,validate_path_chars,validate_domain,validate_port,validate_json,validate_slug,validate_cidr,validate_base64,validate_command_safe,validate_all,sanitize_shell_arg,sanitize_filename,sanitize_sql,sanitize_html,sanitize_json,build_safe_command"
_HINTS_CATEGORIES[array]="array_sort,array_unique,array_filter,array_join,array_contains,array_length,array_first,array_last,array_get,array_slice,array_reverse,array_push,array_pop,array_shift,array_map,array_find,array_flatten"
_HINTS_CATEGORIES[string]="trim_string,trim_left,trim_right,to_lower,to_upper,split_string,replace_all,string_length,string_repeat,string_reverse,starts_with,ends_with,contains,capitalize,camel_case,snake_case,pad_left,pad_right,random_string"
_HINTS_CATEGORIES[path]="path_normalize,path_absolute,path_relative,path_join,path_dir,path_base,path_ext,path_ext_full,path_stem,path_stem_full,path_replace_ext,path_add_suffix,path_to_unix,path_to_windows,path_quote,path_is_safe,path_ensure_dir,path_sanitize,path_expand_tilde,path_common_prefix,path_is_absolute,path_is_relative,path_has_parent_ref,path_depth,path_split,path_unique,path_resolve,path_equals,path_style"
_HINTS_CATEGORIES[crypto]="sha256,md5,base64_encode,base64_decode,random_token,uuid"
_HINTS_CATEGORIES[csv]="csv_row,csv_parse_line,csv_get,csv_to_json,csv_headers,csv_from_json"
_HINTS_CATEGORIES[process]="proc_exists,proc_name,proc_cmd,proc_parent,proc_children,proc_tree,proc_user,proc_start_time,proc_runtime,proc_memory,proc_memory_percent,proc_cpu,proc_threads,proc_open_files,proc_find_by_name,proc_find_by_port,proc_find_by_user,proc_find_by_cmd,pidfile_create,pidfile_read,pidfile_check,pidfile_remove,pidfile_kill,lockfile_acquire,lockfile_release,lockfile_check,with_lock,with_timeout,proc_signal,proc_kill,proc_kill_force,proc_kill_tree,proc_wait,proc_wait_timeout,proc_wait_start,proc_count,proc_load,proc_uptime,proc_uptime_human"
_HINTS_CATEGORIES[observe]="trace_start,trace_step,trace_end,observe_command,stack_trace"
_HINTS_CATEGORIES[contract]="contract_require,contract_ensure,contract_type_check,mainframe_error"
_HINTS_CATEGORIES[atomic]="atomic_write,atomic_replace,safe_remove,file_checkpoint,file_rollback"
_HINTS_CATEGORIES[idempotent]="ensure_dir,ensure_file,ensure_line,ensure_symlink,ensure_command"
_HINTS_CATEGORIES[perf]="bash_version,bash_version_at_least,bash_has_feature,perf_timer_start,perf_timer_stop,perf_benchmark"
_HINTS_CATEGORIES[netscan]="port_check,host_alive,banner_grab,http_headers,scan_range"
_HINTS_CATEGORIES[parsers]="parse_csv_line,parse_key_value,parse_ini,parse_url,parse_semver"
_HINTS_CATEGORIES[env]="env_set,env_get,env_persist,env_unset,env_path_prepend,env_path_append,env_path_remove,env_path_has,env_path_list,env_path_clean,env_load_dotenv,env_save_dotenv,env_is_set,env_is_nonempty,env_require,env_require_all,env_detect_shell,env_config_file,env_with,env_get_int,env_get_bool,env_summary,env_backup,env_restore,env_copy,env_swap,env_diff,env_list"
_HINTS_CATEGORIES[logging]="log_info,log_warn,log_error,log_fatal,log_debug,success,failure,header,subheader,progress_bar,spinner"
_HINTS_CATEGORIES[format]="format_bytes,format_duration,format_percent,format_number"
_HINTS_CATEGORIES[functional]="fp_map,fp_filter,fp_reduce,fp_find,fp_any,fp_all,fp_none,fp_compose,fp_pipe,fp_partition_v,fp_take,fp_drop,fp_zip,fp_count,fp_group_by"
_HINTS_CATEGORIES[guard]="guard_path_exists,guard_path_safe,guard_path_chars,guard_var_set,guard_var_safe,guard_command,guard_commands,guard_lock,guard_unlock,guard_with_lock,guard_disk_space,guard_memory,guard_integer,guard_filename,guard_file_op,guard_destructive_path,guard_symlink"
_HINTS_CATEGORIES[safe]="enable_strict_mode,disable_strict_mode,unsafe_run,safe_exit_code,safe_source,safe_source_all,source_if_exists,retry_backoff,retry_backoff_jitter,retry_with_callback,run_with_timeout,capture_both,capture_stdout,capture_stderr,require_var,default"
_HINTS_CATEGORIES[project]="project_detect,project_commands,project_entry,project_deps"

# =============================================================================
# PUBLIC API
# =============================================================================

# Get hint for a function (returns suggested next functions)
# Usage: mainframe_hint "file_size"
# Output: format_bytes,file_lines,read_file
mainframe_hint() {
    local func="${1:-}"

    if [[ -z "$func" ]]; then
        printf 'Usage: mainframe_hint FUNCTION_NAME\n' >&2
        return 1
    fi

    local hint="${FUNCTION_HINTS[$func]:-}"
    if [[ -n "$hint" ]]; then
        printf '%s\n' "$hint"
        return 0
    fi

    # No hint found
    return 1
}

# List all hints in a category
# Usage: mainframe_hints_for "git"
# Output: git_branch -> git_commit_hash,git_is_dirty,git_log_oneline
#         git_is_dirty -> git_changed_files,git_status_short,git_has_staged
#         ...
mainframe_hints_for() {
    local category="${1:-}"

    if [[ -z "$category" ]]; then
        printf 'Usage: mainframe_hints_for CATEGORY\n' >&2
        printf 'Categories: %s\n' "$(printf '%s\n' "${!_HINTS_CATEGORIES[@]}" | sort | tr '\n' ' ')" >&2
        return 1
    fi

    local funcs="${_HINTS_CATEGORIES[$category]:-}"
    if [[ -z "$funcs" ]]; then
        printf 'Unknown category: %s\n' "$category" >&2
        printf 'Available: %s\n' "$(printf '%s\n' "${!_HINTS_CATEGORIES[@]}" | sort | tr '\n' ' ')" >&2
        return 1
    fi

    local IFS=','
    local func_list=($funcs)

    local func hint
    for func in "${func_list[@]}"; do
        hint="${FUNCTION_HINTS[$func]:-}"
        if [[ -n "$hint" ]]; then
            printf '%s -> %s\n' "$func" "$hint"
        fi
    done

    return 0
}

# Show chain of hints starting from a function
# Usage: mainframe_hints_chain "git_branch" 3
# Output: git_branch -> git_commit_hash -> git_commit_message -> trim_string
#         git_branch -> git_commit_hash -> git_commit_author -> git_commit_date
#         git_branch -> git_commit_hash -> git_log_oneline -> git_changed_since
#         git_branch -> git_is_dirty -> git_changed_files -> array_length
#         ...
mainframe_hints_chain() {
    local start_func="${1:-}"
    local max_depth="${2:-3}"

    if [[ -z "$start_func" ]]; then
        printf 'Usage: mainframe_hints_chain FUNCTION [DEPTH]\n' >&2
        return 1
    fi

    if [[ -z "${FUNCTION_HINTS[$start_func]:-}" ]]; then
        printf 'No hints found for: %s\n' "$start_func" >&2
        return 1
    fi

    # Recursive chain builder (uses depth-first traversal)
    _hints_chain_walk "$start_func" "$max_depth" "$start_func"

    return 0
}

# Internal: Recursive hint chain walker
# Args: current_func, remaining_depth, path_so_far
_hints_chain_walk() {
    local current="$1"
    local depth="$2"
    local path="$3"

    # Base case: depth exhausted or no hints
    if [[ "$depth" -le 0 ]]; then
        printf '%s\n' "$path"
        return 0
    fi

    local hints="${FUNCTION_HINTS[$current]:-}"
    if [[ -z "$hints" ]]; then
        printf '%s\n' "$path"
        return 0
    fi

    local IFS=','
    local hint_list=($hints)

    local next
    for next in "${hint_list[@]}"; do
        # Cycle detection: skip if already in path
        if [[ "$path" == *"$next"* ]]; then
            printf '%s\n' "$path"
            continue
        fi
        _hints_chain_walk "$next" $((depth - 1)) "${path} -> ${next}"
    done
}

# Get the category a function belongs to
# Usage: mainframe_hint_category "git_branch"
# Output: git
mainframe_hint_category() {
    local func="${1:-}"

    if [[ -z "$func" ]]; then
        printf 'Usage: mainframe_hint_category FUNCTION_NAME\n' >&2
        return 1
    fi

    local category funcs
    for category in "${!_HINTS_CATEGORIES[@]}"; do
        funcs="${_HINTS_CATEGORIES[$category]}"
        if [[ ",$funcs," == *",$func,"* ]]; then
            printf '%s\n' "$category"
            return 0
        fi
    done

    return 1
}

# List all available categories
# Usage: mainframe_hint_categories
mainframe_hint_categories() {
    printf '%s\n' "${!_HINTS_CATEGORIES[@]}" | tr ' ' '\n' | sort
}

# Count total number of hints in the database
# Usage: mainframe_hints_count
mainframe_hints_count() {
    printf '%d\n' "${#FUNCTION_HINTS[@]}"
}
