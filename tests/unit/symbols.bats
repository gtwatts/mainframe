#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Multi-Language Symbol Extraction Library Tests
# =============================================================================
# Tests for lib/symbols.sh - symbols_extract, language-specific extractors,
# and analysis functions.
# =============================================================================

load '../test_helper'

setup() {
    # Override MAINFRAME_ROOT for tests in subdirectories
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/../.."
    # symbols.sh depends on json.sh for json_escape
    source_lib "json"
    source_lib "symbols"
    FIXTURES_DIR="${BATS_TEST_DIRNAME}/../fixtures/symbols"
}

# =============================================================================
# LANGUAGE DETECTION TESTS
# =============================================================================

@test "symbols_detect_language identifies Python" {
    run symbols_detect_language "$FIXTURES_DIR/sample.py"
    [ "$status" -eq 0 ]
    [ "$output" = "python" ]
}

@test "symbols_detect_language identifies TypeScript" {
    run symbols_detect_language "$FIXTURES_DIR/sample.ts"
    [ "$status" -eq 0 ]
    [ "$output" = "typescript" ]
}

@test "symbols_detect_language identifies Go" {
    run symbols_detect_language "$FIXTURES_DIR/sample.go"
    [ "$status" -eq 0 ]
    [ "$output" = "go" ]
}

@test "symbols_detect_language identifies Rust" {
    run symbols_detect_language "$FIXTURES_DIR/sample.rs"
    [ "$status" -eq 0 ]
    [ "$output" = "rust" ]
}

@test "symbols_detect_language identifies Bash" {
    run symbols_detect_language "$FIXTURES_DIR/sample.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "bash" ]
}

@test "symbols_detect_language identifies C" {
    run symbols_detect_language "$FIXTURES_DIR/sample.c"
    [ "$status" -eq 0 ]
    [ "$output" = "c" ]
}

@test "symbols_detect_language identifies Ruby" {
    run symbols_detect_language "$FIXTURES_DIR/sample.rb"
    [ "$status" -eq 0 ]
    [ "$output" = "ruby" ]
}

@test "symbols_detect_language identifies Java" {
    run symbols_detect_language "$FIXTURES_DIR/sample.java"
    [ "$status" -eq 0 ]
    [ "$output" = "java" ]
}

@test "symbols_detect_language returns unknown for missing file" {
    run symbols_detect_language "/nonexistent/file.xyz"
    [ "$output" = "unknown" ]
}

# =============================================================================
# PYTHON EXTRACTOR TESTS
# =============================================================================

@test "symbols_python extracts class definitions" {
    run symbols_python "$FIXTURES_DIR/sample.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"class:BaseModel:"* ]]
    [[ "$output" == *"class:UserService:"* ]]
}

@test "symbols_python extracts function definitions" {
    run symbols_python "$FIXTURES_DIR/sample.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function:api_users:"* ]]
    [[ "$output" == *"function:process_data:"* ]]
    [[ "$output" == *"function:_private_helper:"* ]]
}

@test "symbols_python extracts methods inside classes" {
    run symbols_python "$FIXTURES_DIR/sample.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"method:__init__:"* ]]
    [[ "$output" == *"method:validate:"* ]]
    [[ "$output" == *"method:get_user:"* ]]
    [[ "$output" == *"method:list_users:"* ]]
}

@test "symbols_python extracts constants" {
    run symbols_python "$FIXTURES_DIR/sample.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"constant:GLOBAL_CONST:"* ]]
}

# =============================================================================
# TYPESCRIPT EXTRACTOR TESTS
# =============================================================================

@test "symbols_typescript extracts interfaces" {
    run symbols_typescript "$FIXTURES_DIR/sample.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"interface:UserProfile:"* ]]
}

@test "symbols_typescript extracts type aliases" {
    run symbols_typescript "$FIXTURES_DIR/sample.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"type:UserId:"* ]]
}

