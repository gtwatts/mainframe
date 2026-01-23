#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Project Intelligence Tests
# =============================================================================

load 'test_helper'

setup() {
    source_lib "project"
    TEST_DIR=$(create_test_dir "project")
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# project_detect TESTS
# =============================================================================

@test "project_detect returns JSON" {
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == "{"* ]]
    [[ "$result" == *"}" ]]
}

@test "project_detect detects TypeScript + Next.js" {
    echo '{"dependencies":{"react":"18"}}' > "$TEST_DIR/package.json"
    touch "$TEST_DIR/tsconfig.json"
    touch "$TEST_DIR/next.config.js"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"language":"typescript"'* ]]
    [[ "$result" == *'"framework":"nextjs"'* ]]
}

@test "project_detect detects Python + FastAPI" {
    printf '[project]\n[project.dependencies]\nfastapi="*"\n' > "$TEST_DIR/pyproject.toml"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"language":"python"'* ]]
    [[ "$result" == *'"framework":"fastapi"'* ]]
}

@test "project_detect detects Rust + Axum" {
    printf '[dependencies]\naxum = "0.7"\n' > "$TEST_DIR/Cargo.toml"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"language":"rust"'* ]]
    [[ "$result" == *'"framework":"axum"'* ]]
}

@test "project_detect detects Go + Gin" {
    printf 'module myapp\nrequire github.com/gin-gonic/gin v1.9\n' > "$TEST_DIR/go.mod"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"language":"go"'* ]]
    [[ "$result" == *'"framework":"gin"'* ]]
}

@test "project_detect detects bun package manager" {
    echo '{}' > "$TEST_DIR/package.json"
    touch "$TEST_DIR/bun.lockb"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"package_manager":"bun"'* ]]
}

@test "project_detect detects pnpm package manager" {
    echo '{}' > "$TEST_DIR/package.json"
    touch "$TEST_DIR/pnpm-lock.yaml"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"package_manager":"pnpm"'* ]]
}

@test "project_detect detects GitHub Actions CI" {
    mkdir -p "$TEST_DIR/.github/workflows"
    touch "$TEST_DIR/.github/workflows/ci.yml"
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"ci_provider":"github_actions"'* ]]
}

@test "project_detect detects vitest test runner" {
    echo '{"devDependencies":{"vitest":"1.0"}}' > "$TEST_DIR/package.json"
    touch "$TEST_DIR/vitest.config.ts"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"test_runner":"vitest"'* ]]
}

@test "project_detect detects bats test runner" {
    mkdir -p "$TEST_DIR/tests"
    touch "$TEST_DIR/tests/example.bats"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"test_runner":"bats"'* ]]
}

@test "project_detect detects monorepo (turborepo)" {
    echo '{}' > "$TEST_DIR/package.json"
    echo '{}' > "$TEST_DIR/turbo.json"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"has_monorepo":true'* ]]
}

@test "project_detect detects Django" {
    touch "$TEST_DIR/pyproject.toml"
    touch "$TEST_DIR/manage.py"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"framework":"django"'* ]]
}

@test "project_detect detects Ruby on Rails" {
    touch "$TEST_DIR/Gemfile"
    mkdir -p "$TEST_DIR/config"
    touch "$TEST_DIR/config/routes.rb"
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"language":"ruby"'* ]]
    [[ "$result" == *'"framework":"rails"'* ]]
}

@test "project_detect returns unknown for empty dir" {
    local result
    result=$(project_detect "$TEST_DIR")
    [[ "$result" == *'"language":"unknown"'* ]]
}

@test "project_detect fails for nonexistent dir" {
    local result
    ! result=$(project_detect "/nonexistent/dir/12345" 2>/dev/null) || [[ "$result" == *"error"* ]]
}

# =============================================================================
# project_commands TESTS
# =============================================================================

@test "project_commands returns JSON" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(project_commands "$TEST_DIR")
    [[ "$result" == "{"* ]]
}

@test "project_commands detects npm scripts" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"scripts":{"build":"next build","test":"vitest","dev":"next dev","lint":"eslint ."}}
EOF
    touch "$TEST_DIR/package-lock.json"
    local result
    result=$(project_commands "$TEST_DIR")
    [[ "$result" == *"npm run build"* ]]
    [[ "$result" == *"npm run test"* ]]
    [[ "$result" == *"npm run dev"* ]]
}

@test "project_commands uses bun when lockfile present" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"scripts":{"build":"next build","test":"vitest"}}
EOF
    touch "$TEST_DIR/bun.lockb"
    local result
    result=$(project_commands "$TEST_DIR")
    [[ "$result" == *"bun run build"* ]]
    [[ "$result" == *"bun run test"* ]]
}

