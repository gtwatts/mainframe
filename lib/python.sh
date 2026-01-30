#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/python.sh - Python Analysis Library
# =============================================================================
# Description: Pure bash Python project analysis - import graphs, dependency
#              parsing, code quality metrics. Zero dependencies (grep/find based).
# =============================================================================
# LIMITATIONS (regex-based parsing, not AST):
#   - Cannot resolve dynamic imports: __import__('module') or importlib
#   - Cannot handle star imports accurately: from foo import *
#   - May false-positive on imports inside multiline strings or comments
#   - Cannot detect conditional imports (inside if/try blocks) vs top-level
#   - Complexity estimation is approximate (counts keywords, not control flow)
#   - Type hint detection uses heuristics, not full PEP 484 parsing
#   - pyproject.toml parsing handles simple cases only (not nested TOML)
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PY_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Join multiline parenthesized imports into single lines
# Reads stdin, outputs normalized lines
_py_join_multiline_imports() {
    local in_paren=0
    local buffer=""

    while IFS= read -r line; do
        if [[ $in_paren -eq 1 ]]; then
            buffer+=" ${line}"
            if [[ "$line" == *")"* ]]; then
                in_paren=0
                echo "$buffer"
                buffer=""
            fi
        elif [[ "$line" =~ (import|from)[[:space:]] && "$line" == *"("* && "$line" != *")"* ]]; then
            in_paren=1
            buffer="$line"
        else
            echo "$line"
        fi
    done
    # Flush remaining buffer
    [[ -n "$buffer" ]] && echo "$buffer"
}

# Known Python stdlib modules (top-level, Python 3.8+)
_py_stdlib_modules() {
    echo "abc ast asyncio atexit base64 binascii bisect builtins bz2 calendar cgi cgitb chunk cmath cmd code codecs codeop collections colorsys compileall concurrent configparser contextlib contextvars copy copyreg cProfile csv ctypes curses dataclasses datetime dbm decimal difflib dis distutils doctest email encodings enum errno faulthandler fcntl filecmp fileinput fnmatch fractions ftplib functools gc getopt getpass gettext glob grp gzip hashlib heapq hmac html http idlelib imaplib imghdr imp importlib inspect io ipaddress itertools json keyword lib2to3 linecache locale logging lzma mailbox mailcap marshal math mimetypes mmap modulefinder multiprocessing netrc nis nntplib numbers operator optparse os ossaudiodev pathlib pdb pickle pickletools pipes pkgutil platform plistlib poplib posix posixpath pprint profile pstats pty pwd py_compile pyclbr pydoc queue quopri random re readline reprlib resource rlcompleter runpy sched secrets select selectors shelve shlex shutil signal site smtpd smtplib sndhdr socket socketserver sqlite3 sre_compile sre_constants sre_parse ssl stat statistics string stringprep struct subprocess sunau symtable sys sysconfig syslog tabnanny tarfile tempfile termios test textwrap threading time timeit tkinter token tokenize trace traceback tracemalloc tty turtle turtledemo types typing unicodedata unittest urllib uu uuid venv warnings wave weakref webbrowser winreg winsound wsgiref xdrlib xml xmlrpc zipapp zipfile zipimport zlib"
}

# =============================================================================
# PROJECT DETECTION
# =============================================================================

# Check if directory is a Python project
# Returns: 0 if Python project, 1 otherwise
py_is_project() {
    local dir="${1:-.}"
    [[ -f "$dir/setup.py" ]] && return 0
    [[ -f "$dir/setup.cfg" ]] && return 0
    [[ -f "$dir/pyproject.toml" ]] && return 0
    [[ -f "$dir/requirements.txt" ]] && return 0
    [[ -f "$dir/Pipfile" ]] && return 0
    # Check for .py files
    local py_count
    py_count=$(find "$dir" -maxdepth 2 -name "*.py" 2>/dev/null | grep -vc "node_modules\|\.venv\|venv\|__pycache__" 2>/dev/null || echo "0")
    [[ "$py_count" -gt 0 ]] && return 0
    return 1
}

# Detect source directory (src layout vs flat)
py_source_dir() {
    local dir="${1:-.}"
    # Check for src layout
    if [[ -d "$dir/src" ]]; then
        local pkg
        pkg=$(find "$dir/src" -maxdepth 1 -type d ! -name src ! -name "__pycache__" 2>/dev/null | head -1)
        [[ -n "$pkg" ]] && echo "$pkg" && return 0
        echo "$dir/src"
        return 0
    fi
    # Check for package with __init__.py
    local init
    init=$(find "$dir" -maxdepth 2 -name "__init__.py" ! -path "*/venv/*" ! -path "*/.venv/*" ! -path "*/__pycache__/*" ! -path "*/test*/*" 2>/dev/null | head -1)
    if [[ -n "$init" ]]; then
        dirname "$init"
        return 0
    fi
    echo "$dir"
    return 0
}

# =============================================================================
# PYMINER - IMPORT ANALYSIS
# =============================================================================

# Extract imports from a Python file
# Handles: import x, from x import y, multiline parenthesized imports
# Output: One module per line
py_file_imports() {
    local file="$1"
    [[ ! -f "$file" ]] && echo "Error: file not found: $file" >&2 && return 1

    # Preprocess: join multiline imports, then extract
    _py_join_multiline_imports < "$file" | while IFS= read -r line; do
        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Match: from module import ...
        if [[ "$line" =~ ^[[:space:]]*(from)[[:space:]]+([a-zA-Z0-9_.]+)[[:space:]]+import ]]; then
            echo "${BASH_REMATCH[2]}"
        # Match: import module1, module2
        elif [[ "$line" =~ ^[[:space:]]*(import)[[:space:]]+(.+) ]]; then
            local imports="${BASH_REMATCH[2]}"
            # Remove 'as' aliases and split by comma
            imports="${imports%%#*}"  # Remove inline comments
            while [[ "$imports" == *","* ]]; do
                local mod="${imports%%,*}"
                mod="${mod%% as *}"
                mod="${mod## }"
                mod="${mod%% }"
                [[ -n "$mod" ]] && echo "$mod"
                imports="${imports#*,}"
            done
            imports="${imports%% as *}"
            imports="${imports## }"
            imports="${imports%% }"
            [[ -n "$imports" ]] && echo "$imports"
        fi
    done | sort -u
}

# Count import frequency across a project
# Output: "count module" lines sorted by frequency
py_import_frequency() {
    local dir="${1:-.}"
    local threshold="${2:-1}"

    py_is_project "$dir" || { echo "Not a Python project: $dir" >&2; return 1; }

    local tmp
    tmp=$(mktemp)

    find "$dir" -name "*.py" ! -path "*/venv/*" ! -path "*/.venv/*" ! -path "*/__pycache__/*" ! -path "*/node_modules/*" 2>/dev/null | while IFS= read -r file; do
        py_file_imports "$file"
    done | sort | uniq -c | sort -rn | while read -r count mod; do
        [[ "$count" -ge "$threshold" ]] && printf "%4d %s\n" "$count" "$mod"
    done | tee "$tmp"

    local result
    result=$(< "$tmp")
    rm -f "$tmp"
    return 0
}

# Build import dependency graph
# Output: "file -> module" edges
py_import_graph() {
    local dir="${1:-.}"
    py_is_project "$dir" || { echo "Not a Python project: $dir" >&2; return 1; }

    find "$dir" -name "*.py" ! -path "*/venv/*" ! -path "*/.venv/*" ! -path "*/__pycache__/*" ! -path "*/node_modules/*" ! -path "*/test*/*" 2>/dev/null | while IFS= read -r file; do
        local basename="${file#$dir/}"
        py_file_imports "$file" | while IFS= read -r mod; do
            echo "$basename -> $mod"
        done
    done
}

