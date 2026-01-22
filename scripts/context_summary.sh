#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/context_summary.sh - AI Context Window Project Summarizer
# =============================================================================
# Description: Generate token-efficient project summaries for AI context windows
# Usage: context_summary [directory] [options]
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

set -euo pipefail

# Source MAINFRAME
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# =============================================================================
# CONSTANTS
# =============================================================================

readonly VERSION="1.0.0"
readonly DEFAULT_MAX_TOKENS=4000
readonly CHARS_PER_TOKEN=4  # Approximate ratio

# Language detection patterns
declare -A LANG_EXTENSIONS=(
    [".ts"]=TypeScript [".tsx"]=TypeScript [".js"]=JavaScript [".jsx"]=JavaScript
    [".py"]=Python [".rb"]=Ruby [".go"]=Go [".rs"]=Rust [".java"]=Java
    [".c"]=C [".cpp"]=C++ [".h"]=C/C++ [".cs"]=C# [".php"]=PHP
    [".swift"]=Swift [".kt"]=Kotlin [".scala"]=Scala [".sh"]=Bash
    [".pl"]=Perl [".lua"]=Lua [".r"]=R [".sql"]=SQL [".vue"]=Vue
    [".svelte"]=Svelte [".dart"]=Dart [".zig"]=Zig [".nim"]=Nim
    [".ex"]=Elixir [".exs"]=Elixir [".erl"]=Erlang [".clj"]=Clojure
    [".ml"]=OCaml [".hs"]=Haskell [".fs"]=F# [".cr"]=Crystal
)

# Framework detection files
declare -A FRAMEWORK_MARKERS=(
    ["next.config.js"]=Next.js ["next.config.ts"]=Next.js ["next.config.mjs"]=Next.js
    ["nuxt.config.js"]=Nuxt ["nuxt.config.ts"]=Nuxt
    ["vite.config.js"]=Vite ["vite.config.ts"]=Vite
    ["svelte.config.js"]=SvelteKit ["astro.config.mjs"]=Astro
    ["remix.config.js"]=Remix ["gatsby-config.js"]=Gatsby
    ["angular.json"]=Angular ["vue.config.js"]=Vue
    ["webpack.config.js"]=Webpack ["rollup.config.js"]=Rollup
    ["tsconfig.json"]=TypeScript ["jsconfig.json"]=JavaScript
    ["Cargo.toml"]=Rust ["go.mod"]=Go ["pom.xml"]=Maven
    ["build.gradle"]=Gradle ["build.gradle.kts"]=Gradle
    ["setup.py"]=Python ["pyproject.toml"]=Python ["requirements.txt"]=Python
    ["Gemfile"]=Ruby ["mix.exs"]=Elixir ["Package.swift"]=Swift
    ["composer.json"]=PHP ["CMakeLists.txt"]=CMake
    ["Makefile"]=Make [".NET.csproj"]=".NET"
    ["tailwind.config.js"]=Tailwind ["tailwind.config.ts"]=Tailwind
    ["prisma/schema.prisma"]=Prisma ["drizzle.config.ts"]=Drizzle
    ["docker-compose.yml"]=Docker ["Dockerfile"]=Docker
    ["serverless.yml"]=Serverless ["terraform.tf"]=Terraform
    ["pulumi.yaml"]=Pulumi ["cdk.json"]=AWS-CDK
    ["fastapi"]=FastAPI ["django"]=Django ["flask"]=Flask
    ["express"]=Express ["nestjs"]=NestJS ["hono"]=Hono
)

# Package manager detection
declare -A PKG_MANAGERS=(
    ["bun.lockb"]=bun ["bun.lock"]=bun
    ["pnpm-lock.yaml"]=pnpm
    ["yarn.lock"]=yarn
    ["package-lock.json"]=npm
    ["Pipfile.lock"]=pipenv
    ["poetry.lock"]=poetry
    ["Cargo.lock"]=cargo
    ["go.sum"]=go
    ["Gemfile.lock"]=bundler
    ["composer.lock"]=composer
)