@test "symbols_typescript extracts enums" {
    run symbols_typescript "$FIXTURES_DIR/sample.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"enum:Status:"* ]]
}

@test "symbols_typescript extracts classes" {
    run symbols_typescript "$FIXTURES_DIR/sample.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"class:UserController:"* ]]
    [[ "$output" == *"class:AppServer:"* ]]
}

@test "symbols_typescript extracts functions" {
    run symbols_typescript "$FIXTURES_DIR/sample.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function:createApp:"* ]]
}

@test "symbols_typescript extracts arrow functions" {
    run symbols_typescript "$FIXTURES_DIR/sample.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function:fetchUsers:"* ]]
}

@test "symbols_typescript extracts named exports" {
    run symbols_typescript "$FIXTURES_DIR/sample.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"export:Controller:"* ]]
}

# =============================================================================
# GO EXTRACTOR TESTS
# =============================================================================

@test "symbols_go extracts functions" {
    run symbols_go "$FIXTURES_DIR/sample.go"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function:NewServer:"* ]]
    [[ "$output" == *"function:handleRequest:"* ]]
    [[ "$output" == *"function:init:"* ]]
}

@test "symbols_go extracts methods with receivers" {
    run symbols_go "$FIXTURES_DIR/sample.go"
    [ "$status" -eq 0 ]
    [[ "$output" == *"method:Start:"* ]]
    [[ "$output" == *"method:Stop:"* ]]
}

@test "symbols_go extracts structs" {
    run symbols_go "$FIXTURES_DIR/sample.go"
    [ "$status" -eq 0 ]
    [[ "$output" == *"struct:Server:"* ]]
}

@test "symbols_go extracts interfaces" {
    run symbols_go "$FIXTURES_DIR/sample.go"
    [ "$status" -eq 0 ]
    [[ "$output" == *"interface:Handler:"* ]]
}

@test "symbols_go extracts constants and variables" {
    run symbols_go "$FIXTURES_DIR/sample.go"
    [ "$status" -eq 0 ]
    [[ "$output" == *"constant:MaxRetries:"* ]]
    [[ "$output" == *"variable:DefaultTimeout:"* ]]
}

# =============================================================================
# RUST EXTRACTOR TESTS
# =============================================================================

@test "symbols_rust extracts functions" {
    run symbols_rust "$FIXTURES_DIR/sample.rs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function:run_server:"* ]]
    [[ "$output" == *"function:internal_helper:"* ]]
}

@test "symbols_rust extracts structs and enums" {
    run symbols_rust "$FIXTURES_DIR/sample.rs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"struct:Config:"* ]]
    [[ "$output" == *"enum:AppError:"* ]]
}

@test "symbols_rust extracts traits" {
    run symbols_rust "$FIXTURES_DIR/sample.rs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"trait:Service:"* ]]
}

@test "symbols_rust extracts impl blocks" {
    run symbols_rust "$FIXTURES_DIR/sample.rs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"impl:Config:"* ]]
}

@test "symbols_rust extracts modules and constants" {
    run symbols_rust "$FIXTURES_DIR/sample.rs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"module:utils:"* ]]
    [[ "$output" == *"constant:MAX_SIZE:"* ]]
}

# =============================================================================
# BASH EXTRACTOR TESTS
# =============================================================================

@test "symbols_bash extracts short-form functions" {
    run symbols_bash "$FIXTURES_DIR/sample.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function:setup_environment:"* ]]
    [[ "$output" == *"function:parse_args:"* ]]
    [[ "$output" == *"function:main:"* ]]
}

@test "symbols_bash extracts function-keyword style" {
    run symbols_bash "$FIXTURES_DIR/sample.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function:process_files:"* ]]
    [[ "$output" == *"function:cleanup:"* ]]
}

# =============================================================================
# C EXTRACTOR TESTS
# =============================================================================

