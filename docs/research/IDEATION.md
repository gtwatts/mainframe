# MAINFRAME Expansion Ideation Document

**Version**: 1.0.0
**Date**: 2026-01-17
**Status**: Draft Proposals

---

## Executive Summary

This document explores expansion opportunities for MAINFRAME, a pure Bash function library designed to give AI coding assistants superpowers. With 17 libraries and 500+ functions already implemented, we identify 15+ new capability areas that would enhance MAINFRAME's value for AI-assisted development workflows.

Each proposal is evaluated on:
- **AI Assistant Value**: How much it helps AI coding assistants write cleaner, faster bash
- **Implementation Complexity**: Low/Medium/High based on pure bash feasibility
- **Priority Score**: 1-10 (10 = highest priority)

---

## Table of Contents

1. [Testing & Assertions](#1-testing--assertions)
2. [Environment Management](#2-environment-management)
3. [Container Helpers](#3-container-helpers)
4. [Cloud CLI Wrappers](#4-cloud-cli-wrappers)
5. [Database Helpers](#5-database-helpers)
6. [YAML Processing](#6-yaml-processing)
7. [XML Helpers](#7-xml-helpers)
8. [Markdown Processing](#8-markdown-processing)
9. [Log Analysis](#9-log-analysis)
10. [Network Diagnostics](#10-network-diagnostics)
11. [SSH Helpers](#11-ssh-helpers)
12. [AI-Specific Utilities](#12-ai-specific-utilities)
13. [Rate Limiting](#13-rate-limiting)
14. [Template Engine](#14-template-engine)
15. [State Machine](#15-state-machine)
16. [Validation Library](#16-validation-library)
17. [Diff & Patch](#17-diff--patch)

---

## 1. Testing & Assertions

**Library Name**: `test.sh`

**Why It Matters for AI Assistants**:
AI assistants frequently generate test scripts but write verbose assertion code. A testing library enables one-liner assertions, making test generation more reliable and readable. Critical for agentic coding where AI needs to verify its own work.

**Key Function Signatures**:
```bash
assert_eq "actual" "expected" ["message"]     # Assert equality
assert_ne "actual" "expected" ["message"]     # Assert not equal
assert_gt value1 value2 ["message"]           # Assert greater than
assert_lt value1 value2 ["message"]           # Assert less than
assert_contains "haystack" "needle"           # Assert substring exists
assert_matches "string" "regex"               # Assert regex match
assert_file_exists "/path/to/file"            # Assert file exists
assert_dir_exists "/path/to/dir"              # Assert directory exists
assert_exit_code command expected_code        # Assert command exit code
assert_output_contains command "expected"     # Assert command output

test_run "Test Name" test_function            # Run a test with name
test_skip "reason"                            # Skip current test
test_todo "description"                       # Mark test as TODO
test_suite "Suite Name" tests...              # Group tests into suite

mock_command "name" "output"                  # Create mock command
mock_env "VAR" "value"                        # Mock environment variable
restore_mocks                                 # Restore original state

test_report                                   # Print test summary
test_results_json                             # Export results as JSON
```

**Implementation Complexity**: Low
**Priority Score**: 9/10

---

## 2. Environment Management

**Library Name**: `env.sh`

**Why It Matters for AI Assistants**:
AI assistants constantly deal with environment variables for configuration. A clean API for env management, dotenv loading, and variable validation eliminates boilerplate and reduces errors in generated scripts.

**Key Function Signatures**:
```bash
env_load ".env"                               # Load dotenv file
env_load_if_exists ".env.local"               # Load if file exists
env_export "VAR=value"                        # Export variable safely
env_unset "VAR"                               # Unset with cleanup
env_default "VAR" "default_value"             # Set if not defined
env_require "VAR" ["error_message"]           # Require or die
env_require_all "VAR1" "VAR2" "VAR3"          # Require multiple

env_is_set "VAR"                              # Check if defined
env_is_empty "VAR"                            # Check if empty/unset
env_is_true "VAR"                             # Check if truthy (1, true, yes)
env_is_false "VAR"                            # Check if falsy

env_prefix_get "APP_"                         # Get all with prefix
env_prefix_strip "APP_" "VAR"                 # Strip prefix from name
env_to_json                                   # Export env as JSON
env_from_json '{"VAR":"value"}'               # Import from JSON

env_interpolate "Hello ${NAME}"               # Interpolate variables
env_expand_file "config.template"             # Expand template file
env_validate_format "VAR" "pattern"           # Validate value format
```

**Implementation Complexity**: Low
**Priority Score**: 9/10

---

## 3. Container Helpers

**Library Name**: `container.sh`

**Why It Matters for AI Assistants**:
Docker/Podman commands are verbose and error-prone. AI assistants often generate multi-line docker commands. Simple wrappers reduce errors and make container operations intuitive.

**Key Function Signatures**:
```bash
# Container lifecycle
container_run "image" "name" ["options"]      # Run container
container_start "name"                        # Start stopped container
container_stop "name" [timeout]               # Stop container
container_restart "name"                      # Restart container
container_remove "name" [--force]             # Remove container
container_exec "name" "command"               # Execute in container

# Container queries
container_exists "name"                       # Check if exists
container_is_running "name"                   # Check if running
container_get_id "name"                       # Get container ID
container_get_ip "name"                       # Get container IP
container_get_port "name" internal_port       # Get mapped port
container_logs "name" [--tail=100]            # Get container logs
container_stats "name"                        # Get CPU/memory stats

# Image operations
image_exists "name:tag"                       # Check if image exists
image_pull "name:tag"                         # Pull image
image_build "." "name:tag"                    # Build from Dockerfile
image_list [--filter="name"]                  # List images
image_remove "name:tag"                       # Remove image

# Docker Compose wrappers
compose_up [--detach]                         # Start all services
compose_down [--volumes]                      # Stop all services
compose_logs "service"                        # Service logs
compose_exec "service" "command"              # Exec in service
```

**Implementation Complexity**: Low (wrappers around docker/podman CLI)
**Priority Score**: 8/10

---

## 4. Cloud CLI Wrappers

**Library Name**: `cloud.sh`

**Why It Matters for AI Assistants**:
Cloud CLI commands (aws, gcloud, az) have complex syntax. Simplified wrappers let AI generate cloud operations with less context about CLI specifics.

**Key Function Signatures**:
```bash
# AWS S3 operations
s3_list "bucket" ["prefix"]                   # List objects
s3_get "bucket/key" "local_path"              # Download object
s3_put "local_path" "bucket/key"              # Upload object
s3_delete "bucket/key"                        # Delete object
s3_exists "bucket/key"                        # Check if exists
s3_presign "bucket/key" [expiry_secs]         # Generate presigned URL

# AWS EC2 operations (common ones)
ec2_list_instances ["filter"]                 # List instances
ec2_get_instance_ip "instance_id"             # Get public IP
ec2_start_instance "instance_id"              # Start instance
ec2_stop_instance "instance_id"               # Stop instance
ec2_instance_status "instance_id"             # Get status

# AWS Lambda
lambda_invoke "function_name" '{"payload"}'   # Invoke function
lambda_list                                   # List functions

# Generic cloud detection
cloud_detect_provider                         # Detect AWS/GCP/Azure
cloud_get_metadata "key"                      # Get instance metadata
cloud_get_region                              # Get current region
```

**Implementation Complexity**: Medium (requires aws/gcloud/az CLI)
**Priority Score**: 7/10

---

## 5. Database Helpers

**Library Name**: `db.sh`

**Why It Matters for AI Assistants**:
Database CLI operations are common in scripts. Wrappers for psql, mysql, redis-cli, and sqlite reduce command verbosity and standardize error handling.

**Key Function Signatures**:
```bash
# PostgreSQL helpers
pg_query "database" "SELECT * FROM users"    # Execute query
pg_query_json "database" "SELECT..."         # Query with JSON output
pg_databases                                  # List databases
pg_tables "database"                          # List tables
pg_schema "database" "table"                  # Get table schema
pg_count "database" "table"                   # Count rows
pg_dump "database" "output.sql"               # Dump database
pg_restore "database" "input.sql"             # Restore database

# MySQL helpers
mysql_query "database" "SELECT..."            # Execute query
mysql_query_json "database" "SELECT..."       # JSON output
mysql_databases                               # List databases
mysql_tables "database"                       # List tables

# SQLite helpers
sqlite_query "file.db" "SELECT..."            # Execute query
sqlite_tables "file.db"                       # List tables
sqlite_schema "file.db" "table"               # Get schema

# Redis helpers
redis_get "key"                               # Get value
redis_set "key" "value" [ttl]                 # Set value
redis_del "key"                               # Delete key
redis_exists "key"                            # Check if exists
redis_keys "pattern"                          # List keys
redis_hget "hash" "field"                     # Get hash field
redis_hset "hash" "field" "value"             # Set hash field

# Connection testing
db_test_connection "type" "host" "port"       # Test connectivity
db_wait_ready "type" "host" "port" [timeout]  # Wait for DB ready
```

**Implementation Complexity**: Medium (requires database CLIs)
**Priority Score**: 7/10

---

## 6. YAML Processing

**Library Name**: `yaml.sh`

**Why It Matters for AI Assistants**:
YAML is ubiquitous in DevOps (Kubernetes, CI/CD, configs). Pure bash YAML parsing is challenging but subset parsing (simple key-value, lists) is achievable and extremely valuable.

**Key Function Signatures**:
```bash
# Reading YAML (simple subset - no nested objects)
yaml_get "file.yaml" "key"                    # Get simple value
yaml_get_list "file.yaml" "key"               # Get list as array
yaml_get_section "file.yaml" "section"        # Get section as vars
yaml_keys "file.yaml"                         # List top-level keys

# Writing YAML
yaml_set "file.yaml" "key" "value"            # Set simple value
yaml_set_list "file.yaml" "key" val1 val2     # Set list
yaml_append_list "file.yaml" "key" "value"    # Append to list
yaml_delete "file.yaml" "key"                 # Delete key

# Validation
yaml_is_valid "file.yaml"                     # Check syntax
yaml_has_key "file.yaml" "key"                # Check key exists

# Conversion
yaml_to_json "file.yaml"                      # Convert to JSON
yaml_to_env "file.yaml" "PREFIX_"             # Export as env vars
yaml_from_env "PREFIX_" "output.yaml"         # Create from env vars

# Templates (envsubst-style)
yaml_template "template.yaml" "output.yaml"   # Variable substitution
```

**Implementation Complexity**: High (YAML spec is complex; subset implementation)
**Priority Score**: 8/10

---

## 7. XML Helpers

**Library Name**: `xml.sh`

**Why It Matters for AI Assistants**:
XML processing typically requires xmllint/xmlstarlet. Basic pure-bash XML extraction handles common cases like reading Maven POMs, HTML parsing, or config files.

**Key Function Signatures**:
```bash
# Reading XML (simple subset)
xml_get_tag "file.xml" "tagname"              # Get tag content
xml_get_attr "file.xml" "tag" "attr"          # Get attribute
xml_get_all_tags "file.xml" "tagname"         # Get all matching tags
xml_count_tags "file.xml" "tagname"           # Count tag occurrences

# Writing XML
xml_set_tag "file.xml" "tag" "value"          # Set tag content
xml_set_attr "file.xml" "tag" "attr" "value"  # Set attribute
xml_add_tag "file.xml" "parent" "child" "val" # Add child tag
xml_delete_tag "file.xml" "tagname"           # Delete tag

# Validation
xml_is_valid "file.xml"                       # Basic syntax check
xml_has_tag "file.xml" "tagname"              # Check tag exists

# Conversion
xml_to_json "file.xml"                        # Convert to JSON
xml_escape "string"                           # Escape for XML
xml_unescape "string"                         # Unescape XML entities

# HTML-specific (common use case)
html_get_title "page.html"                    # Extract <title>
html_get_meta "page.html" "name"              # Extract meta tags
html_strip_tags "html_string"                 # Remove HTML tags
```

**Implementation Complexity**: High (XML parsing is complex; subset implementation)
**Priority Score**: 5/10

---

## 8. Markdown Processing

**Library Name**: `markdown.sh`

**Why It Matters for AI Assistants**:
AI assistants frequently generate and parse markdown (README files, documentation). Simple markdown parsing and generation helps with doc automation.

**Key Function Signatures**:
```bash
# Reading Markdown
md_get_title "file.md"                        # Get first H1
md_get_headings "file.md" [level]             # Get all headings
md_get_section "file.md" "Heading"            # Get section content
md_get_code_blocks "file.md" [language]       # Extract code blocks
md_get_links "file.md"                        # Extract [text](url)
md_get_images "file.md"                       # Extract images

# Generating Markdown
md_heading level "text"                       # Create heading
md_paragraph "text"                           # Create paragraph
md_code_block "language" "code"               # Create code block
md_list "item1" "item2" "item3"               # Create bullet list
md_numbered_list "item1" "item2"              # Create numbered list
md_link "text" "url"                          # Create link
md_image "alt" "url"                          # Create image
md_table_header "col1" "col2" "col3"          # Create table header
md_table_row "val1" "val2" "val3"             # Create table row
md_blockquote "text"                          # Create blockquote

# Conversion
md_to_text "file.md"                          # Strip formatting
md_escape "text"                              # Escape special chars
```

**Implementation Complexity**: Low-Medium
**Priority Score**: 6/10

---

## 9. Log Analysis

**Library Name**: `logs.sh`

**Why It Matters for AI Assistants**:
Log analysis is a common debugging task. Functions for parsing common log formats, filtering by date/level, and extracting patterns save significant boilerplate.

**Key Function Signatures**:
```bash
# Log reading
log_tail "file.log" [lines]                   # Tail with formatting
log_head "file.log" [lines]                   # Head with formatting
log_follow "file.log"                         # Follow with colors

# Filtering
log_filter_level "file.log" "ERROR"           # Filter by level
log_filter_date "file.log" "2026-01-17"       # Filter by date
log_filter_range "file.log" "start" "end"     # Filter date range
log_filter_pattern "file.log" "regex"         # Filter by pattern
log_exclude_pattern "file.log" "regex"        # Exclude pattern

# Analysis
log_count_by_level "file.log"                 # Count per level
log_count_by_hour "file.log"                  # Count per hour
log_top_errors "file.log" [n]                 # Most common errors
log_error_rate "file.log"                     # Errors per time unit

# Parsing common formats
log_parse_apache "line"                       # Parse Apache log
log_parse_nginx "line"                        # Parse Nginx log
log_parse_syslog "line"                       # Parse syslog
log_parse_json "line"                         # Parse JSON log
log_parse_clf "line"                          # Common Log Format

# Output
log_colorize "file.log"                       # Add ANSI colors
log_to_json "file.log"                        # Convert to JSON
log_summarize "file.log"                      # Generate summary
```

**Implementation Complexity**: Medium
**Priority Score**: 7/10

---

## 10. Network Diagnostics

**Library Name**: `net.sh`

**Why It Matters for AI Assistants**:
Network debugging is common in scripts. Simple wrappers for connectivity tests, DNS lookups, and port scanning make network diagnostics accessible.

**Key Function Signatures**:
```bash
# Connectivity
net_is_online                                 # Check internet access
net_can_reach "host"                          # Check host reachable
net_ping "host" [count]                       # Ping with summary
net_traceroute "host"                         # Trace route
net_latency "host"                            # Average latency ms

# DNS
dns_resolve "hostname"                        # Get IP address
dns_reverse "ip"                              # Reverse lookup
dns_lookup "domain" "type"                    # MX, TXT, CNAME, etc.
dns_servers                                   # Get configured DNS

# Ports
port_is_open "host" "port"                    # Check port open
port_scan "host" [start] [end]                # Scan port range
port_find_available [start] [end]             # Find unused port
port_who_listens "port"                       # What's on port

# Network info
net_interfaces                                # List interfaces
net_ip_local                                  # Get local IP
net_ip_public                                 # Get public IP
net_gateway                                   # Get default gateway
net_mac "interface"                           # Get MAC address
net_is_private_ip "ip"                        # Check if RFC1918

# HTTP/HTTPS
http_status "url"                             # Get status code
http_headers "url"                            # Get response headers
http_is_up "url"                              # Check URL responds
http_response_time "url"                      # Response time ms

# SSL/TLS
ssl_cert_info "host" [port]                   # Get cert details
ssl_cert_expiry "host" [port]                 # Days until expiry
ssl_cert_is_valid "host" [port]               # Check validity
```

**Implementation Complexity**: Low-Medium
**Priority Score**: 8/10

---

## 11. SSH Helpers

**Library Name**: `ssh.sh`

**Why It Matters for AI Assistants**:
SSH operations are common but have complex syntax (port forwarding, key management). Simple wrappers reduce errors and improve readability.

**Key Function Signatures**:
```bash
# Connection
ssh_run "host" "command"                      # Run remote command
ssh_run_script "host" "script.sh"             # Run script on remote
ssh_copy_id "host"                            # Copy public key
ssh_test "host"                               # Test connection

# File transfer
ssh_upload "local" "host:remote"              # Upload file
ssh_download "host:remote" "local"            # Download file
ssh_sync_up "local_dir" "host:remote_dir"     # Rsync upload
ssh_sync_down "host:remote_dir" "local_dir"   # Rsync download

# Port forwarding
ssh_tunnel_local "host" local_port remote_port  # Local forward
ssh_tunnel_remote "host" remote_port local_port # Remote forward
ssh_tunnel_dynamic "host" "port"              # SOCKS proxy
ssh_tunnel_kill "port"                        # Kill tunnel

# Key management
ssh_keygen "name" [type]                      # Generate key pair
ssh_key_fingerprint "keyfile"                 # Get fingerprint
ssh_agent_add "keyfile"                       # Add to agent
ssh_agent_list                                # List loaded keys

# Config helpers
ssh_config_get "host" "option"                # Get config value
ssh_config_add_host "alias" "hostname"        # Add host alias
ssh_known_hosts_add "host"                    # Add to known_hosts
ssh_known_hosts_remove "host"                 # Remove from known_hosts
```

**Implementation Complexity**: Low
**Priority Score**: 7/10

---

## 12. AI-Specific Utilities

**Library Name**: `ai.sh`

**Why It Matters for AI Assistants**:
Meta-utilities specifically designed for AI coding workflows: token estimation, prompt templating, context management, and output parsing.

**Key Function Signatures**:
```bash
# Token estimation (approximate)
ai_estimate_tokens "text"                     # Estimate token count
ai_estimate_tokens_file "file"                # Estimate from file
ai_truncate_to_tokens "text" max_tokens       # Truncate to limit

# Prompt templating
ai_prompt_template "template" var1=val1       # Fill template
ai_prompt_load "template.txt"                 # Load from file
ai_prompt_from_file "file" max_lines          # Create file context

# Context management
ai_context_summarize "text" max_tokens        # Summarize to fit
ai_context_chunk "text" chunk_size            # Split into chunks
ai_context_overlap_chunk "text" size overlap  # Chunking with overlap

# Output parsing
ai_parse_code_block "response"                # Extract code block
ai_parse_json_block "response"                # Extract JSON
ai_parse_list "response"                      # Extract bullet list
ai_parse_numbered_steps "response"            # Extract steps

# Response validation
ai_is_refusal "response"                      # Detect refusal
ai_is_code_response "response"                # Has code block
ai_is_json_response "response"                # Valid JSON response

# Common patterns
ai_format_diff "before" "after"               # Format as diff
ai_format_file_context "file" [line_numbers]  # Format for context
ai_format_error "error_msg" "file" "line"     # Format error context
```

**Implementation Complexity**: Medium
**Priority Score**: 9/10

---

## 13. Rate Limiting

**Library Name**: `ratelimit.sh`

**Why It Matters for AI Assistants**:
API calls need rate limiting. Simple rate limiters prevent abuse and handle backpressure gracefully.

**Key Function Signatures**:
```bash
# Token bucket rate limiter
ratelimit_init "name" requests_per_second     # Initialize limiter
ratelimit_acquire "name"                      # Wait for token
ratelimit_try_acquire "name"                  # Non-blocking try
ratelimit_reset "name"                        # Reset limiter

# Sliding window rate limiter
ratelimit_window_init "name" max_requests window_secs
ratelimit_window_check "name"                 # Check if allowed
ratelimit_window_wait "name"                  # Wait if needed

# Circuit breaker
circuit_init "name" failure_threshold timeout_secs
circuit_call "name" "command"                 # Call through breaker
circuit_is_open "name"                        # Check if open
circuit_reset "name"                          # Reset breaker

# Retry with backoff (enhanced)
backoff_init "name" initial_delay max_delay   # Initialize backoff
backoff_wait "name"                           # Wait current delay
backoff_reset "name"                          # Reset delay
backoff_with_jitter "name"                    # Add random jitter

# Concurrency limiting
semaphore_init "name" max_concurrent          # Initialize semaphore
semaphore_acquire "name"                      # Acquire slot
semaphore_release "name"                      # Release slot
semaphore_count "name"                        # Current count
```

**Implementation Complexity**: Medium
**Priority Score**: 7/10

---

## 14. Template Engine

**Library Name**: `template.sh`

**Why It Matters for AI Assistants**:
Config file generation, script templating, and output formatting require templating. A simple mustache-style engine handles common cases.

**Key Function Signatures**:
```bash
# Basic templating
template_render "template_string" var1=val1   # Render template
template_render_file "template.txt" vars...   # Render from file
template_render_stdin vars...                 # Render from stdin

# Variable syntax support
# {{variable}} - simple substitution
# {{#section}}...{{/section}} - conditional/loop
# {{^section}}...{{/section}} - inverted (if not)
# {{>partial}} - include partial template

# Template management
template_register_partial "name" "content"    # Register partial
template_load_partials "dir"                  # Load from directory
template_clear_partials                       # Clear all partials

# Helpers
template_escape "string"                      # Escape for template
template_unescape "string"                    # Unescape
template_has_variable "template" "var"        # Check if uses var
template_list_variables "template"            # List all variables

# Output formats
template_to_file "template" "output" vars...  # Render to file
template_to_stdout "template" vars...         # Render to stdout
template_validate "template"                  # Check syntax
```

**Implementation Complexity**: Medium
**Priority Score**: 6/10

---

## 15. State Machine

**Library Name**: `fsm.sh`

**Why It Matters for AI Assistants**:
Complex scripts benefit from explicit state management. State machines make script flow clearer and prevent invalid state transitions.

**Key Function Signatures**:
```bash
# State machine definition
fsm_create "name" "initial_state"             # Create FSM
fsm_add_state "name" "state"                  # Add state
fsm_add_transition "name" "from" "to" "event" # Add transition
fsm_add_action "name" "state" "on_enter|on_exit" "command"

# State operations
fsm_current "name"                            # Get current state
fsm_trigger "name" "event"                    # Trigger transition
fsm_can_trigger "name" "event"                # Check if valid
fsm_is_state "name" "state"                   # Check current state

# Introspection
fsm_list_states "name"                        # List all states
fsm_list_events "name"                        # List all events
fsm_list_transitions "name"                   # List transitions
fsm_visualize "name"                          # ASCII diagram

# Persistence
fsm_save "name" "file"                        # Save state to file
fsm_load "name" "file"                        # Load state from file
fsm_reset "name"                              # Reset to initial
fsm_destroy "name"                            # Clean up FSM
```

**Implementation Complexity**: Medium
**Priority Score**: 4/10

---

## 16. Validation Library

**Library Name**: `validate.sh`

**Why It Matters for AI Assistants**:
Input validation is critical for robust scripts. A comprehensive validation library provides declarative validation that AI can reliably generate.

**Key Function Signatures**:
```bash
# Type validation
validate_string "value"                       # Non-empty string
validate_int "value"                          # Integer
validate_float "value"                        # Float/decimal
validate_bool "value"                         # Boolean (true/false/1/0)
validate_uuid "value"                         # UUID format
validate_date "value" ["format"]              # Date format

# Format validation
validate_email "value"                        # Email address
validate_url "value"                          # URL format
validate_ip "value"                           # IPv4 address
validate_ipv6 "value"                         # IPv6 address
validate_mac "value"                          # MAC address
validate_phone "value"                        # Phone number
validate_credit_card "value"                  # Credit card (Luhn)
validate_semver "value"                       # Semantic version

# String validation
validate_length "value" min max               # Length range
validate_regex "value" "pattern"              # Regex match
validate_in "value" opt1 opt2 opt3            # In set of values
validate_not_empty "value"                    # Not empty/whitespace
validate_alphanumeric "value"                 # Only a-z, 0-9
validate_slug "value"                         # URL slug format

# File validation
validate_file_exists "path"                   # File exists
validate_dir_exists "path"                    # Directory exists
validate_readable "path"                      # Is readable
validate_writable "path"                      # Is writable
validate_executable "path"                    # Is executable
validate_extension "path" ext1 ext2           # File extension

# Composite validation
validate_all "value" rule1 rule2 rule3        # All must pass
validate_any "value" rule1 rule2 rule3        # Any must pass
validate_schema "json" "schema"               # JSON schema
```

**Implementation Complexity**: Low
**Priority Score**: 8/10

---

## 17. Diff & Patch

**Library Name**: `diff.sh`

**Why It Matters for AI Assistants**:
AI code assistants need to show changes, apply patches, and merge content. Clean diff/patch utilities support agentic workflows.

**Key Function Signatures**:
```bash
# Diff operations
diff_strings "str1" "str2"                    # Diff two strings
diff_files "file1" "file2"                    # Diff two files
diff_dirs "dir1" "dir2"                       # Diff directories
diff_json "json1" "json2"                     # Diff JSON content

# Diff output formats
diff_unified "file1" "file2"                  # Unified format
diff_context "file1" "file2"                  # Context format
diff_sidebyside "file1" "file2"               # Side-by-side
diff_color "file1" "file2"                    # Colored output

# Patch operations
patch_apply "file" "patchfile"                # Apply patch
patch_create "original" "modified"            # Create patch
patch_reverse "file" "patchfile"              # Reverse patch
patch_dry_run "file" "patchfile"              # Test patch

# Merge operations
merge_files "base" "ours" "theirs" "output"   # 3-way merge
merge_has_conflicts "file"                    # Check for conflicts
merge_resolve "file" "ours|theirs"            # Auto-resolve

# Line-level operations
line_added "diff_output"                      # Get added lines
line_removed "diff_output"                    # Get removed lines
line_changed "diff_output"                    # Get changed lines
diff_stats "file1" "file2"                    # +/- statistics
```

**Implementation Complexity**: Medium
**Priority Score**: 6/10

---

## Priority Matrix

| Priority | Library | Complexity | AI Value |
|----------|---------|------------|----------|
| 1 | test.sh | Low | Critical - AI needs to verify its work |
| 2 | env.sh | Low | Critical - Every script needs env management |
| 3 | ai.sh | Medium | Critical - Meta-utilities for AI workflows |
| 4 | validate.sh | Low | High - Input validation everywhere |
| 5 | net.sh | Low-Medium | High - Network debugging is common |
| 6 | container.sh | Low | High - Docker is ubiquitous |
| 7 | yaml.sh | High | High - DevOps depends on YAML |
| 8 | logs.sh | Medium | High - Debugging assistance |
| 9 | db.sh | Medium | Medium - Common but DB-specific |
| 10 | ssh.sh | Low | Medium - Remote operations |
| 11 | cloud.sh | Medium | Medium - Cloud-specific |
| 12 | ratelimit.sh | Medium | Medium - API protection |
| 13 | template.sh | Medium | Medium - Config generation |
| 14 | markdown.sh | Low-Medium | Medium - Doc automation |
| 15 | diff.sh | Medium | Medium - Change tracking |
| 16 | xml.sh | High | Low - XML is legacy |
| 17 | fsm.sh | Medium | Low - Niche use case |

---

## Implementation Recommendations

### Phase 1 (Quick Wins)
- `test.sh` - Low complexity, high value
- `env.sh` - Low complexity, universal need
- `validate.sh` - Low complexity, reduces errors

### Phase 2 (Core Capabilities)
- `ai.sh` - Strategic value for AI assistants
- `net.sh` - Common debugging need
- `container.sh` - Docker is everywhere

### Phase 3 (DevOps Focus)
- `yaml.sh` - High complexity but high value
- `logs.sh` - Debugging assistance
- `ssh.sh` - Remote operations

### Phase 4 (Specialization)
- `db.sh` - Database operations
- `cloud.sh` - Cloud CLI wrappers
- `ratelimit.sh` - API protection

### Future Consideration
- `template.sh` - Config generation
- `markdown.sh` - Doc automation
- `diff.sh` - Change tracking
- `xml.sh` - Legacy support
- `fsm.sh` - Niche use cases

---

## Design Principles

All new libraries MUST follow MAINFRAME's core principles:

1. **Pure Bash First**: Prefer bash built-ins over external tools
2. **Simple Function Names**: AI-memorable, intuitive naming
3. **Consistent Patterns**: Similar operations across libraries
4. **No Hidden Side Effects**: Functions are predictable
5. **Graceful Degradation**: Fall back to external tools when needed
6. **Performance Matters**: Avoid subshells where possible
7. **Comprehensive Documentation**: Every function has usage examples
8. **Battle-Tested**: Include tests with BATS

---

## Conclusion

This ideation document identifies 17 expansion opportunities for MAINFRAME, prioritized by AI assistant value and implementation complexity. The recommended Phase 1 libraries (`test.sh`, `env.sh`, `validate.sh`) provide immediate value with low implementation effort.

Each library addresses specific pain points AI coding assistants face when generating bash scripts, reducing boilerplate and improving reliability.

---

*"Mainframe can make a computer do anything short of tap dance."*

**Next Steps**:
1. Review and prioritize based on user feedback
2. Create detailed specs for Phase 1 libraries
3. Implement with comprehensive BATS tests
4. Update documentation and CHEATSHEET.md
