# Undiscovered Bash Agentic Power: Research Report

**Research Team Alpha** | **Date**: 2026-01-17
**Objective**: Discover underutilized Bash patterns that could revolutionize agentic CLI tools

---

## Executive Summary

This research reveals that Bash contains sophisticated primitives for building agent systems that most developers overlook. While the industry focuses on Python/TypeScript for AI agents, Bash offers unique advantages: zero dependencies, universal availability, native process orchestration, and real-time IPC mechanisms that can outperform higher-level language implementations for specific use cases.

**Key Finding**: The combination of coprocesses, named pipes (FIFOs), file descriptor manipulation, and signal trapping creates a powerful foundation for building lightweight, fast, and resilient agent orchestration systems directly in Bash.

**Primary Recommendation**: Develop a Bash-native agent framework that leverages these primitives, targeting Claude Code hooks and CLI automation as the primary use case.

---

## Part 1: Top 10 Undiscovered Bash Patterns

### Pattern 1: Coprocess-Based Agent Communication

**Discovery Level**: Highly Underutilized
**Use Case**: Bidirectional real-time communication between AI agents

Coprocesses (`coproc`) were introduced in Bash 4.0 but remain largely unknown. They create a subprocess with a two-way pipe, enabling bidirectional communication without temporary files.

```bash
#!/bin/bash
# Agent Communication Hub using Coprocesses

# Start an AI response processor as a coprocess
coproc AI_AGENT {
    while IFS= read -r message; do
        # Process incoming message (could call an API here)
        echo "[AGENT] Received: $message"
        echo "[AGENT] Processing..."
        # Simulate AI processing
        sleep 0.5
        echo "[RESPONSE] Analyzed: ${message^^}"
    done
}

# Send messages to the agent
echo "analyze this code for bugs" >&"${AI_AGENT[1]}"
echo "suggest improvements" >&"${AI_AGENT[1]}"

# Read responses asynchronously
while IFS= read -r -t 2 response <&"${AI_AGENT[0]}"; do
    echo "Received from agent: $response"
done

# Cleanup
kill "$AI_AGENT_PID" 2>/dev/null
```

**Why It Matters**: Unlike pipes (`|`), coprocesses allow bidirectional communication. You can write to `${COPROC[1]}` and read from `${COPROC[0]}`, enabling true request-response patterns with AI backends.

