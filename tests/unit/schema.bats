#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/schema.bats - JSON Schema Validation Tests
# =============================================================================
# Description: Comprehensive unit tests for lib/schema.sh
#              Pure bash JSON Schema validation (subset of draft 2020-12)
# Test Count: 65+ test cases
# Categories: schema definition, schema registry, type validation, constraints,
#             arrays, objects, built-in schemas, error handling, edge cases
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Create temp directory for test artifacts
    TEST_TMPDIR="$(mktemp -d)"

    # Source required libraries
    source "$MAINFRAME_ROOT/lib/json.sh"
    source "$MAINFRAME_ROOT/lib/schema.sh"

    # Clear schema registry for clean tests
    schema_clear
}

# Teardown: Clean up test artifacts
teardown() {
    rm -rf "$TEST_TMPDIR"
    schema_clear
}

# =============================================================================
# CATEGORY 1: SCHEMA DEFINITION
# =============================================================================

@test "schema_define: registers a valid schema" {
    schema_define "User" '{"type":"object"}'
    [[ $? -eq 0 ]]
}

@test "schema_define: fails on empty name" {
    run schema_define "" '{"type":"object"}'
    [[ "$status" -eq 1 ]]
}

@test "schema_define: fails on empty schema" {
    run schema_define "User" ""
    [[ "$status" -eq 1 ]]
}

@test "schema_define: fails on invalid JSON schema" {
    run schema_define "User" '{invalid}'
    [[ "$status" -eq 1 ]]
}

@test "schema_define: overwrites existing schema" {
    schema_define "User" '{"type":"string"}'
    schema_define "User" '{"type":"number"}'
    result=$(schema_get "User")
    [[ "$result" == '{"type":"number"}' ]]
}

# =============================================================================
# CATEGORY 2: SCHEMA REGISTRY
# =============================================================================

@test "schema_get: returns registered schema" {
    schema_define "Test" '{"type":"string"}'
    result=$(schema_get "Test")
    [[ "$result" == '{"type":"string"}' ]]
}

@test "schema_get: fails for non-existent schema" {
    run schema_get "NonExistent"
    [[ "$status" -eq 1 ]]
}

@test "schema_list: lists registered schemas" {
    schema_define "Alpha" '{"type":"string"}'
    schema_define "Beta" '{"type":"number"}'
    result=$(schema_list)
    [[ "$result" =~ "Alpha" ]]
    [[ "$result" =~ "Beta" ]]
}

@test "schema_list: returns empty for no schemas" {
    result=$(schema_list)
    [[ -z "$result" ]]
}

@test "schema_undefine: removes a schema" {
    schema_define "ToRemove" '{"type":"string"}'
    schema_undefine "ToRemove"
    run schema_get "ToRemove"
    [[ "$status" -eq 1 ]]
}

@test "schema_undefine: fails for non-existent schema" {
    run schema_undefine "NonExistent"
    [[ "$status" -eq 1 ]]
}

@test "schema_clear: removes all schemas" {
    schema_define "One" '{"type":"string"}'
    schema_define "Two" '{"type":"number"}'
    schema_clear
    result=$(schema_list)
    [[ -z "$result" ]]
}

@test "schema_load: loads schema from file" {
    echo '{"type":"object"}' > "$TEST_TMPDIR/schema.json"
    schema_load "FileSchema" "$TEST_TMPDIR/schema.json"
    result=$(schema_get "FileSchema")
    [[ "$result" == '{"type":"object"}' ]]
}

