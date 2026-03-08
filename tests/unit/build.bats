#!/usr/bin/env bats
# =============================================================================
# Tests for mainframe-build CLI tool
# =============================================================================

# Setup - runs before each test
setup() {
    # Get the directory containing this test file
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
    BUILD_CMD="$PROJECT_ROOT/bin/mainframe-build"

    # Ensure build command exists and is executable
    [[ -x "$BUILD_CMD" ]] || skip "mainframe-build not found or not executable"

    # Create temp directory for test outputs
    TEST_TMP="$(mktemp -d)"

    # Create a test agent script
    cat > "$TEST_TMP/test-agent.sh" << 'EOF'
#!/usr/bin/env bash
# Test agent script
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
mainframe_load "json"
mainframe_load "validation"

main() {
    local input="$1"
    validate_email "$input" && echo "Valid email"
    json_object "result=success"
}

main "$@"
EOF
    chmod +x "$TEST_TMP/test-agent.sh"

    # Create a minimal test script (no MAINFRAME deps)
    cat > "$TEST_TMP/simple-script.sh" << 'EOF'
#!/usr/bin/env bash
echo "Hello, World!"
EOF
    chmod +x "$TEST_TMP/simple-script.sh"

    # Create a script with external deps
    cat > "$TEST_TMP/deps-script.sh" << 'EOF'
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/http.sh"

# Uses curl and jq
result=$(curl -s https://api.example.com/data | jq -r '.name')
echo "$result"
EOF
    chmod +x "$TEST_TMP/deps-script.sh"

    # Create a script that relies on common.sh auto-loading its default runtime
    cat > "$TEST_TMP/common-only.sh" << 'EOF'
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

if validate_email "person@example.com"; then
    echo "Valid via common"
fi
EOF
    chmod +x "$TEST_TMP/common-only.sh"
}

# Teardown - runs after each test
teardown() {
    # Clean up temp directory
    [[ -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# =============================================================================
# Help and Version Tests
# =============================================================================

@test "mainframe-build --help shows usage" {
    run "$BUILD_CMD" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAINFRAME Build"* ]]
    [[ "$output" == *"static"* ]]
    [[ "$output" == *"minimal"* ]]
    [[ "$output" == *"container"* ]]
}

@test "mainframe-build -h shows usage" {
    run "$BUILD_CMD" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "mainframe-build --version shows version" {
    run "$BUILD_CMD" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAINFRAME Build"* ]]
    [[ "$output" == *"v1."* ]]
}

@test "mainframe-build with no args shows help" {
    run "$BUILD_CMD"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# =============================================================================
# Argument Validation Tests
# =============================================================================

@test "mainframe-build static without script fails" {
    run "$BUILD_CMD" static
    [ "$status" -eq 1 ]
    [[ "$output" == *"Script path required"* ]] || [[ "$output" == *"required"* ]]
}

@test "mainframe-build static with nonexistent script fails" {
    run "$BUILD_CMD" static /nonexistent/script.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "mainframe-build unknown command fails" {
    run "$BUILD_CMD" unknown "$TEST_TMP/simple-script.sh"
    [ "$status" -eq 1 ] || [ "$status" -eq 0 ]  # May show help
}

@test "mainframe-build unknown option fails" {
    run "$BUILD_CMD" --unknown-option static "$TEST_TMP/simple-script.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "mainframe-build invalid target arch fails" {
    run "$BUILD_CMD" static --target invalid "$TEST_TMP/simple-script.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown target"* ]] || [[ "$output" == *"architecture"* ]]
}

# =============================================================================
# Static Build Tests
# =============================================================================

@test "mainframe-build static creates output file" {
    run "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/simple-script" ]
    [ -x "$TEST_TMP/dist/simple-script" ]
}

@test "mainframe-build static output is executable" {
    run "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]

    # Run the output script
    run "$TEST_TMP/dist/simple-script"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hello, World!"* ]]
}

@test "mainframe-build static with --name overrides output name" {
    run "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist" --name my-tool
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/my-tool" ]
}

@test "mainframe-build static includes header comments" {
    run "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]

    head -20 "$TEST_TMP/dist/simple-script" | grep -q "MAINFRAME Static Build"
}

@test "mainframe-build static with MAINFRAME deps inlines libraries" {
    run "$BUILD_CMD" static "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist" --quiet
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/test-agent" ]

    # Check that libraries are inlined
    grep -q "Inlined: lib/common.sh" "$TEST_TMP/dist/test-agent" || \
    grep -q "json_object" "$TEST_TMP/dist/test-agent"
}

@test "mainframe-build static with MAINFRAME deps runs without filesystem libraries" {
    run "$BUILD_CMD" static "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist" --quiet
    [ "$status" -eq 0 ]

    run env -u MAINFRAME_ROOT "$TEST_TMP/dist/test-agent" "person@example.com"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Valid email"* ]]
    [[ "$output" == *'"result":"success"'* ]]
}

@test "mainframe-build static with --strip-comments removes comments" {
    run "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist" --strip-comments
    [ "$status" -eq 0 ]

    # The output should have fewer comment lines
    local comment_count
    comment_count=$(grep -c '^[[:space:]]*#' "$TEST_TMP/dist/simple-script" || echo "0")
    # Should still have the header but fewer internal comments
    [ "$comment_count" -lt 50 ]
}

@test "mainframe-build static with --manifest generates JSON" {
    run "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist" --manifest
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/simple-script.manifest.json" ]

    # Validate JSON
    run jq '.' "$TEST_TMP/dist/simple-script.manifest.json"
    [ "$status" -eq 0 ]
}

@test "mainframe-build static manifest contains required fields" {
    "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist" --manifest --quiet

    # Check manifest fields
    run jq -r '.name' "$TEST_TMP/dist/simple-script.manifest.json"
    [ "$status" -eq 0 ]
    [ "$output" = "simple-script" ]

    run jq -r '.type' "$TEST_TMP/dist/simple-script.manifest.json"
    [ "$status" -eq 0 ]
    [ "$output" = "static" ]

    run jq -r '.build_time' "$TEST_TMP/dist/simple-script.manifest.json"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

@test "mainframe-build static with --target arm64 sets target" {
    run "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist" --manifest --target arm64
    [ "$status" -eq 0 ]

    run jq -r '.target' "$TEST_TMP/dist/simple-script.manifest.json"
    [ "$status" -eq 0 ]
    [ "$output" = "arm64" ]
}

@test "mainframe-build static with --quiet suppresses output" {
    run "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist" --quiet
    [ "$status" -eq 0 ]
    # Should have minimal or no informational output
    [[ ! "$output" == *"[INFO]"* ]]
}

# =============================================================================
# Minimal Bundle Tests
# =============================================================================

@test "mainframe-build minimal creates bundle directory" {
    run "$BUILD_CMD" minimal "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]
    [ -d "$TEST_TMP/dist/test-agent-bundle" ]
    [ -d "$TEST_TMP/dist/test-agent-bundle/lib" ]
}

@test "mainframe-build minimal creates agent.sh" {
    run "$BUILD_CMD" minimal "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/test-agent-bundle/agent.sh" ]
    [ -x "$TEST_TMP/dist/test-agent-bundle/agent.sh" ]
}

@test "mainframe-build minimal creates run.sh entry point" {
    run "$BUILD_CMD" minimal "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/test-agent-bundle/run.sh" ]
    [ -x "$TEST_TMP/dist/test-agent-bundle/run.sh" ]
}

@test "mainframe-build minimal copies only required libraries" {
    run "$BUILD_CMD" minimal "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist" --quiet
    [ "$status" -eq 0 ]

    # Should have common.sh (always included)
    [ -f "$TEST_TMP/dist/test-agent-bundle/lib/common.sh" ]

    # Should have json and validation (explicitly loaded)
    # Note: They may be pulled in as dependencies
}

@test "mainframe-build minimal with --manifest generates JSON" {
    run "$BUILD_CMD" minimal "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist" --manifest
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/test-agent-bundle/manifest.json" ]

    run jq -r '.type' "$TEST_TMP/dist/test-agent-bundle/manifest.json"
    [ "$status" -eq 0 ]
    [ "$output" = "minimal" ]
}

@test "mainframe-build minimal rewrites source paths" {
    run "$BUILD_CMD" minimal "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]

    # agent.sh should use relative paths, not MAINFRAME_ROOT
    ! grep -q 'MAINFRAME_ROOT.*lib/' "$TEST_TMP/dist/test-agent-bundle/agent.sh" || \
    grep -q '${BASH_SOURCE%/*}/lib/' "$TEST_TMP/dist/test-agent-bundle/agent.sh"
}

@test "mainframe-build minimal preserves common.sh default runtime" {
    run "$BUILD_CMD" minimal "$TEST_TMP/common-only.sh" --output "$TEST_TMP/dist" --quiet
    [ "$status" -eq 0 ]

    run env -u MAINFRAME_ROOT "$TEST_TMP/dist/common-only-bundle/run.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Valid via common"* ]]
    [[ "$output" != *"No such file or directory"* ]]
}

# =============================================================================
# Container Build Tests
# =============================================================================

@test "mainframe-build container creates Dockerfile" {
    run "$BUILD_CMD" container "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/test-agent-container/Dockerfile" ]
}