@test "project_commands returns cargo commands for Rust" {
    touch "$TEST_DIR/Cargo.toml"
    local result
    result=$(project_commands "$TEST_DIR")
    [[ "$result" == *"cargo build"* ]]
    [[ "$result" == *"cargo test"* ]]
    [[ "$result" == *"cargo clippy"* ]]
}

@test "project_commands returns go commands" {
    printf 'module myapp\n' > "$TEST_DIR/go.mod"
    local result
    result=$(project_commands "$TEST_DIR")
    [[ "$result" == *"go build"* ]]
    [[ "$result" == *"go test"* ]]
}

@test "project_commands returns pytest for Python" {
    touch "$TEST_DIR/pyproject.toml"
    local result
    result=$(project_commands "$TEST_DIR")
    [[ "$result" == *"pytest"* ]]
}

# =============================================================================
# project_entry TESTS
# =============================================================================

@test "project_entry finds src/index.ts" {
    mkdir -p "$TEST_DIR/src"
    touch "$TEST_DIR/src/index.ts"
    local result
    result=$(project_entry "$TEST_DIR")
    [[ "$result" == *"src/index.ts"* ]]
}

@test "project_entry finds main.py" {
    touch "$TEST_DIR/main.py"
    local result
    result=$(project_entry "$TEST_DIR")
    [[ "$result" == *"main.py"* ]]
}

@test "project_entry finds src/main.rs" {
    mkdir -p "$TEST_DIR/src"
    touch "$TEST_DIR/src/main.rs"
    local result
    result=$(project_entry "$TEST_DIR")
    [[ "$result" == *"src/main.rs"* ]]
}

@test "project_entry finds main.go" {
    touch "$TEST_DIR/main.go"
    local result
    result=$(project_entry "$TEST_DIR")
    [[ "$result" == *"main.go"* ]]
}

@test "project_entry returns empty array for no entries" {
    local result
    result=$(project_entry "$TEST_DIR")
    [ "$result" = "[]" ]
}

@test "project_entry finds Next.js app router entry" {
    mkdir -p "$TEST_DIR/src/app"
    touch "$TEST_DIR/src/app/page.tsx"
    touch "$TEST_DIR/src/app/layout.tsx"
    local result
    result=$(project_entry "$TEST_DIR")
    [[ "$result" == *"src/app/page.tsx"* ]]
    [[ "$result" == *"src/app/layout.tsx"* ]]
}

# =============================================================================
# project_deps TESTS
# =============================================================================

@test "project_deps returns JSON" {
    echo '{}' > "$TEST_DIR/package.json"
    local result
    result=$(project_deps "$TEST_DIR")
    [[ "$result" == "{"* ]]
    [[ "$result" == *"total"* ]]
}

@test "project_deps counts npm dependencies" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"dependencies":{"react":"18","next":"14"},"devDependencies":{"vitest":"1.0"}}
EOF
    local result
    result=$(project_deps "$TEST_DIR")
    [[ "$result" == *'"production":2'* ]]
    [[ "$result" == *'"development":1'* ]]
}

@test "project_deps detects notable packages" {
    cat > "$TEST_DIR/package.json" << 'EOF'
{"dependencies":{"react":"18","next":"14","tailwindcss":"3"}}
EOF
    local result
    result=$(project_deps "$TEST_DIR")
    [[ "$result" == *"react"* ]]
    [[ "$result" == *"next"* ]]
    [[ "$result" == *"tailwindcss"* ]]
}

# =============================================================================
# project_structure TESTS
# =============================================================================

@test "project_structure returns JSON" {
    local result
    result=$(project_structure "$TEST_DIR")
    [[ "$result" == "{"* ]]
    [[ "$result" == *"directories"* ]]
}

@test "project_structure lists directories" {
    mkdir -p "$TEST_DIR/src" "$TEST_DIR/tests" "$TEST_DIR/docs"
    local result
    result=$(project_structure "$TEST_DIR")
    [[ "$result" == *"src"* ]]
    [[ "$result" == *"tests"* ]]
    [[ "$result" == *"docs"* ]]
}

@test "project_structure skips node_modules" {
    mkdir -p "$TEST_DIR/src" "$TEST_DIR/node_modules"
    local result
    result=$(project_structure "$TEST_DIR")
    [[ "$result" != *"node_modules"* ]]
}

@test "project_structure counts files" {
    touch "$TEST_DIR/a.ts" "$TEST_DIR/b.ts" "$TEST_DIR/c.js"
    local result
    result=$(project_structure "$TEST_DIR")
    [[ "$result" == *"file_count"* ]]
}
