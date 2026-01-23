#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/project.sh - Project Intelligence for AI Agents
# =============================================================================
# Description: Detect project types, frameworks, build systems, and entry
#              points from directory structure. Gives AI coding assistants
#              instant context without reading dozens of files.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_PROJECT_LOADED:-}" ]] && return 0
readonly _MAINFRAME_PROJECT_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_project_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

_project_json_string() {
    printf '"%s"' "$(_project_escape "$1")"
}

_project_json_array() {
    local result="["
    local first=true
    local item
    for item in "$@"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            result+=","
        fi
        result+="\"$(_project_escape "$item")\""
    done
    result+="]"
    printf '%s' "$result"
}

# =============================================================================
# PROJECT DETECTION
# =============================================================================

# @pre: directory exists and is readable
# @post: JSON object with detected project characteristics
# @idempotent: yes
# @returns: 0 on success, 1 if directory doesn't exist
#
# Detect project language, framework, package manager, build system,
# test runner, and CI provider from directory analysis.
#
# Usage: project_detect [directory]
# Example: project_detect .
# Example: project_detect /path/to/project
#
# Output: JSON object with detected characteristics
project_detect() {
    local dir="${1:-.}"

    if [[ ! -d "$dir" ]]; then
        printf '{"error":"directory not found","path":"%s"}' "$(_project_escape "$dir")"
        return 1
    fi

    local language="unknown"
    local framework=""
    local package_manager=""
    local build_system=""
    local test_runner=""
    local ci_provider=""
    local has_monorepo="false"
    local config_files=()

    # --- Language Detection ---
    if [[ -f "$dir/package.json" ]]; then
        language="javascript"
        config_files+=("package.json")
        # Check for TypeScript
        if [[ -f "$dir/tsconfig.json" ]]; then
            language="typescript"
            config_files+=("tsconfig.json")
        fi
    elif [[ -f "$dir/Cargo.toml" ]]; then
        language="rust"
        config_files+=("Cargo.toml")
    elif [[ -f "$dir/go.mod" ]]; then
        language="go"
        config_files+=("go.mod")
    elif [[ -f "$dir/pyproject.toml" ]]; then
        language="python"
        config_files+=("pyproject.toml")
    elif [[ -f "$dir/setup.py" ]]; then
        language="python"
        config_files+=("setup.py")
    elif [[ -f "$dir/requirements.txt" ]]; then
        language="python"
        config_files+=("requirements.txt")
    elif [[ -f "$dir/Gemfile" ]]; then
        language="ruby"
        config_files+=("Gemfile")
    elif [[ -f "$dir/pom.xml" ]]; then
        language="java"
        config_files+=("pom.xml")
    elif [[ -f "$dir/build.gradle" ]] || [[ -f "$dir/build.gradle.kts" ]]; then
        language="java"
        config_files+=("build.gradle")
    elif [[ -f "$dir/mix.exs" ]]; then
        language="elixir"
        config_files+=("mix.exs")
    elif [[ -f "$dir/composer.json" ]]; then
        language="php"
        config_files+=("composer.json")
    elif [[ -f "$dir/Package.swift" ]]; then
        language="swift"
        config_files+=("Package.swift")
    elif [[ -f "$dir/CMakeLists.txt" ]]; then
        language="cpp"
        config_files+=("CMakeLists.txt")
    elif [[ -f "$dir/Makefile" ]]; then
        # Check for C/C++ source files
        if ls "$dir"/*.c "$dir/src/"*.c 2>/dev/null | head -1 &>/dev/null; then
            language="c"
        elif ls "$dir"/*.cpp "$dir/src/"*.cpp 2>/dev/null | head -1 &>/dev/null; then
            language="cpp"
        fi
        config_files+=("Makefile")
    fi

    # --- Framework Detection ---
    if [[ "$language" == "typescript" ]] || [[ "$language" == "javascript" ]]; then
        if [[ -f "$dir/next.config.js" ]] || [[ -f "$dir/next.config.mjs" ]] || [[ -f "$dir/next.config.ts" ]]; then
            framework="nextjs"
            config_files+=("next.config.*")
        elif [[ -f "$dir/nuxt.config.ts" ]] || [[ -f "$dir/nuxt.config.js" ]]; then
            framework="nuxt"
        elif [[ -f "$dir/svelte.config.js" ]]; then
            framework="sveltekit"
        elif [[ -f "$dir/astro.config.mjs" ]] || [[ -f "$dir/astro.config.ts" ]]; then
            framework="astro"
        elif [[ -f "$dir/remix.config.js" ]]; then
            framework="remix"
        elif [[ -f "$dir/vite.config.ts" ]] || [[ -f "$dir/vite.config.js" ]]; then
            framework="vite"
            if [[ -f "$dir/index.html" ]]; then
                # Check for React in package.json
                if grep -q '"react"' "$dir/package.json" 2>/dev/null; then
                    framework="react-vite"
                elif grep -q '"vue"' "$dir/package.json" 2>/dev/null; then
                    framework="vue-vite"
                fi
            fi
        elif grep -q '"react"' "$dir/package.json" 2>/dev/null; then
            framework="react"
        elif grep -q '"vue"' "$dir/package.json" 2>/dev/null; then
            framework="vue"
        elif grep -q '"angular"' "$dir/package.json" 2>/dev/null; then
            framework="angular"
        elif grep -q '"express"' "$dir/package.json" 2>/dev/null; then
            framework="express"
        elif grep -q '"fastify"' "$dir/package.json" 2>/dev/null; then
            framework="fastify"
        fi
    elif [[ "$language" == "python" ]]; then
        if [[ -f "$dir/manage.py" ]]; then
            framework="django"
        elif grep -q "fastapi\|FastAPI" "$dir/pyproject.toml" "$dir/requirements.txt" 2>/dev/null; then
            framework="fastapi"
        elif grep -q "flask\|Flask" "$dir/pyproject.toml" "$dir/requirements.txt" 2>/dev/null; then
            framework="flask"
        fi
    elif [[ "$language" == "ruby" ]]; then
        if [[ -f "$dir/config/routes.rb" ]]; then
            framework="rails"
        fi
    elif [[ "$language" == "rust" ]]; then
        if grep -q "actix-web\|actix_web" "$dir/Cargo.toml" 2>/dev/null; then
            framework="actix"
        elif grep -q "axum" "$dir/Cargo.toml" 2>/dev/null; then
            framework="axum"
        fi
    elif [[ "$language" == "go" ]]; then
        if grep -q "gin-gonic" "$dir/go.mod" 2>/dev/null; then
            framework="gin"
        elif grep -q "labstack/echo" "$dir/go.mod" 2>/dev/null; then
            framework="echo"
        fi
    fi

    # --- Package Manager Detection ---
    if [[ -f "$dir/bun.lockb" ]] || [[ -f "$dir/bun.lock" ]]; then
        package_manager="bun"
    elif [[ -f "$dir/pnpm-lock.yaml" ]]; then
        package_manager="pnpm"
    elif [[ -f "$dir/yarn.lock" ]]; then
        package_manager="yarn"
    elif [[ -f "$dir/package-lock.json" ]]; then
        package_manager="npm"
    elif [[ -f "$dir/Pipfile.lock" ]]; then
        package_manager="pipenv"
    elif [[ -f "$dir/poetry.lock" ]]; then
        package_manager="poetry"
    elif [[ -f "$dir/uv.lock" ]]; then
        package_manager="uv"
    elif [[ -f "$dir/Cargo.lock" ]]; then
        package_manager="cargo"
    elif [[ -f "$dir/go.sum" ]]; then
        package_manager="go-modules"
    elif [[ -f "$dir/Gemfile.lock" ]]; then
        package_manager="bundler"
    elif [[ -f "$dir/composer.lock" ]]; then
        package_manager="composer"
    fi

    # --- Build System Detection ---
    if [[ -f "$dir/turbo.json" ]]; then
        build_system="turborepo"
    elif [[ -f "$dir/nx.json" ]]; then
        build_system="nx"
    elif [[ -f "$dir/webpack.config.js" ]] || [[ -f "$dir/webpack.config.ts" ]]; then
        build_system="webpack"
    elif [[ -f "$dir/rollup.config.js" ]]; then
        build_system="rollup"
    elif [[ -f "$dir/esbuild.config.js" ]] || [[ -f "$dir/esbuild.mjs" ]]; then
        build_system="esbuild"
    elif [[ -f "$dir/vite.config.ts" ]] || [[ -f "$dir/vite.config.js" ]]; then
        build_system="vite"
    elif [[ -f "$dir/Makefile" ]]; then
        build_system="make"
    elif [[ -f "$dir/CMakeLists.txt" ]]; then
        build_system="cmake"
    elif [[ -f "$dir/build.gradle" ]] || [[ -f "$dir/build.gradle.kts" ]]; then
        build_system="gradle"
    elif [[ -f "$dir/pom.xml" ]]; then
        build_system="maven"
    fi

    # --- Test Runner Detection ---
    if [[ -f "$dir/vitest.config.ts" ]] || [[ -f "$dir/vitest.config.js" ]]; then
        test_runner="vitest"
    elif [[ -f "$dir/jest.config.js" ]] || [[ -f "$dir/jest.config.ts" ]]; then
        test_runner="jest"
    elif grep -q '"vitest"' "$dir/package.json" 2>/dev/null; then
        test_runner="vitest"
    elif grep -q '"jest"' "$dir/package.json" 2>/dev/null; then
        test_runner="jest"
    elif grep -q '"mocha"' "$dir/package.json" 2>/dev/null; then
        test_runner="mocha"
    elif [[ -f "$dir/pytest.ini" ]] || [[ -f "$dir/conftest.py" ]]; then
        test_runner="pytest"
    elif grep -q "pytest" "$dir/pyproject.toml" 2>/dev/null; then
        test_runner="pytest"
    elif [[ -d "$dir/tests" ]] && ls "$dir/tests/"*.bats 2>/dev/null | head -1 &>/dev/null; then
        test_runner="bats"
    elif [[ -f "$dir/.rspec" ]]; then
        test_runner="rspec"
    fi

    # --- CI Provider Detection ---
    if [[ -d "$dir/.github/workflows" ]]; then
        ci_provider="github_actions"
    elif [[ -f "$dir/.gitlab-ci.yml" ]]; then
        ci_provider="gitlab_ci"
    elif [[ -f "$dir/Jenkinsfile" ]]; then
        ci_provider="jenkins"
    elif [[ -f "$dir/.circleci/config.yml" ]]; then
        ci_provider="circleci"
    elif [[ -f "$dir/.travis.yml" ]]; then
        ci_provider="travis"
    fi

    # --- Monorepo Detection ---
    if [[ -f "$dir/turbo.json" ]] || [[ -f "$dir/nx.json" ]] || [[ -f "$dir/lerna.json" ]]; then
        has_monorepo="true"
    elif [[ -f "$dir/pnpm-workspace.yaml" ]]; then
        has_monorepo="true"
    elif grep -q '"workspaces"' "$dir/package.json" 2>/dev/null; then
        has_monorepo="true"
    elif [[ -f "$dir/Cargo.toml" ]] && grep -q '\[workspace\]' "$dir/Cargo.toml" 2>/dev/null; then
        has_monorepo="true"
    fi

    # --- Build JSON Output ---
    local config_json
    config_json=$(_project_json_array "${config_files[@]}")

    printf '{"language":"%s","framework":"%s","package_manager":"%s","build_system":"%s","test_runner":"%s","ci_provider":"%s","has_monorepo":%s,"config_files":%s}' \
        "$language" "$framework" "$package_manager" "$build_system" "$test_runner" "$ci_provider" "$has_monorepo" "$config_json"
}

# =============================================================================
# PROJECT COMMANDS
# =============================================================================

# @pre: directory is a detectable project
# @post: JSON object with common commands for the project
# @idempotent: yes
# @returns: 0
#
# Return the standard commands (build, test, lint, dev, start) for the
# detected project type. AI agents can use these instead of guessing.
#
# Usage: project_commands [directory]
# Example: project_commands .
project_commands() {
    local dir="${1:-.}"
    local build="" test="" lint="" dev="" start="" install=""

    # Detect package manager first
    local pkg_mgr=""
    if [[ -f "$dir/bun.lockb" ]] || [[ -f "$dir/bun.lock" ]]; then
        pkg_mgr="bun"
    elif [[ -f "$dir/pnpm-lock.yaml" ]]; then
        pkg_mgr="pnpm"
    elif [[ -f "$dir/yarn.lock" ]]; then
        pkg_mgr="yarn"
    elif [[ -f "$dir/package-lock.json" ]]; then
        pkg_mgr="npm"
    fi

    if [[ -f "$dir/package.json" ]]; then
        local run_cmd="${pkg_mgr:-npm} run"
        [[ "$pkg_mgr" == "bun" ]] && run_cmd="bun run"

        install="${pkg_mgr:-npm} install"
        [[ "$pkg_mgr" == "bun" ]] && install="bun install"

        # Read scripts from package.json
        if grep -q '"build"' "$dir/package.json" 2>/dev/null; then
            build="$run_cmd build"
        fi
        if grep -q '"test"' "$dir/package.json" 2>/dev/null; then
            test="$run_cmd test"
        fi
        if grep -q '"lint"' "$dir/package.json" 2>/dev/null; then
            lint="$run_cmd lint"
        fi
        if grep -q '"dev"' "$dir/package.json" 2>/dev/null; then
            dev="$run_cmd dev"
        elif grep -q '"start"' "$dir/package.json" 2>/dev/null; then
            dev="$run_cmd start"
        fi
        if grep -q '"start"' "$dir/package.json" 2>/dev/null; then
            start="$run_cmd start"
        fi
    elif [[ -f "$dir/Cargo.toml" ]]; then
        install=""
        build="cargo build"
        test="cargo test"
        lint="cargo clippy"
        dev="cargo run"
        start="cargo run --release"
    elif [[ -f "$dir/go.mod" ]]; then
        install="go mod download"
        build="go build ./..."
        test="go test ./..."
        lint="golangci-lint run"
        dev="go run ."
        start="go run ."
    elif [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/setup.py" ]]; then
        if [[ -f "$dir/poetry.lock" ]]; then
            install="poetry install"
        elif [[ -f "$dir/uv.lock" ]]; then
            install="uv sync"
        else
            install="pip install -e ."
        fi
        test="pytest"
        lint="ruff check ."
        if [[ -f "$dir/manage.py" ]]; then
            dev="python manage.py runserver"
            start="python manage.py runserver"
        fi
    elif [[ -f "$dir/Makefile" ]]; then
        build="make"
        if grep -q '^test:' "$dir/Makefile" 2>/dev/null; then
            test="make test"
        fi
        if grep -q '^clean:' "$dir/Makefile" 2>/dev/null; then
            lint="make clean"
        fi
    elif [[ -f "$dir/Gemfile" ]]; then
        install="bundle install"
        test="bundle exec rspec"
        lint="bundle exec rubocop"
        if [[ -f "$dir/config/routes.rb" ]]; then
            dev="rails server"
            start="rails server"
        fi
    fi

    printf '{"install":"%s","build":"%s","test":"%s","lint":"%s","dev":"%s","start":"%s"}' \
        "$(_project_escape "$install")" \
        "$(_project_escape "$build")" \
        "$(_project_escape "$test")" \
        "$(_project_escape "$lint")" \
        "$(_project_escape "$dev")" \
        "$(_project_escape "$start")"
}

# =============================================================================
# PROJECT ENTRY POINTS
# =============================================================================

# @pre: directory is a project
# @post: JSON array of likely entry point files
# @idempotent: yes
# @returns: 0
#
# Find the main entry point files for the project.
# Checks common patterns (main.*, index.*, app.*, etc.)
#
# Usage: project_entry [directory]
# Example: project_entry /path/to/project
project_entry() {
    local dir="${1:-.}"
    local entries=()

    # JavaScript/TypeScript entry points
    local candidates=(
        "src/index.ts" "src/index.js" "src/main.ts" "src/main.js"
        "src/app.ts" "src/app.js" "src/server.ts" "src/server.js"
        "index.ts" "index.js" "main.ts" "main.js" "app.ts" "app.js"
        "src/app/page.tsx" "src/app/layout.tsx"  # Next.js App Router
        "src/pages/index.tsx" "src/pages/index.js"  # Next.js Pages
        "pages/index.tsx" "pages/index.js"
        "app/page.tsx" "app/layout.tsx"
    )

    for f in "${candidates[@]}"; do
        if [[ -f "$dir/$f" ]]; then
            entries+=("$f")
        fi
    done

    # Python entry points
    for f in "main.py" "app.py" "manage.py" "src/main.py" "src/app.py" "__main__.py" "src/__main__.py"; do
        if [[ -f "$dir/$f" ]]; then
            entries+=("$f")
        fi
    done

    # Rust
    if [[ -f "$dir/src/main.rs" ]]; then
        entries+=("src/main.rs")
    elif [[ -f "$dir/src/lib.rs" ]]; then
        entries+=("src/lib.rs")
    fi

    # Go
    if [[ -f "$dir/main.go" ]]; then
        entries+=("main.go")
    elif [[ -f "$dir/cmd/main.go" ]]; then
        entries+=("cmd/main.go")
    fi

    # package.json "main" field
    if [[ -f "$dir/package.json" ]]; then
        local main_field
        main_field=$(grep -o '"main"[[:space:]]*:[[:space:]]*"[^"]*"' "$dir/package.json" 2>/dev/null | head -1)
        if [[ -n "$main_field" ]]; then
            local main_file
            main_file="${main_field##*\"}"
            main_file="${main_field%\"*}"
            main_file="${main_file##*\"}"
            if [[ -f "$dir/$main_file" ]]; then
                entries+=("$main_file")
            fi
        fi
    fi

    _project_json_array "${entries[@]}"
}

# =============================================================================
# PROJECT DEPENDENCIES
# =============================================================================

# @pre: lock file or manifest exists
# @post: JSON object with dependency counts and key deps
# @idempotent: yes
# @returns: 0
#
# Get dependency information (counts and notable packages).
# Reads lock files for accuracy over manifests.
#
# Usage: project_deps [directory]
project_deps() {
    local dir="${1:-.}"
    local total=0
    local dev_count=0
    local prod_count=0
    local notable=()

    if [[ -f "$dir/package.json" ]]; then
        # Count deps using grep -o for robustness with single-line or multi-line JSON
        # Extract the dependencies object value and count quoted keys
        local content
        content=$(<"$dir/package.json")

        # Count production dependencies
        local deps_section
        deps_section="${content#*\"dependencies\"}"
        if [[ "$deps_section" != "$content" ]]; then
            # Found dependencies section - extract first {...} after it
            deps_section="${deps_section#*\{}"
            deps_section="${deps_section%%\}*}"
            # Count "key": patterns
            prod_count=$(printf '%s' "$deps_section" | grep -o '"[^"]*"[[:space:]]*:' 2>/dev/null | wc -l)
            prod_count="${prod_count//[!0-9]/}"
            prod_count="${prod_count:-0}"
        fi

        # Count dev dependencies
        local devdeps_section
        devdeps_section="${content#*\"devDependencies\"}"
        if [[ "$devdeps_section" != "$content" ]]; then
            devdeps_section="${devdeps_section#*\{}"
            devdeps_section="${devdeps_section%%\}*}"
            dev_count=$(printf '%s' "$devdeps_section" | grep -o '"[^"]*"[[:space:]]*:' 2>/dev/null | wc -l)
            dev_count="${dev_count//[!0-9]/}"
            dev_count="${dev_count:-0}"
        fi

        total=$((prod_count + dev_count))

        # Notable deps
        for dep in react next vue angular express fastify prisma drizzle tailwindcss; do
            if grep -q "\"$dep\"" "$dir/package.json" 2>/dev/null; then
                notable+=("$dep")
            fi
        done
    elif [[ -f "$dir/Cargo.toml" ]]; then
        total=$(grep -c '^[a-z]' <(sed -n '/\[dependencies\]/,/^\[/p' "$dir/Cargo.toml") 2>/dev/null || echo "0")
        dev_count=$(grep -c '^[a-z]' <(sed -n '/\[dev-dependencies\]/,/^\[/p' "$dir/Cargo.toml") 2>/dev/null || echo "0")
        prod_count=$((total - dev_count))
    elif [[ -f "$dir/go.mod" ]]; then
        total=$(grep -c '^\t' "$dir/go.mod" 2>/dev/null || echo "0")
        prod_count=$total
    elif [[ -f "$dir/requirements.txt" ]]; then
        total=$(grep -cv '^#\|^$' "$dir/requirements.txt" 2>/dev/null || echo "0")
        prod_count=$total
    elif [[ -f "$dir/pyproject.toml" ]]; then
        total=$(grep -c '^\s*"' <(sed -n '/\[project.dependencies\]/,/^\[/p' "$dir/pyproject.toml") 2>/dev/null || echo "0")
        prod_count=$total
    fi

    local notable_json
    notable_json=$(_project_json_array "${notable[@]}")

    printf '{"total":%d,"production":%d,"development":%d,"notable":%s}' \
        "$total" "$prod_count" "$dev_count" "$notable_json"
}

# =============================================================================
# PROJECT STRUCTURE
# =============================================================================

# @pre: directory exists
# @post: JSON with directory structure summary
# @idempotent: yes
# @returns: 0
#
# Return a high-level structure summary of the project.
# Lists top-level dirs, file counts by extension, and total size.
#
# Usage: project_structure [directory] [max_depth]
# Example: project_structure . 2
project_structure() {
    local dir="${1:-.}"
    local max_depth="${2:-1}"

    local dirs=()
    local file_count=0

    # Get top-level directories
    local entry
    for entry in "$dir"/*/; do
        if [[ -d "$entry" ]]; then
            local name="${entry%/}"
            name="${name##*/}"
            # Skip hidden and common noise dirs
            [[ "$name" == .* ]] && continue
            [[ "$name" == "node_modules" ]] && continue
            [[ "$name" == "__pycache__" ]] && continue
            [[ "$name" == "target" ]] && continue
            [[ "$name" == "dist" ]] && continue
            [[ "$name" == ".git" ]] && continue
            dirs+=("$name")
        fi
    done

    # Count files (non-hidden, non-node_modules)
    if command -v find &>/dev/null; then
        file_count=$(find "$dir" -maxdepth "$max_depth" -type f \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            -not -path '*/target/*' \
            -not -name '.*' 2>/dev/null | wc -l)
    fi

    # Top file extensions
    local extensions=""
    if command -v find &>/dev/null; then
        extensions=$(find "$dir" -maxdepth 3 -type f \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            -not -path '*/target/*' \
            -not -name '.*' 2>/dev/null | \
            grep -o '\.[^./]*$' | sort | uniq -c | sort -rn | head -5 | \
            while read -r count ext; do
                printf '"%s":%d,' "$ext" "$count"
            done)
        extensions="${extensions%,}"
    fi

    local dirs_json
    dirs_json=$(_project_json_array "${dirs[@]}")

    printf '{"directories":%s,"file_count":%d,"extensions":{%s}}' \
        "$dirs_json" "$file_count" "$extensions"
}