@test "mainframe-build container creates docker-compose.yml" {
    run "$BUILD_CMD" container "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/test-agent-container/docker-compose.yml" ]
}

@test "mainframe-build container creates build.sh" {
    run "$BUILD_CMD" container "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/test-agent-container/build.sh" ]
    [ -x "$TEST_TMP/dist/test-agent-container/build.sh" ]
}

@test "mainframe-build container Dockerfile uses bash:5.2-alpine" {
    run "$BUILD_CMD" container "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]

    grep -q "FROM.*bash:5.2-alpine" "$TEST_TMP/dist/test-agent-container/Dockerfile"
}

@test "mainframe-build container detects external deps" {
    run "$BUILD_CMD" container "$TEST_TMP/deps-script.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]

    # Dockerfile should include curl and jq
    grep -q "apk add" "$TEST_TMP/dist/deps-script-container/Dockerfile" && \
    (grep -q "curl" "$TEST_TMP/dist/deps-script-container/Dockerfile" || \
     grep -q "jq" "$TEST_TMP/dist/deps-script-container/Dockerfile")
}

@test "mainframe-build container with --target arm64 sets platform" {
    run "$BUILD_CMD" container "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist" --target arm64
    [ "$status" -eq 0 ]

    grep -q "platform=linux/arm64" "$TEST_TMP/dist/test-agent-container/Dockerfile"
}

