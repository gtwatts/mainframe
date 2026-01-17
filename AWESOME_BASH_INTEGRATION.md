# MAINFRAME: Awesome Bash Integration

```
    __  ______    _____   ________  ___    __  _________
   /  |/  /   |  /  _/ | / / ____/ / _ \  /  |/  / ____/
  / /|_/ / /| |  / //  |/ / /_    / , _/ / /|_/ / __/
 / /  / / ___ |_/ // /|  / __/   / /| | / /  / / /___
/_/  /_/_/  |_/___/_/ |_/_/     /_/ |_|/_/  /_/_____/

    "Knowing your shell is half the battle."
```

**Source**: https://github.com/awesome-lists/awesome-bash
**Purpose**: Integrate best-of-breed bash tools and techniques into MAINFRAME

---

## Implementation Status

### COMPLETED Libraries

| Library | Source | Status | Location |
|---------|--------|--------|----------|
| **pure-string.sh** | Pure Bash Bible | DONE | `lib/pure-string.sh` |
| **pure-array.sh** | Pure Bash Bible | DONE | `lib/pure-array.sh` |
| **pure-util.sh** | Pure Bash Bible | DONE | `lib/pure-util.sh` |
| **pure-file.sh** | Pure Bash Bible | DONE | `lib/pure-file.sh` |
| **semver.sh** | cloudflare/semver_bash | DONE | `lib/semver.sh` |
| **ansi.sh** | fidian/ansi | DONE | `lib/ansi.sh` |
| **json.sh** | h4l/json.bash | DONE | `lib/json.sh` |
| **async.sh** | zombieleet/async-bash | DONE | `lib/async.sh` |

### COMPLETED Scripts

| Script | Source | Status | Location |
|--------|--------|--------|----------|
| **has.sh** | kdabir/has | DONE | `scripts/env/has.sh` |
| **validate-input.sh** | Black Hat Bash | DONE | `scripts/validation/validate-input.sh` |
| **debug-script.sh** | Black Hat Bash | DONE | `scripts/debug/debug-script.sh` |

### Testing Infrastructure

| Component | Status | Location |
|-----------|--------|----------|
| **test_helper.bash** | DONE | `tests/test_helper.bash` |
| **pure-string.bats** | DONE | `tests/pure-string.bats` |
| **pure-array.bats** | DONE | `tests/pure-array.bats` |

---

## Resource Categories

### Tier 1: CRITICAL (Integrated)

| Resource | Why It's Critical | Status |
|----------|-------------------|--------|
| **Pure Bash Bible** | Eliminates external dependencies | INTEGRATED |
| **bash3boilerplate** | Battle-tested script template | TEMPLATE ADOPTED |
| **shellcheck** | Static analysis | REFERENCED |
| **bats-core** | Testing framework | TESTS CREATED |
| **argbash** | Argument parsing generator | PATTERNS USED |

### Tier 2: HIGH VALUE (Partially Integrated)

| Resource | Value Add | Status |
|----------|-----------|--------|
| **Bashmatic** (900+ functions) | DSL for common operations | PATTERNS STUDIED |
| **DevOps-Bash-tools** (1000+ scripts) | Ready-made recipes | PATTERNS STUDIED |
| **has** | Command presence checker | INTEGRATED |
| **semver_bash** | Version management | INTEGRATED |
| **modernish** | Cross-shell compatibility | PATTERNS USED |
| **fidian/ansi** | ANSI escape codes | INTEGRATED |
| **json.bash** | JSON generation | INTEGRATED |
| **async-bash** | Async patterns | INTEGRATED |

---

## Complete Resource Reference

### Documentation & Learning

| Resource | URL | Description |
|----------|-----|-------------|
| Bash-Hackers Wiki | https://web.archive.org/web/20230406205817/https://wiki.bash-hackers.org/ | Human-readable bash docs |
| Bash FAQ (Wooledge) | http://mywiki.wooledge.org/BashFAQ | Frequently asked questions |
| Bash Pitfalls | http://mywiki.wooledge.org/BashPitfalls | Common mistakes to avoid |
| Bash Manual | http://www.gnu.org/software/bash/manual/ | Official GNU manual |
| Google Shell Style Guide | https://google.github.io/styleguide/shellguide.html | Style guidelines |
| Pure Bash Bible | https://github.com/dylanaraps/pure-bash-bible | Pure bash alternatives |
| explainshell | https://explainshell.com | Command explanation |
| Safe Bash | https://github.com/anordal/shellharden/blob/master/how_to_do_things_safely_in_bash.md | Safety practices |