# Detect circular imports using DFS
# Output: Circular dependency chains
py_circular_deps() {
    local dir="${1:-.}"
    py_is_project "$dir" || { echo "Not a Python project: $dir" >&2; return 1; }

    # Build adjacency list from local imports
    local tmp_graph
    tmp_graph=$(mktemp)

    find "$dir" -name "*.py" ! -path "*/venv/*" ! -path "*/.venv/*" ! -path "*/__pycache__/*" 2>/dev/null | while IFS= read -r file; do
        local basename="${file#$dir/}"
        local modname="${basename%.py}"
        modname="${modname//\//.}"

        py_file_imports "$file" | while IFS= read -r imp; do
            # Only track relative/local imports (starting with . or matching project modules)
            if [[ "$imp" == .* ]]; then
                echo "$modname -> $imp"
            fi
        done
    done > "$tmp_graph"

    # Simple cycle detection: check if A->B and B->A exist
    local tmp_lookup="${tmp_graph}.lookup"
    cp "$tmp_graph" "$tmp_lookup"
    local found=0
    while IFS= read -r edge; do
        local from="${edge%% -> *}"
        local to="${edge##* -> }"
        # Check reverse edge
        if grep -q "^${to} -> ${from}$" "$tmp_lookup" 2>/dev/null; then
            echo "CIRCULAR: $from <-> $to"
            found=1
        fi
    done < "$tmp_graph"

    rm -f "$tmp_graph" "$tmp_lookup"
    [[ $found -eq 0 ]] && echo "No circular dependencies detected"
    return 0
}

# Classify an import as stdlib, third-party, or local
# Output: "stdlib", "third-party", or "local"
py_import_classify() {
    local module="$1"
    local dir="${2:-.}"

    # Relative imports are always local
    [[ "$module" == .* ]] && echo "local" && return 0

    # Get top-level module name
    local top="${module%%.*}"

    # Check if it's a known stdlib module
    local stdlib
    stdlib=$(_py_stdlib_modules)
    if [[ " $stdlib " == *" $top "* ]]; then
        echo "stdlib"
        return 0
    fi

    # Check if it matches a local package
    if [[ -d "$dir/$top" ]] || [[ -f "$dir/${top}.py" ]]; then
        echo "local"
        return 0
    fi
    if [[ -d "$dir/src/$top" ]] || [[ -f "$dir/src/${top}.py" ]]; then
        echo "local"
        return 0
    fi

    echo "third-party"
    return 0
}

# Detect frameworks used in a Python project
# Output: Framework names found (django, flask, fastapi, pytest, etc.)
py_framework_detect() {
    local dir="${1:-.}"
    py_is_project "$dir" || { echo "Not a Python project: $dir" >&2; return 1; }

    local frameworks=""

    # Collect all imports
    local all_imports
    all_imports=$(find "$dir" -name "*.py" ! -path "*/venv/*" ! -path "*/.venv/*" ! -path "*/__pycache__/*" -exec grep -h "^\(import\|from\)" {} \; 2>/dev/null)

    # Check for known frameworks
    echo "$all_imports" | grep -q "django" && frameworks="${frameworks}django "
    echo "$all_imports" | grep -q "flask" && frameworks="${frameworks}flask "
    echo "$all_imports" | grep -q "fastapi" && frameworks="${frameworks}fastapi "
    echo "$all_imports" | grep -q "pytest" && frameworks="${frameworks}pytest "
    echo "$all_imports" | grep -q "celery" && frameworks="${frameworks}celery "
    echo "$all_imports" | grep -q "sqlalchemy" && frameworks="${frameworks}sqlalchemy "
    echo "$all_imports" | grep -q "pydantic" && frameworks="${frameworks}pydantic "
    echo "$all_imports" | grep -q "numpy" && frameworks="${frameworks}numpy "
    echo "$all_imports" | grep -q "pandas" && frameworks="${frameworks}pandas "
    echo "$all_imports" | grep -q "torch" && frameworks="${frameworks}pytorch "
    echo "$all_imports" | grep -q "tensorflow" && frameworks="${frameworks}tensorflow "

    # Also check config files
    [[ -f "$dir/manage.py" ]] && [[ "$frameworks" != *"django"* ]] && frameworks="${frameworks}django "
    [[ -f "$dir/conftest.py" ]] && [[ "$frameworks" != *"pytest"* ]] && frameworks="${frameworks}pytest "

    if [[ -z "$frameworks" ]]; then
        echo "none"
    else
        echo "${frameworks% }"
    fi
}

# =============================================================================
# PYDEPS - DEPENDENCY/ENVIRONMENT MANAGEMENT
# =============================================================================

# Parse requirements.txt file
# Output: "package version_spec" lines
py_parse_requirements() {
    local file="${1:-requirements.txt}"
    [[ ! -f "$file" ]] && echo "Error: file not found: $file" >&2 && return 1

    while IFS= read -r line; do
        # Remove comments
        line="${line%%#*}"
        # Remove leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip empty lines, options, and -r includes
        [[ -z "$line" ]] && continue
        [[ "$line" == -* ]] && continue

        # Extract package name and version spec
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+[a-zA-Z0-9._-]*)([=\<\>!~]+.*)? ]]; then
            local pkg="${BASH_REMATCH[1]}"
            local ver="${BASH_REMATCH[2]:-any}"
            printf "%-30s %s\n" "$pkg" "$ver"
        fi
    done < "$file"
}

# Detect virtual environment in project
# Output: Path to venv if found, empty otherwise
py_detect_venv() {
    local dir="${1:-.}"
    local venv_dirs=("venv" ".venv" "env" ".env" ".virtualenv")

    for vdir in "${venv_dirs[@]}"; do
        if [[ -d "$dir/$vdir" && -f "$dir/$vdir/bin/activate" ]]; then
            echo "$dir/$vdir"
            return 0
        fi
        # Windows support
        if [[ -d "$dir/$vdir" && -f "$dir/$vdir/Scripts/activate" ]]; then
            echo "$dir/$vdir"
            return 0
        fi
    done

    return 1
}

