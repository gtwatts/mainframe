#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/examples/temporal_demo.sh - Temporal Database Demo
# =============================================================================
# This demo shows how to use the temporal.sh module for command history
# analysis, pattern detection, anomaly detection, and prediction.
# =============================================================================

# Load mainframe libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINFRAME_ROOT="${SCRIPT_DIR%/examples}"

source "$MAINFRAME_ROOT/lib/output.sh"
source "$MAINFRAME_ROOT/lib/temporal.sh"

# Use demo-specific storage
export TEMPORAL_ROOT="${HOME}/.mainframe/temporal_demo_$$"
export TEMPORAL_BACKEND="bash"  # Use bash backend for portability

echo "======================================================================"
echo "MAINFRAME Temporal Database Demo"
echo "======================================================================"
echo ""

# =============================================================================
# 1. RECORDING COMMAND HISTORY
# =============================================================================

echo "1. Recording command executions..."
echo ""

# Simulate recording some commands
temporal_record \
    --cwd "/home/user/project" \
    --command "npm install" \
    --exit_code 0 \
    --duration_ms 12000 \
    --session_id "demo_session_1" \
    --git_branch "main" \
    --output_lines 45

temporal_record \
    --cwd "/home/user/project" \
    --command "npm test" \
    --exit_code 0 \
    --duration_ms 4500 \
    --session_id "demo_session_1" \
    --git_branch "main" \
    --output_lines 120

temporal_record \
    --cwd "/home/user/project" \
    --command "npm run build" \
    --exit_code 0 \
    --duration_ms 8500 \
    --session_id "demo_session_1" \
    --git_branch "main" \
    --output_lines 30

temporal_record \
    --cwd "/home/user/project" \
    --command "git add ." \
    --exit_code 0 \
    --duration_ms 150 \
    --session_id "demo_session_1" \
    --git_branch "main"

temporal_record \
    --cwd "/home/user/project" \
    --command "git commit -m 'update'" \
    --exit_code 0 \
    --duration_ms 300 \
    --session_id "demo_session_1" \
    --git_branch "main"

# Record some commands with failures
temporal_record \
    --cwd "/home/user/project" \
    --command "npm test" \
    --exit_code 1 \
    --duration_ms 2000 \
    --session_id "demo_session_2" \
    --git_branch "feature/auth"

temporal_record \
    --cwd "/home/user/project" \
    --command "pytest tests/" \
    --exit_code 0 \
    --duration_ms 3200 \
    --session_id "demo_session_2" \
    --git_branch "feature/auth"

# Record some docker commands
temporal_record \
    --cwd "/home/user/project" \
    --command "docker build -t myapp ." \
    --exit_code 0 \
    --duration_ms 45000 \
    --session_id "demo_session_3"

temporal_record \
    --cwd "/home/user/project" \
    --command "docker run -p 3000:3000 myapp" \
    --exit_code 0 \
    --duration_ms 5000 \
    --session_id "demo_session_3"

echo "   ✓ Recorded 8 command executions"
echo ""

# =============================================================================
# 2. QUERYING HISTORY
# =============================================================================

echo "2. Querying command history..."
echo ""

echo "   a) Simple query - all commands:"
result=$(temporal_query "SELECT command, exit_code FROM history LIMIT 5")
echo "      $result"
echo ""

echo "   b) Select with WHERE clause:"
result=$(temporal_select "command, duration_ms" --from "history" --where "exit_code = 0" --limit 3)
echo "      $result"
echo ""

echo "   c) Aggregate - average duration:"
result=$(temporal_aggregate "AVG(duration_ms)" --group_by "exit_code")
echo "      $result"
echo ""

# =============================================================================
# 3. PATTERN DETECTION
# =============================================================================

echo "3. Pattern detection..."
echo ""

echo "   a) Detect command sequences:"
result=$(temporal_detect_pattern "commands that often run together")
echo "      $result"
echo ""

echo "   b) Find similar commands to 'pytest':"
result=$(temporal_find_similar "pytest")
echo "      $result"
echo ""

echo "   c) Frequency analysis:"
result=$(temporal_frequency_analysis)
echo "      $result"
echo ""

# =============================================================================
# 4. ANOMALY DETECTION
# =============================================================================

echo "4. Anomaly detection..."
echo ""

echo "   Detecting anomalies with medium sensitivity:"
result=$(temporal_anomaly_detect --sensitivity medium)
echo "      $result"
echo ""

echo "   Finding duration outliers:"
result=$(temporal_outliers "duration_ms")
echo "      $result"
echo ""

# =============================================================================
# 5. PREDICTION
# =============================================================================

echo "5. Predictions..."
echo ""

echo "   a) Predict success probability for 'npm test':"
result=$(temporal_predict_success "npm test")
echo "      $result"
echo ""

echo "   b) Predict duration for 'docker build':"
result=$(temporal_predict_duration "docker build")
echo "      $result"
echo ""

echo "   c) Recommend commands for 'deploy the app':"
result=$(temporal_recommend "deploy the app")
echo "      $result"
echo ""

# =============================================================================
# 6. STATISTICS
# =============================================================================

echo "6. Temporal database statistics:"
echo ""
result=$(temporal_stats)
echo "      $result"
echo ""

# =============================================================================
# CLEANUP
# =============================================================================

echo "======================================================================"
echo "Cleaning up demo data..."
temporal_clear --confirm 2>/dev/null
rm -rf "$TEMPORAL_ROOT"
echo "Demo complete!"
echo "======================================================================"