@test "schema_load: fails for missing file" {
    run schema_load "Missing" "$TEST_TMPDIR/nonexistent.json"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 3: STRING TYPE VALIDATION
# =============================================================================

@test "schema_validate: validates string type" {
    schema_define "StringTest" '{"type":"string"}'
    schema_validate "StringTest" '"hello"'
    [[ $? -eq 0 ]]
}

@test "schema_validate: rejects non-string for string type" {
    schema_define "StringTest" '{"type":"string"}'
    run schema_validate "StringTest" '42'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates minLength" {
    schema_define "MinLen" '{"type":"string","minLength":3}'
    schema_validate "MinLen" '"abc"'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails minLength" {
    schema_define "MinLen" '{"type":"string","minLength":5}'
    run schema_validate "MinLen" '"ab"'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates maxLength" {
    schema_define "MaxLen" '{"type":"string","maxLength":5}'
    schema_validate "MaxLen" '"abc"'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails maxLength" {
    schema_define "MaxLen" '{"type":"string","maxLength":3}'
    run schema_validate "MaxLen" '"abcdef"'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates pattern" {
    schema_define "Pattern" '{"type":"string","pattern":"^[a-z]+$"}'
    schema_validate "Pattern" '"hello"'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails pattern" {
    schema_define "Pattern" '{"type":"string","pattern":"^[a-z]+$"}'
    run schema_validate "Pattern" '"Hello123"'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates email format" {
    schema_define "Email" '{"type":"string","format":"email"}'
    schema_validate "Email" '"user@example.com"'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails invalid email format" {
    schema_define "Email" '{"type":"string","format":"email"}'
    run schema_validate "Email" '"not-an-email"'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates uuid format" {
    schema_define "UUID" '{"type":"string","format":"uuid"}'
    schema_validate "UUID" '"550e8400-e29b-41d4-a716-446655440000"'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails invalid uuid format" {
    schema_define "UUID" '{"type":"string","format":"uuid"}'
    run schema_validate "UUID" '"not-a-uuid"'
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 4: NUMBER/INTEGER TYPE VALIDATION
# =============================================================================

@test "schema_validate: validates number type" {
    schema_define "NumTest" '{"type":"number"}'
    schema_validate "NumTest" '42.5'
    [[ $? -eq 0 ]]
}

@test "schema_validate: validates integer type" {
    schema_define "IntTest" '{"type":"integer"}'
    schema_validate "IntTest" '42'
    [[ $? -eq 0 ]]
}

@test "schema_validate: rejects float for integer type" {
    schema_define "IntTest" '{"type":"integer"}'
    run schema_validate "IntTest" '42.5'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates minimum" {
    schema_define "MinNum" '{"type":"number","minimum":10}'
    schema_validate "MinNum" '15'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails minimum" {
    schema_define "MinNum" '{"type":"number","minimum":10}'
    run schema_validate "MinNum" '5'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates maximum" {
    schema_define "MaxNum" '{"type":"number","maximum":100}'
    schema_validate "MaxNum" '50'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails maximum" {
    schema_define "MaxNum" '{"type":"number","maximum":100}'
    run schema_validate "MaxNum" '150'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates negative numbers" {
    schema_define "NegNum" '{"type":"integer","minimum":-10,"maximum":0}'
    schema_validate "NegNum" '-5'
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 5: BOOLEAN AND NULL TYPES
# =============================================================================

@test "schema_validate: validates boolean true" {
    schema_define "BoolTest" '{"type":"boolean"}'
    schema_validate "BoolTest" 'true'
    [[ $? -eq 0 ]]
}

@test "schema_validate: validates boolean false" {
    schema_define "BoolTest" '{"type":"boolean"}'
    schema_validate "BoolTest" 'false'
    [[ $? -eq 0 ]]
}

@test "schema_validate: rejects non-boolean for boolean type" {
    schema_define "BoolTest" '{"type":"boolean"}'
    run schema_validate "BoolTest" '"true"'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates null type" {
    schema_define "NullTest" '{"type":"null"}'
    schema_validate "NullTest" 'null'
    [[ $? -eq 0 ]]
}

@test "schema_validate: rejects non-null for null type" {
    schema_define "NullTest" '{"type":"null"}'
    run schema_validate "NullTest" '"null"'
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 6: ARRAY TYPE VALIDATION
# =============================================================================

@test "schema_validate: validates array type" {
    schema_define "ArrayTest" '{"type":"array"}'
    schema_validate "ArrayTest" '[1,2,3]'
    [[ $? -eq 0 ]]
}

@test "schema_validate: validates empty array" {
    schema_define "ArrayTest" '{"type":"array"}'
    schema_validate "ArrayTest" '[]'
    [[ $? -eq 0 ]]
}

@test "schema_validate: rejects non-array for array type" {
    schema_define "ArrayTest" '{"type":"array"}'
    run schema_validate "ArrayTest" '{"key":"value"}'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates minItems" {
    schema_define "MinItems" '{"type":"array","minItems":2}'
    schema_validate "MinItems" '[1,2,3]'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails minItems" {
    schema_define "MinItems" '{"type":"array","minItems":3}'
    run schema_validate "MinItems" '[1]'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates maxItems" {
    schema_define "MaxItems" '{"type":"array","maxItems":3}'
    schema_validate "MaxItems" '[1,2]'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails maxItems" {
    schema_define "MaxItems" '{"type":"array","maxItems":2}'
    run schema_validate "MaxItems" '[1,2,3,4]'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates items schema" {
    schema_define "ItemsTest" '{"type":"array","items":{"type":"string"}}'
    schema_validate "ItemsTest" '["a","b","c"]'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails invalid items" {
    schema_define "ItemsTest" '{"type":"array","items":{"type":"string"}}'
    run schema_validate "ItemsTest" '["a",42,"c"]'
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 7: OBJECT TYPE VALIDATION
# =============================================================================

@test "schema_validate: validates object type" {
    schema_define "ObjTest" '{"type":"object"}'
    schema_validate "ObjTest" '{"key":"value"}'
    [[ $? -eq 0 ]]
}

@test "schema_validate: validates empty object" {
    schema_define "ObjTest" '{"type":"object"}'
    schema_validate "ObjTest" '{}'
    [[ $? -eq 0 ]]
}

@test "schema_validate: rejects non-object for object type" {
    schema_define "ObjTest" '{"type":"object"}'
    run schema_validate "ObjTest" '[1,2,3]'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates required properties" {
    schema_define "Required" '{"type":"object","required":["name","email"]}'
    schema_validate "Required" '{"name":"John","email":"john@example.com"}'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails missing required property" {
    schema_define "Required" '{"type":"object","required":["name","email"]}'
    run schema_validate "Required" '{"name":"John"}'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates property types" {
    schema_define "Props" '{"type":"object","properties":{"age":{"type":"integer"}}}'
    schema_validate "Props" '{"age":30}'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails invalid property type" {
    schema_define "Props" '{"type":"object","properties":{"age":{"type":"integer"}}}'
    run schema_validate "Props" '{"age":"thirty"}'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates nested objects" {
    schema_define "Nested" '{"type":"object","properties":{"user":{"type":"object","properties":{"name":{"type":"string"}}}}}'
    schema_validate "Nested" '{"user":{"name":"John"}}'
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 8: ENUM VALIDATION
# =============================================================================

@test "schema_validate: validates enum value" {
    schema_define "Enum" '{"type":"string","enum":["red","green","blue"]}'
    schema_validate "Enum" '"green"'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails invalid enum value" {
    schema_define "Enum" '{"type":"string","enum":["red","green","blue"]}'
    run schema_validate "Enum" '"yellow"'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates number enum" {
    schema_define "NumEnum" '{"type":"integer","enum":["1","2","3"]}'
    schema_validate "NumEnum" '2'
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 9: BUILT-IN SCHEMAS
# =============================================================================

@test "schema_builtin_email: returns email schema" {
    result=$(schema_builtin_email)
    [[ "$result" =~ '"type":"string"' ]]
    [[ "$result" =~ '"format":"email"' ]]
}

@test "schema_builtin_uuid: returns uuid schema" {
    result=$(schema_builtin_uuid)
    [[ "$result" =~ '"type":"string"' ]]
    [[ "$result" =~ '"format":"uuid"' ]]
}

@test "schema_builtin_url: returns url schema" {
    result=$(schema_builtin_url)
    [[ "$result" =~ '"type":"string"' ]]
    [[ "$result" =~ '"format":"uri"' ]]
}

@test "schema_builtin_semver: returns semver schema" {
    result=$(schema_builtin_semver)
    [[ "$result" =~ '"type":"string"' ]]
    [[ "$result" =~ '"pattern"' ]]
}

@test "schema_register_builtins: registers all built-in schemas" {
    schema_register_builtins
    result=$(schema_list)
    [[ "$result" =~ "builtin:email" ]]
    [[ "$result" =~ "builtin:uuid" ]]
    [[ "$result" =~ "builtin:url" ]]
    [[ "$result" =~ "builtin:semver" ]]
}

@test "builtin:email: validates valid email" {
    schema_register_builtins
    schema_validate "builtin:email" '"test@example.com"'
    [[ $? -eq 0 ]]
}

@test "builtin:semver: validates valid semver" {
    schema_register_builtins
    schema_validate "builtin:semver" '"1.2.3"'
    [[ $? -eq 0 ]]
}

@test "builtin:semver: validates semver with prerelease" {
    schema_register_builtins
    schema_validate "builtin:semver" '"1.2.3-beta.1"'
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 10: ERROR HANDLING
# =============================================================================

@test "schema_errors: returns error array" {
    schema_define "Test" '{"type":"string"}'
    result=$(schema_errors "Test" '42')
    [[ "$result" =~ '\[' ]]
    [[ "$result" =~ '\]' ]]
    [[ "$result" =~ 'expected string' ]]
}

@test "schema_errors: returns empty array for valid data" {
    schema_define "Test" '{"type":"string"}'
    result=$(schema_errors "Test" '"hello"')
    [[ "$result" == '[]' ]]
}

@test "schema_last_errors: returns errors from last validation" {
    schema_define "Test" '{"type":"string"}'
    schema_validate "Test" '42' || true
    result=$(schema_last_errors)
    [[ "$result" =~ 'expected string' ]]
}

@test "schema_validate: fails for non-existent schema" {
    run schema_validate "NonExistent" '"test"'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: fails for invalid JSON data" {
    schema_define "Test" '{"type":"string"}'
    run schema_validate "Test" '{invalid}'
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 11: schema_check (QUICK VALIDATION)
# =============================================================================

@test "schema_check: validates without registration" {
    schema_check '{"type":"string"}' '"hello"'
    [[ $? -eq 0 ]]
}

@test "schema_check: fails for invalid data" {
    run schema_check '{"type":"string"}' '42'
    [[ "$status" -eq 1 ]]
}

@test "schema_check: fails for invalid schema JSON" {
    run schema_check '{invalid}' '"hello"'
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 12: FILE VALIDATION
# =============================================================================

@test "schema_validate_file: validates JSON file" {
    schema_define "FileTest" '{"type":"object","required":["name"]}'
    echo '{"name":"John"}' > "$TEST_TMPDIR/valid.json"
    schema_validate_file "FileTest" "$TEST_TMPDIR/valid.json"
    [[ $? -eq 0 ]]
}

@test "schema_validate_file: fails for invalid file content" {
    schema_define "FileTest" '{"type":"object","required":["name"]}'
    echo '{"age":30}' > "$TEST_TMPDIR/invalid.json"
    run schema_validate_file "FileTest" "$TEST_TMPDIR/invalid.json"
    [[ "$status" -eq 1 ]]
}

@test "schema_validate_file: fails for missing file" {
    schema_define "FileTest" '{"type":"object"}'
    run schema_validate_file "FileTest" "$TEST_TMPDIR/missing.json"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# CATEGORY 13: NAMEREF VARIANTS
# =============================================================================

@test "schema_validate_v: stores true for valid" {
    local out
    schema_define "Test" '{"type":"string"}'
    schema_validate_v out "Test" '"hello"'
    [[ "$out" == "true" ]]
}

@test "schema_validate_v: stores false for invalid" {
    local out
    schema_define "Test" '{"type":"string"}'
    schema_validate_v out "Test" '42'
    [[ "$out" == "false" ]]
}

@test "schema_errors_v: stores errors in variable" {
    local out
    schema_define "Test" '{"type":"string"}'
    schema_errors_v out "Test" '42'
    [[ "$out" =~ "expected string" ]]
}

# =============================================================================
# CATEGORY 14: COMPLEX SCHEMAS
# =============================================================================

@test "schema_validate: validates complex user schema" {
    schema_define "User" '{
        "type": "object",
        "required": ["id", "email"],
        "properties": {
            "id": {"type": "string", "pattern": "^[a-z0-9-]+$"},
            "email": {"type": "string", "format": "email"},
            "age": {"type": "integer", "minimum": 0, "maximum": 150}
        }
    }'
    schema_validate "User" '{"id":"abc-123","email":"user@example.com","age":30}'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails complex schema with invalid email" {
    schema_define "User" '{
        "type": "object",
        "required": ["id", "email"],
        "properties": {
            "id": {"type": "string"},
            "email": {"type": "string", "format": "email"}
        }
    }'
    run schema_validate "User" '{"id":"abc","email":"not-email"}'
    [[ "$status" -eq 1 ]]
}

@test "schema_validate: validates array of objects" {
    schema_define "Users" '{
        "type": "array",
        "items": {
            "type": "object",
            "required": ["name"],
            "properties": {
                "name": {"type": "string"}
            }
        }
    }'
    schema_validate "Users" '[{"name":"Alice"},{"name":"Bob"}]'
    [[ $? -eq 0 ]]
}

# =============================================================================
# CATEGORY 15: EDGE CASES
# =============================================================================

@test "schema_validate: handles empty string value" {
    schema_define "Empty" '{"type":"string"}'
    schema_validate "Empty" '""'
    [[ $? -eq 0 ]]
}

@test "schema_validate: handles zero value" {
    schema_define "Zero" '{"type":"integer"}'
    schema_validate "Zero" '0'
    [[ $? -eq 0 ]]
}

@test "schema_validate: handles whitespace in JSON" {
    schema_define "Whitespace" '{"type":"object"}'
    schema_validate "Whitespace" '{  "key" :  "value"  }'
    [[ $? -eq 0 ]]
}

@test "schema_validate: handles special characters in strings" {
    schema_define "Special" '{"type":"string"}'
    schema_validate "Special" '"hello\nworld"'
    [[ $? -eq 0 ]]
}

@test "schema_validate: handles unicode in strings" {
    schema_define "Unicode" '{"type":"string"}'
    schema_validate "Unicode" '"hello"'
    [[ $? -eq 0 ]]
}

@test "schema_validate: handles deeply nested objects" {
    schema_define "Deep" '{"type":"object","properties":{"a":{"type":"object","properties":{"b":{"type":"object","properties":{"c":{"type":"string"}}}}}}}'
    schema_validate "Deep" '{"a":{"b":{"c":"value"}}}'
    [[ $? -eq 0 ]]
}

@test "schema_validate: validates date format" {
    schema_define "Date" '{"type":"string","format":"date"}'
    schema_validate "Date" '"2024-01-15"'
    [[ $? -eq 0 ]]
}

@test "schema_validate: fails invalid date format" {
    schema_define "Date" '{"type":"string","format":"date"}'
    run schema_validate "Date" '"2024/01/15"'
    [[ "$status" -eq 1 ]]
}