# Infer required Python version from project files
# Output: Version string or "unknown"
# Priority: .python-version (pinned) > runtime.txt > pyproject.toml > setup.cfg
py_python_version() {
    local dir="${1:-.}"

    # Check .python-version (pyenv - most specific/pinned)
    if [[ -f "$dir/.python-version" ]]; then
        local ver
        IFS= read -r ver < "$dir/.python-version"
        echo "$ver"
        return 0
    fi

    # Check runtime.txt (Heroku-style)
    if [[ -f "$dir/runtime.txt" ]]; then
        local ver
        ver=$(< "$dir/runtime.txt")
        ver="${ver#python-}"
        echo "$ver"
        return 0
    fi

    # Check pyproject.toml requires-python
    if [[ -f "$dir/pyproject.toml" ]]; then
        local ver
        ver=$(grep -m1 'requires-python' "$dir/pyproject.toml" 2>/dev/null)
        if [[ "$ver" =~ requires-python[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    fi

    # Check setup.cfg
    if [[ -f "$dir/setup.cfg" ]]; then
        local ver
        ver=$(grep -m1 'python_requires' "$dir/setup.cfg" 2>/dev/null)
        if [[ "$ver" =~ python_requires[[:space:]]*=[[:space:]]*(.*) ]]; then
            local result="${BASH_REMATCH[1]}"
            result="${result#"${result%%[![:space:]]*}"}"
            echo "$result"
            return 0
        fi
    fi

    echo "unknown"
    return 1
}

# Detect which package manager is used
# Output: "pip", "poetry", "pipenv", "uv", "conda", or "unknown"
py_detect_manager() {
    local dir="${1:-.}"

    # Check for Poetry
    if [[ -f "$dir/poetry.lock" ]] || grep -q '\[tool\.poetry\]' "$dir/pyproject.toml" 2>/dev/null; then
        echo "poetry"
        return 0
    fi

    # Check for Pipenv
    if [[ -f "$dir/Pipfile" ]] || [[ -f "$dir/Pipfile.lock" ]]; then
        echo "pipenv"
        return 0
    fi

    # Check for uv
    if [[ -f "$dir/uv.lock" ]]; then
        echo "uv"
        return 0
    fi

    # Check for conda
    if [[ -f "$dir/environment.yml" ]] || [[ -f "$dir/environment.yaml" ]]; then
        echo "conda"
        return 0
    fi

    # Default to pip if requirements.txt exists
    if [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/requirements" ]]; then
        echo "pip"
        return 0
    fi

    # Check pyproject.toml without poetry
    if [[ -f "$dir/pyproject.toml" ]]; then
        echo "pip"
        return 0
    fi

    echo "unknown"
    return 1
}

# Count total dependencies in requirements files
# Output: Number of packages
py_dep_count() {
    local dir="${1:-.}"
    local count=0

    # Count from requirements.txt
    if [[ -f "$dir/requirements.txt" ]]; then
        local c
        c=$(grep -c '^[a-zA-Z]' "$dir/requirements.txt" 2>/dev/null || echo "0")
        count=$((count + c))
    fi

    # Count from requirements/*.txt
    if [[ -d "$dir/requirements" ]]; then
        for req in "$dir/requirements/"*.txt; do
            [[ -f "$req" ]] || continue
            local c
            c=$(grep -c '^[a-zA-Z]' "$req" 2>/dev/null || echo "0")
            count=$((count + c))
        done
    fi

    # Count from pyproject.toml [project.dependencies]
    if [[ -f "$dir/pyproject.toml" ]] && ! grep -q '\[tool\.poetry\]' "$dir/pyproject.toml" 2>/dev/null; then
        local in_deps=0
        while IFS= read -r line; do
            [[ "$line" =~ ^\[project\.dependencies\]$ ]] && in_deps=1 && continue
            [[ "$line" =~ ^\[.*\]$ ]] && in_deps=0 && continue
            if [[ $in_deps -eq 1 && "$line" =~ ^[[:space:]]*\"[a-zA-Z] ]]; then
                ((count++))
            fi
        done < "$dir/pyproject.toml"
    fi

    echo "$count"
}

# =============================================================================
# PYMETRICS - CODE QUALITY
# =============================================================================

# Count lines of Python code (excluding blanks and comments)
py_loc() {
    local dir="${1:-.}"
    local total=0

    while IFS= read -r file; do
        while IFS= read -r line; do
            # Skip blank lines
            [[ -z "${line// }" ]] && continue
            # Skip comment-only lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            ((total++))
        done < "$file"
    done < <(find "$dir" -name "*.py" ! -path "*/venv/*" ! -path "*/.venv/*" ! -path "*/__pycache__/*" ! -path "*/node_modules/*" 2>/dev/null)

    echo "$total"
}

# Count function definitions
py_function_count() {
    local target="${1:-.}"

    if [[ -f "$target" ]]; then
        grep -c '^[[:space:]]*def[[:space:]]' "$target" 2>/dev/null || echo "0"
    elif [[ -d "$target" ]]; then
        find "$target" -name "*.py" ! -path "*/venv/*" ! -path "*/.venv/*" ! -path "*/__pycache__/*" -exec grep -h '^[[:space:]]*def[[:space:]]' {} \; 2>/dev/null | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

# Count class definitions
py_class_count() {
    local target="${1:-.}"

    if [[ -f "$target" ]]; then
        grep -c '^[[:space:]]*class[[:space:]]' "$target" 2>/dev/null || echo "0"
    elif [[ -d "$target" ]]; then
        find "$target" -name "*.py" ! -path "*/venv/*" ! -path "*/.venv/*" ! -path "*/__pycache__/*" -exec grep -h '^[[:space:]]*class[[:space:]]' {} \; 2>/dev/null | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

# Estimate docstring coverage
# Output: "covered/total percent%"
py_docstring_coverage() {
    local dir="${1:-.}"
    local total=0
    local covered=0

    while IFS= read -r file; do
        local prev_was_def=0
        while IFS= read -r line; do
            # Count def/class as needing docstring
            if [[ "$line" =~ ^[[:space:]]*(def|class)[[:space:]] ]]; then
                ((total++))
                prev_was_def=1
                continue
            fi
            # Check if next non-blank line is a docstring
            if [[ $prev_was_def -eq 1 ]]; then
                if [[ "$line" =~ ^[[:space:]]*(\"\"\"|\'\'\') ]]; then
                    ((covered++))
                fi
                # Reset even if not a docstring (only check immediately after def/class)
                [[ -n "${line// }" ]] && prev_was_def=0
            fi
        done < "$file"
    done < <(find "$dir" -name "*.py" ! -path "*/venv/*" ! -path "*/.venv/*" ! -path "*/__pycache__/*" 2>/dev/null)

    if [[ $total -eq 0 ]]; then
        echo "0/0 0%"
        return 0
    fi

    local pct=$((covered * 100 / total))
    echo "${covered}/${total} ${pct}%"
}

# Estimate type hint coverage
# Output: "annotated/total percent%"
py_type_hint_coverage() {
    local dir="${1:-.}"
    local total=0
    local annotated=0

    while IFS= read -r file; do
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*def[[:space:]] ]]; then
                ((total++))
                # Check for return type annotation (->)
                if [[ "$line" == *"->"* ]]; then
                    ((annotated++))
                fi
            fi
        done < "$file"
    done < <(find "$dir" -name "*.py" ! -path "*/venv/*" ! -path "*/.venv/*" ! -path "*/__pycache__/*" 2>/dev/null)

    if [[ $total -eq 0 ]]; then
        echo "0/0 0%"
        return 0
    fi

    local pct=$((annotated * 100 / total))
    echo "${annotated}/${total} ${pct}%"
}

# Count Python files in a project
py_file_count() {
    local dir="${1:-.}"
    find "$dir" -name "*.py" ! -path "*/venv/*" ! -path "*/.venv/*" ! -path "*/__pycache__/*" ! -path "*/node_modules/*" 2>/dev/null | grep -vc "\.pyc$"
}

# Quick project summary
# Output: key=value pairs
py_summary() {
    local dir="${1:-.}"
    py_is_project "$dir" || { echo "Not a Python project: $dir" >&2; return 1; }

    local files loc functions classes manager version framework deps

    files=$(py_file_count "$dir")
    loc=$(py_loc "$dir")
    functions=$(py_function_count "$dir")
    classes=$(py_class_count "$dir")
    manager=$(py_detect_manager "$dir")
    version=$(py_python_version "$dir")
    framework=$(py_framework_detect "$dir")
    deps=$(py_dep_count "$dir")

    echo "files=$files loc=$loc functions=$functions classes=$classes manager=$manager python=$version framework=$framework deps=$deps"
}

# =============================================================================
# PYRUNTIME - AI AGENT INTEGRATION
# =============================================================================
# USOP pattern: {"ok":true,"data":{...}} or {"ok":false,"error":"msg"}
# All functions return exit 0, encode success/failure in JSON
# =============================================================================

# Internal: Truncate output to prevent context bloat
# @param $1 - text to truncate
# @param $2 - max chars (default: 4000)
_py_truncate() {
    local text="$1"
    local max="${2:-4000}"
    local len=${#text}

    if [[ $len -le $max ]]; then
        echo "$text"
    else
        local truncated="${text:0:$max}"
        echo "${truncated}... [truncated, ${len} chars total]"
    fi
}

# Internal: Build JSON object (simple key-value pairs)
_py_json_kv() {
    local first=1
    echo -n "{"
    while [[ $# -gt 0 ]]; do
        local key="$1"
        local val="$2"
        shift 2 || break
        [[ $first -eq 0 ]] && echo -n ","
        first=0
        # Detect type
        if [[ "$val" == "true" || "$val" == "false" ]]; then
            echo -n "\"$key\":$val"
        elif [[ "$val" =~ ^-?[0-9]+$ ]]; then
            echo -n "\"$key\":$val"
        elif [[ "$val" == "null" ]]; then
            echo -n "\"$key\":null"
        else
            # Escape special chars in string
            val="${val//\\/\\\\}"
            val="${val//\"/\\\"}"
            val="${val//$'\n'/\\n}"
            val="${val//$'\t'/\\t}"
            echo -n "\"$key\":\"$val\""
        fi
    done
    echo "}"
}

# Internal: USOP success response
_py_ok() {
    echo -n '{"ok":true,"data":'
    if [[ $# -eq 0 ]]; then
        echo -n '{}'
    else
        echo -n "$1"
    fi
    echo '}'
}

# Internal: USOP error response
_py_err() {
    local msg="$1"
    msg="${msg//\\/\\\\}"
    msg="${msg//\"/\\\"}"
    msg="${msg//$'\n'/\\n}"
    echo "{\"ok\":false,\"error\":\"$msg\"}"
}

# Internal: Get Python interpreter (respects venv)
_py_get_interpreter() {
    local dir="${1:-.}"
    local venv
    venv=$(py_detect_venv "$dir" 2>/dev/null)

    if [[ -n "$venv" && -f "$venv/bin/python" ]]; then
        echo "$venv/bin/python"
    elif [[ -n "${VIRTUAL_ENV:-}" && -f "$VIRTUAL_ENV/bin/python" ]]; then
        echo "$VIRTUAL_ENV/bin/python"
    elif command -v python3 &>/dev/null; then
        command -v python3
    elif command -v python &>/dev/null; then
        command -v python
    else
        return 1
    fi
}

# =============================================================================
# ENVIRONMENT DETECTION
# =============================================================================

# @idempotent Check Python installation
# @return {"ok":true,"data":{"installed":bool,"version":"3.x.y","path":"/usr/bin/python3"}}
py_detect() {
    local python_path version

    if command -v python3 &>/dev/null; then
        python_path=$(command -v python3)
        version=$(python3 --version 2>&1 | sed 's/Python //')
        _py_ok "$(_py_json_kv "installed" "true" "version" "$version" "path" "$python_path")"
    elif command -v python &>/dev/null; then
        python_path=$(command -v python)
        version=$(python --version 2>&1 | sed 's/Python //')
        _py_ok "$(_py_json_kv "installed" "true" "version" "$version" "path" "$python_path")"
    else
        _py_ok "$(_py_json_kv "installed" "false" "version" "null" "path" "null")"
    fi
    return 0
}

# @idempotent Get Python interpreter for project (respects venv)
# @param $1 - project directory (default: .)
# @return {"ok":true,"data":{"interpreter":"/path/to/python","version":"3.x.y","venv":bool}}
py_interpreter() {
    local dir="${1:-.}"
    local interpreter version is_venv="false"

    interpreter=$(_py_get_interpreter "$dir")
    if [[ -z "$interpreter" ]]; then
        _py_err "No Python interpreter found"
        return 0
    fi

    version=$("$interpreter" --version 2>&1 | sed 's/Python //')

    # Check if in a venv
    local venv_path
    venv_path=$(py_detect_venv "$dir" 2>/dev/null)
    if [[ -n "$venv_path" && "$interpreter" == "$venv_path"* ]]; then
        is_venv="true"
    elif [[ -n "${VIRTUAL_ENV:-}" && "$interpreter" == "$VIRTUAL_ENV"* ]]; then
        is_venv="true"
    fi

    _py_ok "$(_py_json_kv "interpreter" "$interpreter" "version" "$version" "venv" "$is_venv")"
    return 0
}

# @idempotent Check if inside active virtual environment
# @return {"ok":true,"data":{"active":bool,"venv_path":"/path","python":"/path/bin/python"}}
py_venv_active() {
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        local python_path="$VIRTUAL_ENV/bin/python"
        [[ ! -f "$python_path" ]] && python_path="$VIRTUAL_ENV/Scripts/python"
        _py_ok "$(_py_json_kv "active" "true" "venv_path" "$VIRTUAL_ENV" "python" "$python_path")"
    else
        _py_ok "$(_py_json_kv "active" "false" "venv_path" "null" "python" "null")"
    fi
    return 0
}

# Create virtual environment
# @param $1 - path for venv (default: .venv)
# @param $2 - python version/path (default: python3)
# @return {"ok":true,"data":{"path":".venv","python":"3.x.y"}}
py_venv_create() {
    local venv_path="${1:-.venv}"
    local python_cmd="${2:-python3}"

    # Check if python exists
    if ! command -v "$python_cmd" &>/dev/null; then
        _py_err "Python command not found: $python_cmd"
        return 0
    fi

    # Check if venv already exists
    if [[ -d "$venv_path" && -f "$venv_path/bin/activate" ]]; then
        local version
        version=$("$venv_path/bin/python" --version 2>&1 | sed 's/Python //')
        _py_ok "$(_py_json_kv "path" "$venv_path" "python" "$version" "created" "false" "message" "venv already exists")"
        return 0
    fi

    # Create venv
    local output
    output=$("$python_cmd" -m venv "$venv_path" 2>&1)
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        _py_err "Failed to create venv: $(_py_truncate "$output" 500)"
        return 0
    fi

    local version
    version=$("$venv_path/bin/python" --version 2>&1 | sed 's/Python //')
    _py_ok "$(_py_json_kv "path" "$venv_path" "python" "$version" "created" "true")"
    return 0
}

# @idempotent Get venv activation command for current shell
# @param $1 - venv path (default: .venv)
# @return {"ok":true,"data":{"command":"source .venv/bin/activate","shell":"bash"}}
py_venv_activate_cmd() {
    local venv_path="${1:-.venv}"
    local shell_name="${SHELL##*/}"
    local cmd

    # Normalize venv_path
    [[ ! -d "$venv_path" ]] && { _py_err "venv not found: $venv_path"; return 0; }

    case "$shell_name" in
        fish)
            cmd="source $venv_path/bin/activate.fish"
            ;;
        csh|tcsh)
            cmd="source $venv_path/bin/activate.csh"
            ;;
        *)
            # bash, zsh, sh
            if [[ -f "$venv_path/bin/activate" ]]; then
                cmd="source $venv_path/bin/activate"
            elif [[ -f "$venv_path/Scripts/activate" ]]; then
                cmd="source $venv_path/Scripts/activate"
            else
                _py_err "activate script not found in $venv_path"
                return 0
            fi
            ;;
    esac

    _py_ok "$(_py_json_kv "command" "$cmd" "shell" "$shell_name")"
    return 0
}

# =============================================================================
# PACKAGE MANAGEMENT (Multi-Manager)
# =============================================================================

# @pre py_detect returns installed=true
# Install dependencies using detected manager
# @param $1 - optional: specific package or requirements file
# @return {"ok":true,"data":{"manager":"pip|poetry|uv","packages_installed":N}}
py_install() {
    local target="${1:-}"
    local dir="${2:-.}"
    local manager output rc

    manager=$(py_detect_manager "$dir")
    local interpreter
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    case "$manager" in
        poetry)
            if [[ -n "$target" ]]; then
                output=$(cd "$dir" && poetry add "$target" 2>&1)
            else
                output=$(cd "$dir" && poetry install 2>&1)
            fi
            rc=$?
            ;;
        pipenv)
            if [[ -n "$target" ]]; then
                output=$(cd "$dir" && pipenv install "$target" 2>&1)
            else
                output=$(cd "$dir" && pipenv install 2>&1)
            fi
            rc=$?
            ;;
        uv)
            if [[ -n "$target" ]]; then
                output=$(cd "$dir" && uv pip install "$target" 2>&1)
            else
                output=$(cd "$dir" && uv pip install -r requirements.txt 2>&1)
            fi
            rc=$?
            ;;
        pip|*)
            if [[ -n "$target" ]]; then
                output=$("$interpreter" -m pip install "$target" 2>&1)
            elif [[ -f "$dir/requirements.txt" ]]; then
                output=$("$interpreter" -m pip install -r "$dir/requirements.txt" 2>&1)
            elif [[ -f "$dir/pyproject.toml" ]]; then
                output=$("$interpreter" -m pip install -e "$dir" 2>&1)
            else
                _py_err "No requirements.txt or pyproject.toml found"
                return 0
            fi
            rc=$?
            ;;
    esac

    if [[ $rc -ne 0 ]]; then
        _py_err "$(_py_truncate "$output" 1000)"
        return 0
    fi

    # Count installed packages (approximate from output)
    local count
    count=$(echo "$output" | grep -c -E "(Successfully installed|Installing)" || echo "0")
    [[ "$count" -eq 0 ]] && count=1  # At least 1 if successful

    _py_ok "$(_py_json_kv "manager" "$manager" "packages_installed" "$count" "output" "$(_py_truncate "$output" 500)")"
    return 0
}

# Add a package
# @param $1 - package name
# @param $2 - optional: --dev, --group=name
# @return {"ok":true,"data":{"package":"name","version":"x.y.z","manager":"pip"}}
py_add() {
    local package="$1"
    local flag="${2:-}"
    local dir="${3:-.}"

    [[ -z "$package" ]] && { _py_err "Package name required"; return 0; }

    local manager output rc version
    manager=$(py_detect_manager "$dir")
    local interpreter
    interpreter=$(_py_get_interpreter "$dir")

    case "$manager" in
        poetry)
            local poetry_flag=""
            [[ "$flag" == "--dev" ]] && poetry_flag="--group dev"
            [[ "$flag" == --group=* ]] && poetry_flag="--group ${flag#--group=}"
            output=$(cd "$dir" && poetry add "$poetry_flag" "$package" 2>&1)
            rc=$?
            ;;
        pipenv)
            local pipenv_flag=""
            [[ "$flag" == "--dev" ]] && pipenv_flag="--dev"
            output=$(cd "$dir" && pipenv install $pipenv_flag "$package" 2>&1)
            rc=$?
            ;;
        uv)
            output=$(cd "$dir" && uv pip install "$package" 2>&1)
            rc=$?
            ;;
        pip|*)
            output=$("$interpreter" -m pip install "$package" 2>&1)
            rc=$?
            ;;
    esac

    if [[ $rc -ne 0 ]]; then
        _py_err "$(_py_truncate "$output" 1000)"
        return 0
    fi

    # Extract version from pip show
    version=$("$interpreter" -m pip show "$package" 2>/dev/null | grep -m1 "^Version:" | cut -d' ' -f2)
    [[ -z "$version" ]] && version="unknown"

    _py_ok "$(_py_json_kv "package" "$package" "version" "$version" "manager" "$manager")"
    return 0
}

# Remove a package
# @param $1 - package name
# @return {"ok":true,"data":{"removed":"name","manager":"pip"}}
py_remove() {
    local package="$1"
    local dir="${2:-.}"

    [[ -z "$package" ]] && { _py_err "Package name required"; return 0; }

    local manager output rc
    manager=$(py_detect_manager "$dir")
    local interpreter
    interpreter=$(_py_get_interpreter "$dir")

    case "$manager" in
        poetry)
            output=$(cd "$dir" && poetry remove "$package" 2>&1)
            rc=$?
            ;;
        pipenv)
            output=$(cd "$dir" && pipenv uninstall "$package" 2>&1)
            rc=$?
            ;;
        uv)
            output=$(cd "$dir" && uv pip uninstall "$package" 2>&1)
            rc=$?
            ;;
        pip|*)
            output=$("$interpreter" -m pip uninstall -y "$package" 2>&1)
            rc=$?
            ;;
    esac

    if [[ $rc -ne 0 ]]; then
        _py_err "$(_py_truncate "$output" 500)"
        return 0
    fi

    _py_ok "$(_py_json_kv "removed" "$package" "manager" "$manager")"
    return 0
}

