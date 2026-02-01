# Advanced Functions

Specialized libraries: streaming, testing, sandbox, events, state, caching, and more.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Stream Processing (streaming.sh)

Functional stream processing primitives.

### Core Streaming

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `stream_map` | `stream_map fn` | `echo -e "1\n2\n3" \| stream_map double` | `2\n4\n6` |
| `stream_filter` | `stream_filter predicate` | `echo -e "1\n2\n3\n4" \| stream_filter is_even` | `2\n4` |
| `stream_reduce` | `stream_reduce fn init` | `echo -e "1\n2\n3" \| stream_reduce sum 0` | `6` |
| `stream_take` | `stream_take n` | `stream_take 3` | First 3 lines |
| `stream_skip` | `stream_skip n` | `stream_skip 2` | Skip first 2 |
| `stream_unique` | `stream_unique` | `stream_unique` | Unique lines |
| `stream_count` | `stream_count` | `stream_count` | Line count |

### Parallel & Batch

| Function | Signature | Example |
|----------|-----------|---------|
| `stream_parallel` | `stream_parallel fn [workers]` | `cat urls.txt \| stream_parallel fetch 4` |
| `stream_batch` | `stream_batch size fn` | `cat items.txt \| stream_batch 10 process` |
| `stream_rate_limit` | `stream_rate_limit n period` | `stream_rate_limit 10 1s` |

### USOP Output

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `stream_to_usop` | `stream_to_usop` | `echo -e "a\nb" \| stream_to_usop` | JSON envelope |
| `stream_stats` | `stream_stats` | `echo -e "1\n2\n3" \| stream_stats` | `{"count":3,"sum":6,...}` |

---

## Functional Programming (functional.sh)

### Predicates

| Function | Example | Returns |
|----------|---------|---------|
| `is_even` | `is_even 4` | 0 (true) |
| `is_odd` | `is_odd 3` | 0 (true) |
| `is_positive` | `is_positive 5` | 0 (true) |
| `is_empty` | `is_empty ""` | 0 (true) |

### Transformers

| Function | Example | Output |
|----------|---------|--------|
| `double` | `double 5` | `10` |
| `square` | `square 5` | `25` |
| `increment` | `increment 5` | `6` |

### FP Operations

| Function | Signature | Example |
|----------|-----------|---------|
| `fp_map` | `fp_map "func" elem...` | `fp_map double 1 2 3` |
| `fp_filter` | `fp_filter "pred" elem...` | `fp_filter is_even 1 2 3 4` |
| `fp_reduce` | `fp_reduce "func" init elem...` | `fp_reduce sum 0 1 2 3` |
| `fp_find` | `fp_find "pred" elem...` | `fp_find is_even 1 3 5 6` |
| `fp_any` | `fp_any "pred" elem...` | `fp_any is_even 1 3 5 6` |
| `fp_all` | `fp_all "pred" elem...` | `fp_all is_positive 1 2 3` |

---

## Testing/Mocking (testing.sh)

### Mocking

| Function | Signature | Example |
|----------|-----------|---------|
| `mock_function` | `mock_function "func" "response"` | `mock_function "http_get" "data"` |
| `mock_function_restore` | `mock_function_restore "func"` | `mock_function_restore "http_get"` |
| `mock_call_count` | `mock_call_count "func"` | `mock_call_count "http_get"` |

### Assertions

| Function | Signature | Example |
|----------|-----------|---------|
| `assert_equals` | `assert_equals "exp" "got"` | `assert_equals "5" "$x"` |
| `assert_contains` | `assert_contains "hay" "needle"` | `assert_contains "$out" "OK"` |
| `assert_empty` | `assert_empty "val"` | `assert_empty "$err"` |
| `assert_exit_code` | `assert_exit_code exp cmd...` | `assert_exit_code 0 true` |
| `assert_file_exists` | `assert_file_exists "path"` | `assert_file_exists "$f"` |

### Fixtures

| Function | Signature | Example |
|----------|-----------|---------|
| `fixture_tempdir` | `fixture_tempdir ["name"]` | `d=$(fixture_tempdir "test")` |
| `fixture_tempfile` | `fixture_tempfile ["name"] ["content"]` | `f=$(fixture_tempfile "cfg" "{}")` |
| `fixture_cleanup` | `fixture_cleanup` | `fixture_cleanup` |

---

## Task Graphs (taskgraph.sh)

Declarative task DAG with dependency resolution.

| Function | Signature | Example |
|----------|-----------|---------|
| `task_define` | `task_define "name" "cmd" ["deps"]` | `task_define "build" "./build.sh" "lint test"` |
| `task_run` | `task_run "name"` | `task_run "build"` |
| `task_run_graph` | `task_run_graph ["root"]` | `task_run_graph "deploy"` |
| `task_status` | `task_status` | Show all task statuses |
| `task_graph` | `task_graph` | Show dependency graph |

---

## Execution Sandboxing (sandbox.sh)

Filesystem restriction layer for autonomous agent execution.

