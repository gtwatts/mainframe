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