# @idempotent List installed packages
# @return {"ok":true,"data":{"packages":[{"name":"pkg","version":"1.0.0"}]}}
py_list() {
    local dir="${1:-.}"
    local interpreter
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    local output
    output=$("$interpreter" -m pip list --format=json 2>/dev/null)
    local rc=$?

    if [[ $rc -ne 0 || -z "$output" ]]; then
        # Fallback to parsing text output
        output=$("$interpreter" -m pip list 2>/dev/null | tail -n +3)
        if [[ -z "$output" ]]; then
            _py_ok '{"packages":[]}'
            return 0
        fi
        # Convert to JSON array
        local json_arr="["
        local first=1
        while read -r name version _; do
            [[ -z "$name" ]] && continue
            [[ $first -eq 0 ]] && json_arr+=","
            first=0
            json_arr+="{\"name\":\"$name\",\"version\":\"$version\"}"
        done <<< "$output"
        json_arr+="]"
        _py_ok "{\"packages\":$json_arr}"
        return 0
    fi

    # pip list --format=json returns proper JSON
    _py_ok "{\"packages\":$output}"
    return 0
}

# Generate requirements.txt from installed packages
# @param $1 - output file (default: stdout as data)
# @return {"ok":true,"data":{"packages":N,"file":"requirements.txt"}}
py_freeze() {
    local outfile="${1:-}"
    local dir="${2:-.}"
    local interpreter
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    local output
    output=$("$interpreter" -m pip freeze 2>/dev/null)
    local count
    count=$(echo "$output" | grep -c "==" || echo "0")

    if [[ -n "$outfile" ]]; then
        echo "$output" > "$outfile"
        _py_ok "$(_py_json_kv "packages" "$count" "file" "$outfile")"
    else
        _py_ok "$(_py_json_kv "packages" "$count" "content" "$(_py_truncate "$output" 2000)")"
    fi
    return 0
}

