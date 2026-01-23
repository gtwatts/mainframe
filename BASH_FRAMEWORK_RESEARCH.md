# Advanced Bash Patterns for AI Coding Assistants

## Executive Summary

This research document provides a comprehensive guide to advanced Bash patterns targeting AI coding assistants working with pure bash libraries. The patterns leverage Bash 4.0+ and 5.0+ features to achieve functional programming paradigms, maximum performance through subshell avoidance, and memory-efficient data processing. These patterns are specifically designed for MAINFRAME-style libraries where external dependencies are minimized or eliminated.

**Primary Recommendation**: Prioritize `printf -v` for variable assignment, namerefs for function return values, and `mapfile` for bulk data loading. Avoid subshells in loops at all costs - performance gains of 20-80% are achievable.

**Key Decision Factors**:
- Bash 4.0+ is the minimum target (associative arrays, namerefs in 4.3+)
- Bash 5.0+ enables EPOCHSECONDS/EPOCHREALTIME for high-performance timing
- Bash 5.3+ introduces current-shell command substitution (major performance win)

---

## Table of Contents

1. [Bash Version Feature Matrix](#1-bash-version-feature-matrix)
2. [Subshell Avoidance Patterns](#2-subshell-avoidance-patterns)
3. [Parameter Expansion Mastery](#3-parameter-expansion-mastery)
4. [Nameref and Indirect Reference Patterns](#4-nameref-and-indirect-reference-patterns)
5. [Functional Programming Patterns](#5-functional-programming-patterns)
6. [Memory-Efficient Data Processing](#6-memory-efficient-data-processing)
7. [Advanced Pattern Matching](#7-advanced-pattern-matching)
8. [Performance Benchmarking Techniques](#8-performance-benchmarking-techniques)
9. [Associative Array Patterns](#9-associative-array-patterns)
10. [Recommendations for MAINFRAME](#10-recommendations-for-mainframe)

---

## 1. Bash Version Feature Matrix

### Bash 4.0 Features (2009)
| Feature | Syntax | Use Case |
|---------|--------|----------|
| Associative arrays | `declare -A map` | Hash tables, dictionaries |
| Case modification | `${var^^}`, `${var,,}` | String case conversion |
| Coprocesses | `coproc name { cmd; }` | Bidirectional process communication |
| `mapfile`/`readarray` | `mapfile -t arr < file` | Bulk array loading |
| `&>>` redirect | `cmd &>> file` | Append stdout+stderr |

### Bash 4.3 Features (2014)
| Feature | Syntax | Use Case |
|---------|--------|----------|
| Namerefs | `declare -n ref=var` | Indirect variable access, function returns |
| Negative array indices | `${arr[-1]}` | Access from end of array |
| `[[ -v var ]]` | `[[ -v myvar ]]` | Test if variable is set |

### Bash 5.0 Features (2019)
| Feature | Syntax | Use Case |
|---------|--------|----------|
| EPOCHSECONDS | `$EPOCHSECONDS` | Unix timestamp (integer) |
| EPOCHREALTIME | `$EPOCHREALTIME` | Microsecond precision timing |
| BASH_ARGV0 | `BASH_ARGV0="name"` | Set/get $0 |
| `localvar_inherit` | `shopt -s localvar_inherit` | Local vars inherit parent scope |
| `assoc_expand_once` | `shopt -s assoc_expand_once` | Prevent double expansion |

### Bash 5.3 Features (July 2025) - CUTTING EDGE
| Feature | Syntax | Use Case |
|---------|--------|----------|
| Current-shell substitution | `${ cmd; }` | Capture output without fork |
| REPLY substitution | `${| cmd; }` | Store result in REPLY variable |
| GLOBSORT | `GLOBSORT=name` | Control glob ordering |
| compgen to variable | `compgen -V var` | Direct completion to variable |

**Critical Bash 5.3 Example - No Fork Command Substitution**:
```bash
# OLD (forks a subshell):
result=$(echo "hello" | tr 'a-z' 'A-Z')

# NEW in Bash 5.3 (no fork, runs in current shell):
result=${ printf '%s' "hello" | tr 'a-z' 'A-Z'; }

# Or using REPLY:
${| REPLY="HELLO"; }
echo "$REPLY"  # HELLO
```

**Sources**:
- [Bash 5.0 Features - Packt](https://www.packtpub.com/en-us/learning/how-to-tutorials/gnu-bash-5-0-is-here-with-new-features-and-improvements)
- [Bash 5.3 Release - Phoronix](https://www.phoronix.com/news/GNU-Bash-5.3)
- [Bash 5.3 Command Substitution - Linuxiac](https://linuxiac.com/bash-shell-5-3-released-with-new-command-substitution/)

---

## 2. Subshell Avoidance Patterns

Subshells are the #1 performance killer in bash scripts. Every `$()`, pipe, or backgrounded command creates a new process with fork overhead.

### The Problem: Subshell Costs
```bash
# SLOW: Creates 1000 subshells
for i in {1..1000}; do
    result=$(echo "$i" | tr -d '\n')  # 2 subshells per iteration!
done

# FAST: Zero subshells
for i in {1..1000}; do
    printf -v result '%s' "$i"
done
```

**Performance Impact**: Reducing subshell usage can improve execution by **20-80%** in loop-heavy scripts.

### Pattern 1: printf -v Instead of $()
```bash
# SLOW: Subshell
timestamp=$(date +%Y-%m-%d)

# FAST: No subshell (Bash 5.0+)
printf -v timestamp '%(%Y-%m-%d)T' -1

# FAST: For string formatting
name="world"
# SLOW:
greeting=$(printf 'Hello, %s!' "$name")
# FAST:
printf -v greeting 'Hello, %s!' "$name"
```

### Pattern 2: Here Strings Instead of Echo Pipe
```bash
# SLOW: Pipe creates subshell
result=$(echo "hello" | tr 'a-z' 'A-Z')

# FASTER: Here string (no subshell on left side)
result=$(tr 'a-z' 'A-Z' <<< "hello")

# FASTEST: Parameter expansion (no external command)
str="hello"
result="${str^^}"
```

### Pattern 3: Process Substitution to Preserve Variables
```bash
# BROKEN: Variable lost in subshell
count=0
cat file.txt | while read -r line; do
    ((count++))  # This count is lost!
done
echo "$count"  # Always 0

# CORRECT: Process substitution keeps loop in current shell
count=0
while read -r line; do
    ((count++))
done < <(cat file.txt)
echo "$count"  # Correct value
```

### Pattern 4: Built-in Arithmetic
```bash
# SLOW: External command
result=$(expr $a + $b)

# FAST: Built-in arithmetic
result=$((a + b))

# Also works for complex expressions
result=$((a * b + c / d - e % f))
```

### Pattern 5: [[ ]] Instead of [ ]
```bash
# SLOWER: [ ] is a command
if [ "$a" = "$b" ]; then

# FASTER: [[ ]] is a keyword (25% faster)
if [[ "$a" == "$b" ]]; then
```

**Sources**:
- [Bash Performance Optimization - MoldStud](https://moldstud.com/articles/p-how-to-avoid-common-bash-scripting-performance-issues-essential-tips-and-best-practices)
- [Avoid Subshells in Loops - LinuxBash](https://www.linuxbash.sh/post/avoid-subshells-in-loops-using-process-substitution)
- [printf -v Pattern - LinuxBash](https://www.linuxbash.sh/post/use-printf--v-to-assign-formatted-output-to-a-variable)

---

## 3. Parameter Expansion Mastery

Parameter expansion is the most powerful tool for avoiding external commands like `sed`, `awk`, and `cut`.

### Default Values
```bash
# Use default if unset or empty
${var:-default}      # Use default, don't modify var
${var:=default}      # Use default AND set var
${var:+alternate}    # Use alternate if var IS set
${var:?error msg}    # Exit with error if unset
```

### String Manipulation
```bash
str="hello world"

# Length
${#str}              # 11

# Substring extraction
${str:0:5}           # "hello" (start:length)
${str:6}             # "world" (from position to end)
${str: -5}           # "world" (last 5 chars - note the space!)
${str:(-5)}          # "world" (alternate syntax)

# Case modification (Bash 4.0+)
${str^}              # "Hello world" (first char upper)
${str^^}             # "HELLO WORLD" (all upper)
${str,}              # "hello world" (first char lower)
${str,,}             # "hello world" (all lower)
${str~}              # "Hello world" (toggle first)
${str~~}             # "HELLO WORLD" (toggle all)
```

### Pattern Removal
```bash
file="/path/to/file.tar.gz"

# Remove shortest match from beginning
${file#*/}           # "path/to/file.tar.gz"

# Remove longest match from beginning
${file##*/}          # "file.tar.gz" (basename!)

# Remove shortest match from end
${file%.*}           # "/path/to/file.tar"

# Remove longest match from end
${file%%.*}          # "/path/to/file"

# Mnemonic: # is on left of $ on keyboard (beginning)
#           % is on right of $ on keyboard (end)
```

### Pattern Substitution
```bash
str="foo bar foo baz foo"

# Replace first occurrence
${str/foo/FOO}       # "FOO bar foo baz foo"

# Replace all occurrences
${str//foo/FOO}      # "FOO bar FOO baz FOO"

# Replace at beginning only
${str/#foo/FOO}      # "FOO bar foo baz foo"

# Replace at end only
str2="hello foo"
${str2/%foo/FOO}     # "hello FOO"

# Delete (replace with nothing)
${str//foo/}         # " bar  baz " (removes all "foo")
```

### Indirect Expansion
```bash
varname="greeting"
greeting="Hello"

# Get value of variable whose name is in another variable
${!varname}          # "Hello"

# List all variables with prefix
${!BASH*}            # Lists all BASH* variable names
${!USER*}            # Lists all USER* variable names
```

### Array Slicing
```bash
arr=(a b c d e f g)

# Slice from index with count
${arr[@]:2:3}        # c d e (start at 2, take 3)

# Slice from index to end
${arr[@]:4}          # e f g (from index 4 to end)

# Slice from beginning
${arr[@]::3}         # a b c (first 3 elements)

# Negative indices (Bash 4.3+)
${arr[@]: -3}        # e f g (last 3 elements)
${arr[-1]}           # g (last element)
```

**Sources**:
- [GNU Bash Manual - Parameter Expansion](https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html)
- [Parameter Expansion Guide - TecAdmin](https://tecadmin.net/bash-parameter-expansion/)
- [Array Slicing - LinuxSimply](https://linuxsimply.com/bash-scripting-tutorial/array/array-operations/array-slice/)

---

## 4. Nameref and Indirect Reference Patterns

Namerefs (Bash 4.3+) are essential for writing generic functions that can return values without subshells.

### Basic Nameref Pattern
```bash
# Function that "returns" a value via nameref
get_user_data() {
    local -n result=$1  # nameref to caller's variable
    result="John Doe"
}

# Usage
my_var=""
get_user_data my_var
echo "$my_var"  # "John Doe"
```

### Returning Multiple Values
```bash
parse_url() {
    local url="$1"
    local -n out_host=$2
    local -n out_port=$3
    local -n out_path=$4

    # Parse URL and set values
    out_host="${url#*://}"
    out_host="${out_host%%:*}"
    out_port="${url##*:}"
    out_port="${out_port%%/*}"
    out_path="${url#*://*/}"
}

# Usage
host="" port="" path=""
parse_url "https://example.com:8080/api/v1" host port path
echo "Host: $host, Port: $port, Path: $path"
```

### Modifying Variables In-Place
```bash
increment() {
    local -n num=$1
    ((num++))
}

counter=5
increment counter
echo "$counter"  # 6
```

### Nameref with Arrays
```bash
# Note: Arrays CANNOT be namerefs, but namerefs CAN reference arrays
populate_array() {
    local -n arr=$1
    arr=(one two three four)
}

my_array=()
populate_array my_array
echo "${my_array[@]}"  # one two three four

# Reference specific array element
get_element() {
    local -n elem=$1
    echo "Element value: $elem"
}

data=(alpha beta gamma)
get_element "data[1]"  # "Element value: beta"
```

### Flexible Return Pattern (Works With or Without Nameref)
```bash
# This pattern supports both stdout and nameref returns
flexible_func() {
    local result_var="${1:-}"
    local value="computed_value"

    if [[ -n "$result_var" ]]; then
        printf -v "$result_var" '%s' "$value"
    else
        printf '%s\n' "$value"
    fi
}

# Usage 1: Get via variable (no subshell)
flexible_func my_result
echo "$my_result"

# Usage 2: Get via stdout (subshell, but sometimes needed)
result=$(flexible_func)
```

### Nameref Naming Convention (Prevent Collisions)
```bash
# DANGER: If caller passes "result_", collision occurs
bad_func() {
    local -n result_=$1  # If caller passes "result_", infinite loop!
    local temp="value"
    result_=$temp
}

# SAFE: Use unlikely prefix/suffix
safe_func() {
    local -n __ref__=$1
    local _temp_="value"
    __ref__=$_temp_
}

# Or namespace with function name
my_module_func() {
    local -n _my_module_func_result=$1
    _my_module_func_result="value"
}
```

**Sources**:
- [Bash Namerefs - LinuxBash](https://www.linuxbash.sh/post/use-declare--n-for-indirect-variable-references)
- [BashFAQ/006 - Indirection](https://mywiki.wooledge.org/BashFAQ/006)
- [Approach Bash Like a Developer - Indirection](https://www.binaryphile.com/bash/2018/10/28/approach-bash-like-a-developer-part-34-indirection.html)

---

## 5. Functional Programming Patterns

Implementing `map`, `filter`, and `reduce` in pure bash enables composable, readable data transformations.

### Map Implementation
```bash
# Apply function to each element
# Usage: map <function> element1 element2 ...
# Or:    echo -e "a\nb\nc" | map <function>
map() {
    local func="$1"
    shift

    if [[ $# -gt 0 ]]; then
        # Arguments provided
        for item in "$@"; do
            "$func" "$item"
        done
    else
        # Read from stdin
        while IFS= read -r item || [[ -n "$item" ]]; do
            "$func" "$item"
        done
    fi
}

# Example functions
double() { echo $(($1 * 2)); }
upper() { echo "${1^^}"; }

# Usage
map double 1 2 3 4 5          # 2 4 6 8 10
echo -e "hello\nworld" | map upper  # HELLO WORLD
```

### Filter Implementation
```bash
# Keep elements where function returns 0 (true)
# Usage: filter <predicate> element1 element2 ...
filter() {
    local pred="$1"
    shift

    if [[ $# -gt 0 ]]; then
        for item in "$@"; do
            "$pred" "$item" && printf '%s\n' "$item"
        done
    else
        while IFS= read -r item || [[ -n "$item" ]]; do
            "$pred" "$item" && printf '%s\n' "$item"
        done
    fi
}

# Predicates
is_even() { (($1 % 2 == 0)); }
is_positive() { (($1 > 0)); }
starts_with_a() { [[ "$1" == a* ]]; }

# Usage
filter is_even 1 2 3 4 5 6    # 2 4 6
echo -e "apple\nbanana\napricot" | filter starts_with_a  # apple apricot
```

### Reduce Implementation
```bash
# Fold elements into single value
# Usage: reduce <function> <initial> element1 element2 ...
reduce() {
    local func="$1"
    local acc="$2"
    shift 2

    if [[ $# -gt 0 ]]; then
        for item in "$@"; do
            acc=$("$func" "$acc" "$item")
        done
    else
        while IFS= read -r item || [[ -n "$item" ]]; do
            acc=$("$func" "$acc" "$item")
        done
    fi
    printf '%s\n' "$acc"
}

# Binary functions for reduce
sum() { echo $(($1 + $2)); }
product() { echo $(($1 * $2)); }
concat() { echo "$1$2"; }
max() { (($1 > $2)) && echo "$1" || echo "$2"; }

# Usage
reduce sum 0 1 2 3 4 5        # 15
reduce product 1 2 3 4        # 24
reduce max 0 5 2 8 3 1        # 8
```

### High-Performance Variants (No Subshells)
```bash
# Map using nameref (no subshells in loop)
map_fast() {
    local func="$1"
    local -n _out=$2
    shift 2
    _out=()

    for item in "$@"; do
        local result
        "$func" "$item" result
        _out+=("$result")
    done
}

# Function that uses nameref for output
double_nr() {
    local -n _result=$2
    _result=$(($1 * 2))
}

# Usage
result_array=()
map_fast double_nr result_array 1 2 3 4 5
echo "${result_array[@]}"  # 2 4 6 8 10
```

### Composable Pipeline Style
```bash
# Chain operations using pipes
seq 1 10 \
    | filter is_even \
    | map double \
    | reduce sum 0
# Result: 60 (2+4+6+8+10 doubled = 4+8+12+16+20 = 60)
```

**Sources**:
- [bashFunc Library](https://github.com/timonson/bashFunc)
- [Functional Programming in Bash - Scalastic](https://scalastic.io/en/bash-functional-programming/)
- [Approach Bash Like a Developer - FP](http://www.binaryphile.com/bash/2018/10/31/approach-bash-like-a-developer-part-36-functional-programming.html)

---

## 6. Memory-Efficient Data Processing

When processing large files, avoid loading entire files into memory.

### Pattern 1: mapfile vs while-read Performance
```bash
# FASTEST: mapfile (Bash 4.0+)
# Loads entire file into array in one operation
mapfile -t lines < largefile.txt
for line in "${lines[@]}"; do
    process "$line"
done

# SLOWER but memory-efficient: while-read
# Processes line by line, constant memory
while IFS= read -r line || [[ -n "$line" ]]; do
    process "$line"
done < largefile.txt

# IMPORTANT: Use process substitution to keep in current shell
while IFS= read -r line; do
    ((count++))
done < <(command_that_outputs_lines)
```

### Pattern 2: Streaming Large Files
```bash
# Process file without loading into memory
# Good for files larger than available RAM
process_large_file() {
    local file="$1"
    local chunk_size="${2:-1000}"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Process line here
        process_line "$line"

        # Optional: Progress indicator every N lines
        ((line_num % chunk_size == 0)) && echo "Processed $line_num lines..." >&2
    done < "$file"
}
```

### Pattern 3: Batch Processing with mapfile
```bash
# Process file in batches to balance memory/performance
batch_process() {
    local file="$1"
    local batch_size="${2:-100}"
    local -a batch

    while mapfile -t -n "$batch_size" batch && ((${#batch[@]})); do
        # Process batch
        for item in "${batch[@]}"; do
            process "$item"
        done
    done < "$file"
}
```

### Pattern 4: Parallel Processing with Controlled Memory
```bash
# Process with limited parallelism
parallel_limited() {
    local max_jobs="${1:-4}"
    shift
    local -a items=("$@")
    local running=0

    for item in "${items[@]}"; do
        process_item "$item" &
        ((running++))

        if ((running >= max_jobs)); then
            wait -n  # Wait for any one job (Bash 4.3+)
            ((running--))
        fi
    done
    wait  # Wait for remaining jobs
}
```

### Pattern 5: Using Temporary Files for Intermediate Results
```bash
# For very large transformations, use temp files instead of variables
transform_large_data() {
    local input="$1"
    local tmp1 tmp2
    tmp1=$(mktemp)
    tmp2=$(mktemp)
    trap "rm -f '$tmp1' '$tmp2'" EXIT

    # Stage 1: Filter
    grep -E 'pattern' "$input" > "$tmp1"

    # Stage 2: Transform
    while IFS= read -r line; do
        transform "$line"
    done < "$tmp1" > "$tmp2"

    # Stage 3: Output
    cat "$tmp2"
}
```

**Sources**:
- [mapfile Performance - LinuxBash](https://www.linuxbash.sh/post/use-mapfile-to-read-files-faster-than-while-read-loops)
- [Script Performance Optimization - LinuxBash](https://www.linuxbash.sh/post/script-performance-optimization)

---

## 7. Advanced Pattern Matching

### BASH_REMATCH for Regex Capture Groups
```bash
# Extract parts from a string using regex
parse_semver() {
    local version="$1"
    local -n major=$2 minor=$3 patch=$4

    if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"
        return 0
    fi
    return 1
}

# Usage
maj="" min="" pat=""
parse_semver "1.2.3-beta" maj min pat
echo "Major: $maj, Minor: $min, Patch: $pat"  # 1, 2, 3
```

### BASH_REMATCH Reference
```bash
string="user@example.com"
if [[ "$string" =~ ^([^@]+)@(.+)$ ]]; then
    echo "Full match: ${BASH_REMATCH[0]}"    # user@example.com
    echo "Username: ${BASH_REMATCH[1]}"      # user
    echo "Domain: ${BASH_REMATCH[2]}"        # example.com
fi
```

### Extended Glob Patterns (extglob)
```bash
shopt -s extglob

# Pattern operators:
# ?(pattern)  - 0 or 1 occurrence
# *(pattern)  - 0 or more occurrences
# +(pattern)  - 1 or more occurrences
# @(pattern)  - exactly 1 occurrence
# !(pattern)  - anything EXCEPT pattern

# Examples:
file="document.backup.tar.gz"

# Match specific extensions
[[ "$file" == *.@(tar.gz|tgz|tar.bz2) ]] && echo "Compressed tar"

# Match anything except certain patterns
ls !(*.log|*.tmp)  # List all except .log and .tmp files

# Match optional parts
[[ "color" == colo?(u)r ]] && echo "Matches color or colour"

# Match one or more digits
[[ "file123" == file+([0-9]) ]] && echo "Matches file followed by digits"
```

### globstar for Recursive Matching
```bash
shopt -s globstar

# Match all .sh files recursively
for file in **/*.sh; do
    echo "$file"
done

# Match specific patterns at any depth
for config in **/config.{json,yaml,yml}; do
    process_config "$config"
done
```

### Pattern Matching in Case Statements
```bash
shopt -s extglob

case "$input" in
    +([0-9]))           echo "Integer" ;;
    +([0-9]).+([0-9]))  echo "Decimal" ;;
    @(yes|no|true|false)) echo "Boolean" ;;
    *.@(jpg|png|gif))   echo "Image file" ;;
    !(*.tmp|*.log))     echo "Not a temp/log file" ;;
    *)                  echo "Unknown" ;;
esac
```

### nullglob for Safe Iteration
```bash
shopt -s nullglob

# Without nullglob: if no match, glob is literal string
# With nullglob: if no match, glob expands to nothing

for file in *.nonexistent; do
    echo "$file"  # This loop runs 0 times with nullglob
done

# Useful for conditional processing
files=(*.txt)
if ((${#files[@]} > 0)); then
    echo "Found ${#files[@]} text files"
else
    echo "No text files found"
fi
```

**Sources**:
- [BASH_REMATCH - BashSupport](https://www.bashsupport.com/bash/variables/bash_rematch/)
- [Extended Globbing - Linux Journal](https://www.linuxjournal.com/content/bash-extended-globbing)
- [Pattern Matching - GNU Manual](https://www.gnu.org/software/bash/manual/html_node/Pattern-Matching.html)

---

## 8. Performance Benchmarking Techniques

### Using EPOCHREALTIME (Bash 5.0+)
```bash
# High-precision timing without external commands
benchmark() {
    local start end elapsed
    start=$EPOCHREALTIME

    # Code to benchmark
    "$@"

    end=$EPOCHREALTIME
    # Calculate difference (pure bash arithmetic can't do floats)
    # Convert to microseconds for integer math
    local start_us=${start/./}
    local end_us=${end/./}
    elapsed=$((end_us - start_us))

    printf 'Elapsed: %d.%06d seconds\n' $((elapsed / 1000000)) $((elapsed % 1000000))
}

# Usage
benchmark sleep 0.5
benchmark my_function arg1 arg2
```

### Simple Timing with EPOCHSECONDS
```bash
# Less precise but simpler
time_seconds() {
    local start=$EPOCHSECONDS
    "$@"
    local elapsed=$((EPOCHSECONDS - start))
    echo "Elapsed: ${elapsed}s"
}
```

### Comparative Benchmarking
```bash
compare_implementations() {
    local iterations="${1:-1000}"
    shift
    local -A results

    for impl in "$@"; do
        local start=$EPOCHREALTIME
        for ((i=0; i<iterations; i++)); do
            $impl >/dev/null 2>&1
        done
        local end=$EPOCHREALTIME
        local start_us=${start/./}
        local end_us=${end/./}
        results[$impl]=$((end_us - start_us))
    done

    # Print results
    printf "Results for %d iterations:\n" "$iterations"
    for impl in "${!results[@]}"; do
        local us=${results[$impl]}
        printf "  %-20s: %d.%03d ms\n" "$impl" $((us / 1000)) $((us % 1000))
    done
}

# Example
impl1() { result=$(echo "test" | tr 'a-z' 'A-Z'); }
impl2() { str="test"; result="${str^^}"; }
compare_implementations 1000 impl1 impl2
```

### Memory Usage Tracking
```bash
# Track memory before/after operation
memory_usage() {
    if [[ -f /proc/self/status ]]; then
        grep VmRSS /proc/self/status | awk '{print $2}'
    else
        ps -o rss= -p $$
    fi
}

track_memory() {
    local before after
    before=$(memory_usage)
    "$@"
    after=$(memory_usage)
    echo "Memory delta: $((after - before)) KB"
}
```

**Sources**:
- [EPOCHREALTIME - BashSupport](https://www.bashsupport.com/bash/variables/epochrealtime/)
- [EPOCHSECONDS - BashSupport](https://www.bashsupport.com/bash/variables/epochseconds/)
- [Measuring Execution Time - BashWizard](https://bashwizard.com/measuring-execution-time-part-2-of-2/)

---

## 9. Associative Array Patterns

### Basic Operations
```bash
declare -A config

# Set values
config[host]="localhost"
config[port]="8080"
config[debug]="true"

# Get value
echo "${config[host]}"

# Check if key exists
[[ -v config[host] ]] && echo "host is set"

# Get all keys
echo "${!config[@]}"  # host port debug

# Get all values
echo "${config[@]}"   # localhost 8080 true

# Iterate
for key in "${!config[@]}"; do
    echo "$key = ${config[$key]}"
done

# Delete key
unset 'config[debug]'

# Get length
echo "${#config[@]}"  # Number of keys
```

### Emulating Multi-Level Hashes
```bash
# Bash doesn't support nested arrays, but we can emulate with composite keys
declare -A data

# Store hierarchical data
data["user.name"]="John"
data["user.email"]="john@example.com"
data["server.host"]="localhost"
data["server.port"]="8080"

# Access
echo "${data[user.name]}"

# Get all keys under a "namespace"
for key in "${!data[@]}"; do
    [[ "$key" == user.* ]] && echo "$key = ${data[$key]}"
done
```

### JSON-like Object Builder
```bash
# Build JSON-like objects using associative arrays
declare -A user
user[name]="John Doe"
user[age]=30
user[active]=true

to_json() {
    local -n obj=$1
    local json="{"
    local first=1

    for key in "${!obj[@]}"; do
        ((first)) || json+=","
        first=0

        local val="${obj[$key]}"
        # Detect type (simplified)
        if [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" == "true" ]] || [[ "$val" == "false" ]]; then
            json+="\"$key\":$val"
        else
            json+="\"$key\":\"$val\""
        fi
    done

    echo "$json}"
}

to_json user  # {"name":"John Doe","age":30,"active":true}
```

### Performance Considerations
```bash
# Associative arrays use hash tables internally
# O(1) average lookup, but:
# - Earlier bash versions had O(n) insert for large arrays
# - Fixed in recent versions with proper rehashing

# For very large datasets (millions of entries), consider:
# 1. Using external tools (sqlite, redis)
# 2. Splitting into multiple smaller arrays
# 3. Using files with grep for lookup
```

**Sources**:
- [Bash Associative Arrays - PhoenixNAP](https://phoenixnap.com/kb/bash-associative-array)
- [Bash Performance Tricks - CodeArcana](https://codearcana.com/posts/2013/08/06/bash-performance-tricks.html)
- [Associative Array Performance Fix](https://eludom.github.io/blog/20200418/)

---

## 10. Recommendations for MAINFRAME

Based on this research, here are specific recommendations for enhancing the MAINFRAME library:

### High Priority Additions

#### 1. Add Nameref-Based Function Variants
```bash
# Current pattern (requires subshell):
result=$(json_object "name=John")

# Proposed addition (no subshell):
json_object_v result "name=John"

# Implementation:
json_object_v() {
    local -n __result=$1
    shift
    # ... existing logic ...
    __result="$json"
}
```

#### 2. Add EPOCHREALTIME Timing Functions
```bash
# New timing module
timer_start() {
    local -n __timer=$1
    __timer=$EPOCHREALTIME
}

timer_elapsed_ms() {
    local start="$1"
    local end="${2:-$EPOCHREALTIME}"
    local start_us=${start/./}
    local end_us=${end/./}
    echo $(( (end_us - start_us) / 1000 ))
}
```

#### 3. Add Memory-Efficient Stream Variants
```bash
# Batch processor that doesn't load entire file
stream_batch() {
    local batch_size="${1:-100}"
    local processor="$2"
    local -a batch

    while mapfile -t -n "$batch_size" batch && ((${#batch[@]})); do
        "$processor" "${batch[@]}"
    done
}
```

### Medium Priority Additions

#### 4. Enhanced Functional Programming Module
```bash
# New lib/functional.sh
# - map, filter, reduce with nameref variants
# - compose, pipe functions
# - curry, partial application
```

#### 5. Bash Version Detection and Feature Flags
```bash
# In common.sh
declare -g BASH_HAS_NAMEREFS=0
declare -g BASH_HAS_EPOCHREALTIME=0
declare -g BASH_HAS_ASSOC_ARRAYS=0

((BASH_VERSINFO[0] >= 4)) && BASH_HAS_ASSOC_ARRAYS=1
((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3))) && BASH_HAS_NAMEREFS=1
((BASH_VERSINFO[0] >= 5)) && BASH_HAS_EPOCHREALTIME=1
```

#### 6. Extended Glob Helpers
```bash
# Enable safely and provide helpers
enable_extglob() {
    shopt -s extglob nullglob globstar
}

# Pattern helpers
glob_except() {
    local pattern="$1"
    shopt -s extglob
    printf '%s\n' !($pattern)
}
```

### Documentation Additions

#### 7. Performance Guidelines Section
Add to CLAUDE.md or create PERFORMANCE.md:
- When to use subshells vs namerefs
- Memory vs speed tradeoffs
- Batch size recommendations
- External command alternatives

#### 8. Pattern Cookbook
Common patterns with before/after showing the optimization:
- String manipulation without sed
- Arithmetic without expr
- File processing without awk
- JSON building without jq

---

## References and Sources

### Official Documentation
- [GNU Bash Manual - Parameter Expansion](https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html)
- [GNU Bash Manual - Pattern Matching](https://www.gnu.org/software/bash/manual/html_node/Pattern-Matching.html)
- [GNU Bash Manual - Process Substitution](https://www.gnu.org/software/bash/manual/html_node/Process-Substitution.html)
- [Bash CHANGES - GitHub](https://github.com/bminor/bash/blob/master/CHANGES)

### Performance and Optimization
- [Bash Performance Optimization - MoldStud](https://moldstud.com/articles/p-how-to-avoid-common-bash-scripting-performance-issues-essential-tips-and-best-practices)
- [Bash Performance Tricks - CodeArcana](https://codearcana.com/posts/2013/08/06/bash-performance-tricks.html)
- [Avoid Subshells in Loops - LinuxBash](https://www.linuxbash.sh/post/avoid-subshells-in-loops-using-process-substitution)
- [Script Performance Optimization - LinuxBash](https://www.linuxbash.sh/post/script-performance-optimization)

### Functional Programming
- [bashFunc Library - GitHub](https://github.com/timonson/bashFunc)
- [bash-lambda - GitHub](https://github.com/spencertipping/bash-lambda)
- [Functional Programming in Bash - Scalastic](https://scalastic.io/en/bash-functional-programming/)
- [Approach Bash Like a Developer - FP](http://www.binaryphile.com/bash/2018/10/31/approach-bash-like-a-developer-part-36-functional-programming.html)

### Version-Specific Features
- [Bash 5.0 Features - Packt](https://www.packtpub.com/en-us/learning/how-to-tutorials/gnu-bash-5-0-is-here-with-new-features-and-improvements)
- [Bash 5.3 Release - Phoronix](https://www.phoronix.com/news/GNU-Bash-5.3)
- [Bash 5.3 Command Substitution - Linuxiac](https://linuxiac.com/bash-shell-5-3-released-with-new-command-substitution/)
- [What's New in Bash 5 - Shell-Tips](https://www.shell-tips.com/bash/what-is-new-in-gnu-bash-5/)

### Indirection and Namerefs
- [BashFAQ/006 - Indirection](https://mywiki.wooledge.org/BashFAQ/006)
- [Namerefs - LinuxBash](https://www.linuxbash.sh/post/use-declare--n-for-indirect-variable-references)
- [Approach Bash Like a Developer - Indirection](https://www.binaryphile.com/bash/2018/10/28/approach-bash-like-a-developer-part-34-indirection.html)

### Pattern Matching
- [Extended Globbing - Linux Journal](https://www.linuxjournal.com/content/bash-extended-globbing)
- [BASH_REMATCH - Linux Journal](https://www.linuxjournal.com/content/bash-regular-expressions)
- [Greg's Wiki - Patterns](https://mywiki.wooledge.org/BashGuide/Patterns)

---

*Research compiled: 2026-01-22*
*Target: MAINFRAME Pure Bash Library*
*Minimum Bash Version: 4.0 (4.3+ recommended for namerefs)*