### Command-Line Productivity

| Tool | URL | Description |
|------|-----|-------------|
| aliases | https://github.com/sebglazebrook/aliases | Contextual aliases |
| bashmarks | https://github.com/huyng/bashmarks | Directory bookmarks |
| ble.sh | https://github.com/akinomyoga/ble.sh | Readline replacement |
| fzf | https://github.com/junegunn/fzf | Fuzzy finder |
| hstr | https://github.com/dvorka/hstr | History suggest box |
| zoxide | https://github.com/ajeetdsouza/zoxide | Smarter cd |

### Script Development Frameworks

| Framework | URL | Description |
|-----------|-----|-------------|
| bash3boilerplate | https://github.com/kvz/bash3boilerplate | Script templates |
| bashly | https://github.com/DannyBen/bashly | CLI framework |
| Bash Infinity | https://github.com/niieani/bash-oo-framework | Modern framework |
| Bashmatic | https://github.com/kigster/bashmatic | DSL library (900+ functions) |
| lobash | https://github.com/adoyle-h/lobash | Utility library |

### Testing Frameworks

| Framework | URL | Description |
|-----------|-----|-------------|
| bats-core | https://github.com/bats-core/bats-core | TAP-compliant testing |
| assert.sh | https://github.com/lehmannro/assert.sh | Simple assertions |
| shunit2 | https://github.com/kward/shunit2 | JUnit-style testing |
| bash_unit | https://github.com/pgrange/bash_unit | Unit testing |
| bashunit | https://github.com/TypedDevs/bashunit | Simple testing |

### Static Analysis & Formatting

| Tool | URL | Description |
|------|-----|-------------|
| shellcheck | https://github.com/koalaman/shellcheck | Static analysis |
| shellharden | https://github.com/anordal/shellharden | Syntax correction |
| shfmt | https://github.com/mvdan/sh | Code formatter |

### DevOps & Automation

| Tool | URL | Description |
|------|-----|-------------|
| DevOps-Bash-tools | https://github.com/HariSekhon/DevOps-Bash-tools | 1000+ DevOps scripts |
| utility-bash-scripts | https://github.com/aviaryan/utility-bash-scripts | Automation scripts |
| mkdkr | https://github.com/rosineygp/mkdkr | Make + Docker CI |

### Package Management

| Tool | URL | Description |
|------|-----|-------------|
| bash-it | https://github.com/Bash-it/bash-it | Community framework |
| basher | https://github.com/basherpm/basher | Script package manager |
| bpkg | https://github.com/bpkg/bpkg | Lightweight PM |
| homeshick | https://github.com/andsens/homeshick | Dotfile sync |

### Customization & Theming

| Tool | URL | Description |
|------|-----|-------------|
| oh-my-bash | https://github.com/ohmybash/oh-my-bash | Bash configuration |
| bash-git-prompt | https://github.com/magicmonty/bash-git-prompt | Git-aware prompt |
| liquidprompt | https://github.com/nojhan/liquidprompt | Adaptive prompt |
| sexy-bash-prompt | https://github.com/twolfson/sexy-bash-prompt | Colored prompt |
| bash-sensible | https://github.com/mrzool/bash-sensible | Saner defaults |

### Web Servers & Networking

| Tool | URL | Description |
|------|-----|-------------|
| bashttpd | https://github.com/avleen/bashttpd | Web server in bash |
| sherver | https://github.com/remileduc/sherver | Lightweight server |
| bash-stack | https://github.com/cgsdev0/bash-stack | Modern web framework |
| Dropbox-Uploader | https://github.com/andreafabrizi/Dropbox-Uploader | Dropbox CLI |

### Applications

| Tool | URL | Description |
|------|-----|-------------|
| todo.sh | https://github.com/todotxt/todo.txt-cli | Todo manager |
| bashblog | https://github.com/cfenollosa/bashblog | Blog posting |

### Community

| Resource | URL |
|----------|-----|
| Stack Overflow | http://stackoverflow.com/questions/tagged/bash |
| r/bash | https://www.reddit.com/r/bash |
| r/commandline | https://www.reddit.com/r/commandline |
| Bash One-Liners | http://www.bashoneliners.com/ |
| commandlinefu | http://www.commandlinefu.com/ |

---

## MAINFRAME Library Reference