# Default exclusions (common large/generated directories)
DEFAULT_EXCLUDES=(
    "node_modules" ".git" "dist" "build" "__pycache__" ".next" ".nuxt"
    "target" "vendor" "coverage" ".pytest_cache" ".mypy_cache"
    ".venv" "venv" "env" ".env" "*.egg-info" ".tox"
    ".cache" ".parcel-cache" ".turbo" ".vercel" ".netlify"
    "out" "output" "bin" "obj" ".idea" ".vscode" "*.log"
    ".svelte-kit" ".output" "storybook-static" "public/build"
)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Print usage information
usage() {
    cat << 'EOF'
Usage: context_summary [DIRECTORY] [OPTIONS]

Generate token-efficient project summaries for AI context windows.

Options:
    -t, --max-tokens NUM    Maximum tokens in output (default: 4000)
    -f, --focus PATTERN     Focus on files matching pattern (can repeat)
    -e, --exclude PATTERN   Exclude files matching pattern (can repeat)
    -d, --depth NUM         Maximum directory depth (default: 4)
    -k, --key-files NUM     Number of key files to highlight (default: 10)
    -g, --git-history NUM   Number of recent commits (default: 5)
    -j, --json              Output as JSON
    -q, --quiet             Minimal output (structure only)
    -v, --verbose           Include more details
    -h, --help              Show this help
    --version               Show version

Examples:
    # Summarize current directory
    context_summary .

    # Limit to 2000 tokens
    context_summary . --max-tokens 2000

    # Focus on TypeScript files
    context_summary . --focus "*.ts" --focus "*.tsx"

    # Exclude test files
    context_summary . --exclude "*test*" --exclude "*spec*"

    # JSON output for programmatic use
    context_summary . --json
EOF
}

# Estimate token count from character count
estimate_tokens() {
    local chars="$1"
    echo $(( (chars + CHARS_PER_TOKEN - 1) / CHARS_PER_TOKEN ))
}