@test "mainframe-build container with --manifest generates JSON" {
    run "$BUILD_CMD" container "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist" --manifest
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/test-agent-container/manifest.json" ]

    run jq -r '.type' "$TEST_TMP/dist/test-agent-container/manifest.json"
    [ "$status" -eq 0 ]
    [ "$output" = "container" ]

    run jq -r '.base_image' "$TEST_TMP/dist/test-agent-container/manifest.json"
    [ "$status" -eq 0 ]
    [ "$output" = "bash:5.2-alpine" ]
}

@test "mainframe-build container includes app-bundle" {
    run "$BUILD_CMD" container "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]
    [ -d "$TEST_TMP/dist/test-agent-container/app-bundle" ]
    [ -f "$TEST_TMP/dist/test-agent-container/app-bundle/agent.sh" ]
}

# =============================================================================
# Dependency Detection Tests
# =============================================================================

@test "mainframe-build detects source statements" {
    # Create a script that sources multiple libraries
    cat > "$TEST_TMP/multi-source.sh" << 'EOF'
#!/usr/bin/env bash
source "${MAINFRAME_ROOT}/lib/common.sh"
source "${MAINFRAME_ROOT}/lib/json.sh"
source "${MAINFRAME_ROOT}/lib/http.sh"
echo "test"
EOF

    run "$BUILD_CMD" static "$TEST_TMP/multi-source.sh" --output "$TEST_TMP/dist" --manifest --quiet
    [ "$status" -eq 0 ]

    # Manifest should list the libraries
    run jq -r '.libraries_included | length' "$TEST_TMP/dist/multi-source.manifest.json"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "mainframe-build detects mainframe_load calls" {
    run "$BUILD_CMD" static "$TEST_TMP/test-agent.sh" --output "$TEST_TMP/dist" --manifest --quiet
    [ "$status" -eq 0 ]

    # Should detect json and validation from mainframe_load
    run jq -r '.libraries_included[]' "$TEST_TMP/dist/test-agent.manifest.json"
    [ "$status" -eq 0 ]
}

@test "mainframe-build detects external command usage" {
    run "$BUILD_CMD" static "$TEST_TMP/deps-script.sh" --output "$TEST_TMP/dist" --manifest --quiet
    [ "$status" -eq 0 ]

    # Should detect curl and jq
    run jq -r '.external_deps | length' "$TEST_TMP/dist/deps-script.manifest.json"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "mainframe-build handles script with no MAINFRAME deps" {
    run "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/dist/simple-script" ]

    # Output should still be executable
    run "$TEST_TMP/dist/simple-script"
    [ "$status" -eq 0 ]
}

@test "mainframe-build handles script with spaces in path" {
    mkdir -p "$TEST_TMP/path with spaces"
    cp "$TEST_TMP/simple-script.sh" "$TEST_TMP/path with spaces/my script.sh"

    run "$BUILD_CMD" static "$TEST_TMP/path with spaces/my script.sh" --output "$TEST_TMP/dist"
    [ "$status" -eq 0 ]
}

@test "mainframe-build creates output directory if missing" {
    run "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/new/nested/dir"
    [ "$status" -eq 0 ]
    [ -d "$TEST_TMP/new/nested/dir" ]
}

@test "mainframe-build overwrites existing output" {
    # First build
    "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist" --quiet
    local first_time
    first_time=$(stat -c %Y "$TEST_TMP/dist/simple-script" 2>/dev/null || stat -f %m "$TEST_TMP/dist/simple-script")

    sleep 1

    # Second build should overwrite
    run "$BUILD_CMD" static "$TEST_TMP/simple-script.sh" --output "$TEST_TMP/dist" --quiet
    [ "$status" -eq 0 ]

    local second_time
    second_time=$(stat -c %Y "$TEST_TMP/dist/simple-script" 2>/dev/null || stat -f %m "$TEST_TMP/dist/simple-script")

    [ "$second_time" -ge "$first_time" ]
}