| Function | Signature | Example |
|----------|-----------|---------|
| `sandbox_enable` | `sandbox_enable` | Enable sandbox |
| `sandbox_allow_write` | `sandbox_allow_write "path"` | `sandbox_allow_write "$PWD"` |
| `sandbox_deny_write` | `sandbox_deny_write "path"` | `sandbox_deny_write "/etc"` |
| `sandbox_exec` | `sandbox_exec cmd [args]` | `sandbox_exec rm -rf "$dir"` |
| `sandbox_write` | `sandbox_write "path" "content"` | `sandbox_write "$f" "data"` |

---

## State Persistence (state.sh)

Key-value state management with checkpointing.

| Function | Signature | Example |
|----------|-----------|---------|
| `state_init` | `state_init "/path"` | `state_init "/tmp/my_state"` |
| `state_set` | `state_set "key" "value"` | `state_set "step" "3"` |
| `state_get` | `state_get "key" [--default val]` | `state_get "step" --default "1"` |
| `state_checkpoint` | `state_checkpoint ["label"]` | `state_checkpoint "pre_deploy"` |
| `state_rollback` | `state_rollback ["label"]` | `state_rollback "pre_deploy"` |

---

## Event/Hook System (events.sh)

Pub/sub events and synchronous hooks.

### Hooks (Synchronous)

| Function | Signature | Example |
|----------|-----------|---------|
| `hook_on` | `hook_on "name" "callback"` | `hook_on "pre_deploy" "my_fn"` |
| `hook_trigger` | `hook_trigger "name" [args...]` | `hook_trigger "pre_deploy" "$ver"` |

### Events (Async)

| Function | Signature | Example |
|----------|-----------|---------|
| `event_on` | `event_on "event" "callback"` | `event_on "file_changed" "reload"` |
| `event_emit` | `event_emit "event" [args...]` | `event_emit "file_changed" "$f"` |
| `event_once` | `event_once "event" "callback"` | `event_once "ready" "init"` |

---

## Caching & Memoization (cache.sh)

High-performance caching with function memoization.

| Function | Signature | Example |
|----------|-----------|---------|
| `memoize` | `memoize [--ttl SECS] fn [args]` | `memoize --ttl 300 http_get "url"` |
| `memoize_clear` | `memoize_clear [pattern]` | `memoize_clear "http_get"` |
| `cas_store` | `cas_store "content"` | `hash=$(cas_store "data")` |
| `cas_get` | `cas_get "hash"` | `content=$(cas_get "$hash")` |
| `session_cache_set` | `session_cache_set key value` | `session_cache_set "user" "Gordon"` |
| `session_cache_get` | `session_cache_get key [default]` | `session_cache_get "user"` |
| `cache_stats` | `cache_stats [--json]` | `cache_stats --json` |

---

## Runtime Introspection (introspect.sh)

Self-discovery API for AI agents.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `mainframe_describe` | `mainframe_describe "func"` | `mainframe_describe "json_object"` | Function metadata JSON |
| `mainframe_capabilities` | `mainframe_capabilities ["cat"]` | `mainframe_capabilities "json"` | List functions by category |
| `mainframe_search` | `mainframe_search "pattern"` | `mainframe_search "array"` | Search functions |
| `mainframe_version` | `mainframe_version` | `mainframe_version` | MAINFRAME version |

---

## System Information (sysinfo.sh)

Cross-platform system information.

| Function | Example | Output |
|----------|---------|--------|
| `cpu_count` | `cpu_count` | `8` |
| `memory_total` | `memory_total` | `17179869184` (bytes) |
| `memory_available` | `memory_available` | `8589934592` |
| `disk_usage` | `disk_usage "/"` | JSON stats |
| `os_name` | `os_name` | `linux` or `darwin` |
| `is_root` | `is_root` | (returns 0/1) |
| `is_container` | `is_container` | (returns 0/1) |
| `system_info` | `system_info` | Full JSON summary |

---

## Cloud Extensions (lib/ext/)

Optional wrappers for cloud CLI tools. Load explicitly:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/ext/aws.sh"
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/ext/gcp.sh"
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/ext/k8s.sh"
```

### AWS

| Function | Example |
|----------|---------|
| `aws_available` | Check if AWS CLI is configured |
| `aws_s3_list` | List S3 buckets |
| `aws_ec2_list` | List EC2 instances |
| `aws_lambda_invoke` | Invoke Lambda function |

### GCP

| Function | Example |
|----------|---------|
| `gcp_available` | Check if gcloud is configured |
| `gcp_gcs_list` | List GCS buckets |
| `gcp_compute_list` | List compute instances |

### Kubernetes

| Function | Example |
|----------|---------|
| `k8s_available` | Check if kubectl is configured |
| `k8s_pods` | List pods |
| `k8s_scale` | Scale deployment |
| `k8s_restart` | Restart deployment |

---

## BSD/GNU Compatibility (compat.sh)

Cross-platform compatibility wrappers.

| Function | Purpose |
|----------|---------|
| `is_mac` | Check if running on macOS |
| `psed` | Portable sed (uses gsed on Mac) |
| `pawk` | Portable awk (uses gawk on Mac) |
| `pgrep` | Portable grep (uses ggrep on Mac) |
| `pfind` | Portable find (uses gfind on Mac) |
| `pdate` | Portable date (uses gdate on Mac) |
| `pstat_size` | Get file size (portable) |
| `preadlink_f` | Canonical path (portable) |