### lib/pure-string.sh

String manipulation without sed/awk:

```bash
# Whitespace
trim_string "  hello  "      # "hello"
trim_left "  hello"          # "hello"
trim_right "hello  "         # "hello"

# Case conversion (Bash 4+)
to_lower "HELLO"             # "hello"
to_upper "hello"             # "HELLO"
capitalize "hello"           # "Hello"
reverse_case "HeLLo"         # "hEllO"

# Pattern operations
strip_all "hello" "l"        # "heo"
strip_first "hello" "l"      # "helo"
lstrip "hello" "hel"         # "lo"
rstrip "hello" "lo"          # "hel"
replace_all "hello" "l" "L"  # "heLLo"

# Substring
substring "hello" 1 3        # "ell"
strlen "hello"               # "5"
char_at "hello" 2            # "l"

# Checks
contains "hello world" "world"    # true
starts_with "hello" "hel"         # true
ends_with "hello" "lo"            # true
is_empty ""                       # true
matches "abc123" '^[a-z]+[0-9]+$' # true

# URL encoding
urlencode "hello world"      # "hello%20world"
urldecode "hello%20world"    # "hello world"

# Generation
repeat_string "-" 10         # "----------"
pad_right "hi" 5 "."         # "hi..."
pad_left "hi" 5 "."          # "...hi"
center "hi" 10               # "    hi    "
```

### lib/pure-array.sh

Array operations without external tools:

```bash
# Basics
array_length "a" "b" "c"     # "3"
array_first "a" "b" "c"      # "a"
array_last "a" "b" "c"       # "c"
array_get 1 "a" "b" "c"      # "b"

# Search
array_contains "b" "a" "b" "c"    # true
array_index_of "b" "a" "b" "c"    # "1"
array_count "a" "a" "b" "a"       # "3"

# Transform
array_reverse "a" "b" "c"    # c, b, a
array_unique "a" "b" "a"     # a, b
array_sort "c" "a" "b"       # a, b, c
array_sort_num "10" "2" "1"  # 1, 2, 10
array_shuffle "a" "b" "c"    # random order

# Selection
array_random "a" "b" "c"     # random element
array_sample 2 "a" "b" "c"   # 2 random elements
array_filter '*or*' ...      # matching elements
array_reject '*or*' ...      # non-matching elements

# Join
array_join "," "a" "b" "c"   # "a,b,c"

# Comparison (pass array names)
array_intersect arr1 arr2    # common elements
array_diff arr1 arr2         # elements only in arr1
array_union arr1 arr2        # combined unique

# Aggregation
array_sum 1 2 3 4 5          # "15"
array_min 5 2 8 1 9          # "1"
array_max 5 2 8 1 9          # "9"
array_avg 2 4 6 8 10         # "6"
```

### lib/pure-util.sh

Utilities without external commands:

```bash
# Time
timestamp                     # "2024-01-15 10:30:45"
timestamp_iso                 # "2024-01-15T10:30:45-0500"
epoch                         # "1705326645"
format_date "%Y-%m-%d"        # "2024-01-15"
day_of_week                   # "Monday"

# Random
uuid                          # UUID v4
random_string 16              # 16-char alphanumeric
random_range 1 100            # number between 1-100
random_hex 8                  # 8-char hex string

# Colors
hex_to_rgb "#ff5500"          # "255 85 0"
rgb_to_hex 255 85 0           # "#ff5500"

# Terminal
term_size                     # "24 80" (lines columns)
term_width                    # "80"
term_height                   # "24"
is_terminal                   # true if stdout is terminal

# System
is_root                       # true if running as root
is_macos                      # true on macOS
is_linux                      # true on Linux
is_wsl                        # true on WSL

# Commands
cmd_exists curl               # true if curl installed
cmd_path curl                 # "/usr/bin/curl"
cmd_version curl              # curl version string

# Validation
is_int "123"                  # true
is_positive_int "123"         # true
is_float "3.14"               # true
is_hex "ff00ff"               # true
is_ip "192.168.1.1"           # true
is_email "a@b.com"            # true
is_url "https://x.com"        # true

# Path operations
basename_pure "/path/to/file.txt"    # "file.txt"
dirname_pure "/path/to/file.txt"     # "/path/to"
extension "/path/to/file.txt"        # "txt"
filename_no_ext "/path/to/file.txt"  # "file"

# Math
abs -5                        # "5"
clamp 150 0 100               # "100"
pow 2 10                      # "1024"
factorial 5                   # "120"
gcd 24 36                     # "12"
lcm 4 6                       # "12"

# Progress
progress_bar 50 100           # [###...] 50%
show_spinner $pid             # spinning indicator
```