# Sync environment from requirements file
# @param $1 - requirements file (default: requirements.txt)
# @return {"ok":true,"data":{"installed":N,"removed":N}}
py_sync() {
    local reqfile="${1:-requirements.txt}"
    local dir="${2:-.}"

    [[ ! -f "$reqfile" ]] && { _py_err "Requirements file not found: $reqfile"; return 0; }

    local manager interpreter output rc
    manager=$(py_detect_manager "$dir")
    interpreter=$(_py_get_interpreter "$dir")

    case "$manager" in
        poetry)
            output=$(cd "$dir" && poetry install --sync 2>&1)
            rc=$?
            ;;
        pipenv)
            output=$(cd "$dir" && pipenv sync 2>&1)
            rc=$?
            ;;
        uv)
            output=$(cd "$dir" && uv pip sync "$reqfile" 2>&1)
            rc=$?
            ;;
        pip|*)
            # pip-sync from pip-tools if available, otherwise just install
            if "$interpreter" -m pip show pip-tools &>/dev/null; then
                output=$("$interpreter" -m piptools sync "$reqfile" 2>&1)
            else
                output=$("$interpreter" -m pip install -r "$reqfile" 2>&1)
            fi
            rc=$?
            ;;
    esac

    if [[ $rc -ne 0 ]]; then
        _py_err "$(_py_truncate "$output" 1000)"
        return 0
    fi

    local installed removed
    installed=$(echo "$output" | grep -c -E "(Successfully installed|Installing)" || echo "0")
    removed=$(echo "$output" | grep -c -E "(Uninstalling|Removed)" || echo "0")

    _py_ok "$(_py_json_kv "installed" "$installed" "removed" "$removed" "manager" "$manager")"
    return 0
}

