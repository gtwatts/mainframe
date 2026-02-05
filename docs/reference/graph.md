# Graph Functions

DAG workflow execution engine - dependency graph construction and execution with auto-parallelization, topological sort (Kahn's algorithm), cycle detection, ASCII visualization, and rollback.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Workflow Definition (graph.sh)

| Function | Signature | Description |
|----------|-----------|-------------|
| `graph_define` | `graph_define "workflow_name"` | Create a new workflow. Name must be alphanumeric with underscores/hyphens. |
| `graph_add_task` | `graph_add_task "wf" "task_name" "command" [--rollback "cmd"]` | Add a task to a workflow with an optional rollback command. |
| `graph_add_dep` | `graph_add_dep "wf" "task" "dependency"` | Add a dependency edge: `task` depends on `dependency` completing first. |

---

## Execution

| Function | Signature | Description |
|----------|-----------|-------------|
| `graph_execute` | `graph_execute "wf" [--parallel N] [--continue-on-fail]` | Execute workflow respecting dependencies with auto-parallelization. Default parallelism: 4. |

---

## Visualization and Status

| Function | Signature | Description |
|----------|-----------|-------------|
| `graph_visualize` | `graph_visualize "wf"` | Print ASCII flowchart showing task status with color-coded icons. |
| `graph_status` | `graph_status "wf"` | Get execution status counts: total, pending, running, completed, failed, rolled_back. |

---

## Rollback and Utilities

| Function | Signature | Description |
|----------|-----------|-------------|
| `graph_rollback` | `graph_rollback "wf"` | Execute rollback commands in reverse topological order for completed tasks. |
| `graph_clear` | `graph_clear "wf"` | Remove all data for a workflow. |
| `graph_list` | `graph_list` | List all defined workflows. |
| `graph_task_output` | `graph_task_output "wf" "task"` | Get stdout output from a completed task. |
| `graph_task_error` | `graph_task_error "wf" "task"` | Get error output from a failed task. |

---

## Task Status Icons

| Status | Icon | Color |
|--------|------|-------|
| pending | `o` | dim |
| running | `(half)` | yellow |
| completed | `(check)` | green |
| failed | `x` | red |
| rolled_back | `(undo)` | magenta |

---

## Usage Examples

```bash
# Define a deployment workflow
graph_define "deploy"
graph_add_task "deploy" "test" "npm test" --rollback "echo 'tests rolled back'"
graph_add_task "deploy" "build" "npm run build" --rollback "rm -rf dist/"
graph_add_task "deploy" "deploy" "rsync dist/ server:/app/" --rollback "rsync server:/app.bak/ server:/app/"

# Set dependencies: deploy depends on build, build depends on test
graph_add_dep "deploy" "build" "test"
graph_add_dep "deploy" "deploy" "build"

# Execute with parallelism
graph_execute "deploy" --parallel 4

# Visualize the workflow
graph_visualize "deploy"
# Shows ASCII flowchart:
#   [check] test
#       |
#       v
#   [check] build
#       |
#       v
#   [check] deploy

# Check status
graph_status "deploy"
# {"ok":true,"data":{"workflow":"deploy","total":3,"completed":3,"failed":0,...}}

# Rollback on failure
graph_rollback "deploy"

# Get task output
output=$(graph_task_output "deploy" "test")
```

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAPH_DEFAULT_PARALLEL` | `4` | Default parallelism limit |
| `GRAPH_STATE_DIR` | `/tmp/mainframe_graph` | Directory for workflow state files |
| `GRAPH_CONTINUE_ON_FAIL` | `false` | Continue executing on task failure |

## Notes

- Cycle detection prevents workflows with circular dependencies from executing
- Deadlock detection stops execution if no tasks can proceed
- Tasks execute in background subshells for parallelism
- Rollback executes in reverse topological order