### lib/pure-file.sh

File operations without cat/head/tail:

```bash
# Reading
read_file "/path/to/file"              # entire file
read_file_lines "/path" arr            # into array
file_head 10 "/path/to/file"           # first 10 lines
file_tail 10 "/path/to/file"           # last 10 lines
file_line 5 "/path/to/file"            # line 5
file_range 5 10 "/path/to/file"        # lines 5-10

# Info
file_lines "/path/to/file"             # line count
file_words "/path/to/file"             # word count
file_chars "/path/to/file"             # char count
file_size "/path/to/file"              # bytes

# Checks
file_exists "/path/to/file"            # true
dir_exists "/path/to/dir"              # true
file_empty "/path/to/file"             # true if empty
file_readable "/path/to/file"          # true
file_writable "/path/to/file"          # true
file_executable "/path/to/file"        # true
file_symlink "/path/to/file"           # true
file_newer "file1" "file2"             # true if file1 newer

# Path operations
path_basename "/path/to/file.txt"      # "file.txt"
path_dirname "/path/to/file.txt"       # "/path/to"
path_extension "/path/to/file.txt"     # "txt"
path_stem "/path/to/file.txt"          # "file"
path_join "/path" "to" "file.txt"      # "/path/to/file.txt"
path_is_absolute "/path/to/file"       # true
path_is_relative "path/to/file"        # true

# Creation
file_touch "/path/to/file"             # create empty
file_write "/path" "content"           # write content
file_append "/path" "content"          # append content
dir_create "/path/to/new/dir"          # mkdir -p

# Glob
glob_files "*.sh"                      # matching files
glob_dirs "/path"                      # subdirectories
find_by_ext ".sh" "/path"              # recursive find

# Content
file_grep "pattern" "/path"            # grep-like
file_count_pattern "pattern" "/path"   # count matches
file_replace "old" "new" "/path"       # replace in content
```

### lib/semver.sh

Semantic versioning:

```bash
# Parsing (sets SEMVER_MAJOR, SEMVER_MINOR, SEMVER_PATCH, etc.)
semver_parse "1.2.3-alpha.1+build.123"
semver_valid "1.2.3"                   # true
semver_normalize "v1.2"                # "1.2.0"

# Comparison
semver_compare "1.2.3" "1.2.4"         # 0=equal, 1=gt, 2=lt
semver_eq "1.2.3" "1.2.3"              # true
semver_gt "1.2.4" "1.2.3"              # true
semver_ge "1.2.3" "1.2.3"              # true
semver_lt "1.2.3" "1.2.4"              # true
semver_le "1.2.3" "1.2.3"              # true

# Manipulation
semver_bump_major "1.2.3"              # "2.0.0"
semver_bump_minor "1.2.3"              # "1.3.0"
semver_bump_patch "1.2.3"              # "1.2.4"
semver_set_prerelease "1.2.3" "alpha"  # "1.2.3-alpha"
semver_set_build "1.2.3" "123"         # "1.2.3+123"
semver_release "1.2.3-alpha+build"     # "1.2.3"

# Range checking
semver_satisfies "1.2.3" ">=1.0.0"     # true
semver_satisfies "1.2.3" "^1.0.0"      # true (caret)
semver_satisfies "1.2.3" "~1.2.0"      # true (tilde)

# Utilities
semver_latest "1.0.0" "1.2.0" "1.1.0"  # "1.2.0"
semver_sort "1.2.0" "1.0.0" "1.1.0"    # sorted list
semver_format "1.2.3" "v"              # "v1.2.3"
```

### lib/ansi.sh

ANSI terminal escape codes:

