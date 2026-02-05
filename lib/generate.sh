#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/generate.sh - Bash Code Generation from Natural Language
# =============================================================================
# Description: Generate bash functions from descriptions, explain generated code,
#              and generate tests for bash code.
# Version: 1.0.0 (V10 Code Generation)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_GENERATE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_GENERATE_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

readonly GENERATE_VERSION="1.0.0"
readonly GENERATE_MAX_FUNCTION_LENGTH=500

# =============================================================================
# TEMPLATE LIBRARY
# =============================================================================

# Function templates by category
declare -gA _GENERATE_TEMPLATES=(
    ["validation"]='validate_${name}() {
    local input="$1"
    
    # Check if input is provided
    [[ -z "$input" ]] && return 1
    
    # Validation logic here
    ${logic}
    
    return 0
}'

    ["processing"]='process_${name}() {
    local input="$1"
    local output=""
    
    # Input validation
    [[ -z "$input" ]] && return 1
    
    # Processing logic
    ${logic}
    
    printf "%s\\n" "$output"
    return 0
}'

    ["file_operation"]='${name}() {
    local file="$1"
    local target="${2:-}"
    
    # Safety check: file must exist
    [[ ! -f "$file" ]] && {
        printf "Error: File not found: %s\\n" "$file" >&2
        return 1
    }
    
    # Operation logic
    ${logic}
    
    return 0
}'

    ["directory_operation"]='${name}() {
    local dir="${1:-.}"
    
    # Safety check: directory must exist
    [[ ! -d "$dir" ]] && {
        printf "Error: Directory not found: %s\\n" "$dir" >&2
        return 1
    }
    
    # Operation logic
    ${logic}
    
    return 0
}'

    ["batch_processing"]='${name}() {
    local -a items=("$@")
    local result=0
    
    # Process each item
    for item in "${items[@]}"; do
        ${logic}
        result=$?
        [[ $result -ne 0 ]] && break
    done
    
    return $result
}'

    ["with_backup"]='${name}() {
    local target="$1"
    local backup_suffix=".bak.$(date +%Y%m%d_%H%M%S)"
    
    # Safety: create backup
    if [[ -e "$target" ]]; then
        cp -r "$target" "${target}${backup_suffix}" || {
            printf "Error: Failed to create backup\\n" >&2
            return 1
        }
    fi
    
    # Main operation
    ${logic}
    local result=$?
    
    # Cleanup on success (optional)
    # rm -f "${target}${backup_suffix}"
    
    return $result
}'

    ["standard"]='${name}() {
    local arg1="$1"
    local arg2="${2:-}"
    
    # Validate inputs
    [[ -z "$arg1" ]] && {
        printf "Usage: %s <arg1> [arg2]\\n" "${FUNCNAME[0]}" >&2
        return 1
    }
    
    # Main logic
    ${logic}
    
    return 0
}'
)

# Common function patterns for pattern matching
declare -gA _GENERATE_PATTERNS=(
    ["validate"]='validation'
    ["check"]='validation'
    ["verify"]='validation'
    ["is_"]='validation'
    ["has_"]='validation'
    ["process"]='processing'
    ["transform"]='processing'
    ["convert"]='processing'
    ["parse"]='processing'
    ["format"]='processing'
    ["backup"]='with_backup'
    ["safe_"]='with_backup'
    ["batch"]='batch_processing'
    ["bulk"]='batch_processing'
    ["for each"]='batch_processing'
    ["directory"]='directory_operation'
    ["folder"]='directory_operation'
    ["file"]='file_operation'
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Escape string for JSON output
_generate_escape_json() {
    local str="$1"
    local result=""
    local i char

    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')   result+='\\"' ;;
            '\\')   result+='\\\\' ;;
            $'\b') result+='\\b' ;;
            $'\f') result+='\\f' ;;
            $'\n') result+='\\n' ;;
            $'\r') result+='\\r' ;;
            $'\t') result+='\\t' ;;
            *)
                if [[ "$char" < $'\x20' ]]; then
                    printf -v char '\\u%04x' "'$char"
                fi
                result+="$char"
                ;;
        esac
    done

    printf '%s' "$result"
}

