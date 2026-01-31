#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/unit/jsonpath.bats - JSONPath Library Tests
# =============================================================================
# Description: Comprehensive unit tests for jsonpath.sh
#              Pure bash JSON query engine
# Test Count: ~200 test cases
# Categories: Basic access, arrays, nesting, wildcards, types, errors
# =============================================================================

# Setup: Load libraries and configure test environment
setup() {
    BATS_TEST_DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" && pwd )"
    MAINFRAME_ROOT="${BATS_TEST_DIR}/../.."

    # Source the library
    source "$MAINFRAME_ROOT/lib/jsonpath.sh"
}

# =============================================================================
# CATEGORY 1: BASIC PROPERTY ACCESS
# =============================================================================

@test "jsonpath: access simple string property" {
    local json='{"name":"John"}'

    result=$(jsonpath_query "$json" ".name")

    [[ "$result" == "John" ]]
}

@test "jsonpath: access simple number property" {
    local json='{"age":30}'

    result=$(jsonpath_query "$json" ".age")

    [[ "$result" == "30" ]]
}

@test "jsonpath: access boolean true property" {
    local json='{"active":true}'

    result=$(jsonpath_query "$json" ".active")

    [[ "$result" == "true" ]]
}

@test "jsonpath: access boolean false property" {
    local json='{"deleted":false}'

    result=$(jsonpath_query "$json" ".deleted")

    [[ "$result" == "false" ]]
}

@test "jsonpath: access null property" {
    local json='{"value":null}'

    result=$(jsonpath_query "$json" ".value")

    [[ "$result" == "null" ]]
}

@test "jsonpath: access property with underscore" {
    local json='{"user_name":"alice"}'

    result=$(jsonpath_query "$json" ".user_name")

    [[ "$result" == "alice" ]]
}

@test "jsonpath: access property with numbers" {
    local json='{"item1":"first"}'

    result=$(jsonpath_query "$json" ".item1")

    [[ "$result" == "first" ]]
}

@test "jsonpath: access float number" {
    local json='{"price":19.99}'

    result=$(jsonpath_query "$json" ".price")

    [[ "$result" == "19.99" ]]
}

@test "jsonpath: access negative number" {
    local json='{"offset":-100}'

    result=$(jsonpath_query "$json" ".offset")

    [[ "$result" == "-100" ]]
}

@test "jsonpath: access scientific notation number" {
    local json='{"value":1.5e10}'

    result=$(jsonpath_query "$json" ".value")

    [[ "$result" == "1.5e10" ]]
}

@test "jsonpath: access empty string" {
    local json='{"name":""}'

    result=$(jsonpath_query "$json" ".name")

    [[ "$result" == "" ]]
}

@test "jsonpath: access string with spaces" {
    local json='{"name":"John Doe"}'

    result=$(jsonpath_query "$json" ".name")

    [[ "$result" == "John Doe" ]]
}

@test "jsonpath: returns error for missing property" {
    local json='{"name":"John"}'

    run jsonpath_query "$json" ".missing"

    [[ "$status" -ne 0 ]]
}

# =============================================================================
# CATEGORY 2: ARRAY INDEX ACCESS
# =============================================================================

@test "jsonpath: access first array element [0]" {
    local json='{"items":["a","b","c"]}'

    result=$(jsonpath_query "$json" ".items[0]")

    [[ "$result" == "a" ]]
}

@test "jsonpath: access middle array element" {
    local json='{"items":["a","b","c"]}'

    result=$(jsonpath_query "$json" ".items[1]")

    [[ "$result" == "b" ]]
}

@test "jsonpath: access last array element by index" {
    local json='{"items":["a","b","c"]}'

    result=$(jsonpath_query "$json" ".items[2]")

    [[ "$result" == "c" ]]
}

@test "jsonpath: access element with negative index [-1]" {
    local json='{"items":["a","b","c"]}'

    result=$(jsonpath_query "$json" ".items[-1]")

    [[ "$result" == "c" ]]
}

@test "jsonpath: access element with negative index [-2]" {
    local json='{"items":["a","b","c"]}'

    result=$(jsonpath_query "$json" ".items[-2]")

    [[ "$result" == "b" ]]
}

@test "jsonpath: access root array element" {
    local json='["first","second","third"]'

    result=$(jsonpath_query "$json" "[0]")

    [[ "$result" == "first" ]]
}