@test "symbols_c extracts macros" {
    run symbols_c "$FIXTURES_DIR/sample.c"
    [ "$status" -eq 0 ]
    [[ "$output" == *"macro:MAX_BUFFER:"* ]]
    [[ "$output" == *"macro:VERSION:"* ]]
}

@test "symbols_c extracts structs" {
    run symbols_c "$FIXTURES_DIR/sample.c"
    [ "$status" -eq 0 ]
    [[ "$output" == *"struct:Config:"* ]]
}

@test "symbols_c extracts enums" {
    run symbols_c "$FIXTURES_DIR/sample.c"
    [ "$status" -eq 0 ]
    [[ "$output" == *"enum:Status:"* ]]
}

@test "symbols_c extracts functions" {
    run symbols_c "$FIXTURES_DIR/sample.c"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function:initialize:"* ]]
    [[ "$output" == *"function:process_data:"* ]]
    [[ "$output" == *"function:main:"* ]]
}

# =============================================================================
# RUBY EXTRACTOR TESTS
# =============================================================================

@test "symbols_ruby extracts modules" {
    run symbols_ruby "$FIXTURES_DIR/sample.rb"
    [ "$status" -eq 0 ]
    [[ "$output" == *"module:Authentication:"* ]]
}

@test "symbols_ruby extracts classes" {
    run symbols_ruby "$FIXTURES_DIR/sample.rb"
    [ "$status" -eq 0 ]
    [[ "$output" == *"class:Authenticator:"* ]]
    [[ "$output" == *"class:TokenStore:"* ]]
}

@test "symbols_ruby extracts methods" {
    run symbols_ruby "$FIXTURES_DIR/sample.rb"
    [ "$status" -eq 0 ]
    [[ "$output" == *"method:initialize:"* ]]
    [[ "$output" == *"method:authenticate:"* ]]
    [[ "$output" == *"method:standalone_helper:"* ]]
}

@test "symbols_ruby extracts attr_accessor attributes" {
    run symbols_ruby "$FIXTURES_DIR/sample.rb"
    [ "$status" -eq 0 ]
    [[ "$output" == *"attribute:token:"* ]]
    [[ "$output" == *"attribute:expiry:"* ]]
    [[ "$output" == *"attribute:user_id:"* ]]
}

# =============================================================================
# JAVA EXTRACTOR TESTS
# =============================================================================

@test "symbols_java extracts classes" {
    run symbols_java "$FIXTURES_DIR/sample.java"
    [ "$status" -eq 0 ]
    [[ "$output" == *"class:UserService:"* ]]
}

@test "symbols_java extracts interfaces" {
    run symbols_java "$FIXTURES_DIR/sample.java"
    [ "$status" -eq 0 ]
    [[ "$output" == *"interface:Repository:"* ]]
}

@test "symbols_java extracts enums" {
    run symbols_java "$FIXTURES_DIR/sample.java"
    [ "$status" -eq 0 ]
    [[ "$output" == *"enum:Priority:"* ]]
}

@test "symbols_java extracts methods" {
    run symbols_java "$FIXTURES_DIR/sample.java"
    [ "$status" -eq 0 ]
    [[ "$output" == *"method:findById:"* ]]
    [[ "$output" == *"method:findAll:"* ]]
    [[ "$output" == *"method:save:"* ]]
    [[ "$output" == *"method:delete:"* ]]
}

# =============================================================================
# UNIVERSAL ENTRY POINT TESTS
# =============================================================================

@test "symbols_extract auto-detects language and extracts" {
    run symbols_extract "$FIXTURES_DIR/sample.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"class:BaseModel:"* ]]
    [[ "$output" == *"function:api_users:"* ]]
}

@test "symbols_extract --type filters by type" {
    run symbols_extract "$FIXTURES_DIR/sample.py" --type function
    [ "$status" -eq 0 ]
    [[ "$output" == *"function:"* ]]
    [[ "$output" != *"class:"* ]]
    [[ "$output" != *"method:"* ]]
}