# Build JSON array from bash array
_generate_array_to_json() {
    local first=true
    printf '['
    for item in "$@"; do
        $first || printf ','
        first=false
        printf '"%s"' "$(_generate_escape_json "$item")"
    done
    printf ']'
}

# Convert description to valid function name
_generate_to_function_name() {
    local description="$1"
    local name=""

    # Remove common stop words and convert to snake_case
    name=$(printf '%s' "$description" | tr '[:upper:]' '[:lower:]')
    
    # Replace non-alphanumeric with underscores
    name=${name//[^a-z0-9_]/_}
    
    # Collapse multiple underscores
    while [[ "$name" == *"__"* ]]; do
        name=${name//__/_}
    done
    
    # Trim leading/trailing underscores
    name=${name#_}
    name=${name%_}
    
    # Limit length
    if [[ ${#name} -gt 50 ]]; then
        name="${name:0:50}"
        name=${name%_}  # Ensure doesn't end with underscore
    fi
    
    # Ensure starts with letter
    if [[ "$name" =~ ^[0-9] ]]; then
        name="fn_$name"
    fi
    
    printf '%s' "$name"
}

# Detect template category from description
_generate_detect_template() {
    local description="${1,,}"
    local category="standard"

    for pattern in "${!_GENERATE_PATTERNS[@]}"; do
        if [[ "$description" == *"$pattern"* ]]; then
            category="${_GENERATE_PATTERNS[$pattern]}"
            break
        fi
    done

    printf '%s' "$category"
}

# Generate logic from description
_generate_logic_from_description() {
    local description="${1,,}"
    local logic=""

    case "$description" in
        *"email"*)
            logic='# Validate email format
    if [[ "$input" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    fi
    return 1'
            ;;
        *"url"*|*"http"*)
            logic='# Validate URL format
    if [[ "$input" =~ ^https?:// ]]; then
        return 0
    fi
    return 1'
            ;;
        *"number"*|*"integer"*)
            logic='# Validate numeric input
    if [[ "$input" =~ ^-?[0-9]+$ ]]; then
        return 0
    fi
    return 1'
            ;;
        *"file exists"*)
            logic='# Check file exists
    [[ -f "$input" ]]'
            ;;
        *"directory exists"*)
            logic='# Check directory exists
    [[ -d "$input" ]]'
            ;;
        *"empty"*)
            logic='# Check if empty
    [[ -z "$input" ]]'
            ;;
        *"line count"*|*"count lines"*)
            logic='# Count lines
    output=$(wc -l < "$input")'
            ;;
        *"word count"*|*"count words"*)
            logic='# Count words
    output=$(wc -w < "$input")'
            ;;
        *"size"*)
            logic='# Get file size
    output=$(stat -f%z "$input" 2>/dev/null || stat -c%s "$input" 2>/dev/null)'
            ;;
        *"timestamp"*)
            logic='# Generate timestamp
    output=$(date +%Y%m%d_%H%M%S)'
            ;;
        *"backup"*)
            logic='# Create backup
    local backup="${input}.bak.$(date +%Y%m%d_%H%M%S)"
    cp -r "$input" "$backup"'
            ;;
        *"sort"*)
            logic='# Sort input
    output=$(printf "%s" "$input" | sort)'
            ;;
        *"unique"*)
            logic='# Remove duplicates
    output=$(printf "%s" "$input" | sort -u)'
            ;;
        *"reverse"*)
            logic='# Reverse input
    output=$(printf "%s" "$input" | rev)'
            ;;
        *)
            logic='# TODO: Implement logic based on description
    # Description: '"$description"'
    output="$input"'
            ;;
    esac

    printf '%s' "$logic"
}

# =============================================================================
# PUBLIC API - Core Functions
# =============================================================================