# Upgrade a package or all packages
# @param $1 - package name or "all"
# @return {"ok":true,"data":{"upgraded":[{"name":"pkg","from":"1.0","to":"2.0"}]}}
py_upgrade() {
    local target="${1:-all}"
    local dir="${2:-.}"
    local manager interpreter output rc

    manager=$(py_detect_manager "$dir")
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    if [[ "$target" == "all" ]]; then
        case "$manager" in
            poetry)
                output=$(cd "$dir" && poetry update 2>&1)
                rc=$?
                ;;
            uv)
                output=$(cd "$dir" && uv pip install --upgrade-all 2>&1)
                rc=$?
                ;;
            pip|*)
                # Upgrade all outdated packages
                local outdated
                outdated=$("$interpreter" -m pip list --outdated --format=json 2>/dev/null)
                if [[ -n "$outdated" && "$outdated" != "[]" ]]; then
                    local pkgs
                    pkgs=$(echo "$outdated" | grep -oP '"name":\s*"\K[^"]+' | tr '\n' ' ')
                    output=$("$interpreter" -m pip install --upgrade "$pkgs" 2>&1)
                    rc=$?
                else
                    _py_ok '{"upgraded":[],"message":"All packages up to date"}'
                    return 0
                fi
                ;;
        esac
    else
        case "$manager" in
            poetry)
                output=$(cd "$dir" && poetry update "$target" 2>&1)
                rc=$?
                ;;
            uv)
                output=$(cd "$dir" && uv pip install --upgrade "$target" 2>&1)
                rc=$?
                ;;
            pip|*)
                output=$("$interpreter" -m pip install --upgrade "$target" 2>&1)
                rc=$?
                ;;
        esac
    fi

    if [[ $rc -ne 0 ]]; then
        _py_err "$(_py_truncate "$output" 1000)"
        return 0
    fi

    # Parse upgraded packages from output (simplified)
    local upgraded_json="[]"
    if echo "$output" | grep -q "Successfully installed"; then
        # Extract package names and versions
        local pkgs
        pkgs=$(echo "$output" | grep -oP 'Successfully installed \K.*' | tr ' ' '\n' | head -10)
        upgraded_json="["
        local first=1
        while read -r pkg; do
            [[ -z "$pkg" ]] && continue
            local name="${pkg%-*}"
            local ver="${pkg##*-}"
            [[ $first -eq 0 ]] && upgraded_json+=","
            first=0
            upgraded_json+="{\"name\":\"$name\",\"version\":\"$ver\"}"
        done <<< "$pkgs"
        upgraded_json+="]"
    fi

    _py_ok "{\"upgraded\":$upgraded_json,\"manager\":\"$manager\"}"
    return 0
}

# =============================================================================
# EXECUTION
# =============================================================================

# Run a Python file
# @param $1 - file path
# @param $@ - additional args
# @return {"ok":true,"data":{"file":"path","exit_code":N,"output":"..."}}
py_run() {
    local file="$1"
    shift

    [[ -z "$file" ]] && { _py_err "File path required"; return 0; }
    [[ ! -f "$file" ]] && { _py_err "File not found: $file"; return 0; }

    local interpreter dir
    dir=$(dirname "$file")
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    local output
    output=$("$interpreter" "$file" "$@" 2>&1)
    local rc=$?

    _py_ok "$(_py_json_kv "file" "$file" "exit_code" "$rc" "output" "$(_py_truncate "$output")")"
    return 0
}

# Run a Python module (python -m)
# @param $1 - module name
# @param $@ - args
# @return {"ok":true,"data":{"module":"name","exit_code":N,"output":"..."}}
py_module() {
    local module="$1"
    shift
    local dir="${PWD}"

    [[ -z "$module" ]] && { _py_err "Module name required"; return 0; }

    local interpreter
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    local output
    output=$("$interpreter" -m "$module" "$@" 2>&1)
    local rc=$?

    _py_ok "$(_py_json_kv "module" "$module" "exit_code" "$rc" "output" "$(_py_truncate "$output")")"
    return 0
}

# Run inline Python code
# @param $1 - code string
# @return {"ok":true,"data":{"exit_code":N,"output":"..."}}
py_exec() {
    local code="$1"
    local dir="${2:-.}"

    [[ -z "$code" ]] && { _py_err "Code string required"; return 0; }

    local interpreter
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    local output
    output=$("$interpreter" -c "$code" 2>&1)
    local rc=$?

    _py_ok "$(_py_json_kv "exit_code" "$rc" "output" "$(_py_truncate "$output")")"
    return 0
}

# Run pytest
# @param $@ - optional test file patterns
# @return {"ok":true,"data":{"passed":N,"failed":N,"skipped":N,"errors":N}}
py_test() {
    local dir="${PWD}"
    local interpreter
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    # Check if pytest is available
    if ! "$interpreter" -c "import pytest" 2>/dev/null; then
        _py_err "pytest not installed"
        return 0
    fi

    local output
    output=$("$interpreter" -m pytest --tb=short -q "$@" 2>&1)
    local rc=$?

    # Parse pytest output for counts
    local passed=0 failed=0 skipped=0 errors=0
    if [[ "$output" =~ ([0-9]+)[[:space:]]passed ]]; then
        passed="${BASH_REMATCH[1]}"
    fi
    if [[ "$output" =~ ([0-9]+)[[:space:]]failed ]]; then
        failed="${BASH_REMATCH[1]}"
    fi
    if [[ "$output" =~ ([0-9]+)[[:space:]]skipped ]]; then
        skipped="${BASH_REMATCH[1]}"
    fi
    if [[ "$output" =~ ([0-9]+)[[:space:]]error ]]; then
        errors="${BASH_REMATCH[1]}"
    fi

    echo -n '{"ok":true,"data":{'
    echo -n "\"passed\":$passed,\"failed\":$failed,\"skipped\":$skipped,\"errors\":$errors,"
    echo -n "\"exit_code\":$rc,"
    echo -n "\"output\":\"$(_py_truncate "$output" 2000 | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')\""
    echo '}}'
    return 0
}