```bash
# Foreground colors
ansi_red; ansi_green; ansi_blue; ansi_yellow; ...
ansi_bright_red; ansi_bright_green; ...

# Background colors
ansi_bg_red; ansi_bg_green; ansi_bg_blue; ...
ansi_bg_bright_red; ...

# 256 colors
ansi_color 196                         # palette color
ansi_bg_color 196

# True color (24-bit)
ansi_rgb 255 128 0                     # RGB foreground
ansi_bg_rgb 255 128 0                  # RGB background
ansi_hex "#ff8000"                     # hex foreground
ansi_bg_hex "#ff8000"                  # hex background

# Formatting
ansi_bold; ansi_dim; ansi_italic; ansi_underline
ansi_blink; ansi_inverse; ansi_strike
ansi_reset                             # reset all

# Cursor movement
ansi_up 5; ansi_down 5; ansi_forward 5; ansi_backward 5
ansi_position 5 10                     # row, column
ansi_save_cursor; ansi_restore_cursor
ansi_hide_cursor; ansi_show_cursor

# Display
ansi_clear                             # clear screen
ansi_erase_line                        # clear line
ansi_erase_screen                      # clear screen

# Terminal
ansi_bell                              # beep
ansi_title "My Terminal"               # set title

# Convenience
ansi_print red "Error message"         # colored output
ansi_styled "bold,red" "Important!"    # styled output
ansi_color_table                       # display colors
```

### lib/json.sh

JSON generation in pure bash:

```bash
# String escaping
json_escape "hello\nworld"             # escaped string

# Values
json_string "hello"                    # "hello"
json_number 42                         # 42
json_bool true                         # true
json_null                              # null
json_value "auto-detect"               # auto-typed

# Arrays
json_array "a" "b" "c"                 # ["a","b","c"]
json_array_typed number 1 2 3          # [1,2,3]
echo -e "a\nb" | json_array_from_lines # ["a","b"]

# Objects
json_object name="John" age:number=30  # {"name":"John","age":30}
json_from_assoc myarray                # from assoc array
json_nested "a.b.c" "value"            # {"a":{"b":{"c":"value"}}}

# Merging
json_merge '{"a":1}' '{"b":2}'         # {"a":1,"b":2}

# Pretty print
json_pretty '{"a":1}'                  # formatted output

# Validation
json_valid '{"a":1}'                   # true

# Extraction (simple)
json_get '{"name":"John"}' "name"      # "John"
json_keys '{"a":1,"b":2}'              # a, b

# File operations
json_read "/path/to/file.json"         # read file
json_write "/path" '{"a":1}'           # write file
json_write_pretty "/path" '{"a":1}'    # write formatted
```

### lib/async.sh

Asynchronous execution:

```bash
# Timers (like JavaScript)
pid=$(set_timeout 5 "echo hello")      # after 5 seconds
pid=$(set_interval 5 "echo tick")      # every 5 seconds
clear_timeout $pid                      # cancel
clear_interval $pid

# Async execution
pid=$(async "long_command")            # run in background
pid=$(async_callback "cmd" "on_ok" "on_fail")
pid=$(promise "cmd" resolve reject)

# Parallel execution
parallel "cmd1" "cmd2" "cmd3"          # run all
parallel_limit 4 "cmd1" "cmd2" ...     # max 4 concurrent
parallel_map "func" "${items[@]}"      # map over array
parallel_map_limit 4 "func" "${items[@]}"

# Job management
async_jobs                             # list jobs
async_kill $pid                        # kill job
async_kill_all                         # kill all
async_wait $pid                        # wait for job
async_wait_all                         # wait for all

# Debounce & Throttle
debounce "my_func" 2                   # wait 2s without calls
throttle "my_func" 2                   # max once per 2s

# Retry
retry 5 "curl http://example.com"      # retry with backoff
retry_callback 5 "cmd" "on_fail"       # with callback
```

---

## Script Template (MAINFRAME Standard)

```bash
#!/usr/bin/env bash
# =============================================================================
# MAINFRAME: Script Name
# =============================================================================
# Description: What this script does
# Category:    category
# WOW Factor:  X/10
# =============================================================================

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$MAINFRAME_ROOT/lib/common.sh"

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_VERSION="1.0.0"

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [options] <arguments>

Options:
    -h, --help      Show this help
    -v, --version   Show version

YO JOE!
EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) show_help; exit 0 ;;
            -v|--version) printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
            *) break ;;
        esac
    done

    # Script logic here
    info "Starting $SCRIPT_NAME..."
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
```

---

## Key Takeaways

1. **Pure Bash > External Tools**: Parameter expansion is faster than sed/awk
2. **Strict Mode**: Always use `set -euo pipefail`
3. **Test Everything**: BATS provides robust testing
4. **Document Well**: Inline help reduces user friction
5. **Fail Fast**: Validate inputs before execution
6. **Use Libraries**: Don't reinvent - use MAINFRAME's lib/

---

**YO JOE!**