# generate_function - Generate bash function from description
# @description Generate a working bash function based on natural language description
# @pre        None
# @post       Returns bash function code
# @idempotent Yes (same description produces same function)
# @param      $1 description - Natural language description of desired function
# @param      --json - Output as JSON with metadata
# @param      --template - Specify template category (validation, processing, etc.)
# @param      --name - Specify function name (auto-generated if omitted)
# @stdout     Bash function code
# @return     0 on success, 1 on generation failure
#
# Usage: generate_function "validate email addresses"
# Usage: generate_function "count lines in file" --name "count_lines"
generate_function() {
    local description="$1"
    shift

    local json_output=0
    local template=""
    local custom_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=1; shift ;;
            --template) template="$2"; shift 2 ;;
            --name) custom_name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Validate input
    if [[ -z "$description" ]]; then
        if [[ $json_output -eq 1 ]]; then
            printf '{"error":"empty description","success":false}\n'
        else
            printf '# Error: Empty description provided\n'
        fi
        return 1
    fi

    # Generate function name
    local func_name
    if [[ -n "$custom_name" ]]; then
        func_name="$custom_name"
    else
        func_name=$(_generate_to_function_name "$description")
    fi

    # Detect template if not specified
    if [[ -z "$template" ]]; then
        template=$(_generate_detect_template "$description")
    fi
    
    # Strip template prefix from function name to avoid duplication (e.g., validate_validate_)
    case "$template" in
        validation) func_name=${func_name#validate_} ;;
        processing) func_name=${func_name#process_} ;;
    esac
    [[ -z "$func_name" ]] && func_name="item"  # Fallback if name was all prefix

    # Get template
    local template_str="${_GENERATE_TEMPLATES[$template]:-${_GENERATE_TEMPLATES[standard]}}"

    # Generate logic
    local logic
    logic=$(_generate_logic_from_description "$description")

    # Substitute placeholders
    local func_code="${template_str//\$\{name\}/$func_name}"
    func_code="${func_code//\$\{logic\}/$logic}"

    # Add header comment
    func_code="# =============================================================================
# $description
# =============================================================================
$func_code"

    # Output result
    if [[ $json_output -eq 1 ]]; then
        local escaped_code escaped_desc
        escaped_code=$(_generate_escape_json "$func_code")
        escaped_desc=$(_generate_escape_json "$description")
        printf '{"description":"%s","function_name":"%s","template":"%s","code":"%s","success":true}\n' \
            "$escaped_desc" "$func_name" "$template" "$escaped_code"
    else
        printf '%s\n' "$func_code"
    fi

    return 0
}