# Run linter (auto-detects ruff, flake8, pylint)
# @param $@ - files or directories
# @return {"ok":true,"data":{"linter":"ruff","issues":N,"output":"..."}}
py_lint() {
    local dir="${PWD}"
    local interpreter
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    local linter output rc issues
    local targets=("$@")
    [[ ${#targets[@]} -eq 0 ]] && targets=(".")

    # Try linters in order of preference
    if command -v ruff &>/dev/null || "$interpreter" -c "import ruff" 2>/dev/null; then
        linter="ruff"
        output=$(ruff check "${targets[@]}" 2>&1) || output=$("$interpreter" -m ruff check "${targets[@]}" 2>&1)
        rc=$?
    elif "$interpreter" -c "import flake8" 2>/dev/null; then
        linter="flake8"
        output=$("$interpreter" -m flake8 "${targets[@]}" 2>&1)
        rc=$?
    elif "$interpreter" -c "import pylint" 2>/dev/null; then
        linter="pylint"
        output=$("$interpreter" -m pylint "${targets[@]}" 2>&1)
        rc=$?
    else
        _py_err "No linter found (install ruff, flake8, or pylint)"
        return 0
    fi

    # Count issues (lines of output that look like errors/warnings)
    issues=$(echo "$output" | grep -cE "^[^[:space:]].*:[0-9]+:" || echo "0")

    _py_ok "$(_py_json_kv "linter" "$linter" "issues" "$issues" "exit_code" "$rc" "output" "$(_py_truncate "$output" 2000)")"
    return 0
}

# Run formatter (auto-detects ruff, black, autopep8)
# @param $@ - files or directories
# @return {"ok":true,"data":{"formatter":"ruff","files_changed":N}}
py_format() {
    local dir="${PWD}"
    local interpreter
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    local formatter output rc files_changed
    local targets=("$@")
    [[ ${#targets[@]} -eq 0 ]] && targets=(".")

    # Try formatters in order of preference
    if command -v ruff &>/dev/null || "$interpreter" -c "import ruff" 2>/dev/null; then
        formatter="ruff"
        output=$(ruff format "${targets[@]}" 2>&1) || output=$("$interpreter" -m ruff format "${targets[@]}" 2>&1)
        rc=$?
    elif "$interpreter" -c "import black" 2>/dev/null; then
        formatter="black"
        output=$("$interpreter" -m black "${targets[@]}" 2>&1)
        rc=$?
    elif "$interpreter" -c "import autopep8" 2>/dev/null; then
        formatter="autopep8"
        output=$("$interpreter" -m autopep8 --in-place --recursive "${targets[@]}" 2>&1)
        rc=$?
    else
        _py_err "No formatter found (install ruff, black, or autopep8)"
        return 0
    fi

    # Count changed files
    files_changed=$(echo "$output" | grep -cE "(reformatted|would reformat)" || echo "0")

    _py_ok "$(_py_json_kv "formatter" "$formatter" "files_changed" "$files_changed" "exit_code" "$rc" "output" "$(_py_truncate "$output" 1000)")"
    return 0
}

# Run type checker (auto-detects mypy, pyright)
# @param $@ - files or directories
# @return {"ok":true,"data":{"checker":"mypy","errors":N,"output":"..."}}
py_typecheck() {
    local dir="${PWD}"
    local interpreter
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    local checker output rc errors
    local targets=("$@")
    [[ ${#targets[@]} -eq 0 ]] && targets=(".")

    # Try type checkers in order of preference
    if "$interpreter" -c "import mypy" 2>/dev/null; then
        checker="mypy"
        output=$("$interpreter" -m mypy "${targets[@]}" 2>&1)
        rc=$?
    elif command -v pyright &>/dev/null; then
        checker="pyright"
        output=$(pyright "${targets[@]}" 2>&1)
        rc=$?
    else
        _py_err "No type checker found (install mypy or pyright)"
        return 0
    fi

    # Count errors
    if [[ "$checker" == "mypy" ]]; then
        errors=$(echo "$output" | grep -cE ": error:" || echo "0")
    else
        errors=$(echo "$output" | grep -cE "error" || echo "0")
    fi

    _py_ok "$(_py_json_kv "checker" "$checker" "errors" "$errors" "exit_code" "$rc" "output" "$(_py_truncate "$output" 2000)")"
    return 0
}

# =============================================================================
# AI AGENT HELPERS
# =============================================================================

# @idempotent Get project summary for AI context
# @return {"ok":true,"data":{"name":"proj","python":"3.11","manager":"poetry","framework":"fastapi","scripts":[...],"deps_count":N}}
py_project_summary() {
    local dir="${1:-.}"

    if ! py_is_project "$dir"; then
        _py_err "Not a Python project: $dir"
        return 0
    fi

    local name="unknown"
    local python_ver manager framework deps_count
    local scripts_json="[]"

    # Get project name from pyproject.toml or setup.py
    if [[ -f "$dir/pyproject.toml" ]]; then
        name=$(grep -m1 "^name" "$dir/pyproject.toml" 2>/dev/null | sed 's/.*=\s*"\([^"]*\)".*/\1/' || echo "unknown")
    elif [[ -f "$dir/setup.py" ]]; then
        name=$(grep -m1 "name=" "$dir/setup.py" 2>/dev/null | sed "s/.*name=['\"]\\([^'\"]*\\)['\"].*/\\1/" || echo "unknown")
    fi
    [[ "$name" == "unknown" || -z "$name" ]] && name=$(basename "$(cd "$dir" && pwd)")

    python_ver=$(py_python_version "$dir")
    manager=$(py_detect_manager "$dir")
    framework=$(py_framework_detect "$dir")
    deps_count=$(py_dep_count "$dir")

    # Get scripts from pyproject.toml
    if [[ -f "$dir/pyproject.toml" ]]; then
        local in_scripts=0
        local scripts_arr=""
        while IFS= read -r line; do
            [[ "$line" =~ ^\[project\.scripts\]$ || "$line" =~ ^\[tool\.poetry\.scripts\]$ ]] && in_scripts=1 && continue
            [[ "$line" =~ ^\[.*\]$ ]] && in_scripts=0 && continue
            if [[ $in_scripts -eq 1 && "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+)[[:space:]]*= ]]; then
                local script_name="${BASH_REMATCH[1]}"
                [[ -n "$scripts_arr" ]] && scripts_arr+=","
                scripts_arr+="\"$script_name\""
            fi
        done < "$dir/pyproject.toml"
        [[ -n "$scripts_arr" ]] && scripts_json="[$scripts_arr]"
    fi

    echo -n '{"ok":true,"data":{'
    echo -n "\"name\":\"$name\","
    echo -n "\"python\":\"$python_ver\","
    echo -n "\"manager\":\"$manager\","
    echo -n "\"framework\":\"$framework\","
    echo -n "\"scripts\":$scripts_json,"
    echo -n "\"deps_count\":$deps_count"
    echo '}}'
    return 0
}

# @idempotent Parse pyproject.toml, setup.py, or setup.cfg
# @return {"ok":true,"data":{"name":"proj","version":"1.0.0","scripts":{...},"dependencies":[...]}}
py_config() {
    local dir="${1:-.}"
    local name="unknown" version="unknown"
    local deps_json="[]" scripts_json="{}"

    if [[ -f "$dir/pyproject.toml" ]]; then
        # Parse pyproject.toml
        local toml="$dir/pyproject.toml"

        # Name and version
        name=$(grep -m1 "^name" "$toml" 2>/dev/null | sed 's/.*=\s*"\([^"]*\)".*/\1/' || echo "unknown")
        version=$(grep -m1 "^version" "$toml" 2>/dev/null | sed 's/.*=\s*"\([^"]*\)".*/\1/' || echo "unknown")

        # Dependencies
        local in_deps=0 deps_arr=""
        while IFS= read -r line; do
            [[ "$line" =~ ^\[project\.dependencies\]$ || "$line" =~ ^dependencies[[:space:]]*=.*\[$ ]] && in_deps=1 && continue
            [[ "$line" =~ ^\[tool\.poetry\.dependencies\]$ ]] && in_deps=1 && continue
            [[ "$line" =~ ^\[.*\]$ && ! "$line" =~ dependencies ]] && in_deps=0 && continue
            [[ "$line" == "]" ]] && in_deps=0 && continue
            if [[ $in_deps -eq 1 ]]; then
                local dep
                dep=$(echo "$line" | grep -oP '^[[:space:]]*"?\K[a-zA-Z0-9_-]+' | head -1)
                if [[ -n "$dep" && "$dep" != "python" ]]; then
                    [[ -n "$deps_arr" ]] && deps_arr+=","
                    deps_arr+="\"$dep\""
                fi
            fi
        done < "$toml"
        [[ -n "$deps_arr" ]] && deps_json="[$deps_arr]"

        # Scripts
        local in_scripts=0 scripts_obj=""
        while IFS= read -r line; do
            [[ "$line" =~ ^\[project\.scripts\]$ || "$line" =~ ^\[tool\.poetry\.scripts\]$ ]] && in_scripts=1 && continue
            [[ "$line" =~ ^\[.*\]$ ]] && in_scripts=0 && continue
            if [[ $in_scripts -eq 1 && "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+)[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
                [[ -n "$scripts_obj" ]] && scripts_obj+=","
                scripts_obj+="\"${BASH_REMATCH[1]}\":\"${BASH_REMATCH[2]}\""
            fi
        done < "$toml"
        [[ -n "$scripts_obj" ]] && scripts_json="{$scripts_obj}"

    elif [[ -f "$dir/setup.py" ]]; then
        # Basic setup.py parsing
        name=$(grep -m1 "name=" "$dir/setup.py" 2>/dev/null | sed "s/.*name=['\"]\\([^'\"]*\\)['\"].*/\\1/" || echo "unknown")
        version=$(grep -m1 "version=" "$dir/setup.py" 2>/dev/null | sed "s/.*version=['\"]\\([^'\"]*\\)['\"].*/\\1/" || echo "unknown")

    elif [[ -f "$dir/setup.cfg" ]]; then
        # Basic setup.cfg parsing
        name=$(grep -m1 "^name" "$dir/setup.cfg" 2>/dev/null | sed 's/.*=\s*//' || echo "unknown")
        version=$(grep -m1 "^version" "$dir/setup.cfg" 2>/dev/null | sed 's/.*=\s*//' || echo "unknown")
    else
        _py_err "No pyproject.toml, setup.py, or setup.cfg found"
        return 0
    fi

    echo -n '{"ok":true,"data":{'
    echo -n "\"name\":\"$name\","
    echo -n "\"version\":\"$version\","
    echo -n "\"scripts\":$scripts_json,"
    echo -n "\"dependencies\":$deps_json"
    echo '}}'
    return 0
}

# Get recommended commands for common tasks
# @param $1 - task: "dev", "test", "lint", "format", "build", "publish"
# @return {"ok":true,"data":{"task":"test","command":"pytest","alternatives":["python -m pytest"]}}
py_suggest_command() {
    local task="$1"
    local dir="${2:-.}"

    [[ -z "$task" ]] && { _py_err "Task name required (dev, test, lint, format, build, publish)"; return 0; }

    local manager cmd alternatives
    manager=$(py_detect_manager "$dir")

    case "$task" in
        dev|run)
            case "$manager" in
                poetry) cmd="poetry run python" ;;
                pipenv) cmd="pipenv run python" ;;
                *) cmd="python" ;;
            esac
            alternatives='["python -m <module>","uvicorn app:app --reload"]'
            ;;
        test)
            case "$manager" in
                poetry) cmd="poetry run pytest" ;;
                pipenv) cmd="pipenv run pytest" ;;
                *) cmd="pytest" ;;
            esac
            alternatives='["python -m pytest","pytest -v","pytest --cov"]'
            ;;
        lint)
            cmd="ruff check ."
            alternatives='["flake8","pylint","mypy"]'
            ;;
        format)
            cmd="ruff format ."
            alternatives='["black .","autopep8 --in-place -r ."]'
            ;;
        build)
            case "$manager" in
                poetry) cmd="poetry build" ;;
                *) cmd="python -m build" ;;
            esac
            alternatives='["python setup.py sdist bdist_wheel","flit build"]'
            ;;
        publish)
            case "$manager" in
                poetry) cmd="poetry publish" ;;
                *) cmd="twine upload dist/*" ;;
            esac
            alternatives='["flit publish","python -m twine upload dist/*"]'
            ;;
        *)
            _py_err "Unknown task: $task (valid: dev, test, lint, format, build, publish)"
            return 0
            ;;
    esac

    echo -n '{"ok":true,"data":{'
    echo -n "\"task\":\"$task\","
    echo -n "\"command\":\"$cmd\","
    echo -n "\"alternatives\":$alternatives,"
    echo -n "\"manager\":\"$manager\""
    echo '}}'
    return 0
}