@test "symbols_extract returns error for missing file" {
    run symbols_extract "/nonexistent/file.py"
    [ "$status" -ne 0 ]
}

@test "symbols_extract_json produces valid JSON structure" {
    run symbols_extract_json "$FIXTURES_DIR/sample.py"
    [ "$status" -eq 0 ]
    [[ "$output" == '{"file":'* ]]
    [[ "$output" == *'"language":"python"'* ]]
    [[ "$output" == *'"symbols":['* ]]
    [[ "$output" == *'"type":"class"'* ]]
    [[ "$output" == *'"name":"BaseModel"'* ]]
}

@test "symbols_extract_json includes line numbers" {
    run symbols_extract_json "$FIXTURES_DIR/sample.go"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"line":'* ]]
}

@test "symbols_extract_dir processes multiple files" {
    run symbols_extract_dir "$FIXTURES_DIR" --extensions "py,go"
    [ "$status" -eq 0 ]
    [[ "$output" == '['* ]]
    [[ "$output" == *'"language":"python"'* ]]
    [[ "$output" == *'"language":"go"'* ]]
}

# =============================================================================
# ANALYSIS FUNCTION TESTS
# =============================================================================

@test "symbols_outline produces indented output" {
    run symbols_outline "$FIXTURES_DIR/sample.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"class BaseModel"* ]]
    [[ "$output" == *"  method __init__"* ]]
    [[ "$output" == *"function api_users"* ]]
}

@test "symbols_count returns JSON with counts" {
    run symbols_count "$FIXTURES_DIR/sample.py"
    [ "$status" -eq 0 ]
    [[ "$output" == '{"functions":'* ]]
    [[ "$output" == *'"total":'* ]]
    # Verify total is positive
    [[ "$output" =~ \"total\":([0-9]+) ]]
    [ "${BASH_REMATCH[1]}" -gt 0 ]
}

@test "symbols_count has correct function count for bash" {
    run symbols_count "$FIXTURES_DIR/sample.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ \"functions\":([0-9]+) ]]
    [ "${BASH_REMATCH[1]}" -ge 5 ]
}

@test "symbols_find locates symbol across files" {
    run symbols_find "main" "$FIXTURES_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sample.c:"* ]] || [[ "$output" == *"sample.sh:"* ]] || [[ "$output" == *"sample.go:"* ]]
}

@test "symbols_find with --type filters results" {
    run symbols_find "main" "$FIXTURES_DIR" --type function
    [ "$status" -eq 0 ]
    # Should find main in .c and .sh files at minimum
    [[ "$output" == *":"* ]]
}

@test "symbols_find returns empty for nonexistent symbol" {
    run symbols_find "zzz_nonexistent_symbol_zzz" "$FIXTURES_DIR"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "symbols_signatures extracts function signatures" {
    run symbols_signatures "$FIXTURES_DIR/sample.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"def"* ]]
}

@test "symbols_signatures --public-only skips private" {
    run symbols_signatures "$FIXTURES_DIR/sample.py" --public-only
    [ "$status" -eq 0 ]
    [[ "$output" != *"_private_helper"* ]]
}

@test "symbols_public_api returns only public symbols" {
    run symbols_public_api "$FIXTURES_DIR/sample.go"
    [ "$status" -eq 0 ]
    [[ "$output" == '['* ]]
    # Go exports start with uppercase
    [[ "$output" == *'"name":"NewServer"'* ]]
    [[ "$output" == *'"name":"Server"'* ]]
    # Lowercase functions should be excluded
    [[ "$output" != *'"name":"handleRequest"'* ]]
    [[ "$output" != *'"name":"init"'* ]]
}

@test "symbols_public_api returns exports for TypeScript" {
    run symbols_public_api "$FIXTURES_DIR/sample.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == '['* ]]
    [[ "$output" == *'"name":"UserProfile"'* ]]
    [[ "$output" == *'"name":"createApp"'* ]]
}