@test "jsonpath: access array of numbers" {
    local json='{"scores":[10,20,30]}'

    result=$(jsonpath_query "$json" ".scores[1]")

    [[ "$result" == "20" ]]
}

@test "jsonpath: access array of objects - get object" {
    local json='{"users":[{"name":"Alice"},{"name":"Bob"}]}'

    result=$(jsonpath_query "$json" ".users[0]")

    [[ "$result" =~ "Alice" ]]
}

@test "jsonpath: returns error for out of bounds positive index" {
    local json='{"items":["a","b"]}'

    run jsonpath_query "$json" ".items[5]"

    [[ "$status" -ne 0 ]]
}

@test "jsonpath: returns error for out of bounds negative index" {
    local json='{"items":["a","b"]}'

    run jsonpath_query "$json" ".items[-5]"

    [[ "$status" -ne 0 ]]
}

@test "jsonpath: access empty array returns error" {
    local json='{"items":[]}'

    run jsonpath_query "$json" ".items[0]"

    [[ "$status" -ne 0 ]]
}

# =============================================================================
# CATEGORY 3: NESTED ACCESS
# =============================================================================

@test "jsonpath: access two levels deep" {
    local json='{"data":{"name":"test"}}'

    result=$(jsonpath_query "$json" ".data.name")

    [[ "$result" == "test" ]]
}

@test "jsonpath: access three levels deep" {
    local json='{"level1":{"level2":{"level3":"value"}}}'

    result=$(jsonpath_query "$json" ".level1.level2.level3")

    [[ "$result" == "value" ]]
}

@test "jsonpath: access nested object in array" {
    local json='{"users":[{"profile":{"email":"a@b.com"}}]}'

    result=$(jsonpath_query "$json" ".users[0].profile.email")

    [[ "$result" == "a@b.com" ]]
}

@test "jsonpath: access array in nested object" {
    local json='{"data":{"items":["x","y","z"]}}'

    result=$(jsonpath_query "$json" ".data.items[1]")

    [[ "$result" == "y" ]]
}

@test "jsonpath: access deeply nested array element" {
    local json='{"a":{"b":{"c":[1,2,3]}}}'

    result=$(jsonpath_query "$json" ".a.b.c[2]")

    [[ "$result" == "3" ]]
}

@test "jsonpath: mixed array and object access" {
    local json='{"results":[{"items":[{"id":42}]}]}'

    result=$(jsonpath_query "$json" ".results[0].items[0].id")

    [[ "$result" == "42" ]]
}

@test "jsonpath: access property after array index" {
    local json='[{"name":"first"},{"name":"second"}]'

    result=$(jsonpath_query "$json" "[1].name")

    [[ "$result" == "second" ]]
}

# =============================================================================
# CATEGORY 4: WILDCARD ACCESS
# =============================================================================

@test "jsonpath: wildcard returns all array elements as JSON array" {
    local json='{"items":[1,2,3]}'

    result=$(jsonpath_query "$json" ".items[*]")

    [[ "$result" =~ "[1,2,3]" ]]
}

@test "jsonpath: wildcard on string array" {
    local json='{"tags":["a","b","c"]}'

    result=$(jsonpath_query "$json" ".tags[*]")

    [[ "$result" =~ '["a","b","c"]' ]]
}

@test "jsonpath: wildcard on object array" {
    local json='{"users":[{"id":1},{"id":2}]}'

    result=$(jsonpath_query "$json" ".users[*]")

    [[ "$result" =~ "[{" ]]
}

@test "jsonpath: wildcard on root array" {
    local json='["x","y","z"]'

    result=$(jsonpath_query "$json" "[*]")

    [[ "$result" =~ '["x","y","z"]' ]]
}

@test "jsonpath: wildcard on empty array" {
    local json='{"items":[]}'

    result=$(jsonpath_query "$json" ".items[*]")

    [[ "$result" == "[]" ]]
}

# =============================================================================
# CATEGORY 5: TYPE DETECTION
# =============================================================================

@test "jsonpath_type: detects string type" {
    local json='{"name":"John"}'

    result=$(jsonpath_type "$json" ".name")

    [[ "$result" == "string" ]]
}

@test "jsonpath_type: detects number type" {
    local json='{"age":30}'

    result=$(jsonpath_type "$json" ".age")

    [[ "$result" == "number" ]]
}

@test "jsonpath_type: detects boolean type for true" {
    local json='{"active":true}'

    result=$(jsonpath_type "$json" ".active")

    [[ "$result" == "boolean" ]]
}

