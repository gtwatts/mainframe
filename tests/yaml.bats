#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: YAML Parser Library Tests
# =============================================================================
# Tests for lib/yaml.sh - YAML parsing, key access, sections, JSON conversion
# =============================================================================

load 'test_helper'

setup() {
    source_lib "yaml"
    FIXTURES="${BATS_TEST_DIRNAME}/fixtures/yaml"
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "yaml_parse: returns error for missing file" {
    run yaml_parse "/nonexistent/file.yml"
    [[ $status -eq 1 ]]
    [[ "$output" == *"file not found"* ]]
}

@test "yaml_parse: returns error for empty path" {
    run yaml_parse ""
    [[ $status -eq 1 ]]
    [[ "$output" == *"no file specified"* ]]
}

@test "yaml_get: returns 1 for missing key" {
    run yaml_get "$FIXTURES/simple.yml" "nonexistent"
    [[ $status -eq 1 ]]
}

@test "yaml_has: returns 1 for missing key" {
    run yaml_has "$FIXTURES/simple.yml" "nonexistent_key"
    [[ $status -eq 1 ]]
}

# =============================================================================
# SIMPLE KEY-VALUE TESTS
# =============================================================================

@test "yaml_parse: parses simple string value" {
    local result
    result=$(yaml_parse "$FIXTURES/simple.yml")
    assert_contains "$result" "name=myapp"
}

@test "yaml_parse: parses integer value" {
    local result
    result=$(yaml_parse "$FIXTURES/simple.yml")
    assert_contains "$result" "port=8080"
}

@test "yaml_parse: parses boolean value" {
    local result
    result=$(yaml_parse "$FIXTURES/simple.yml")
    assert_contains "$result" "debug=true"
}

@test "yaml_parse: parses float value" {
    local result
    result=$(yaml_parse "$FIXTURES/simple.yml")
    assert_contains "$result" "rate=3.14"
}

@test "yaml_parse: parses quoted string value" {
    local result
    result=$(yaml_parse "$FIXTURES/simple.yml")
    assert_contains "$result" "description=A simple application"
}

@test "yaml_get: retrieves simple value" {
    local result
    result=$(yaml_get "$FIXTURES/simple.yml" "name")
    assert_equal "myapp" "$result"
}

@test "yaml_get: retrieves version" {
    local result
    result=$(yaml_get "$FIXTURES/simple.yml" "version")
    assert_equal "1.0.0" "$result"
}

@test "yaml_has: returns 0 for existing key" {
    yaml_has "$FIXTURES/simple.yml" "name"
}

@test "yaml_has: returns 0 for nested key" {
    yaml_has "$FIXTURES/docker-compose.yml" "services.web.image"
}

# =============================================================================
# NESTED STRUCTURE TESTS
# =============================================================================

@test "yaml_parse: parses nested mappings" {
    local result
    result=$(yaml_parse "$FIXTURES/docker-compose.yml")
    assert_contains "$result" "services.web.image=nginx:latest"
}

@test "yaml_parse: parses deeply nested values" {
    local result
    result=$(yaml_parse "$FIXTURES/docker-compose.yml")
    assert_contains "$result" "services.web.environment.NODE_ENV=production"
}

@test "yaml_get: retrieves nested value" {
    local result
    result=$(yaml_get "$FIXTURES/docker-compose.yml" "services.web.image")
    assert_equal "nginx:latest" "$result"
}

@test "yaml_get: retrieves deeply nested value" {
    local result
    result=$(yaml_get "$FIXTURES/docker-compose.yml" "services.api.environment.DATABASE_URL")
    assert_equal "postgres://user:pass@db:5432/mydb" "$result"
}

# =============================================================================
# SEQUENCE (ARRAY) TESTS
# =============================================================================

@test "yaml_parse: parses block sequences" {
    local result
    result=$(yaml_parse "$FIXTURES/docker-compose.yml")
    assert_contains "$result" 'services.web.ports[0]=8080:80'
    assert_contains "$result" 'services.web.ports[1]=443:443'
}

@test "yaml_get_array: returns sequence elements" {
    local result
    result=$(yaml_get_array "$FIXTURES/docker-compose.yml" "services.web.ports")
    assert_contains "$result" '8080:80'
    assert_contains "$result" '443:443'
}

@test "yaml_array_length: counts sequence items" {
    local result
    result=$(yaml_array_length "$FIXTURES/docker-compose.yml" "services.web.ports")
    assert_equal "2" "$result"
}

@test "yaml_parse: parses depends_on list" {
    local result
    result=$(yaml_parse "$FIXTURES/docker-compose.yml")
    assert_contains "$result" "services.web.depends_on[0]=api"
    assert_contains "$result" "services.web.depends_on[1]=db"
}

# =============================================================================
# FLOW COLLECTION TESTS
# =============================================================================

@test "yaml_parse: parses flow sequences" {
    local result
    result=$(yaml_parse "$FIXTURES/flow.yml")
    assert_contains "$result" "ports[0]=8080"
    assert_contains "$result" "ports[1]=8081"
    assert_contains "$result" "ports[2]=8082"
}

@test "yaml_parse: parses flow sequences with quoted strings" {
    local result
    result=$(yaml_parse "$FIXTURES/flow.yml")
    assert_contains "$result" "tags[0]=web"
    assert_contains "$result" "tags[1]=api"
    assert_contains "$result" "tags[2]=v2"
}

@test "yaml_parse: parses flow mappings" {
    local result
    result=$(yaml_parse "$FIXTURES/flow.yml")
    assert_contains "$result" "config.host=localhost"
    assert_contains "$result" "config.port=3000"
    assert_contains "$result" "config.debug=true"
}

@test "yaml_parse: parses nested flow sequences" {
    local result
    result=$(yaml_parse "$FIXTURES/flow.yml")
    assert_contains "$result" "nested.items[0]=one"
    assert_contains "$result" "nested.items[1]=two"
    assert_contains "$result" "nested.items[2]=three"
}

@test "yaml_parse: parses nested flow mappings" {
    local result
    result=$(yaml_parse "$FIXTURES/flow.yml")
    assert_contains "$result" "nested.settings.timeout=30"
    assert_contains "$result" "nested.settings.retries=3"
}

# =============================================================================
# MULTILINE STRING TESTS
# =============================================================================

@test "yaml_parse: parses literal block scalar" {
    local result
    result=$(yaml_parse "$FIXTURES/multiline.yml")
    assert_contains "$result" "literal_block="
}

@test "yaml_parse: parses folded block scalar" {
    local result
    result=$(yaml_parse "$FIXTURES/multiline.yml")
    assert_contains "$result" "folded_block="
}

@test "yaml_get: retrieves value after multiline block" {
    local result
    result=$(yaml_get "$FIXTURES/multiline.yml" "simple_key")
    assert_equal "simple_value" "$result"
}

@test "yaml_get: retrieves nested value after multiline" {
    local result
    result=$(yaml_get "$FIXTURES/multiline.yml" "nested.child")
    assert_equal "value" "$result"
}

# =============================================================================
# SECTION/SUBTREE TESTS
# =============================================================================

@test "yaml_get_section: returns subtree pairs" {
    local result
    result=$(yaml_get_section "$FIXTURES/docker-compose.yml" "services.web")
    assert_contains "$result" "image=nginx:latest"
}

@test "yaml_get_section: returns environment subtree" {
    local result
    result=$(yaml_get_section "$FIXTURES/docker-compose.yml" "services.web.environment")
    assert_contains "$result" "NODE_ENV=production"
}

# =============================================================================
# KEYS FUNCTION TESTS
# =============================================================================

@test "yaml_keys: lists top-level keys" {
    local result
    result=$(yaml_keys "$FIXTURES/simple.yml")
    assert_contains "$result" "name"
    assert_contains "$result" "version"
    assert_contains "$result" "port"
}

@test "yaml_keys_at: lists keys at parent path" {
    local result
    result=$(yaml_keys_at "$FIXTURES/docker-compose.yml" "services")
    assert_contains "$result" "web"
    assert_contains "$result" "api"
    assert_contains "$result" "db"
    assert_contains "$result" "redis"
}

# =============================================================================
# GITHUB ACTIONS TESTS (real-world)
# =============================================================================

@test "yaml_get: reads GitHub Actions workflow name" {
    local result
    result=$(yaml_get "$FIXTURES/github-actions.yml" "name")
    assert_equal "CI Pipeline" "$result"
}

@test "yaml_parse: parses GitHub Actions on.push.branches" {
    local result
    result=$(yaml_parse "$FIXTURES/github-actions.yml")
    assert_contains "$result" "on.push.branches[0]=main"
    assert_contains "$result" "on.push.branches[1]=develop"
}

@test "yaml_get: reads GitHub Actions env variable" {
    local result
    result=$(yaml_get "$FIXTURES/github-actions.yml" "env.NODE_VERSION")
    assert_equal '20' "$result"
}

@test "yaml_parse: parses jobs structure" {
    local result
    result=$(yaml_parse "$FIXTURES/github-actions.yml")
    assert_contains "$result" "jobs.test.runs-on=ubuntu-latest"
}

@test "yaml_parse: parses matrix values" {
    local result
    result=$(yaml_parse "$FIXTURES/github-actions.yml")
    assert_contains "$result" "jobs.test.strategy.matrix.node-version[0]=18"
    assert_contains "$result" "jobs.test.strategy.matrix.node-version[1]=20"
    assert_contains "$result" "jobs.test.strategy.matrix.node-version[2]=22"
}

# =============================================================================
# KUBERNETES TESTS (real-world)
# =============================================================================

@test "yaml_get: reads k8s apiVersion" {
    local result
    result=$(yaml_get "$FIXTURES/kubernetes.yml" "apiVersion")
    assert_equal "apps/v1" "$result"
}

@test "yaml_get: reads k8s kind" {
    local result
    result=$(yaml_get "$FIXTURES/kubernetes.yml" "kind")
    assert_equal "Deployment" "$result"
}

@test "yaml_get: reads k8s metadata.name" {
    local result
    result=$(yaml_get "$FIXTURES/kubernetes.yml" "metadata.name")
    assert_equal "web-app" "$result"
}

@test "yaml_get: reads k8s replicas" {
    local result
    result=$(yaml_get "$FIXTURES/kubernetes.yml" "spec.replicas")
    assert_equal "3" "$result"
}

@test "yaml_parse: parses k8s labels" {
    local result
    result=$(yaml_parse "$FIXTURES/kubernetes.yml")
    assert_contains "$result" "metadata.labels.app=web-app"
    assert_contains "$result" "metadata.labels.tier=frontend"
}

# =============================================================================
# DOCKER COMPOSE TESTS (real-world)
# =============================================================================

@test "yaml_get: reads compose version" {
    local result
    result=$(yaml_get "$FIXTURES/docker-compose.yml" "version")
    assert_equal '3.8' "$result"
}

@test "yaml_get: reads compose service build" {
    local result
    result=$(yaml_get "$FIXTURES/docker-compose.yml" "services.api.build")
    assert_equal "./api" "$result"
}

@test "yaml_parse: parses compose redis ports" {
    local result
    result=$(yaml_parse "$FIXTURES/docker-compose.yml")
    assert_contains "$result" 'services.redis.ports[0]=6379:6379'
}

@test "yaml_get: reads compose postgres env" {
    local result
    result=$(yaml_get "$FIXTURES/docker-compose.yml" "services.db.environment.POSTGRES_DB")
    assert_equal "mydb" "$result"
}

# =============================================================================
# JSON CONVERSION TESTS
# =============================================================================

@test "yaml_to_json: converts simple values" {
    local result
    result=$(yaml_to_json "$FIXTURES/simple.yml")
    assert_contains "$result" '"name":"myapp"'
    assert_contains "$result" '"port":8080'
}

@test "yaml_to_json: converts boolean values" {
    local result
    result=$(yaml_to_json "$FIXTURES/simple.yml")
    assert_contains "$result" '"debug":true'
}

@test "yaml_to_json: returns valid JSON structure" {
    local result
    result=$(yaml_to_json "$FIXTURES/simple.yml")
    assert_starts_with "$result" "{"
    assert_ends_with "$result" "}"
}

@test "yaml_to_json: returns empty object for empty file" {
    local tmpfile
    tmpfile=$(mktemp)
    printf '' > "$tmpfile"
    local result
    result=$(yaml_to_json "$tmpfile")
    assert_equal "{}" "$result"
    rm -f "$tmpfile"
}

# =============================================================================
# ANCHOR/ALIAS TESTS
# =============================================================================

@test "yaml_parse: handles anchors and aliases" {
    local result
    result=$(yaml_parse "$FIXTURES/anchors.yml")
    assert_contains "$result" "defaults.timeout=30"
    assert_contains "$result" "defaults.retries=3"
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "yaml_parse: handles comments correctly" {
    local tmpfile
    tmpfile=$(mktemp)
    printf '# Full line comment\nkey: value # inline comment\n' > "$tmpfile"
    local result
    result=$(yaml_parse "$tmpfile")
    assert_contains "$result" "key=value"
    rm -f "$tmpfile"
}

@test "yaml_parse: handles empty file" {
    local tmpfile
    tmpfile=$(mktemp)
    printf '' > "$tmpfile"
    local result
    result=$(yaml_parse "$tmpfile")
    [[ -z "$result" ]]
    rm -f "$tmpfile"
}

@test "yaml_parse: skips blank lines" {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'a: 1\n\n\nb: 2\n' > "$tmpfile"
    local result
    result=$(yaml_parse "$tmpfile")
    assert_contains "$result" "a=1"
    assert_contains "$result" "b=2"
    rm -f "$tmpfile"
}

@test "yaml_parse: handles document separator" {
    local tmpfile
    tmpfile=$(mktemp)
    printf '%s\n' '---' 'name: first' 'version: 1' '---' 'name: second' > "$tmpfile"
    local result
    result=$(yaml_parse "$tmpfile")
    assert_contains "$result" "name=first"
    # Should NOT contain second document
    [[ "$result" != *"name=second"* ]]
    rm -f "$tmpfile"
}

@test "yaml_parse: handles null values" {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'empty: ~\nnull_val: null\nblank:\n' > "$tmpfile"
    local result
    result=$(yaml_parse "$tmpfile")
    assert_contains "$result" "empty="
    assert_contains "$result" "null_val="
    rm -f "$tmpfile"
}

@test "yaml_array_length: returns 0 for non-array" {
    local result
    result=$(yaml_array_length "$FIXTURES/simple.yml" "name")
    assert_equal "0" "$result"
}

@test "yaml_keys: returns 1 for missing file" {
    run yaml_keys "/nonexistent"
    [[ $status -eq 1 ]]
}