# @idempotent Detect installed CLI tools (pytest, ruff, black, mypy, etc.)
# @return {"ok":true,"data":{"tools":{"pytest":"8.0.0","ruff":"0.3.0",...}}}
py_tools_detect() {
    local dir="${1:-.}"
    local interpreter
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    local tools_json="{"
    local first=1
    local tools=("pytest" "ruff" "black" "flake8" "pylint" "mypy" "pyright" "isort" "autopep8" "pip-tools" "pre-commit" "tox" "nox" "coverage" "twine" "build" "uv")

    for tool in "${tools[@]}"; do
        local version=""

        # Check if installed via pip
        version=$("$interpreter" -m pip show "$tool" 2>/dev/null | grep -m1 "^Version:" | cut -d' ' -f2)

        # If not found, check command line
        if [[ -z "$version" ]]; then
            case "$tool" in
                pyright) version=$(pyright --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1) ;;
                uv) version=$(uv --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+') ;;
            esac
        fi

        if [[ -n "$version" ]]; then
            [[ $first -eq 0 ]] && tools_json+=","
            first=0
            tools_json+="\"$tool\":\"$version\""
        fi
    done

    tools_json+="}"

    _py_ok "{\"tools\":$tools_json}"
    return 0
}

# Check for security vulnerabilities
# @return {"ok":true,"data":{"scanner":"pip-audit|safety","vulnerabilities":N,"details":[...]}}
py_security_check() {
    local dir="${1:-.}"
    local interpreter scanner output rc vulns
    interpreter=$(_py_get_interpreter "$dir")
    [[ -z "$interpreter" ]] && { _py_err "No Python interpreter found"; return 0; }

    # Try pip-audit first (preferred)
    if "$interpreter" -c "import pip_audit" 2>/dev/null; then
        scanner="pip-audit"
        output=$("$interpreter" -m pip_audit --format json 2>&1)
        rc=$?

        if [[ $rc -eq 0 ]]; then
            # pip-audit returns JSON directly
            vulns=$(echo "$output" | grep -c '"id":' || echo "0")
            echo -n '{"ok":true,"data":{'
            echo -n "\"scanner\":\"$scanner\","
            echo -n "\"vulnerabilities\":$vulns,"
            echo -n "\"details\":$(_py_truncate "$output" 3000)"
            echo '}}'
            return 0
        fi
    fi

    # Fall back to safety
    if "$interpreter" -c "import safety" 2>/dev/null; then
        scanner="safety"
        output=$("$interpreter" -m safety check --json 2>&1)
        rc=$?

        vulns=$(echo "$output" | grep -c '"vulnerability_id":' || echo "0")
        echo -n '{"ok":true,"data":{'
        echo -n "\"scanner\":\"$scanner\","
        echo -n "\"vulnerabilities\":$vulns,"
        echo -n "\"output\":\"$(_py_truncate "$output" 2000 | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')\""
        echo '}}'
        return 0
    fi

    _py_err "No security scanner found (install pip-audit or safety)"
    return 0
}