**Sources**:
- [Bash Coprocesses - Medium](https://copyconstruct.medium.com/bash-coprocess-2092a93ad912)
- [GNU Bash Reference Manual - Coprocesses](https://www.gnu.org/software/bash/manual/html_node/Coprocesses.html)

---

### Pattern 2: Named Pipes (FIFOs) for Multi-Agent Message Bus

**Discovery Level**: Known but rarely used for agent systems
**Use Case**: Pub/sub style communication between multiple agent processes

Named pipes create persistent IPC channels in the filesystem, enabling unrelated processes to communicate.

```bash
#!/bin/bash
# Multi-Agent Message Bus using FIFOs

AGENT_BUS="/tmp/agent_bus_$$"
mkfifo "$AGENT_BUS"

# Cleanup on exit
trap "rm -f $AGENT_BUS" EXIT

# Agent 1: Research Agent (runs in background)
(
    while true; do
        if read -r task < "$AGENT_BUS"; then
            [[ "$task" == "SHUTDOWN" ]] && break
            if [[ "$task" == RESEARCH:* ]]; then
                topic="${task#RESEARCH:}"
                echo "[Research Agent] Investigating: $topic"
                # Perform research...
                echo "RESULT:$topic:findings_here" > "$AGENT_BUS" &
            fi
        fi
    done
) &
RESEARCH_PID=$!

# Agent 2: Writer Agent (runs in background)
(
    while true; do
        if read -r task < "$AGENT_BUS"; then
            [[ "$task" == "SHUTDOWN" ]] && break
            if [[ "$task" == RESULT:* ]]; then
                echo "[Writer Agent] Writing report for: ${task#RESULT:}"
            fi
        fi
    done
) &
WRITER_PID=$!

# Orchestrator sends tasks
echo "RESEARCH:quantum computing" > "$AGENT_BUS"
sleep 2
echo "SHUTDOWN" > "$AGENT_BUS"
echo "SHUTDOWN" > "$AGENT_BUS"

wait $RESEARCH_PID $WRITER_PID
```

**Key Insight**: Writes under PIPE_BUF (typically 4096 bytes) are atomic, preventing message interleaving from concurrent writers.

**Sources**:
- [Using Named Pipes with Bash - Linux Journal](https://www.linuxjournal.com/content/using-named-pipes-fifos-bash)
- [Fun with Unix Named Pipes](http://hassansin.github.io/fun-with-unix-named-pipes)

---

### Pattern 3: Dynamic File Descriptor Allocation for Parallel Streams

**Discovery Level**: Expert-level, rarely documented
**Use Case**: Managing multiple concurrent data streams from different AI agents

```bash
#!/bin/bash
# Dynamic FD allocation for parallel agent streams

# Dynamically allocate file descriptors (Bash 4.1+)
exec {fd_agent1}<> <(:)  # Agent 1 stream
exec {fd_agent2}<> <(:)  # Agent 2 stream
exec {fd_agent3}<> <(:)  # Agent 3 stream

echo "Allocated FDs: Agent1=$fd_agent1, Agent2=$fd_agent2, Agent3=$fd_agent3"

# Write to specific agent streams
echo "Task for agent 1" >&$fd_agent1
echo "Task for agent 2" >&$fd_agent2
echo "Task for agent 3" >&$fd_agent3

# Read from streams (would be async in real implementation)
read -t 1 response <&$fd_agent1 && echo "Agent 1: $response"

# Close file descriptors
exec {fd_agent1}>&-
exec {fd_agent2}>&-
exec {fd_agent3}>&-
```

**Advanced Pattern - Multiplexing with select-like behavior**:
```bash
#!/bin/bash
# Poor man's select() - poll multiple FDs

poll_agents() {
    local timeout=$1
    shift
    local fds=("$@")

    for fd in "${fds[@]}"; do
        if read -t 0.1 -u "$fd" line 2>/dev/null; then
            echo "$fd:$line"
            return 0
        fi
    done
    return 1
}
```

**Sources**:
- [Bash Redirection Fun with Descriptors - Medium](https://copyconstruct.medium.com/bash-redirection-fun-with-descriptors-e799ec5a3c16)
- [Use exec {fd} for dynamic file descriptors](https://www.linuxbash.sh/post/use-exec-fdfile-to-dynamically-assign-file-descriptors)

---

### Pattern 4: Signal-Based Agent Lifecycle Management

**Discovery Level**: Underutilized for agent systems
**Use Case**: Graceful shutdown, configuration reload, and agent health monitoring

```bash
#!/bin/bash
# Agent Lifecycle Manager with Signal Handling

declare -A AGENT_PIDS
declare -A AGENT_STATUS
SHUTDOWN_REQUESTED=false

# Signal handlers
handle_shutdown() {
    echo "[Lifecycle] Shutdown requested, stopping all agents..."
    SHUTDOWN_REQUESTED=true
    for name in "${!AGENT_PIDS[@]}"; do
        kill -TERM "${AGENT_PIDS[$name]}" 2>/dev/null
        echo "[Lifecycle] Sent SIGTERM to $name (PID: ${AGENT_PIDS[$name]})"
    done
}

handle_reload() {
    echo "[Lifecycle] Reloading agent configurations..."
    for name in "${!AGENT_PIDS[@]}"; do
        kill -HUP "${AGENT_PIDS[$name]}" 2>/dev/null
    done
}

handle_status() {
    echo "[Lifecycle] Agent Status Report:"
    for name in "${!AGENT_PIDS[@]}"; do
        if kill -0 "${AGENT_PIDS[$name]}" 2>/dev/null; then
            echo "  $name: RUNNING (PID: ${AGENT_PIDS[$name]})"
        else
            echo "  $name: STOPPED"
        fi
    done
}

# Trap signals
trap handle_shutdown SIGTERM SIGINT
trap handle_reload SIGHUP
trap handle_status SIGUSR1

# Start agents
start_agent() {
    local name=$1
    local command=$2

    (
        trap 'echo "[$name] Received HUP, reloading..."' HUP
        trap 'echo "[$name] Shutting down gracefully..."; exit 0' TERM

        while true; do
            eval "$command"
            sleep 1
        done
    ) &

    AGENT_PIDS[$name]=$!
    AGENT_STATUS[$name]="running"
    echo "[Lifecycle] Started $name with PID ${AGENT_PIDS[$name]}"
}

# Example usage
start_agent "researcher" "echo 'Researching...'"
start_agent "writer" "echo 'Writing...'"

echo "Send SIGUSR1 to $$ for status, SIGHUP to reload, SIGTERM to shutdown"

# Wait for all agents
wait
```

**Sources**:
- [Signal Trapping in Bash - Medium](https://medium.com/@agarwaldaksh18/%EF%B8%8F-day-65-signal-trapping-in-bash-secure-exit-and-cleanup-dcf77fff07eb)
- [The Bash Trap Command - Linux Journal](https://www.linuxjournal.com/content/bash-trap-command)

---

### Pattern 5: Associative Arrays for Agent State Management

**Discovery Level**: Known but underutilized for complex state
**Use Case**: Maintaining agent memory, task queues, and session state

```bash
#!/bin/bash
# Agent State Machine with Associative Arrays

declare -A AGENT_MEMORY        # Key-value memory store
declare -A TASK_QUEUE          # Pending tasks by priority
declare -A CONVERSATION_HISTORY # Session memory
declare -a TASK_ORDER          # Maintain insertion order

# State persistence functions
save_state() {
    local state_file="${1:-/tmp/agent_state_$$}"
    declare -p AGENT_MEMORY TASK_QUEUE CONVERSATION_HISTORY > "$state_file"
    echo "[State] Saved to $state_file"
}

load_state() {
    local state_file="${1:-/tmp/agent_state_$$}"
    [[ -f "$state_file" ]] && source "$state_file"
    echo "[State] Loaded from $state_file"
}

# Memory operations
remember() {
    local key=$1 value=$2
    AGENT_MEMORY["$key"]="$value"
    echo "[Memory] Stored: $key"
}

recall() {
    local key=$1
    echo "${AGENT_MEMORY[$key]:-}"
}

# Task queue operations
enqueue_task() {
    local priority=$1 task=$2
    local task_id="task_$(date +%s%N)"
    TASK_QUEUE["$task_id"]="$priority:$task"
    TASK_ORDER+=("$task_id")
    echo "[Queue] Added $task_id (priority: $priority)"
}

dequeue_task() {
    local highest_priority=999
    local selected_id=""

    for id in "${TASK_ORDER[@]}"; do
        [[ -z "${TASK_QUEUE[$id]:-}" ]] && continue
        local priority="${TASK_QUEUE[$id]%%:*}"
        if (( priority < highest_priority )); then
            highest_priority=$priority
            selected_id=$id
        fi
    done

    if [[ -n "$selected_id" ]]; then
        local task="${TASK_QUEUE[$selected_id]#*:}"
        unset 'TASK_QUEUE[$selected_id]'
        echo "$task"
    fi
}

# Conversation history
add_message() {
    local role=$1 content=$2
    local timestamp=$(date +%s)
    CONVERSATION_HISTORY["${timestamp}_${role}"]="$content"
}

# Example usage
remember "user_preference" "dark_mode"
remember "last_topic" "bash scripting"
enqueue_task 1 "urgent: respond to user"
enqueue_task 3 "low: cleanup temp files"
enqueue_task 2 "medium: update index"

echo "Next task: $(dequeue_task)"
echo "User preference: $(recall user_preference)"

save_state
```

**Sources**:
- [Bash Associative Arrays - Linux Journal](https://www.linuxjournal.com/content/bash-associative-arrays)
- [Take control with associative arrays - Opensource.com](https://opensource.com/article/20/6/associative-arrays-bash)

---

### Pattern 6: Event-Driven Architecture with inotify

**Discovery Level**: Known for file watching, novel for agent triggers
**Use Case**: File-system event triggers for agent actions (hot reload, auto-run)

```bash
#!/bin/bash
# Event-Driven Agent using inotifywait

WATCH_DIR="${1:-.}"
declare -A EVENT_HANDLERS

# Register event handlers
EVENT_HANDLERS["*.md:CREATE"]="handle_new_doc"
EVENT_HANDLERS["*.md:MODIFY"]="handle_doc_change"
EVENT_HANDLERS["*.py:CLOSE_WRITE"]="handle_code_change"
EVENT_HANDLERS["config.yaml:MODIFY"]="handle_config_reload"

handle_new_doc() {
    local file=$1
    echo "[Agent] New document detected: $file"
    echo "[Agent] Scheduling indexing task..."
}

handle_doc_change() {
    local file=$1
    echo "[Agent] Document modified: $file"
    echo "[Agent] Triggering re-analysis..."
}

handle_code_change() {
    local file=$1
    echo "[Agent] Code change detected: $file"
    echo "[Agent] Running tests and linting..."
}

handle_config_reload() {
    echo "[Agent] Configuration changed, reloading..."
    # Reload configuration
}

# Main event loop
inotifywait -m -r -e create,modify,close_write,delete \
    --format '%w%f:%e' "$WATCH_DIR" 2>/dev/null | \
while IFS=: read -r filepath event; do
    filename=$(basename "$filepath")

    # Match against handlers
    for pattern in "${!EVENT_HANDLERS[@]}"; do
        file_pattern="${pattern%%:*}"
        event_pattern="${pattern##*:}"

        # Check if file matches pattern and event matches
        if [[ "$filename" == $file_pattern && "$event" == *"$event_pattern"* ]]; then
            handler="${EVENT_HANDLERS[$pattern]}"
            $handler "$filepath" &
        fi
    done
done
```

**Claude Code Integration Example**:
```bash
#!/bin/bash
# Auto-trigger Claude Code on file changes

WATCH_DIR="${1:-.}"

inotifywait -m -e close_write --format '%w%f' "$WATCH_DIR" | \
while read -r file; do
    case "$file" in
        *.test.ts|*.spec.ts)
            echo "Test file changed, running tests..."
            npm test -- --testPathPattern="$file"
            ;;
        *.ts|*.tsx)
            echo "Source changed, type-checking..."
            npx tsc --noEmit
            ;;
    esac
done
```

**Sources**:
- [Linux Filesystem Events with inotify - Linux Journal](https://www.linuxjournal.com/content/linux-filesystem-events-inotify)
- [inotifywait to trigger actions on file changes](https://www.linuxbash.sh/post/use-inotifywait-to-trigger-actions-on-file-changes)

---

### Pattern 7: Job Control for Parallel Agent Orchestration

**Discovery Level**: Underutilized for AI workloads
**Use Case**: Running multiple AI tasks concurrently with controlled parallelism

```bash
#!/bin/bash
# Parallel Agent Execution with Semaphore Pattern

MAX_PARALLEL=4
declare -a RUNNING_JOBS=()

# Semaphore implementation
wait_for_slot() {
    while (( ${#RUNNING_JOBS[@]} >= MAX_PARALLEL )); do
        # Clean up completed jobs
        local new_jobs=()
        for pid in "${RUNNING_JOBS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                new_jobs+=("$pid")
            fi
        done
        RUNNING_JOBS=("${new_jobs[@]}")

        if (( ${#RUNNING_JOBS[@]} >= MAX_PARALLEL )); then
            sleep 0.1
        fi
    done
}

run_agent_task() {
    local task=$1
    wait_for_slot

    (
        echo "[Task $$] Starting: $task"
        # Simulate AI processing
        sleep $((RANDOM % 3 + 1))
        echo "[Task $$] Completed: $task"
    ) &

    RUNNING_JOBS+=($!)
}

# Cleanup handler
cleanup() {
    echo "Cleaning up..."
    for pid in "${RUNNING_JOBS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    wait
}
trap cleanup EXIT

# Submit tasks
tasks=(
    "analyze_code:main.py"
    "review_pr:123"
    "generate_tests:utils.py"
    "optimize_query:slow_query.sql"
    "document_api:endpoints.yaml"
    "check_security:deps.lock"
)

for task in "${tasks[@]}"; do
    run_agent_task "$task"
done

# Wait for all to complete
wait
echo "All tasks completed!"
```

**Using GNU Parallel for complex orchestration**:
```bash
#!/bin/bash
# Parallel agent tasks with GNU Parallel

agent_task() {
    local task=$1
    echo "[Agent $$] Processing: $task"
    # Actual AI call would go here
    sleep $((RANDOM % 3))
    echo "[Agent $$] Done: $task"
}
export -f agent_task

# Run tasks in parallel with controlled concurrency
echo -e "task1\ntask2\ntask3\ntask4\ntask5" | \
    parallel -j 4 --progress agent_task {}
```

**Sources**:
- [Job Control in Bash](http://corysimon.github.io/articles/parallel-jobs-in-bash/)
- [Parallel processing in Bash with limited concurrency](https://medium.com/cloud-life/parallel-processing-bash-with-limited-concurrency-e5d32c70269f)

---

### Pattern 8: Process Substitution for Data Pipeline Agents

**Discovery Level**: Known but not applied to agent architectures
**Use Case**: Zero-copy data flow between agent processing stages

```bash
#!/bin/bash
# Multi-stage Agent Pipeline with Process Substitution

# Agent stages as functions
stage_extract() {
    echo "[Extract] Reading input..."
    while IFS= read -r line; do
        echo "EXTRACTED:$line"
    done
}

stage_transform() {
    echo "[Transform] Processing..." >&2
    while IFS= read -r line; do
        if [[ "$line" == EXTRACTED:* ]]; then
            data="${line#EXTRACTED:}"
            echo "TRANSFORMED:${data^^}"  # Uppercase
        fi
    done
}

stage_analyze() {
    echo "[Analyze] Analyzing..." >&2
    while IFS= read -r line; do
        if [[ "$line" == TRANSFORMED:* ]]; then
            data="${line#TRANSFORMED:}"
            echo "ANALYZED: $data (length: ${#data})"
        fi
    done
}

# Pipeline using process substitution
# Allows parallel execution and tee-ing to multiple destinations
echo -e "hello world\nfoo bar\nbash rocks" | \
    tee >(stage_extract | stage_transform | stage_analyze > results.txt) \
        >(wc -l > line_count.txt) \
    | cat > raw_input.txt

echo "Pipeline complete!"
cat results.txt
```

**Diff-like agent comparison**:
```bash
#!/bin/bash
# Compare outputs from two different AI agents

diff <(
    echo "What is 2+2?" | ./agent_gpt.sh
) <(
    echo "What is 2+2?" | ./agent_claude.sh
)
```

**Sources**:
- [Process Substitution - TLDP](https://tldp.org/LDP/abs/html/process-sub.html)
- [Process Substitution in Bash - Linux Journal](https://www.linuxjournal.com/content/shell-process-redirection)

---

### Pattern 9: flock-Based Distributed Agent Mutex

**Discovery Level**: Known for files, novel for agent coordination
**Use Case**: Preventing race conditions when multiple agents access shared resources

```bash
#!/bin/bash
# Distributed Agent Locking with flock

LOCK_DIR="/tmp/agent_locks"
mkdir -p "$LOCK_DIR"

# Critical section wrapper
with_lock() {
    local resource=$1
    shift
    local lockfile="$LOCK_DIR/${resource}.lock"

    (
        flock -x -w 30 200 || {
            echo "[Lock] Failed to acquire lock for $resource" >&2
            return 1
        }

        echo "[Lock] Acquired lock for $resource"
        "$@"
        local result=$?
        echo "[Lock] Releasing lock for $resource"
        return $result
    ) 200>"$lockfile"
}

# Non-blocking lock attempt
try_lock() {
    local resource=$1
    shift
    local lockfile="$LOCK_DIR/${resource}.lock"

    (
        flock -n 200 || {
            echo "[Lock] Resource $resource is busy" >&2
            return 1
        }
        "$@"
    ) 200>"$lockfile"
}

# Example: Only one agent can update the database at a time
update_database() {
    echo "[DB] Starting database update..."
    sleep 2  # Simulate work
    echo "[DB] Update complete"
}

# Example: Only one agent can write to log
write_log() {
    local message=$1
    echo "[$(date -Iseconds)] $message" >> /tmp/agent.log
}

# Usage
with_lock "database" update_database &
with_lock "database" update_database &  # Will wait for first one
try_lock "quick_task" echo "Got lock!" || echo "Busy, skipping"

wait
```

**Semaphore for limited concurrency**:
```bash
#!/bin/bash
# Counting semaphore with flock

SEMAPHORE_DIR="/tmp/semaphores"
MAX_WORKERS=3

acquire_semaphore() {
    local name=$1
    mkdir -p "$SEMAPHORE_DIR/$name"

    for i in $(seq 1 $MAX_WORKERS); do
        if (
            flock -n 200
            echo "Acquired slot $i"
            return 0
        ) 200>"$SEMAPHORE_DIR/$name/slot_$i" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}
```

**Sources**:
- [Lock your script against parallel execution - Bash Hackers Wiki](https://flokoe.github.io/bash-hackers-wiki/howto/mutex/)
- [Linux-Fu: Critical Sections in Bash Scripts - Hackaday](https://hackaday.com/2020/08/18/linux-fu-one-at-a-time-please-critical-sections-in-bash-scripts/)

---

### Pattern 10: DEBUG Trap for Agent Execution Tracing

**Discovery Level**: Known for debugging, novel for agent observability
**Use Case**: Building execution traces, timing, and observability for agent systems

```bash
#!/bin/bash
# Agent Execution Tracer with DEBUG Trap

# Tracing state
declare -a TRACE_LOG=()
declare -A TIMING=()
TRACE_START=$(date +%s%N)

# Enable tracing
enable_tracing() {
    set -o functrace
    trap 'trace_command "$BASH_COMMAND" "$LINENO" "${FUNCNAME[0]:-main}"' DEBUG
}

# Disable tracing
disable_tracing() {
    trap - DEBUG
}

# Trace handler
trace_command() {
    local cmd=$1 line=$2 func=$3
    local now=$(date +%s%N)
    local elapsed=$(( (now - TRACE_START) / 1000000 ))  # ms

    # Skip internal commands
    [[ "$cmd" == trace_* ]] && return
    [[ "$cmd" == "local "* ]] && return

    TRACE_LOG+=("$(printf '%6dms [%s:%d] %s' $elapsed "$func" "$line" "$cmd")")
}

# Function timing wrapper
timed() {
    local name=$1
    shift
    local start=$(date +%s%N)

    "$@"
    local result=$?

    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))
    TIMING["$name"]=$duration

    return $result
}

# Print trace report
print_trace_report() {
    echo "=== Execution Trace ==="
    printf '%s\n' "${TRACE_LOG[@]}"
    echo ""
    echo "=== Timing Summary ==="
    for name in "${!TIMING[@]}"; do
        printf '  %-30s %dms\n' "$name" "${TIMING[$name]}"
    done
}

# Example agent functions
agent_research() {
    echo "Researching topic..."
    sleep 0.5
    return 0
}

agent_analyze() {
    local data=$1
    echo "Analyzing: $data"
    sleep 0.3
    return 0
}

agent_generate() {
    echo "Generating response..."
    sleep 0.4
    return 0
}

# Main execution with tracing
enable_tracing

timed "research" agent_research
timed "analyze" agent_analyze "sample data"
timed "generate" agent_generate

disable_tracing
print_trace_report
```

**Profiling with PS4 and timestamps**:
```bash
#!/bin/bash
# Detailed execution profiling

# Set up profiling output
exec 5> >(ts '[%Y-%m-%d %H:%M:%.S]' > /tmp/agent_profile.log)
export BASH_XTRACEFD=5

# Custom trace format with file:line:function
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

set -x

# Your agent code here
echo "Agent starting..."
sleep 1
echo "Agent finished"

set +x
exec 5>&-

echo "Profile saved to /tmp/agent_profile.log"
```

**Sources**:
- [Traps, debugging, profiling - Linux Shell Tutorial](https://aaltoscicomp.github.io/linux-shell/traps-debugging-profiling/)
- [DEBUG trap and PROMPT_COMMAND in Bash](https://jichu4n.com/posts/debug-trap-and-prompt_command-in-bash/)

---

## Part 2: Five Revolutionary Agentic Use Cases

### Use Case 1: Self-Healing Claude Code Hook System

**What It Does**: A Bash-based hook system that monitors Claude Code executions, detects failures, and automatically applies fixes or escalates to human review.

```bash
#!/bin/bash
# Self-Healing Claude Code Hook
# Location: ~/.claude/hooks/self_heal.sh

FAILURE_DB="/tmp/claude_failures.db"
MAX_RETRIES=3

hook_post_tool_use() {
    local tool_name=$(jq -r '.tool' <<< "$CLAUDE_TOOL_OUTPUT")
    local exit_code=$(jq -r '.exit_code // 0' <<< "$CLAUDE_TOOL_OUTPUT")
    local output=$(jq -r '.output // ""' <<< "$CLAUDE_TOOL_OUTPUT")

    if [[ $exit_code -ne 0 ]]; then
        local failure_hash=$(echo "$tool_name:$output" | md5sum | cut -d' ' -f1)
        local retry_count=$(grep -c "$failure_hash" "$FAILURE_DB" 2>/dev/null || echo 0)

        if (( retry_count < MAX_RETRIES )); then
            echo "$failure_hash" >> "$FAILURE_DB"

            # Attempt self-healing based on error patterns
            case "$output" in
                *"Permission denied"*)
                    echo '{"action": "suggest", "message": "Try: chmod +x <file>"}'
                    ;;
                *"No such file"*)
                    echo '{"action": "suggest", "message": "File not found, check path"}'
                    ;;
                *"npm ERR!"*)
                    echo '{"action": "auto_fix", "command": "rm -rf node_modules && npm install"}'
                    ;;
                *)
                    echo '{"action": "escalate", "reason": "Unknown error pattern"}'
                    ;;
            esac
        else
            echo '{"action": "stop", "reason": "Max retries exceeded for this error"}'
        fi
    fi
}

# Parse Claude Code hook input
hook_post_tool_use
```

**Why Revolutionary**: Most AI agent systems have no self-healing capability. This pattern creates a feedback loop where common failures are automatically addressed, dramatically improving reliability.

---

### Use Case 2: Memory Persistence Layer for Stateless AI Calls

**What It Does**: Creates a file-system based "brain" for AI agents that persists between invocations, enabling context continuity.

```bash
#!/bin/bash
# Agent Memory Persistence Layer
# Enables stateless AI calls to maintain context

MEMORY_DIR="${HOME}/.agent_memory"
MEMORY_INDEX="$MEMORY_DIR/index.db"
EMBEDDINGS_CACHE="$MEMORY_DIR/embeddings"

mkdir -p "$MEMORY_DIR" "$EMBEDDINGS_CACHE"

# Initialize memory index (SQLite would be better, using flat files for demo)
init_memory() {
    [[ -f "$MEMORY_INDEX" ]] || touch "$MEMORY_INDEX"
}

# Store a memory with semantic key
remember() {
    local key=$1
    local value=$2
    local timestamp=$(date +%s)
    local memory_file="$MEMORY_DIR/mem_${timestamp}_$(echo "$key" | md5sum | cut -c1-8)"

    # Store memory content
    cat > "$memory_file" << EOF
KEY: $key
TIMESTAMP: $timestamp
VALUE: $value
EOF

    # Index for retrieval
    echo "$memory_file:$key:$timestamp" >> "$MEMORY_INDEX"
    echo "[Memory] Stored: $key"
}

# Recall by fuzzy key match
recall() {
    local query=$1
    local matches=()

    while IFS=: read -r file key timestamp; do
        if [[ "$key" == *"$query"* ]]; then
            matches+=("$file")
        fi
    done < "$MEMORY_INDEX"

    # Return most recent match
    if [[ ${#matches[@]} -gt 0 ]]; then
        local latest="${matches[-1]}"
        grep "^VALUE:" "$latest" | sed 's/^VALUE: //'
    fi
}

# Forget old memories (garbage collection)
forget_old() {
    local max_age=${1:-86400}  # Default: 1 day
    local now=$(date +%s)
    local temp_index=$(mktemp)

    while IFS=: read -r file key timestamp; do
        if (( now - timestamp < max_age )); then
            echo "$file:$key:$timestamp" >> "$temp_index"
        else
            rm -f "$file"
            echo "[Memory] Forgot: $key (age: $((now - timestamp))s)"
        fi
    done < "$MEMORY_INDEX"

    mv "$temp_index" "$MEMORY_INDEX"
}

# Get recent context for AI prompt injection
get_context() {
    local limit=${1:-5}
    local context=""

    tail -n "$limit" "$MEMORY_INDEX" | while IFS=: read -r file key timestamp; do
        [[ -f "$file" ]] && context+="- $key: $(recall "$key")\n"
    done

    echo -e "$context"
}

# Export for use in AI prompts
export_context() {
    echo "## Recent Context"
    echo "The following information was remembered from previous interactions:"
    echo ""
    get_context 10
}

# Usage
init_memory
remember "user_preference" "prefers concise responses"
remember "last_project" "building a CLI tool"
remember "coding_style" "uses TypeScript with strict mode"

echo "Recalling user preference: $(recall 'preference')"
echo ""
echo "Context for AI:"
export_context
```

**Why Revolutionary**: Most AI CLI tools are completely stateless. This pattern enables "memory" between sessions without requiring a database, using only the filesystem.

---

### Use Case 3: Agent Swarm Orchestrator

**What It Does**: Orchestrates multiple specialized AI agents working in parallel on complex tasks, with automatic load balancing and result aggregation.

```bash
#!/bin/bash
# Agent Swarm Orchestrator
# Manages multiple AI agents working on decomposed tasks

SWARM_DIR="/tmp/agent_swarm_$$"
RESULT_PIPE="$SWARM_DIR/results"
TASK_QUEUE="$SWARM_DIR/tasks"
MAX_AGENTS=4

mkdir -p "$SWARM_DIR"
mkfifo "$RESULT_PIPE" "$TASK_QUEUE"

# Agent types
declare -A AGENT_TYPES=(
    ["researcher"]="Research and gather information"
    ["coder"]="Write and review code"
    ["reviewer"]="Analyze and critique"
    ["writer"]="Generate documentation"
)

# Spawn an agent worker
spawn_agent() {
    local agent_type=$1
    local agent_id="${agent_type}_$(date +%s%N)"

    (
        echo "[Agent $agent_id] Started"

        while read -r task < "$TASK_QUEUE"; do
            [[ "$task" == "SHUTDOWN" ]] && break

            # Parse task
            local task_id="${task%%:*}"
            local task_content="${task#*:}"

            echo "[Agent $agent_id] Processing task $task_id"

            # Simulate AI processing (replace with actual API call)
            local result=$(process_task "$agent_type" "$task_content")

            # Send result back
            echo "$task_id:$agent_id:$result" > "$RESULT_PIPE"
        done

        echo "[Agent $agent_id] Shutting down"
    ) &

    echo $!
}

# Process a task (stub - replace with actual AI call)
process_task() {
    local agent_type=$1
    local content=$2

    sleep $((RANDOM % 2 + 1))  # Simulate processing
    echo "Processed by $agent_type: ${content:0:50}..."
}

# Result aggregator
aggregate_results() {
    local expected=$1
    local results=()

    while (( ${#results[@]} < expected )); do
        if read -r -t 30 result < "$RESULT_PIPE"; then
            results+=("$result")
            echo "[Aggregator] Received: $result"
        else
            echo "[Aggregator] Timeout waiting for results"
            break
        fi
    done

    echo "[Aggregator] Collected ${#results[@]} results"
    printf '%s\n' "${results[@]}"
}

# Main orchestration
orchestrate() {
    local task_description=$1

    echo "[Orchestrator] Decomposing task..."

    # Decompose into subtasks (in real system, use AI for this)
    local subtasks=(
        "1:Research the topic"
        "2:Write initial code"
        "3:Review the code"
        "4:Document the solution"
    )

    # Spawn agents
    local agent_pids=()
    for agent_type in "${!AGENT_TYPES[@]}"; do
        agent_pids+=("$(spawn_agent "$agent_type")")
    done

    # Start result collector in background
    aggregate_results ${#subtasks[@]} &
    local aggregator_pid=$!

    # Submit tasks
    for task in "${subtasks[@]}"; do
        echo "$task" > "$TASK_QUEUE"
    done

    # Wait for aggregation
    wait $aggregator_pid

    # Shutdown agents
    for _ in "${agent_pids[@]}"; do
        echo "SHUTDOWN" > "$TASK_QUEUE"
    done

    wait
    echo "[Orchestrator] Swarm completed"
}

# Cleanup
trap "rm -rf '$SWARM_DIR'" EXIT

# Run
orchestrate "Build a CLI tool for file management"
```

**Why Revolutionary**: This enables complex, multi-step AI tasks to be parallelized across multiple agent "personalities", dramatically reducing total execution time while improving quality through specialization.

---

### Use Case 4: Real-Time Code Change Reactor

**What It Does**: Watches for code changes and automatically triggers relevant AI actions (test generation, documentation, linting) in real-time.

```bash
#!/bin/bash
# Real-Time Code Change Reactor
# Automatically triggers AI actions on file changes

PROJECT_DIR="${1:-.}"
declare -A HANDLERS
declare -a PENDING_TASKS=()

# Configuration
DEBOUNCE_MS=500
AI_ENDPOINT="${AI_ENDPOINT:-http://localhost:11434/api/generate}"

# Handler registration
register_handler() {
    local pattern=$1
    local handler=$2
    HANDLERS["$pattern"]="$handler"
}

# Default handlers
handle_test_file() {
    local file=$1
    echo "[Reactor] Test file changed: $file"
    echo "[Reactor] Running related tests..."
    npm test -- --testPathPattern="$(dirname "$file")" 2>&1 | head -20
}

handle_source_file() {
    local file=$1
    echo "[Reactor] Source changed: $file"

    # Type check
    echo "[Reactor] Type checking..."
    npx tsc --noEmit "$file" 2>&1 | head -10

    # AI-powered suggestions
    echo "[Reactor] Generating AI suggestions..."
    # In real implementation, call AI API
}

handle_doc_file() {
    local file=$1
    echo "[Reactor] Documentation changed: $file"
    echo "[Reactor] Validating links and format..."
}

handle_config_file() {
    local file=$1
    echo "[Reactor] Configuration changed: $file"
    echo "[Reactor] Validating configuration..."

    case "$file" in
        *package.json)
            npm ls --depth=0 2>&1 | head -5
            ;;
        *tsconfig.json)
            npx tsc --showConfig | head -20
            ;;
    esac
}

# Register handlers
register_handler "*.test.ts" "handle_test_file"
register_handler "*.spec.ts" "handle_test_file"
register_handler "*.ts" "handle_source_file"
register_handler "*.tsx" "handle_source_file"
register_handler "*.md" "handle_doc_file"
register_handler "package.json" "handle_config_file"
register_handler "tsconfig.json" "handle_config_file"

# Debounced execution
last_event_time=0
declare -A pending_files

process_event() {
    local file=$1
    local event=$2
    local now=$(date +%s%N)

    # Skip node_modules and hidden files
    [[ "$file" == *node_modules* ]] && return
    [[ "$file" == *.* ]] && [[ "$(basename "$file")" == .* ]] && return

    # Debounce
    pending_files["$file"]=1

    (
        sleep 0.5

        # Check if still pending (not superseded)
        if [[ "${pending_files[$file]:-}" == "1" ]]; then
            unset 'pending_files[$file]'

            local filename=$(basename "$file")

            for pattern in "${!HANDLERS[@]}"; do
                if [[ "$filename" == $pattern ]]; then
                    ${HANDLERS[$pattern]} "$file"
                    break
                fi
            done
        fi
    ) &
}

# Main watch loop
echo "[Reactor] Watching $PROJECT_DIR for changes..."
echo "[Reactor] Registered handlers: ${!HANDLERS[*]}"

inotifywait -m -r -e close_write,create,moved_to \
    --exclude '(node_modules|\.git|\.next)' \
    --format '%w%f %e' "$PROJECT_DIR" 2>/dev/null | \
while read -r file event; do
    process_event "$file" "$event"
done
```

**Why Revolutionary**: Integrates AI assistance into the development flow seamlessly. Instead of manually invoking AI tools, the system proactively assists based on developer actions.

---

### Use Case 5: Conversational Agent with Persistent Session

**What It Does**: A command-line chatbot that maintains conversation history, context, and can execute tools - all in pure Bash.

```bash
#!/bin/bash
# Conversational Agent with Persistent Session
# Full chatbot experience in Bash

SESSION_DIR="${HOME}/.agent_sessions"
CURRENT_SESSION=""
HISTORY_FILE=""
CONTEXT_FILE=""

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Initialize session
init_session() {
    local session_id=${1:-$(date +%Y%m%d_%H%M%S)}
    CURRENT_SESSION="$SESSION_DIR/$session_id"
    mkdir -p "$CURRENT_SESSION"

    HISTORY_FILE="$CURRENT_SESSION/history.jsonl"
    CONTEXT_FILE="$CURRENT_SESSION/context.txt"

    [[ -f "$HISTORY_FILE" ]] || touch "$HISTORY_FILE"
    [[ -f "$CONTEXT_FILE" ]] || echo "New conversation started at $(date)" > "$CONTEXT_FILE"

    echo -e "${GREEN}Session initialized: $session_id${NC}"
}

# Add message to history
add_to_history() {
    local role=$1
    local content=$2
    local timestamp=$(date -Iseconds)

    jq -nc --arg role "$role" --arg content "$content" --arg ts "$timestamp" \
        '{role: $role, content: $content, timestamp: $ts}' >> "$HISTORY_FILE"
}

# Get conversation context for AI
get_conversation_context() {
    local limit=${1:-10}

    echo "## Conversation History"
    tail -n "$limit" "$HISTORY_FILE" | while read -r line; do
        local role=$(jq -r '.role' <<< "$line")
        local content=$(jq -r '.content' <<< "$line")
        echo "[$role]: $content"
    done
    echo ""
    echo "## Additional Context"
    cat "$CONTEXT_FILE"
}

# Execute a tool (simplified)
execute_tool() {
    local tool=$1
    shift
    local args=("$@")

    case "$tool" in
        "shell")
            echo -e "${YELLOW}Executing: ${args[*]}${NC}"
            eval "${args[*]}" 2>&1
            ;;
        "read_file")
            if [[ -f "${args[0]}" ]]; then
                head -100 "${args[0]}"
            else
                echo "File not found: ${args[0]}"
            fi
            ;;
        "write_file")
            echo "${args[1]}" > "${args[0]}"
            echo "Written to ${args[0]}"
            ;;
        "search")
            grep -r "${args[0]}" . 2>/dev/null | head -20
            ;;
        *)
            echo "Unknown tool: $tool"
            ;;
    esac
}

# Parse tool calls from AI response
parse_and_execute_tools() {
    local response=$1

    # Simple pattern matching for tool calls
    # Format: [TOOL:name:arg1:arg2:...]
    while [[ "$response" =~ \[TOOL:([^:]+):([^\]]+)\] ]]; do
        local tool="${BASH_REMATCH[1]}"
        local args="${BASH_REMATCH[2]}"

        echo -e "${BLUE}Tool call detected: $tool${NC}"
        execute_tool "$tool" "$args"

        # Remove processed tool call
        response="${response/${BASH_REMATCH[0]}/}"
    done

    # Return remaining response
    echo "$response"
}

# Call AI (stub - replace with actual API)
call_ai() {
    local prompt=$1

    # Simulate AI response for demo
    # In production, this would call Ollama, Claude API, etc.
    case "$prompt" in
        *"list files"*)
            echo "I'll list the files for you. [TOOL:shell:ls -la]"
            ;;
        *"read"*|*"show"*)
            local file=$(echo "$prompt" | grep -oP '(?<=read |show )[\w./]+')
            echo "Reading file $file. [TOOL:read_file:$file]"
            ;;
        *"help"*)
            echo "I can help you with:
- List files: 'list files'
- Read files: 'read filename'
- Search: 'search for pattern'
- Execute commands: 'run command'
- Exit: 'quit' or 'exit'"
            ;;
        *)
            echo "I understood: $prompt. How can I help further?"
            ;;
    esac
}

# Main conversation loop
conversation_loop() {
    echo -e "${GREEN}Agent ready. Type 'help' for commands, 'quit' to exit.${NC}"
    echo ""

    while true; do
        echo -ne "${BLUE}You: ${NC}"
        read -r user_input

        # Handle exit
        [[ "$user_input" =~ ^(quit|exit|bye)$ ]] && {
            echo -e "${GREEN}Goodbye!${NC}"
            break
        }

        # Handle empty input
        [[ -z "$user_input" ]] && continue

        # Add to history
        add_to_history "user" "$user_input"

        # Build prompt with context
        local full_prompt="$(get_conversation_context 5)

User's latest message: $user_input

Respond helpfully. If you need to use a tool, format it as [TOOL:name:args]."

        # Get AI response
        local response=$(call_ai "$full_prompt")

        # Parse and execute any tools
        response=$(parse_and_execute_tools "$response")

        # Display response
        echo -e "${GREEN}Agent: ${NC}$response"
        echo ""

        # Add to history
        add_to_history "assistant" "$response"
    done
}

# List sessions
list_sessions() {
    echo "Available sessions:"
    ls -1 "$SESSION_DIR" 2>/dev/null || echo "No sessions found"
}

# Main
main() {
    mkdir -p "$SESSION_DIR"

    case "${1:-}" in
        "list")
            list_sessions
            ;;
        "resume")
            if [[ -n "$2" ]]; then
                init_session "$2"
                conversation_loop
            else
                echo "Usage: $0 resume <session_id>"
                list_sessions
            fi
            ;;
        *)
            init_session
            conversation_loop
            ;;
    esac
}

main "$@"
```

**Why Revolutionary**: Demonstrates that a full-featured conversational AI interface can be built in pure Bash, making it portable, fast, and requiring zero external dependencies beyond curl for API calls.

---

## Part 3: Competitive Analysis

### Existing Bash Agent Tools

| Project | Focus | Strengths | Gaps |
|---------|-------|-----------|------|
| **Claude-Flow** | Multi-agent orchestration | Full-featured, MCP support | Heavy dependency, not pure Bash |
| **wshobson/agents** | Claude Code plugins | 100+ agents, comprehensive | TypeScript-based, not Bash |
| **CrewAI** | Agent teams | Role-based, popular | Python-only, heavy |
| **bashbot** (various) | Simple chatbots | Lightweight | No agent orchestration |

### Unique Bash Advantages

1. **Zero Dependencies**: Pure Bash runs everywhere with no installation
2. **Native Process Control**: Direct access to fork/exec, signals, pipes
3. **Shell Integration**: Natural fit for CLI tools and dev workflows
4. **Performance**: Sub-millisecond overhead for simple operations
5. **Debugging**: Easy to trace and understand (set -x)

### Gaps in the Market

1. **No Production-Ready Bash Agent Framework**: Most frameworks are Python/TypeScript
2. **Missing: Bash-Native Claude Code Integration**: Hooks exist but no comprehensive library
3. **Missing: Persistent State Library for Bash**: No standard solution
4. **Missing: FIFO-Based Agent Communication Standard**: Ad-hoc implementations only
5. **Missing: VHS-Compatible Demo Framework**: No standard for creating CLI agent demos

---

## Part 4: Gap Opportunities for Basher Project

### Opportunity 1: Bash Agent Primitives Library

Create a library of reusable functions for:
- Coprocess management
- FIFO-based message passing
- State persistence
- Signal-based lifecycle management
- Job control with semaphores

### Opportunity 2: Claude Code Hooks Framework

Build a comprehensive hook system with:
- Pre/post tool execution
- Self-healing patterns
- Execution tracing
- Automatic retries

### Opportunity 3: VHS-Ready Demo Recorder

Develop templates and utilities for:
- Recording agent interactions
- Generating documentation GIFs
- CI/CD integration tests
- Shareable demos

### Opportunity 4: Agent Communication Protocol (ACP)

Define a standard for:
- Message format for FIFO communication
- Agent discovery and registration
- Task distribution patterns
- Result aggregation

### Opportunity 5: Documentation and Education

Create resources that:
- Show developers "I had no idea Bash could do that"
- Provide copy-paste patterns
- Include real-world examples
- Offer performance comparisons

---

## Sources and References

### Official Documentation
- [GNU Bash Reference Manual - Coprocesses](https://www.gnu.org/software/bash/manual/html_node/Coprocesses.html)
- [Bash Reference Manual](https://www.gnu.org/software/bash/manual/bash.html)
- [inotify(7) - Linux Manual](https://man7.org/linux/man-pages/man7/inotify.7.html)
- [flock(2) - Linux Manual](https://man7.org/linux/man-pages/man2/flock.2.html)

### Technical Articles
- [Bash Coprocess - Medium](https://copyconstruct.medium.com/bash-coprocess-2092a93ad912)
- [Bash Redirection Fun with Descriptors](https://copyconstruct.medium.com/bash-redirection-fun-with-descriptors-e799ec5a3c16)
- [Fun with Unix Named Pipes](http://hassansin.github.io/fun-with-unix-named-pipes)
- [Using Named Pipes with Bash - Linux Journal](https://www.linuxjournal.com/content/using-named-pipes-fifos-bash)

### Claude Code Resources
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- [Demystifying Claude Code Hooks](https://www.brethorsting.com/blog/2025/08/demystifying-claude-code-hooks/)
- [Automate with Claude Code Hooks - GitButler](https://blog.gitbutler.com/automate-your-ai-workflows-with-claude-code-hooks)
- [Claude Code Best Practices - Anthropic](https://www.anthropic.com/engineering/claude-code-best-practices)

### GitHub Projects
- [charmbracelet/vhs](https://github.com/charmbracelet/vhs) - Terminal GIF recorder
- [ruvnet/claude-flow](https://github.com/ruvnet/claude-flow) - Agent orchestration
- [NobodyXu/bash-loadables](https://github.com/NobodyXu/bash-loadables) - Bash builtins

### Performance and Optimization
- [Script Performance Optimization](https://www.linuxbash.sh/post/script-performance-optimization)
- [Shell Scripting: Subshell vs Subprocess](https://jitpaul.blog/2018/09/16/shell-scripting-sub-shell-vs-sub-process/)

---

## Conclusion

Bash contains powerful, underutilized primitives that can form the foundation of lightweight, fast, and portable AI agent systems. The combination of coprocesses, named pipes, file descriptor manipulation, and signal handling enables sophisticated orchestration patterns that rival higher-level language implementations while maintaining the simplicity and universality of shell scripting.

The gap analysis reveals significant opportunities for a Bash-native agent framework, particularly for Claude Code integration. By providing well-documented patterns and reusable libraries, we can enable developers to build sophisticated AI-powered CLI tools without heavy dependencies.

**Next Steps**:
1. Create a `basher` library with the patterns documented here
2. Build example hooks for Claude Code
3. Create VHS demo recordings
4. Publish documentation targeting developers who "had no idea Bash could do that"

---

*Report generated by Research Team Alpha | 2026-01-17*