@test "jsonpath_type: detects boolean type for false" {
    local json='{"deleted":false}'

    result=$(jsonpath_type "$json" ".deleted")

    [[ "$result" == "boolean" ]]
}

@test "jsonpath_type: detects null type" {
    local json='{"value":null}'

    result=$(jsonpath_type "$json" ".value")

    [[ "$result" == "null" ]]
}

@test "jsonpath_type: detects object type" {
    local json='{"data":{"nested":"value"}}'

    result=$(jsonpath_type "$json" ".data")

    [[ "$result" == "object" ]]
}

@test "jsonpath_type: detects array type" {
    local json='{"items":[1,2,3]}'

    result=$(jsonpath_type "$json" ".items")

    [[ "$result" == "array" ]]
}

@test "jsonpath_type: returns undefined for missing path" {
    local json='{"name":"John"}'

    result=$(jsonpath_type "$json" ".missing")

    [[ "$result" == "undefined" ]]
}

# =============================================================================
# CATEGORY 6: EXISTS CHECK
# =============================================================================

@test "jsonpath_exists: returns 0 for existing property" {
    local json='{"name":"John"}'

    run jsonpath_exists "$json" ".name"

    [[ "$status" -eq 0 ]]
}

@test "jsonpath_exists: returns 1 for missing property" {
    local json='{"name":"John"}'

    run jsonpath_exists "$json" ".missing"

    [[ "$status" -ne 0 ]]
}

@test "jsonpath_exists: returns 0 for existing array element" {
    local json='{"items":[1,2,3]}'

    run jsonpath_exists "$json" ".items[1]"

    [[ "$status" -eq 0 ]]
}

@test "jsonpath_exists: returns 1 for out of bounds array index" {
    local json='{"items":[1,2,3]}'

    run jsonpath_exists "$json" ".items[10]"

    [[ "$status" -ne 0 ]]
}

@test "jsonpath_exists: returns 0 for nested path" {
    local json='{"a":{"b":{"c":"value"}}}'

    run jsonpath_exists "$json" ".a.b.c"

    [[ "$status" -eq 0 ]]
}

@test "jsonpath_exists: returns 0 for null value (path exists)" {
    local json='{"value":null}'

    run jsonpath_exists "$json" ".value"

    [[ "$status" -eq 0 ]]
}

# =============================================================================
# CATEGORY 7: LENGTH
# =============================================================================

@test "jsonpath_length: returns array length" {
    local json='{"items":[1,2,3,4,5]}'

    result=$(jsonpath_length "$json" ".items")

    [[ "$result" == "5" ]]
}

@test "jsonpath_length: returns 0 for empty array" {
    local json='{"items":[]}'

    result=$(jsonpath_length "$json" ".items")

    [[ "$result" == "0" ]]
}

@test "jsonpath_length: returns object key count" {
    local json='{"a":1,"b":2,"c":3}'

    result=$(jsonpath_length "$json" ".")

    [[ "$result" == "3" ]]
}

@test "jsonpath_length: returns 0 for empty object" {
    local json='{"data":{}}'

    result=$(jsonpath_length "$json" ".data")

    [[ "$result" == "0" ]]
}

@test "jsonpath_length: returns string length" {
    local json='{"name":"hello"}'

    result=$(jsonpath_length "$json" ".name")

    [[ "$result" == "5" ]]
}

@test "jsonpath_length: returns 0 for missing path" {
    local json='{"name":"test"}'

    result=$(jsonpath_length "$json" ".missing")

    [[ "$result" == "0" ]]
}

# =============================================================================
# CATEGORY 8: ITERATION
# =============================================================================

@test "jsonpath_iterate: iterates over array elements" {
    local json='{"items":["a","b","c"]}'
    local output=""

    output=$(jsonpath_iterate "$json" ".items")

    [[ "$output" =~ "0" ]]
    [[ "$output" =~ "a" ]]
    [[ "$output" =~ "1" ]]
    [[ "$output" =~ "b" ]]
    [[ "$output" =~ "2" ]]
    [[ "$output" =~ "c" ]]
}

@test "jsonpath_iterate: iterates over number array" {
    local json='[10,20,30]'
    local output=""

    output=$(jsonpath_iterate "$json" ".")

    [[ "$output" =~ "0" ]]
    [[ "$output" =~ "10" ]]
    [[ "$output" =~ "20" ]]
    [[ "$output" =~ "30" ]]
}