# generate_explain - Explain what generated code does
# @description Provide detailed explanation of generated bash code
# @pre        None
# @post       Returns human-readable explanation
# @idempotent Yes
# @param      $1 code - Bash code to explain
# @param      --json - Output as JSON
# @param      --verbose - Include line-by-line breakdown
# @stdout     Detailed explanation
# @return     0 always
#
# Usage: generate_explain "my_function() { echo hello; }"
generate_explain() {
    local code="$1"
    shift

    local json_output=0 verbose=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=1; shift ;;
            --verbose) verbose=1; shift ;;
            *) shift ;;
        esac
    done

    # Handle multiline input
    code="${code//$'\n'/ }"

    # Extract function name
    local func_name=""
    if [[ "$code" =~ ([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(\) ]]; then
        func_name="${BASH_REMATCH[1]}"
    fi

    # Analyze structure
    local -a features=()
    local -a safety=()
    local -a inputs=()
    local -a outputs=()

    # Check for features
    [[ "$code" == *"local "* ]] && features+=("Uses local variables (good practice)")
    [[ "$code" == *"[[ -"* ]] && features+=("Input validation")
    [[ "$code" == *"return 1"* ]] && features+=("Error handling with return codes")
    [[ "$code" == *"printf "* ]] && features+=("Formatted output")
    [[ "$code" == *"for "* ]] && features+=("Loop iteration")
    [[ "$code" == *"if "* ]] && features+=("Conditional logic")
    [[ "$code" == *"cp -r"* ]] && features+=("Recursive copy")
    [[ "$code" == *"*.bak."* ]] && features+=("Automatic backup creation")

    # Check safety features
    [[ "$code" == *"[[ -f "* ]] && safety+=("Checks if file exists before operation")
    [[ "$code" == *"[[ -d "* ]] && safety+=("Checks if directory exists")
    [[ "$code" == *".bak."* ]] && safety+=("Creates backups before modification")
    [[ "$code" == *"local arg"* ]] && safety+=("Proper variable scoping")
    [[ "$code" == *"Error:"* ]] && safety+=("User-friendly error messages")

    # Check inputs
    if [[ "$code" =~ local[[:space:]]+arg1=[[:space:]]*\"?\$1 ]]; then
        inputs+=("Primary argument (\$1)")
    fi
    if [[ "$code" =~ local[[:space:]]+arg2=[[:space:]]*\"?\$2 ]]; then
        inputs+=("Secondary argument (\$2, optional)")
    fi
    if [[ "$code" =~ local[[:space:]]+input=[[:space:]]*\"?\$1 ]]; then
        inputs+=("Input data (\$1)")
    fi
    if [[ "$code" =~ local[[:space:]]+file=[[:space:]]*\"?\$1 ]]; then
        inputs+=("File path (\$1)")
    fi

    # Check outputs
    [[ "$code" == *"printf "%s"*"* ]] && outputs+=("Returns string via stdout")
    [[ "$code" == *"return 0"* ]] && outputs+=("Success/failure via exit code")

    # Build explanation
    local summary="This function"
    if [[ -n "$func_name" ]]; then
        summary="'$func_name'"
    fi

    # Output
    if [[ $json_output -eq 1 ]]; then
        local escaped_code escaped_name
        escaped_code=$(_generate_escape_json "$code")
        escaped_name=$(_generate_escape_json "$func_name")
        local features_json safety_json inputs_json outputs_json
        features_json=$(_generate_array_to_json "${features[@]}")
        safety_json=$(_generate_array_to_json "${safety[@]}")
        inputs_json=$(_generate_array_to_json "${inputs[@]}")
        outputs_json=$(_generate_array_to_json "${outputs[@]}")
        printf '{"function_name":"%s","features":%s,"safety":%s,"inputs":%s,"outputs":%s,"code":"%s"}\n' \
            "$escaped_name" "$features_json" "$safety_json" "$inputs_json" "$outputs_json" "$escaped_code"
    else
        printf 'Function Analysis\n'
        printf '=================\n\n'
        
        if [[ -n "$func_name" ]]; then
            printf 'Name: %s\n' "$func_name"
        fi
        
        printf '\nPurpose:\n'
        printf '  This function provides bash automation with built-in safety checks\n'
        printf '  and proper error handling.\n'
        
        if [[ ${#inputs[@]} -gt 0 ]]; then
            printf '\nInputs:\n'
            for input in "${inputs[@]}"; do
                printf '  • %s\n' "$input"
            done
        fi
        
        if [[ ${#outputs[@]} -gt 0 ]]; then
            printf '\nOutputs:\n'
            for output in "${outputs[@]}"; do
                printf '  • %s\n' "$output"
            done
        fi
        
        if [[ ${#features[@]} -gt 0 ]]; then
            printf '\nFeatures:\n'
            for feature in "${features[@]}"; do
                printf '  ✓ %s\n' "$feature"
            done
        fi
        
        if [[ ${#safety[@]} -gt 0 ]]; then
            printf '\nSafety Measures:\n'
            for measure in "${safety[@]}"; do
                printf '  🛡 %s\n' "$measure"
            done
        fi
        
        if [[ $verbose -eq 1 ]]; then
            printf '\nCode Structure:\n'
            printf '  1. Input validation and parameter handling\n'
            printf '  2. Safety checks (file existence, permissions)\n'
            printf '  3. Main operation logic\n'
            printf '  4. Error handling and cleanup\n'
            printf '  5. Return value signaling success/failure\n'
        fi
    fi

    return 0
}

# generate_test - Generate tests for bash code
# @description Generate unit tests for bash function
# @pre        Valid bash function code
# @post       Returns test code
# @idempotent Yes
# @param      $1 code - Bash function to test
# @param      --json - Output as JSON with test cases
# @param      --framework - Test framework (bats, shunit2, assert) - default: bats
# @stdout     Test code
# @return     0 on success, 1 on failure
#
# Usage: generate_test "my_func() { echo hello; }"
generate_test() {
    local code="$1"
    shift

    local json_output=0
    local framework="bats"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=1; shift ;;
            --framework) framework="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Extract function name
    local func_name=""
    if [[ "$code" =~ ([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(\) ]]; then
        func_name="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$func_name" ]]; then
        if [[ $json_output -eq 1 ]]; then
            printf '{"error":"could not extract function name","success":false}\n'
        else
            printf '# Error: Could not extract function name from code\n'
        fi
        return 1
    fi

    # Generate test cases based on function analysis
    local -a test_cases=()

    # Basic success test
    test_cases+=("${func_name}_returns_success_with_valid_input")
    
    # Empty input test
    test_cases+=("${func_name}_handles_empty_input")
    
    # Error handling test
    if [[ "$code" == *"return 1"* ]]; then
        test_cases+=("${func_name}_returns_error_on_invalid_input")
    fi
    
    # File-related tests
    if [[ "$code" == *"[[ -f "* ]]; then
        test_cases+=("${func_name}_checks_file_exists")
        test_cases+=("${func_name}_handles_missing_file")
    fi
    
    # Directory-related tests
    if [[ "$code" == *"[[ -d "* ]]; then
        test_cases+=("${func_name}_checks_directory_exists")
    fi

    # Generate test code based on framework
    local test_code=""
    
    case "$framework" in
        bats)
            test_code="#!/usr/bin/env bats

# =============================================================================
# Tests for $func_name
# =============================================================================

# Load the function
source \"\${BATS_TEST_DIRNAME}/../your_script.sh\"

"
            for test_name in "${test_cases[@]}"; do
                test_code+="@test \"$test_name\" {
    # TODO: Set up test conditions
    
    # Run the function
    run $func_name \"test_input\"
    
    # Assert expected behavior
    [[ \$status -eq 0 ]]
}\n\n"
            done
            ;;
        
        shunit2)
            test_code="#!/bin/bash
# =============================================================================
# Tests for $func_name (shunit2)
# =============================================================================

# Load the function
source \"\${0%/*}/../your_script.sh\"

"
            for test_name in "${test_cases[@]}"; do
                test_code+="test_$test_name() {
    # TODO: Set up test conditions
    
    # Run and assert
    result=\$($func_name \"test_input\")
    assertEquals \"expected\" \"\$result\"
}\n\n"
            done
            test_code+="# Run tests
. shunit2"
            ;;
        
        assert)
            test_code="#!/bin/bash
# =============================================================================
# Tests for $func_name (assert.sh)
# =============================================================================

source assert.sh
source \"\${0%/*}/../your_script.sh\"

"
            for test_name in "${test_cases[@]}"; do
                test_code+="# Test: $test_name
assert_eq \"\$($func_name 'input')\" \"expected_output\"\n\n"
            done
            ;;
        
        *)
            if [[ $json_output -eq 1 ]]; then
                printf '{"error":"unknown framework: %s","success":false}\n' "$framework"
            else
                printf '# Error: Unknown framework: %s\n' "$framework"
                printf '# Supported: bats, shunit2, assert\n'
            fi
            return 1
            ;;
    esac

    # Output result
    if [[ $json_output -eq 1 ]]; then
        local escaped_code escaped_func
        escaped_code=$(_generate_escape_json "$test_code")
        escaped_func=$(_generate_escape_json "$func_name")
        local tests_json
        tests_json=$(_generate_array_to_json "${test_cases[@]}")
        printf '{"function_name":"%s","framework":"%s","test_cases":%s,"code":"%s","success":true}\n' \
            "$escaped_func" "$framework" "$tests_json" "$escaped_code"
    else
        printf '%s\n' "$test_code"
    fi

    return 0
}

# generate_improve - Suggest improvements for bash code
# @description Analyze code and suggest improvements
# @pre        Valid bash function code
# @post       Returns list of improvement suggestions
# @idempotent Yes
# @param      $1 code - Bash code to analyze
# @param      --json - Output as JSON
# @stdout     Improvement suggestions
# @return     0 always
#
# Usage: generate_improve "my_old_func() { echo $1; }"
generate_improve() {
    local code="$1"
    shift

    local json_output=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=1; shift ;;
            *) shift ;;
        esac
    done

    local -a improvements=()
    local -a warnings=()
    local -a suggestions=()

    # Check for common issues
    [[ "$code" == *'$1'* ]] && [[ "$code" != *'local '* ]] && 
        warnings+=("Consider using 'local' for variables")
    
    [[ "$code" == *'eval '* ]] && 
        warnings+=("WARNING: eval is dangerous and should be avoided")
    
    [[ "$code" == *'`'* ]] && 
        suggestions+=("Consider using \$() instead of backticks for command substitution")
    
    [[ "$code" != *'[[ -'* ]] && [[ "$code" == *'$1'* ]] &&
        suggestions+=("Add input validation before using arguments")
    
    [[ "$code" != *'return '* ]] &&
        suggestions+=("Add explicit return statements for clarity")
    
    [[ "$code" == *'echo '* ]] &&
        suggestions+=("Consider using 'printf' instead of 'echo' for better portability")
    
    [[ "$code" == *'rm '* ]] && [[ "$code" != *'-i'* ]] &&
        warnings+=("Destructive operation without interactive flag")
    
    [[ "$code" == *'cat '* ]] && [[ "$code" == *'| grep'* ]] &&
        suggestions+=("Use 'grep file pattern' instead of 'cat file | grep'")

    # Score the code
    local score=100
    (( ${#warnings[@]} * 10 )) && score=$((score - ${#warnings[@]} * 10))
    (( ${#suggestions[@]} * 5 )) && score=$((score - ${#suggestions[@]} * 5))
    [[ $score -lt 0 ]] && score=0

    # Categorize score
    local rating="excellent"
    [[ $score -lt 90 ]] && rating="good"
    [[ $score -lt 70 ]] && rating="fair"
    [[ $score -lt 50 ]] && rating="poor"

    # Output
    if [[ $json_output -eq 1 ]]; then
        local escaped_code
        escaped_code=$(_generate_escape_json "$code")
        local warnings_json suggestions_json
        warnings_json=$(_generate_array_to_json "${warnings[@]}")
        suggestions_json=$(_generate_array_to_json "${suggestions[@]}")
        printf '{"score":%d,"rating":"%s","warnings":%s,"suggestions":%s,"code":"%s"}\n' \
            "$score" "$rating" "$warnings_json" "$suggestions_json" "$escaped_code"
    else
        printf 'Code Improvement Analysis\n'
        printf '=========================\n\n'
        printf 'Score: %d/100 (%s)\n\n' "$score" "$rating"
        
        if [[ ${#warnings[@]} -gt 0 ]]; then
            printf '⚠ Warnings:\n'
            for warning in "${warnings[@]}"; do
                printf '  • %s\n' "$warning"
            done
            printf '\n'
        fi
        
        if [[ ${#suggestions[@]} -gt 0 ]]; then
            printf '💡 Suggestions:\n'
            for suggestion in "${suggestions[@]}"; do
                printf '  • %s\n' "$suggestion"
            done
        fi
        
        if [[ ${#warnings[@]} -eq 0 && ${#suggestions[@]} -eq 0 ]]; then
            printf '✓ No improvements needed - code looks good!\n'
        fi
    fi

    return 0
}

# generate_document - Generate documentation for bash function
# @description Generate documentation in various formats
# @pre        Valid bash function code
# @post       Returns formatted documentation
# @idempotent Yes
# @param      $1 code - Bash code to document
# @param      --format - Output format (markdown, man, help) - default: markdown
# @param      --json - Output as JSON
# @stdout     Documentation
# @return     0 on success, 1 on failure
#
# Usage: generate_document "my_func() { ... }"
generate_document() {
    local code="$1"
    shift

    local format="markdown"
    local json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2 ;;
            --json) json_output=1; shift ;;
            *) shift ;;
        esac
    done

    # Extract function name and parameters
    local func_name=""
    if [[ "$code" =~ ([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(\) ]]; then
        func_name="${BASH_REMATCH[1]}"
    fi

    # Extract parameters
    local -a params=()
    while [[ "$code" =~ local[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)=[[:space:]]*\"?\$([0-9]+) ]]; do
        params+=("${BASH_REMATCH[1]}")
        code="${code#*${BASH_REMATCH[0]}}"
    done

    local doc=""

    case "$format" in
        markdown)
            doc="## \`$func_name\`

**Usage:** \`$func_name"
            for ((i=1; i<=${#params[@]}; i++)); do
                doc+=" <${params[i-1]}>"
            done
            doc+="\`\n\n"
            
            if [[ ${#params[@]} -gt 0 ]]; then
                doc+="### Parameters\n\n"
                for param in "${params[@]}"; do
                    doc+="- \`$param\`: Description of parameter\n"
                done
                doc+="\n"
            fi
            
            doc+="### Return Value\n\n"
            doc+="Returns 0 on success, non-zero on failure.\n\n"
            
            doc+="### Example\n\n"
            doc+="\`\`\`bash\n"
            doc+="# Example usage\n"
            doc+="$func_name"
            for param in "${params[@]}"; do
                doc+=" \"value\""
            done
            doc+="\n\`\`\`\n"
            ;;
        
        man)
            doc=".TH ${func_name^^} 1 \"$(date +%Y-%m-%d)\" \"Mainframe\" \"User Commands\"
.SH NAME
$func_name \- description of what this function does
.SH SYNOPSIS
.B $func_name"
            for param in "${params[@]}"; do
                doc+=" \fI$param\fR"
            done
            doc+="\n.SH DESCRIPTION\n.PP\nDescription of the function.\n"
            
            if [[ ${#params[@]} -gt 0 ]]; then
                doc+=".SH OPTIONS\n"
                for param in "${params[@]}"; do
                    doc+=".TP\n.BI $param\nDescription of parameter.\n"
                done
            fi
            
            doc+=".SH EXIT STATUS\n.TP\n.B 0\nSuccess\n.TP\n.B 1\nFailure\n"
            doc+=".SH SEE ALSO\nbash(1)\n"
            ;;
        
        help)
            doc="$func_name: Description of what this function does\n\n"
            doc+="Usage: $func_name"
            for param in "${params[@]}"; do
                doc+" <$param>"
            done
            doc+="\n\n"
            
            if [[ ${#params[@]} -gt 0 ]]; then
                doc+="Arguments:\n"
                for param in "${params[@]}"; do
                    doc+"  $param    Description\n"
                done
            fi
            ;;
        
        *)
            if [[ $json_output -eq 1 ]]; then
                printf '{"error":"unknown format: %s","success":false}\n' "$format"
            else
                printf 'Error: Unknown format: %s\n' "$format"
                printf 'Supported: markdown, man, help\n'
            fi
            return 1
            ;;
    esac

    # Output
    if [[ $json_output -eq 1 ]]; then
        local escaped_doc escaped_func
        escaped_doc=$(_generate_escape_json "$doc")
        escaped_func=$(_generate_escape_json "$func_name")
        local params_json
        params_json=$(_generate_array_to_json "${params[@]}")
        printf '{"function_name":"%s","format":"%s","parameters":%s,"documentation":"%s","success":true}\n' \
            "$escaped_func" "$format" "$params_json" "$escaped_doc"
    else
        printf '%s\n' "$doc"
    fi

    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

declare -ga _GENERATE_EXPORTS=(
    generate_function
    generate_explain
    generate_test
    generate_improve
    generate_document
)

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f "${_GENERATE_EXPORTS[@]}" 2>/dev/null || true
fi