# Truncate output to fit token budget
truncate_to_tokens() {
    local content="$1"
    local max_tokens="$2"
    local max_chars=$(( max_tokens * CHARS_PER_TOKEN ))

    if (( ${#content} <= max_chars )); then
        printf '%s' "$content"
    else
        printf '%s\n\n[... truncated to fit %d token budget ...]' \
            "${content:0:$max_chars}" "$max_tokens"
    fi
}

# Detect primary programming language
detect_language() {
    local dir="$1"
    local -A lang_counts
    local max_count=0
    local primary_lang="Unknown"

    while IFS= read -r -d '' file; do
        local ext=".${file##*.}"
        if [[ -n "${LANG_EXTENSIONS[$ext]:-}" ]]; then
            local lang="${LANG_EXTENSIONS[$ext]}"
            lang_counts[$lang]=$(( ${lang_counts[$lang]:-0} + 1 ))
            if (( lang_counts[$lang] > max_count )); then
                max_count=${lang_counts[$lang]}
                primary_lang="$lang"
            fi
        fi
    done < <(find "$dir" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" \
        -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" \
        -o -name "*.java" -o -name "*.rb" -o -name "*.php" -o -name "*.c" \
        -o -name "*.cpp" -o -name "*.sh" -o -name "*.vue" -o -name "*.svelte" \) \
        -print0 2>/dev/null | head -z -n 500)

    printf '%s' "$primary_lang"
}

# Detect framework from marker files
detect_framework() {
    local dir="$1"
    local frameworks=()

    for marker in "${!FRAMEWORK_MARKERS[@]}"; do
        if [[ -e "$dir/$marker" ]]; then
            frameworks+=("${FRAMEWORK_MARKERS[$marker]}")
        fi
    done

    # Check package.json for framework dependencies
    if [[ -f "$dir/package.json" ]]; then
        local deps
        deps=$(cat "$dir/package.json" 2>/dev/null)

        # Check common frameworks in dependencies
        [[ "$deps" =~ \"next\" ]] && frameworks+=("Next.js")
        [[ "$deps" =~ \"react\" ]] && frameworks+=("React")
        [[ "$deps" =~ \"vue\" ]] && frameworks+=("Vue")
        [[ "$deps" =~ \"svelte\" ]] && frameworks+=("Svelte")
        [[ "$deps" =~ \"express\" ]] && frameworks+=("Express")
        [[ "$deps" =~ \"fastify\" ]] && frameworks+=("Fastify")
        [[ "$deps" =~ \"hono\" ]] && frameworks+=("Hono")
        [[ "$deps" =~ \"@nestjs\" ]] && frameworks+=("NestJS")
        [[ "$deps" =~ \"tailwindcss\" ]] && frameworks+=("Tailwind")
        [[ "$deps" =~ \"prisma\" ]] && frameworks+=("Prisma")
        [[ "$deps" =~ \"drizzle-orm\" ]] && frameworks+=("Drizzle")
    fi

    # Check Python frameworks
    if [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/pyproject.toml" ]]; then
        local reqs=""
        [[ -f "$dir/requirements.txt" ]] && reqs+=$(cat "$dir/requirements.txt" 2>/dev/null)
        [[ -f "$dir/pyproject.toml" ]] && reqs+=$(cat "$dir/pyproject.toml" 2>/dev/null)

        [[ "$reqs" =~ fastapi ]] && frameworks+=("FastAPI")
        [[ "$reqs" =~ django ]] && frameworks+=("Django")
        [[ "$reqs" =~ flask ]] && frameworks+=("Flask")
        [[ "$reqs" =~ pytorch|torch ]] && frameworks+=("PyTorch")
        [[ "$reqs" =~ tensorflow ]] && frameworks+=("TensorFlow")
    fi

    # Deduplicate and join
    local unique_frameworks
    unique_frameworks=$(printf '%s\n' "${frameworks[@]}" 2>/dev/null | sort -u | head -5 | tr '\n' ', ' | sed 's/,$//')

    printf '%s' "${unique_frameworks:-None detected}"
}

# Detect package manager
detect_package_manager() {
    local dir="$1"

    for lockfile in "${!PKG_MANAGERS[@]}"; do
        if [[ -f "$dir/$lockfile" ]]; then
            printf '%s' "${PKG_MANAGERS[$lockfile]}"
            return 0
        fi
    done

    # Fallback checks
    [[ -f "$dir/package.json" ]] && printf 'npm' && return 0
    [[ -f "$dir/Cargo.toml" ]] && printf 'cargo' && return 0
    [[ -f "$dir/go.mod" ]] && printf 'go' && return 0
    [[ -f "$dir/Gemfile" ]] && printf 'bundler' && return 0
    [[ -f "$dir/requirements.txt" ]] && printf 'pip' && return 0

    printf 'Unknown'
}

# Build find exclusion arguments
build_exclude_args() {
    local -n patterns="$1"
    local args=""

    for pat in "${patterns[@]}"; do
        args+=" -name '$pat' -prune -o"
    done

    printf '%s' "$args"
}

# Count files and lines in directory
count_files_and_lines() {
    local dir="$1"
    local -n excludes="$2"
    local -n focuses="$3"

    local file_count=0
    local line_count=0
    local exclude_pattern=""

    # Build exclude pattern for grep
    for pat in "${excludes[@]}"; do
        exclude_pattern+="${exclude_pattern:+|}$pat"
    done

    # Find all code files
    while IFS= read -r file; do
        # Skip if matches exclude pattern
        if [[ -n "$exclude_pattern" ]] && echo "$file" | grep -qE "$exclude_pattern"; then
            continue
        fi

        # If focus patterns specified, only count matching files
        if (( ${#focuses[@]} > 0 )); then
            local match=0
            for focus in "${focuses[@]}"; do
                if [[ "$file" == $focus ]]; then
                    match=1
                    break
                fi
            done
            (( match == 0 )) && continue
        fi

        ((file_count++)) || true
        local lines
        lines=$(wc -l < "$file" 2>/dev/null || echo 0)
        line_count=$((line_count + lines))
    done < <(find "$dir" -type f \( \
        -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
        -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \
        -o -name "*.rb" -o -name "*.php" -o -name "*.c" -o -name "*.cpp" \
        -o -name "*.h" -o -name "*.sh" -o -name "*.vue" -o -name "*.svelte" \
        -o -name "*.css" -o -name "*.scss" -o -name "*.html" -o -name "*.sql" \
        -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.toml" \
        -o -name "*.md" \) 2>/dev/null)

    printf '%d %d' "$file_count" "$line_count"
}

# Generate directory structure with annotations
generate_structure() {
    local dir="$1"
    local max_depth="$2"
    local -n excludes_ref="$3"
    local prefix="${4:-}"
    local current_depth="${5:-0}"

    (( current_depth >= max_depth )) && return

    local items=()
    local item

    # Get directory contents
    while IFS= read -r item; do
        items+=("$item")
    done < <(ls -1 "$dir" 2>/dev/null | sort)

    local count=${#items[@]}
    local i=0

    for item in "${items[@]}"; do
        ((i++)) || true
        local path="$dir/$item"
        local is_last=$(( i == count ))
        local connector=$( (( is_last )) && echo "└── " || echo "├── " )
        local child_prefix=$( (( is_last )) && echo "    " || echo "│   " )

        # Check exclusions
        local excluded=0
        for excl in "${excludes_ref[@]}"; do
            if [[ "$item" == $excl ]]; then
                excluded=1
                break
            fi
        done
        (( excluded )) && continue

        if [[ -d "$path" ]]; then
            # Directory: count files and lines
            local stats
            stats=$(count_dir_stats "$path" excludes_ref)
            local dir_files dir_lines
            read -r dir_files dir_lines <<< "$stats"

            local annotation=""
            if (( dir_files > 0 )); then
                annotation=" ($dir_files files, $(format_number "$dir_lines") lines)"

                # Add purpose annotation based on directory name
                case "$item" in
                    app|pages)      annotation+=" - Routes/pages" ;;
                    components)     annotation+=" - UI components" ;;
                    lib|utils|util) annotation+=" - Utilities" ;;
                    hooks)          annotation+=" - React hooks" ;;
                    types)          annotation+=" - Type definitions" ;;
                    api)            annotation+=" - API routes" ;;
                    services)       annotation+=" - Service layer" ;;
                    models)         annotation+=" - Data models" ;;
                    controllers)    annotation+=" - Controllers" ;;
                    routes)         annotation+=" - Route handlers" ;;
                    middleware)     annotation+=" - Middleware" ;;
                    config)         annotation+=" - Configuration" ;;
                    tests|__tests__|test|spec) annotation+=" - Tests" ;;
                    styles|css)     annotation+=" - Stylesheets" ;;
                    public|static|assets) annotation+=" - Static assets" ;;
                    scripts)        annotation+=" - Scripts" ;;
                    db|database|migrations) annotation+=" - Database" ;;
                    store|stores|state) annotation+=" - State management" ;;
                    features)       annotation+=" - Feature modules" ;;
                    domain)         annotation+=" - Domain logic" ;;
                    infrastructure) annotation+=" - Infrastructure" ;;
                    presentation)   annotation+=" - Presentation layer" ;;
                esac
            fi

            printf '%s%s%s/%s\n' "$prefix" "$connector" "$item" "$annotation"

            # Recurse into subdirectory
            if (( dir_files > 0 && current_depth < max_depth - 1 )); then
                generate_structure "$path" "$max_depth" excludes_ref \
                    "${prefix}${child_prefix}" $((current_depth + 1))
            fi
        fi
    done
}

# Count files and lines in a single directory
count_dir_stats() {
    local dir="$1"
    local -n excl_ref="$2"

    local file_count=0
    local line_count=0

    while IFS= read -r -d '' file; do
        ((file_count++)) || true
        local lines
        lines=$(wc -l < "$file" 2>/dev/null || echo 0)
        line_count=$((line_count + lines))
    done < <(find "$dir" -type f \( \
        -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
        -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \
        -o -name "*.rb" -o -name "*.php" -o -name "*.c" -o -name "*.cpp" \
        -o -name "*.sh" -o -name "*.vue" -o -name "*.svelte" \) \
        -print0 2>/dev/null)

    printf '%d %d' "$file_count" "$line_count"
}

# Get key files (most important based on heuristics)
get_key_files() {
    local dir="$1"
    local count="$2"
    local -n excl_ref="$3"

    declare -A file_scores

    # Find all code files and score them
    while IFS= read -r -d '' file; do
        local rel_path="${file#$dir/}"
        local score=0
        local lines
        lines=$(wc -l < "$file" 2>/dev/null || echo 0)

        # Base score from line count (larger files more important, but cap it)
        score=$(( lines > 500 ? 500 : lines ))

        # Boost entry points and config
        local basename="${file##*/}"
        case "$basename" in
            main.*|index.*|app.*|server.*) score=$((score + 300)) ;;
            layout.*|page.*) score=$((score + 200)) ;;
            config.*|settings.*) score=$((score + 150)) ;;
            routes.*|router.*|api.*) score=$((score + 150)) ;;
            schema.*|model.*|types.*) score=$((score + 100)) ;;
            README*|CLAUDE*) score=$((score + 250)) ;;
            package.json|Cargo.toml|go.mod|pyproject.toml) score=$((score + 200)) ;;
        esac

        # Boost based on directory
        case "$rel_path" in
            */app/*|*/pages/*) score=$((score + 100)) ;;
            */lib/*|*/core/*) score=$((score + 100)) ;;
            */api/*|*/routes/*) score=$((score + 100)) ;;
            src/*) score=$((score + 50)) ;;
        esac

        # Penalize test files
        [[ "$rel_path" =~ test|spec|__tests__ ]] && score=$((score - 200))

        file_scores["$rel_path"]=$score
    done < <(find "$dir" -type f \( \
        -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
        -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \
        -o -name "*.rb" -o -name "*.sh" -o -name "package.json" \
        -o -name "Cargo.toml" -o -name "go.mod" -o -name "pyproject.toml" \
        -o -name "README*" -o -name "CLAUDE*" \) \
        -print0 2>/dev/null | head -z -n 200)

    # Sort by score and output top N
    for file in "${!file_scores[@]}"; do
        printf '%d %s\n' "${file_scores[$file]}" "$file"
    done | sort -rn | head -n "$count" | while read -r score file; do
        local full_path="$dir/$file"
        local lines
        lines=$(wc -l < "$full_path" 2>/dev/null || echo 0)

        # Generate description based on filename and content
        local desc=""
        local basename="${file##*/}"
        case "$basename" in
            layout.*) desc="Root layout" ;;
            page.*) desc="Page component" ;;
            index.*) desc="Entry point" ;;
            main.*) desc="Main entry" ;;
            app.*) desc="App bootstrap" ;;
            server.*) desc="Server entry" ;;
            config.*) desc="Configuration" ;;
            routes.*|router.*) desc="Route definitions" ;;
            schema.*) desc="Schema definitions" ;;
            types.*) desc="Type definitions" ;;
            api.*) desc="API handlers" ;;
            package.json) desc="Dependencies" ;;
            README*) desc="Documentation" ;;
            CLAUDE*) desc="AI instructions" ;;
            *)
                # Try to infer from content
                if [[ -f "$full_path" ]]; then
                    local first_lines
                    first_lines=$(head -20 "$full_path" 2>/dev/null || true)
                    if [[ "$first_lines" =~ export[[:space:]]+default|export[[:space:]]+function ]]; then
                        desc="Module exports"
                    elif [[ "$first_lines" =~ class[[:space:]] ]]; then
                        desc="Class definition"
                    elif [[ "$first_lines" =~ interface[[:space:]]|type[[:space:]] ]]; then
                        desc="Type definitions"
                    fi
                fi
                ;;
        esac

        printf '- %s (%d lines)%s\n' "$file" "$lines" "${desc:+ - $desc}"
    done
}