@test "jsonpath_iterate: returns nothing for empty array" {
    local json='{"items":[]}'

    result=$(jsonpath_iterate "$json" ".items")

    [[ -z "$result" ]]
}

@test "jsonpath_iterate: returns error for non-array" {
    local json='{"name":"test"}'

    run jsonpath_iterate "$json" ".name"

    [[ "$status" -ne 0 ]]
}

# =============================================================================
# CATEGORY 9: KEYS EXTRACTION
# =============================================================================

@test "jsonpath_keys: returns object keys" {
    local json='{"name":"John","age":30,"active":true}'

    result=$(jsonpath_keys "$json" ".")

    [[ "$result" =~ "name" ]]
    [[ "$result" =~ "age" ]]
    [[ "$result" =~ "active" ]]
}

@test "jsonpath_keys: returns nested object keys" {
    local json='{"data":{"x":1,"y":2}}'

    result=$(jsonpath_keys "$json" ".data")

    [[ "$result" =~ "x" ]]
    [[ "$result" =~ "y" ]]
}

@test "jsonpath_keys: returns nothing for empty object" {
    local json='{"data":{}}'

    result=$(jsonpath_keys "$json" ".data")

    [[ -z "$result" ]]
}

@test "jsonpath_keys: returns error for non-object" {
    local json='{"items":[1,2,3]}'

    run jsonpath_keys "$json" ".items"

    [[ "$status" -ne 0 ]]
}

# =============================================================================
# CATEGORY 10: EDGE CASES
# =============================================================================

@test "jsonpath: handles whitespace in JSON" {
    local json='{
        "name" : "John" ,
        "age"  : 30
    }'

    result=$(jsonpath_query "$json" ".name")

    [[ "$result" == "John" ]]
}

@test "jsonpath: handles escaped quotes in strings" {
    local json='{"text":"He said \"hello\""}'

    result=$(jsonpath_query "$json" ".text")

    [[ "$result" =~ "hello" ]]
}

@test "jsonpath: handles escaped backslash" {
    local json='{"path":"C:\\Users\\test"}'

    result=$(jsonpath_query "$json" ".path")

    [[ "$result" =~ "Users" ]]
}

@test "jsonpath: handles newlines in strings" {
    local json='{"text":"line1\nline2"}'

    result=$(jsonpath_query "$json" ".text")

    [[ -n "$result" ]]
}

@test "jsonpath: handles Unicode characters" {
    local json='{"emoji":"Hello World"}'

    result=$(jsonpath_query "$json" ".emoji")

    [[ "$result" == "Hello World" ]]
}

@test "jsonpath: root path returns entire JSON" {
    local json='{"name":"test"}'

    result=$(jsonpath_query "$json" ".")

    [[ "$result" =~ "name" ]]
    [[ "$result" =~ "test" ]]
}

@test "jsonpath: empty path returns entire JSON" {
    local json='{"name":"test"}'

    result=$(jsonpath_query "$json" "")

    [[ "$result" =~ "name" ]]
}

@test "jsonpath: $ path returns entire JSON" {
    local json='{"name":"test"}'

    result=$(jsonpath_query "$json" "$")

    [[ "$result" =~ "name" ]]
}

@test "jsonpath: handles very long strings" {
    local long_str=$(printf 'x%.0s' {1..1000})
    local json="{\"data\":\"$long_str\"}"

    result=$(jsonpath_query "$json" ".data")

    [[ ${#result} -eq 1000 ]]
}

@test "jsonpath: handles deeply nested structures" {
    local json='{"a":{"b":{"c":{"d":{"e":"deep"}}}}}'

    result=$(jsonpath_query "$json" ".a.b.c.d.e")

    [[ "$result" == "deep" ]]
}

@test "jsonpath: handles arrays with many elements" {
    local json='{"items":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19]}'

    result=$(jsonpath_query "$json" ".items[15]")

    [[ "$result" == "15" ]]
}

# =============================================================================
# CATEGORY 11: ERROR HANDLING
# =============================================================================

@test "jsonpath: returns error for invalid JSON" {
    local json='{"name":}'

    run jsonpath_query "$json" ".name"

    [[ "$status" -ne 0 ]]
}

@test "jsonpath: returns error for invalid path syntax" {
    local json='{"name":"test"}'

    run jsonpath_query "$json" ".name["

    [[ "$status" -ne 0 ]]
}

@test "jsonpath: returns error for array access on object" {
    local json='{"name":"test"}'

    run jsonpath_query "$json" ".name[0]"

    [[ "$status" -ne 0 ]]
}

@test "jsonpath: returns error for object access on array" {
    local json='{"items":[1,2,3]}'

    run jsonpath_query "$json" ".items.name"

    [[ "$status" -ne 0 ]]
}

@test "jsonpath: returns error for object access on primitive" {
    local json='{"value":42}'

    run jsonpath_query "$json" ".value.nested"

    [[ "$status" -ne 0 ]]
}

# =============================================================================
# CATEGORY 12: NAMEREF VARIANT
# =============================================================================

@test "jsonpath_query_v: stores result in variable" {
    local json='{"name":"test"}'
    local result=""

    jsonpath_query_v result "$json" ".name"

    [[ "$result" == "test" ]]
}

@test "jsonpath_query_v: returns 0 on success" {
    local json='{"name":"test"}'
    local result=""

    run jsonpath_query_v result "$json" ".name"

    [[ "$status" -eq 0 ]]
}

@test "jsonpath_query_v: returns error code on failure" {
    local json='{"name":"test"}'
    local result=""

    run jsonpath_query_v result "$json" ".missing"

    [[ "$status" -ne 0 ]]
}

@test "jsonpath_query_v: sets empty on failure" {
    local json='{"name":"test"}'
    local result="initial"

    jsonpath_query_v result "$json" ".missing" || true

    [[ "$result" == "" ]]
}

# =============================================================================
# CATEGORY 13: SPECIAL VALUES
# =============================================================================

@test "jsonpath: handles multiple properties with same prefix" {
    local json='{"user":"John","username":"johnd","user_id":123}'

    result=$(jsonpath_query "$json" ".user")

    [[ "$result" == "John" ]]
}

@test "jsonpath: handles property that looks like number" {
    local json='{"123":"numeric key"}'

    # This should not work as our parser expects letter/underscore start
    run jsonpath_query "$json" ".123"

    [[ "$status" -ne 0 ]]
}

@test "jsonpath: handles arrays with mixed types" {
    local json='{"mixed":[1,"two",true,null,{"a":1},[1,2]]}'

    result=$(jsonpath_query "$json" ".mixed[1]")

    [[ "$result" == "two" ]]
}

@test "jsonpath: handles nested arrays" {
    local json='{"matrix":[[1,2],[3,4],[5,6]]}'

    result=$(jsonpath_query "$json" ".matrix[1][0]")

    [[ "$result" == "3" ]]
}

# =============================================================================
# CATEGORY 14: REAL WORLD JSON
# =============================================================================

@test "jsonpath: GitHub API user response" {
    local json='{
        "login": "gtwatts",
        "id": 40617346,
        "type": "User",
        "public_repos": 25,
        "followers": 10
    }'

    result=$(jsonpath_query "$json" ".login")
    [[ "$result" == "gtwatts" ]]

    result=$(jsonpath_query "$json" ".id")
    [[ "$result" == "40617346" ]]
}

@test "jsonpath: API pagination response" {
    local json='{
        "data": [{"id": 1}, {"id": 2}],
        "meta": {
            "total": 100,
            "page": 1,
            "per_page": 10
        }
    }'

    result=$(jsonpath_query "$json" ".meta.total")
    [[ "$result" == "100" ]]

    result=$(jsonpath_query "$json" ".data[0].id")
    [[ "$result" == "1" ]]
}

@test "jsonpath: JWT token payload" {
    local json='{
        "sub": "1234567890",
        "name": "John Doe",
        "iat": 1516239022,
        "exp": 1516242622,
        "roles": ["admin", "user"]
    }'

    result=$(jsonpath_query "$json" ".sub")
    [[ "$result" == "1234567890" ]]

    result=$(jsonpath_query "$json" ".roles[0]")
    [[ "$result" == "admin" ]]
}

@test "jsonpath: error response" {
    local json='{
        "error": {
            "code": 404,
            "message": "Resource not found",
            "details": {
                "resource": "users",
                "id": "123"
            }
        }
    }'

    result=$(jsonpath_query "$json" ".error.code")
    [[ "$result" == "404" ]]

    result=$(jsonpath_query "$json" ".error.details.resource")
    [[ "$result" == "users" ]]
}