# Extract dependencies from package.json
get_npm_deps() {
    local pkg_file="$1"
    local verbose="$2"

    if [[ ! -f "$pkg_file" ]]; then
        return
    fi

    local content
    content=$(cat "$pkg_file" 2>/dev/null)

    # Extract dependencies section (simple approach without jq)
    local in_deps=0
    local in_dev_deps=0
    local prod_deps=()
    local dev_deps=()

    while IFS= read -r line; do
        if [[ "$line" =~ \"dependencies\" ]]; then
            in_deps=1
            in_dev_deps=0
        elif [[ "$line" =~ \"devDependencies\" ]]; then
            in_deps=0
            in_dev_deps=1
        elif [[ "$line" =~ ^\s*\} ]]; then
            in_deps=0
            in_dev_deps=0
        elif [[ "$line" =~ \"([^\"]+)\":[[:space:]]*\" ]]; then
            local dep="${BASH_REMATCH[1]}"
            if (( in_deps )); then
                prod_deps+=("$dep")
            elif (( in_dev_deps )); then
                dev_deps+=("$dep")
            fi
        fi
    done <<< "$content"

    local prod_count=${#prod_deps[@]}
    local dev_count=${#dev_deps[@]}

    printf '## Dependencies (%d production, %d dev)\n' "$prod_count" "$dev_count"

    if (( prod_count > 0 )); then
        if [[ "$verbose" == "true" ]] || (( prod_count <= 15 )); then
            printf 'Production: %s\n' "$(IFS=', '; echo "${prod_deps[*]}")"
        else
            # Show first 10 + count of others
            local shown=("${prod_deps[@]:0:10}")
            printf 'Production: %s, ... (+%d more)\n' "$(IFS=', '; echo "${shown[*]}")" $((prod_count - 10))
        fi
    fi

    if (( dev_count > 0 )) && [[ "$verbose" == "true" ]]; then
        if (( dev_count <= 10 )); then
            printf 'Dev: %s\n' "$(IFS=', '; echo "${dev_deps[*]}")"
        else
            local shown=("${dev_deps[@]:0:8}")
            printf 'Dev: %s, ... (+%d more)\n' "$(IFS=', '; echo "${shown[*]}")" $((dev_count - 8))
        fi
    fi
}

# Extract Python dependencies
get_python_deps() {
    local dir="$1"
    local verbose="$2"

    local deps=()

    if [[ -f "$dir/requirements.txt" ]]; then
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^#|^$ ]] && continue
            # Extract package name (before ==, >=, etc.)
            local pkg="${line%%[=<>!~]*}"
            pkg="${pkg%%[[:space:]]*}"
            [[ -n "$pkg" ]] && deps+=("$pkg")
        done < "$dir/requirements.txt"
    fi

    if [[ -f "$dir/pyproject.toml" ]]; then
        local in_deps=0
        while IFS= read -r line; do
            if [[ "$line" =~ ^\[.*dependencies\] ]]; then
                in_deps=1
            elif [[ "$line" =~ ^\[ ]]; then
                in_deps=0
            elif (( in_deps )) && [[ "$line" =~ ^([a-zA-Z0-9_-]+) ]]; then
                deps+=("${BASH_REMATCH[1]}")
            fi
        done < "$dir/pyproject.toml"
    fi

    local count=${#deps[@]}
    if (( count > 0 )); then
        printf '## Dependencies (%d packages)\n' "$count"
        if [[ "$verbose" == "true" ]] || (( count <= 15 )); then
            printf 'Packages: %s\n' "$(IFS=', '; echo "${deps[*]}")"
        else
            local shown=("${deps[@]:0:12}")
            printf 'Packages: %s, ... (+%d more)\n' "$(IFS=', '; echo "${shown[*]}")" $((count - 12))
        fi
    fi
}

# Get entry points/scripts from package.json
get_scripts() {
    local pkg_file="$1"

    if [[ ! -f "$pkg_file" ]]; then
        return
    fi

    local content
    content=$(cat "$pkg_file" 2>/dev/null)

    local in_scripts=0
    local scripts=()

    while IFS= read -r line; do
        if [[ "$line" =~ \"scripts\" ]]; then
            in_scripts=1
        elif [[ "$line" =~ ^\s*\} ]] && (( in_scripts )); then
            break
        elif (( in_scripts )) && [[ "$line" =~ \"([^\"]+)\":[[:space:]]*\"([^\"]+)\" ]]; then
            local name="${BASH_REMATCH[1]}"
            local cmd="${BASH_REMATCH[2]}"
            # Truncate long commands
            (( ${#cmd} > 40 )) && cmd="${cmd:0:37}..."
            scripts+=("$name: $cmd")
        fi
    done <<< "$content"

    if (( ${#scripts[@]} > 0 )); then
        printf '## Scripts/Entry Points\n'
        for script in "${scripts[@]:0:8}"; do
            printf '- %s\n' "$script"
        done
        (( ${#scripts[@]} > 8 )) && printf '- ... (+%d more)\n' $(( ${#scripts[@]} - 8 ))
    fi
}

# Get recent git history
get_git_history() {
    local dir="$1"
    local count="$2"

    if ! git -C "$dir" rev-parse --git-dir &>/dev/null; then
        return
    fi

    printf '## Recent Changes (git)\n'

    git -C "$dir" log --oneline --pretty=format:'%ar: %s' -n "$count" 2>/dev/null | \
        while IFS= read -r line; do
            printf '- %s\n' "$line"
        done

    printf '\n'
}

# Get git status summary
get_git_status() {
    local dir="$1"

    if ! git -C "$dir" rev-parse --git-dir &>/dev/null; then
        return
    fi

    local branch
    branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || echo "detached")

    local status
    status=$(git -C "$dir" status --porcelain 2>/dev/null)

    local modified=0 staged=0 untracked=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local st="${line:0:2}"
        case "$st" in
            "M "*|" M") ((modified++)) || true ;;
            "A "*|"MM") ((staged++)) || true ;;
            "??") ((untracked++)) || true ;;
        esac
    done <<< "$status"

    local status_str=""
    (( staged > 0 )) && status_str+="$staged staged, "
    (( modified > 0 )) && status_str+="$modified modified, "
    (( untracked > 0 )) && status_str+="$untracked untracked"
    status_str="${status_str%, }"

    printf 'Git: %s%s\n' "$branch" "${status_str:+ ($status_str)}"
}

# Generate JSON output
generate_json_output() {
    local project_name="$1"
    local dir="$2"
    local language="$3"
    local framework="$4"
    local pkg_manager="$5"
    local file_count="$6"
    local line_count="$7"

    printf '{\n'
    printf '  "project": %s,\n' "$(json_string "$project_name")"
    printf '  "path": %s,\n' "$(json_string "$dir")"
    printf '  "language": %s,\n' "$(json_string "$language")"
    printf '  "framework": %s,\n' "$(json_string "$framework")"
    printf '  "packageManager": %s,\n' "$(json_string "$pkg_manager")"
    printf '  "stats": {\n'
    printf '    "files": %d,\n' "$file_count"
    printf '    "lines": %d\n' "$line_count"
    printf '  }\n'
    printf '}\n'
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

context_summary() {
    local dir="${1:-.}"
    shift || true

    # Default options
    local max_tokens="$DEFAULT_MAX_TOKENS"
    local -a focus_patterns=()
    local -a exclude_patterns=("${DEFAULT_EXCLUDES[@]}")
    local max_depth=4
    local key_files_count=10
    local git_history_count=5
    local json_output=false
    local quiet=false
    local verbose=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--max-tokens) max_tokens="$2"; shift 2 ;;
            -f|--focus) focus_patterns+=("$2"); shift 2 ;;
            -e|--exclude) exclude_patterns+=("$2"); shift 2 ;;
            -d|--depth) max_depth="$2"; shift 2 ;;
            -k|--key-files) key_files_count="$2"; shift 2 ;;
            -g|--git-history) git_history_count="$2"; shift 2 ;;
            -j|--json) json_output=true; shift ;;
            -q|--quiet) quiet=true; shift ;;
            -v|--verbose) verbose=true; shift ;;
            -h|--help) usage; return 0 ;;
            --version) echo "context_summary v$VERSION"; return 0 ;;
            -*) log_error "Unknown option: $1"; usage; return 1 ;;
            *) shift ;;
        esac
    done

    # Normalize directory path
    dir=$(realpath "$dir" 2>/dev/null || echo "$dir")

    if [[ ! -d "$dir" ]]; then
        log_error "Directory not found: $dir"
        return 1
    fi

    # Detect project info
    local project_name
    project_name=$(basename "$dir")

    local language
    language=$(detect_language "$dir")

    local framework
    framework=$(detect_framework "$dir")

    local pkg_manager
    pkg_manager=$(detect_package_manager "$dir")

    # Count files and lines
    local stats
    stats=$(count_files_and_lines "$dir" exclude_patterns focus_patterns)
    local file_count line_count
    read -r file_count line_count <<< "$stats"

    # JSON output mode
    if [[ "$json_output" == "true" ]]; then
        generate_json_output "$project_name" "$dir" "$language" "$framework" \
            "$pkg_manager" "$file_count" "$line_count"
        return 0
    fi

    # Build output
    local output=""

    # Header
    output+="## Project: $project_name"$'\n'
    output+="Language: $language | Framework: $framework | Package Manager: $pkg_manager"$'\n'
    output+=$'\n'

    # Git status
    local git_status
    git_status=$(get_git_status "$dir")
    [[ -n "$git_status" ]] && output+="$git_status"$'\n\n'

    # Structure
    output+="## Structure ($(format_number "$file_count") files, $(format_number "$line_count") lines)"$'\n'

    if [[ "$quiet" != "true" ]]; then
        local structure
        structure=$(generate_structure "$dir" "$max_depth" exclude_patterns)
        [[ -n "$structure" ]] && output+="$structure"$'\n'
    fi
    output+=$'\n'

    # Key files
    if [[ "$quiet" != "true" ]]; then
        output+="## Key Files"$'\n'
        local key_files
        key_files=$(get_key_files "$dir" "$key_files_count" exclude_patterns)
        [[ -n "$key_files" ]] && output+="$key_files"$'\n'
        output+=$'\n'
    fi

    # Dependencies
    local deps=""
    if [[ -f "$dir/package.json" ]]; then
        deps=$(get_npm_deps "$dir/package.json" "$verbose")
    elif [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/pyproject.toml" ]]; then
        deps=$(get_python_deps "$dir" "$verbose")
    fi
    [[ -n "$deps" ]] && output+="$deps"$'\n\n'

    # Scripts/entry points
    if [[ -f "$dir/package.json" ]] && [[ "$quiet" != "true" ]]; then
        local scripts
        scripts=$(get_scripts "$dir/package.json")
        [[ -n "$scripts" ]] && output+="$scripts"$'\n\n'
    fi

    # Git history
    if [[ "$quiet" != "true" ]] && (( git_history_count > 0 )); then
        local history
        history=$(get_git_history "$dir" "$git_history_count")
        [[ -n "$history" ]] && output+="$history"
    fi

    # Truncate to token budget and output
    local final_output
    final_output=$(truncate_to_tokens "$output" "$max_tokens")

    printf '%s\n' "$final_output"

    # Print token estimate to stderr
    local char_count=${#final_output}
    local token_estimate
    token_estimate=$(estimate_tokens "$char_count")
    >&2 printf '\n[Estimated tokens: ~%d / %d budget]\n' "$token_estimate" "$max_tokens"
}

# =============================================================================
# ENTRY POINT
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    context_summary "$@"
fi
