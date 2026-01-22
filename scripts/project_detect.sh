#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/scripts/project_detect.sh - Project Type Detection
# =============================================================================
# Description: Analyzes a directory to detect project type, framework, language,
#              and key files - essential for AI agents to understand codebases.
# Usage: project_detect [directory]
# Output: JSON object with project metadata
# =============================================================================

# Source MAINFRAME
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# =============================================================================
# LANGUAGE DETECTION
# =============================================================================

# Detect primary programming language
# Usage: _detect_language "/path/to/project"
_detect_language() {
    local dir="$1"
    local language=""

    # Check in order of specificity (more specific first)
    [[ -f "$dir/tsconfig.json" ]] && language="typescript"
    [[ -z "$language" && -f "$dir/package.json" ]] && language="javascript"
    [[ -f "$dir/Cargo.toml" ]] && language="rust"
    [[ -f "$dir/go.mod" ]] && language="go"
    [[ -f "$dir/pyproject.toml" ]] && language="python"
    [[ -z "$language" && -f "$dir/setup.py" ]] && language="python"
    [[ -z "$language" && -f "$dir/requirements.txt" ]] && language="python"
    [[ -z "$language" && -f "$dir/Pipfile" ]] && language="python"
    [[ -f "$dir/Gemfile" ]] && language="ruby"
    [[ -f "$dir/composer.json" ]] && language="php"
    [[ -f "$dir/pom.xml" ]] && language="java"
    [[ -f "$dir/build.gradle" || -f "$dir/build.gradle.kts" ]] && language="java"
    [[ -f "$dir/build.sbt" ]] && language="scala"
    [[ -f "$dir/mix.exs" ]] && language="elixir"
    [[ -f "$dir/pubspec.yaml" ]] && language="dart"
    [[ -f "$dir/Package.swift" ]] && language="swift"
    [[ -f "$dir/CMakeLists.txt" ]] && language="cpp"
    [[ -f "$dir/Makefile" && -z "$language" ]] && {
        # Check for C/C++ indicators
        if compgen -G "$dir/*.c" > /dev/null 2>&1; then
            language="c"
        elif compgen -G "$dir/*.cpp" > /dev/null 2>&1 || compgen -G "$dir/*.cc" > /dev/null 2>&1; then
            language="cpp"
        fi
    }
    # C# detection - check for .csproj or .sln files
    if compgen -G "$dir/*.csproj" > /dev/null 2>&1 || compgen -G "$dir/*.sln" > /dev/null 2>&1; then
        language="csharp"
    fi
    [[ -f "$dir/deno.json" || -f "$dir/deno.jsonc" ]] && language="typescript"

    # Fallback: check for source files if still unknown
    if [[ -z "$language" ]]; then
        compgen -G "$dir/*.rs" > /dev/null 2>&1 && language="rust"
        compgen -G "$dir/*.go" > /dev/null 2>&1 && language="go"
        compgen -G "$dir/*.py" > /dev/null 2>&1 && language="python"
        compgen -G "$dir/*.rb" > /dev/null 2>&1 && language="ruby"
        compgen -G "$dir/*.ts" > /dev/null 2>&1 && language="typescript"
        compgen -G "$dir/*.js" > /dev/null 2>&1 && language="javascript"
    fi

    printf '%s' "$language"
}

# =============================================================================
# FRAMEWORK DETECTION
# =============================================================================

# Detect framework from package.json dependencies
# Usage: _detect_js_framework "/path/to/package.json"
_detect_js_framework() {
    local pkg_json="$1"
    local framework=""

    [[ ! -f "$pkg_json" ]] && return

    local content
    content=$(<"$pkg_json")

    # Frontend frameworks (check in order of specificity)
    if [[ "$content" == *'"next"'* ]]; then
        framework="nextjs"
    elif [[ "$content" == *'"nuxt"'* ]]; then
        framework="nuxt"
    elif [[ "$content" == *'"@angular/core"'* ]]; then
        framework="angular"
    elif [[ "$content" == *'"svelte"'* || "$content" == *'"@sveltejs/kit"'* ]]; then
        framework="svelte"
    elif [[ "$content" == *'"vue"'* ]]; then
        framework="vue"
    elif [[ "$content" == *'"react"'* ]]; then
        framework="react"
    elif [[ "$content" == *'"solid-js"'* ]]; then
        framework="solid"
    elif [[ "$content" == *'"preact"'* ]]; then
        framework="preact"
    elif [[ "$content" == *'"astro"'* ]]; then
        framework="astro"
    elif [[ "$content" == *'"gatsby"'* ]]; then
        framework="gatsby"
    elif [[ "$content" == *'"remix"'* || "$content" == *'"@remix-run"'* ]]; then
        framework="remix"
    fi

    # Backend frameworks (if no frontend detected)
    if [[ -z "$framework" ]]; then
        if [[ "$content" == *'"fastify"'* ]]; then
            framework="fastify"
        elif [[ "$content" == *'"express"'* ]]; then
            framework="express"
        elif [[ "$content" == *'"koa"'* ]]; then
            framework="koa"
        elif [[ "$content" == *'"hono"'* ]]; then
            framework="hono"
        elif [[ "$content" == *'"@nestjs/core"'* ]]; then
            framework="nestjs"
        elif [[ "$content" == *'"elysia"'* ]]; then
            framework="elysia"
        fi
    fi

    printf '%s' "$framework"
}

# Detect Python framework
# Usage: _detect_python_framework "/path/to/project"
_detect_python_framework() {
    local dir="$1"
    local framework=""

    # Check manage.py for Django
    [[ -f "$dir/manage.py" ]] && framework="django"

    # Check for Flask indicators
    if [[ -z "$framework" ]]; then
        if [[ -f "$dir/app.py" ]] && grep -q "flask\|Flask" "$dir/app.py" 2>/dev/null; then
            framework="flask"
        fi
    fi

    # Check for FastAPI
    if [[ -z "$framework" ]]; then
        for f in "$dir"/*.py "$dir"/main.py "$dir"/app.py "$dir"/api.py; do
            [[ -f "$f" ]] && grep -q "fastapi\|FastAPI" "$f" 2>/dev/null && framework="fastapi" && break
        done
    fi

    # Check requirements.txt or pyproject.toml
    if [[ -z "$framework" ]]; then
        local deps_file=""
        [[ -f "$dir/requirements.txt" ]] && deps_file="$dir/requirements.txt"
        [[ -f "$dir/pyproject.toml" ]] && deps_file="$dir/pyproject.toml"

        if [[ -n "$deps_file" ]]; then
            grep -qi "django" "$deps_file" 2>/dev/null && framework="django"
            grep -qi "flask" "$deps_file" 2>/dev/null && [[ -z "$framework" ]] && framework="flask"
            grep -qi "fastapi" "$deps_file" 2>/dev/null && [[ -z "$framework" ]] && framework="fastapi"
            grep -qi "streamlit" "$deps_file" 2>/dev/null && [[ -z "$framework" ]] && framework="streamlit"
            grep -qi "gradio" "$deps_file" 2>/dev/null && [[ -z "$framework" ]] && framework="gradio"
        fi
    fi

    printf '%s' "$framework"
}

# Main framework detection
# Usage: _detect_framework "/path/to/project" "language"
_detect_framework() {
    local dir="$1"
    local language="$2"
    local framework=""

    case "$language" in
        typescript|javascript)
            framework=$(_detect_js_framework "$dir/package.json")
            ;;
        python)
            framework=$(_detect_python_framework "$dir")
            ;;
        ruby)
            [[ -f "$dir/config/application.rb" ]] && framework="rails"
            [[ -f "$dir/config.ru" && -z "$framework" ]] && framework="sinatra"
            ;;
        rust)
            if [[ -f "$dir/Cargo.toml" ]]; then
                grep -q "actix-web" "$dir/Cargo.toml" 2>/dev/null && framework="actix"
                grep -q "axum" "$dir/Cargo.toml" 2>/dev/null && [[ -z "$framework" ]] && framework="axum"
                grep -q "rocket" "$dir/Cargo.toml" 2>/dev/null && [[ -z "$framework" ]] && framework="rocket"
                grep -q "tauri" "$dir/Cargo.toml" 2>/dev/null && [[ -z "$framework" ]] && framework="tauri"
            fi
            ;;
        go)
            if [[ -f "$dir/go.mod" ]]; then
                grep -q "gin-gonic" "$dir/go.mod" 2>/dev/null && framework="gin"
                grep -q "echo" "$dir/go.mod" 2>/dev/null && [[ -z "$framework" ]] && framework="echo"
                grep -q "fiber" "$dir/go.mod" 2>/dev/null && [[ -z "$framework" ]] && framework="fiber"
            fi
            ;;
        php)
            [[ -f "$dir/artisan" ]] && framework="laravel"
            [[ -f "$dir/bin/console" ]] && framework="symfony"
            ;;
        java)
            if [[ -f "$dir/pom.xml" ]]; then
                grep -q "spring-boot" "$dir/pom.xml" 2>/dev/null && framework="spring-boot"
            elif [[ -f "$dir/build.gradle" ]]; then
                grep -q "spring-boot" "$dir/build.gradle" 2>/dev/null && framework="spring-boot"
            fi
            ;;
        elixir)
            [[ -d "$dir/lib" && -f "$dir/mix.exs" ]] && grep -q "phoenix" "$dir/mix.exs" 2>/dev/null && framework="phoenix"
            ;;
        dart)
            [[ -f "$dir/pubspec.yaml" ]] && grep -q "flutter" "$dir/pubspec.yaml" 2>/dev/null && framework="flutter"
            ;;
    esac

    printf '%s' "$framework"
}

# =============================================================================
# PACKAGE MANAGER DETECTION
# =============================================================================

# Detect package manager
# Usage: _detect_package_manager "/path/to/project" "language"
_detect_package_manager() {
    local dir="$1"
    local language="$2"
    local pkg_manager=""

    case "$language" in
        typescript|javascript)
            # Check lockfiles in order of preference
            [[ -f "$dir/bun.lockb" ]] && pkg_manager="bun"
            [[ -z "$pkg_manager" && -f "$dir/pnpm-lock.yaml" ]] && pkg_manager="pnpm"
            [[ -z "$pkg_manager" && -f "$dir/yarn.lock" ]] && pkg_manager="yarn"
            [[ -z "$pkg_manager" && -f "$dir/package-lock.json" ]] && pkg_manager="npm"
            # Fallback if no lockfile
            [[ -z "$pkg_manager" && -f "$dir/package.json" ]] && pkg_manager="npm"
            ;;
        python)
            [[ -f "$dir/poetry.lock" ]] && pkg_manager="poetry"
            [[ -z "$pkg_manager" && -f "$dir/Pipfile.lock" ]] && pkg_manager="pipenv"
            [[ -z "$pkg_manager" && -f "$dir/uv.lock" ]] && pkg_manager="uv"
            [[ -z "$pkg_manager" && -f "$dir/pdm.lock" ]] && pkg_manager="pdm"
            [[ -z "$pkg_manager" && -f "$dir/requirements.txt" ]] && pkg_manager="pip"
            [[ -z "$pkg_manager" && -f "$dir/pyproject.toml" ]] && pkg_manager="pip"
            ;;
        ruby)
            [[ -f "$dir/Gemfile" ]] && pkg_manager="bundler"
            ;;
        rust)
            [[ -f "$dir/Cargo.toml" ]] && pkg_manager="cargo"
            ;;
        go)
            [[ -f "$dir/go.mod" ]] && pkg_manager="go"
            ;;
        php)
            [[ -f "$dir/composer.json" ]] && pkg_manager="composer"
            ;;
        java)
            [[ -f "$dir/pom.xml" ]] && pkg_manager="maven"
            [[ -f "$dir/build.gradle" || -f "$dir/build.gradle.kts" ]] && pkg_manager="gradle"
            ;;
        elixir)
            [[ -f "$dir/mix.exs" ]] && pkg_manager="mix"
            ;;
        dart)
            [[ -f "$dir/pubspec.yaml" ]] && pkg_manager="pub"
            ;;
    esac

    printf '%s' "$pkg_manager"
}

# =============================================================================
# BUILD SYSTEM DETECTION
# =============================================================================

# Detect build system
# Usage: _detect_build_system "/path/to/project" "language"
_detect_build_system() {
    local dir="$1"
    local language="$2"
    local build_system=""

    # Generic build systems
    [[ -f "$dir/Makefile" || -f "$dir/makefile" || -f "$dir/GNUmakefile" ]] && build_system="make"
    [[ -f "$dir/justfile" ]] && build_system="just"
    [[ -f "$dir/Taskfile.yml" || -f "$dir/Taskfile.yaml" ]] && build_system="task"
    [[ -f "$dir/BUILD.bazel" || -f "$dir/WORKSPACE" ]] && build_system="bazel"
    [[ -f "$dir/meson.build" ]] && build_system="meson"
    [[ -f "$dir/CMakeLists.txt" ]] && build_system="cmake"
    [[ -f "$dir/Earthfile" ]] && build_system="earthly"

    # Language-specific build systems
    case "$language" in
        typescript|javascript)
            [[ -f "$dir/turbo.json" ]] && build_system="turbo"
            [[ -z "$build_system" && -f "$dir/nx.json" ]] && build_system="nx"
            [[ -z "$build_system" && -f "$dir/lerna.json" ]] && build_system="lerna"
            # Bundlers
            [[ -z "$build_system" && -f "$dir/vite.config.ts" ]] && build_system="vite"
            [[ -z "$build_system" && -f "$dir/vite.config.js" ]] && build_system="vite"
            [[ -z "$build_system" && -f "$dir/webpack.config.js" ]] && build_system="webpack"
            [[ -z "$build_system" && -f "$dir/rollup.config.js" ]] && build_system="rollup"
            [[ -z "$build_system" && -f "$dir/esbuild.config.js" ]] && build_system="esbuild"
            ;;
        rust)
            build_system="cargo"
            ;;
        go)
            build_system="go"
            [[ -f "$dir/Makefile" ]] && build_system="make"
            ;;
        java)
            [[ -f "$dir/pom.xml" ]] && build_system="maven"
            [[ -f "$dir/build.gradle" || -f "$dir/build.gradle.kts" ]] && build_system="gradle"
            ;;
    esac

    printf '%s' "$build_system"
}

# =============================================================================
# TEST FRAMEWORK DETECTION
# =============================================================================

# Detect test framework
# Usage: _detect_test_framework "/path/to/project" "language"
_detect_test_framework() {
    local dir="$1"
    local language="$2"
    local test_framework=""

    case "$language" in
        typescript|javascript)
            if [[ -f "$dir/package.json" ]]; then
                local pkg
                pkg=$(<"$dir/package.json")
                [[ "$pkg" == *'"vitest"'* ]] && test_framework="vitest"
                [[ -z "$test_framework" && "$pkg" == *'"jest"'* ]] && test_framework="jest"
                [[ -z "$test_framework" && "$pkg" == *'"mocha"'* ]] && test_framework="mocha"
                [[ -z "$test_framework" && "$pkg" == *'"ava"'* ]] && test_framework="ava"
                [[ -z "$test_framework" && "$pkg" == *'"bun:test"'* ]] && test_framework="bun"
                [[ -z "$test_framework" && "$pkg" == *'"@playwright/test"'* ]] && test_framework="playwright"
                [[ -z "$test_framework" && "$pkg" == *'"cypress"'* ]] && test_framework="cypress"
            fi
            # Config file detection
            [[ -z "$test_framework" && -f "$dir/vitest.config.ts" ]] && test_framework="vitest"
            [[ -z "$test_framework" && -f "$dir/jest.config.js" ]] && test_framework="jest"
            [[ -z "$test_framework" && -f "$dir/jest.config.ts" ]] && test_framework="jest"
            [[ -z "$test_framework" && -f "$dir/playwright.config.ts" ]] && test_framework="playwright"
            [[ -z "$test_framework" && -f "$dir/cypress.config.js" ]] && test_framework="cypress"
            ;;
        python)
            [[ -f "$dir/pytest.ini" || -f "$dir/pyproject.toml" ]] && test_framework="pytest"
            [[ -d "$dir/tests" ]] && test_framework="pytest"
            ;;
        rust)
            test_framework="cargo"  # Built-in
            ;;
        go)
            test_framework="go"  # Built-in
            ;;
        ruby)
            [[ -f "$dir/spec/spec_helper.rb" ]] && test_framework="rspec"
            [[ -z "$test_framework" && -d "$dir/test" ]] && test_framework="minitest"
            ;;
        java)
            test_framework="junit"  # Default assumption
            ;;
        elixir)
            test_framework="exunit"  # Built-in
            ;;
    esac

    printf '%s' "$test_framework"
}

# =============================================================================
# ENTRY POINTS DETECTION
# =============================================================================

# Detect entry points
# Usage: _detect_entry_points "/path/to/project" "language" "framework"
_detect_entry_points() {
    local dir="$1"
    local language="$2"
    local framework="$3"
    local -a entry_points=()

    case "$framework" in
        nextjs)
            [[ -f "$dir/src/app/page.tsx" ]] && entry_points+=("src/app/page.tsx")
            [[ -f "$dir/src/app/layout.tsx" ]] && entry_points+=("src/app/layout.tsx")
            [[ -f "$dir/app/page.tsx" ]] && entry_points+=("app/page.tsx")
            [[ -f "$dir/app/layout.tsx" ]] && entry_points+=("app/layout.tsx")
            [[ -f "$dir/pages/index.tsx" ]] && entry_points+=("pages/index.tsx")
            [[ -f "$dir/pages/_app.tsx" ]] && entry_points+=("pages/_app.tsx")
            ;;
        react)
            [[ -f "$dir/src/main.tsx" ]] && entry_points+=("src/main.tsx")
            [[ -f "$dir/src/index.tsx" ]] && entry_points+=("src/index.tsx")
            [[ -f "$dir/src/App.tsx" ]] && entry_points+=("src/App.tsx")
            [[ -f "$dir/src/main.jsx" ]] && entry_points+=("src/main.jsx")
            [[ -f "$dir/src/index.jsx" ]] && entry_points+=("src/index.jsx")
            ;;
        vue|nuxt)
            [[ -f "$dir/src/main.ts" ]] && entry_points+=("src/main.ts")
            [[ -f "$dir/src/App.vue" ]] && entry_points+=("src/App.vue")
            [[ -f "$dir/app.vue" ]] && entry_points+=("app.vue")
            ;;
        svelte)
            [[ -f "$dir/src/routes/+page.svelte" ]] && entry_points+=("src/routes/+page.svelte")
            [[ -f "$dir/src/App.svelte" ]] && entry_points+=("src/App.svelte")
            ;;
        express|fastify|nestjs|hono|elysia)
            [[ -f "$dir/src/index.ts" ]] && entry_points+=("src/index.ts")
            [[ -f "$dir/src/main.ts" ]] && entry_points+=("src/main.ts")
            [[ -f "$dir/src/server.ts" ]] && entry_points+=("src/server.ts")
            [[ -f "$dir/src/app.ts" ]] && entry_points+=("src/app.ts")
            [[ -f "$dir/index.js" ]] && entry_points+=("index.js")
            [[ -f "$dir/server.js" ]] && entry_points+=("server.js")
            ;;
        django)
            [[ -f "$dir/manage.py" ]] && entry_points+=("manage.py")
            # Find wsgi.py
            local wsgi
            wsgi=$(find "$dir" -maxdepth 3 -name "wsgi.py" 2>/dev/null | head -1)
            [[ -n "$wsgi" ]] && entry_points+=("${wsgi#$dir/}")
            ;;
        flask|fastapi)
            [[ -f "$dir/app.py" ]] && entry_points+=("app.py")
            [[ -f "$dir/main.py" ]] && entry_points+=("main.py")
            [[ -f "$dir/api.py" ]] && entry_points+=("api.py")
            [[ -f "$dir/src/main.py" ]] && entry_points+=("src/main.py")
            ;;
        rails)
            [[ -f "$dir/config/application.rb" ]] && entry_points+=("config/application.rb")
            [[ -f "$dir/config.ru" ]] && entry_points+=("config.ru")
            ;;
        *)
            # Generic detection by language
            case "$language" in
                typescript|javascript)
                    [[ -f "$dir/src/index.ts" ]] && entry_points+=("src/index.ts")
                    [[ -f "$dir/src/main.ts" ]] && entry_points+=("src/main.ts")
                    [[ -f "$dir/index.ts" ]] && entry_points+=("index.ts")
                    [[ -f "$dir/index.js" ]] && entry_points+=("index.js")
                    ;;
                python)
                    [[ -f "$dir/main.py" ]] && entry_points+=("main.py")
                    [[ -f "$dir/app.py" ]] && entry_points+=("app.py")
                    [[ -f "$dir/__main__.py" ]] && entry_points+=("__main__.py")
                    [[ -f "$dir/src/main.py" ]] && entry_points+=("src/main.py")
                    ;;
                rust)
                    [[ -f "$dir/src/main.rs" ]] && entry_points+=("src/main.rs")
                    [[ -f "$dir/src/lib.rs" ]] && entry_points+=("src/lib.rs")
                    ;;
                go)
                    [[ -f "$dir/main.go" ]] && entry_points+=("main.go")
                    [[ -f "$dir/cmd/main.go" ]] && entry_points+=("cmd/main.go")
                    ;;
            esac
            ;;
    esac

    # Output as JSON array
    if [[ ${#entry_points[@]} -gt 0 ]]; then
        json_array "${entry_points[@]}"
    else
        printf '[]'
    fi
}

# =============================================================================
# CONFIG FILES DETECTION
# =============================================================================

# Detect configuration files
# Usage: _detect_config_files "/path/to/project"
_detect_config_files() {
    local dir="$1"
    local -a config_files=()

    # Common config files
    local common_configs=(
        "package.json" "tsconfig.json" "jsconfig.json"
        "pyproject.toml" "setup.py" "setup.cfg" "requirements.txt"
        "Cargo.toml" "go.mod" "Gemfile" "composer.json"
        ".env" ".env.example" ".env.local"
        "Makefile" "justfile" "Taskfile.yml"
        ".eslintrc" ".eslintrc.js" ".eslintrc.json" "eslint.config.js"
        ".prettierrc" ".prettierrc.js" "prettier.config.js"
        "vite.config.ts" "vite.config.js"
        "next.config.js" "next.config.mjs" "next.config.ts"
        "tailwind.config.js" "tailwind.config.ts"
        "postcss.config.js"
        "vitest.config.ts" "jest.config.js" "jest.config.ts"
        ".gitignore" ".dockerignore"
        "docker-compose.yml" "docker-compose.yaml"
        "Dockerfile"
        ".github/workflows" ".gitlab-ci.yml" ".travis.yml"
        "turbo.json" "nx.json" "lerna.json"
        "biome.json" "biome.jsonc"
    )

    for config in "${common_configs[@]}"; do
        if [[ -f "$dir/$config" || -d "$dir/$config" ]]; then
            config_files+=("$config")
        fi
    done

    # Output as JSON array
    if [[ ${#config_files[@]} -gt 0 ]]; then
        json_array "${config_files[@]}"
    else
        printf '[]'
    fi
}

# =============================================================================
# CI/CD DETECTION
# =============================================================================

# Detect CI/CD system
# Usage: _detect_ci "/path/to/project"
_detect_ci() {
    local dir="$1"
    local ci=""

    [[ -d "$dir/.github/workflows" ]] && ci="github_actions"
    [[ -z "$ci" && -f "$dir/.gitlab-ci.yml" ]] && ci="gitlab_ci"
    [[ -z "$ci" && -f "$dir/.travis.yml" ]] && ci="travis"
    [[ -z "$ci" && -f "$dir/Jenkinsfile" ]] && ci="jenkins"
    [[ -z "$ci" && -f "$dir/.circleci/config.yml" ]] && ci="circleci"
    [[ -z "$ci" && -f "$dir/bitbucket-pipelines.yml" ]] && ci="bitbucket"
    [[ -z "$ci" && -f "$dir/azure-pipelines.yml" ]] && ci="azure_devops"
    [[ -z "$ci" && -f "$dir/.drone.yml" ]] && ci="drone"
    [[ -z "$ci" && -f "$dir/buildkite.yml" ]] && ci="buildkite"

    printf '%s' "$ci"
}

# =============================================================================
# MONOREPO DETECTION
# =============================================================================

# Detect if project is a monorepo
# Usage: _detect_monorepo "/path/to/project"
_detect_monorepo() {
    local dir="$1"

    # Check for monorepo indicators
    [[ -f "$dir/pnpm-workspace.yaml" ]] && printf 'true' && return
    [[ -f "$dir/lerna.json" ]] && printf 'true' && return
    [[ -f "$dir/nx.json" ]] && printf 'true' && return
    [[ -f "$dir/turbo.json" ]] && printf 'true' && return
    [[ -d "$dir/packages" ]] && printf 'true' && return
    [[ -d "$dir/apps" ]] && printf 'true' && return

    # Check package.json for workspaces
    if [[ -f "$dir/package.json" ]]; then
        grep -q '"workspaces"' "$dir/package.json" 2>/dev/null && printf 'true' && return
    fi

    printf 'false'
}

# =============================================================================
# README DETECTION
# =============================================================================

# Detect README file
# Usage: _detect_readme "/path/to/project"
_detect_readme() {
    local dir="$1"
    local readme=""

    local readme_variants=(
        "README.md" "Readme.md" "readme.md"
        "README.rst" "README.txt" "README"
        "README.markdown"
    )

    for variant in "${readme_variants[@]}"; do
        if [[ -f "$dir/$variant" ]]; then
            readme="$variant"
            break
        fi
    done

    printf '%s' "$readme"
}

# =============================================================================
# DOCKER DETECTION
# =============================================================================

# Detect Docker presence
# Usage: _detect_docker "/path/to/project"
_detect_docker() {
    local dir="$1"

    [[ -f "$dir/Dockerfile" ]] && printf 'true' && return
    [[ -f "$dir/docker-compose.yml" ]] && printf 'true' && return
    [[ -f "$dir/docker-compose.yaml" ]] && printf 'true' && return
    [[ -f "$dir/compose.yml" ]] && printf 'true' && return
    [[ -f "$dir/compose.yaml" ]] && printf 'true' && return
    [[ -f "$dir/.dockerignore" ]] && printf 'true' && return
    [[ -d "$dir/docker" ]] && printf 'true' && return

    printf 'false'
}

# =============================================================================
# LINTING/FORMATTING DETECTION
# =============================================================================

# Detect linter
# Usage: _detect_linter "/path/to/project" "language"
_detect_linter() {
    local dir="$1"
    local language="$2"
    local linter=""

    case "$language" in
        typescript|javascript)
            [[ -f "$dir/biome.json" || -f "$dir/biome.jsonc" ]] && linter="biome"
            [[ -z "$linter" && -f "$dir/eslint.config.js" ]] && linter="eslint"
            [[ -z "$linter" && -f "$dir/.eslintrc" ]] && linter="eslint"
            [[ -z "$linter" && -f "$dir/.eslintrc.js" ]] && linter="eslint"
            [[ -z "$linter" && -f "$dir/.eslintrc.json" ]] && linter="eslint"
            ;;
        python)
            [[ -f "$dir/ruff.toml" || -f "$dir/.ruff.toml" ]] && linter="ruff"
            [[ -z "$linter" && -f "$dir/.flake8" ]] && linter="flake8"
            [[ -z "$linter" && -f "$dir/pylintrc" ]] && linter="pylint"
            # Check pyproject.toml for tool config
            if [[ -z "$linter" && -f "$dir/pyproject.toml" ]]; then
                grep -q '\[tool.ruff\]' "$dir/pyproject.toml" 2>/dev/null && linter="ruff"
                grep -q '\[tool.flake8\]' "$dir/pyproject.toml" 2>/dev/null && [[ -z "$linter" ]] && linter="flake8"
            fi
            ;;
        rust)
            linter="clippy"  # Built-in
            ;;
        go)
            linter="golangci-lint"
            [[ -f "$dir/.golangci.yml" ]] || linter=""
            ;;
    esac

    printf '%s' "$linter"
}

# Detect formatter
# Usage: _detect_formatter "/path/to/project" "language"
_detect_formatter() {
    local dir="$1"
    local language="$2"
    local formatter=""

    case "$language" in
        typescript|javascript)
            [[ -f "$dir/biome.json" || -f "$dir/biome.jsonc" ]] && formatter="biome"
            [[ -z "$formatter" && -f "$dir/.prettierrc" ]] && formatter="prettier"
            [[ -z "$formatter" && -f "$dir/.prettierrc.js" ]] && formatter="prettier"
            [[ -z "$formatter" && -f "$dir/prettier.config.js" ]] && formatter="prettier"
            ;;
        python)
            [[ -f "$dir/ruff.toml" || -f "$dir/.ruff.toml" ]] && formatter="ruff"
            if [[ -z "$formatter" && -f "$dir/pyproject.toml" ]]; then
                grep -q '\[tool.ruff\]' "$dir/pyproject.toml" 2>/dev/null && formatter="ruff"
                grep -q '\[tool.black\]' "$dir/pyproject.toml" 2>/dev/null && [[ -z "$formatter" ]] && formatter="black"
            fi
            ;;
        rust)
            formatter="rustfmt"  # Built-in
            ;;
        go)
            formatter="gofmt"  # Built-in
            ;;
    esac

    printf '%s' "$formatter"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

# Main project detection function
# Usage: project_detect [directory]
project_detect() {
    local dir="${1:-.}"

    # Normalize directory path
    dir=$(cd "$dir" 2>/dev/null && pwd) || {
        log_error "Cannot access directory: $1"
        return 1
    }

    # Detect all properties
    local language framework pkg_manager build_system test_framework
    local has_docker has_ci monorepo readme linter formatter
    local entry_points config_files

    language=$(_detect_language "$dir")
    framework=$(_detect_framework "$dir" "$language")
    pkg_manager=$(_detect_package_manager "$dir" "$language")
    build_system=$(_detect_build_system "$dir" "$language")
    test_framework=$(_detect_test_framework "$dir" "$language")
    has_docker=$(_detect_docker "$dir")
    has_ci=$(_detect_ci "$dir")
    monorepo=$(_detect_monorepo "$dir")
    readme=$(_detect_readme "$dir")
    linter=$(_detect_linter "$dir" "$language")
    formatter=$(_detect_formatter "$dir" "$language")
    entry_points=$(_detect_entry_points "$dir" "$language" "$framework")
    config_files=$(_detect_config_files "$dir")

    # Build JSON output
    local json_parts=()

    # Required fields (always present)
    json_parts+=("\"language\":$(json_value "$language" string)")
    json_parts+=("\"framework\":$(json_value "$framework" string)")
    json_parts+=("\"package_manager\":$(json_value "$pkg_manager" string)")
    json_parts+=("\"build_system\":$(json_value "$build_system" string)")
    json_parts+=("\"entry_points\":$entry_points")
    json_parts+=("\"config_files\":$config_files")
    json_parts+=("\"test_framework\":$(json_value "$test_framework" string)")
    json_parts+=("\"linter\":$(json_value "$linter" string)")
    json_parts+=("\"formatter\":$(json_value "$formatter" string)")
    json_parts+=("\"has_docker\":$has_docker")

    # CI field - only add if detected
    if [[ -n "$has_ci" ]]; then
        json_parts+=("\"has_ci\":$(json_value "$has_ci" string)")
    else
        json_parts+=("\"has_ci\":false")
    fi

    json_parts+=("\"monorepo\":$monorepo")

    # README field - only add if exists
    if [[ -n "$readme" ]]; then
        json_parts+=("\"readme\":$(json_value "$readme" string)")
    else
        json_parts+=("\"readme\":null")
    fi

    # Output JSON
    local IFS=','
    printf '{%s}\n' "${json_parts[*]}"
}

# =============================================================================
# USAGE HELP
# =============================================================================

_show_help() {
    cat <<'EOF'
Usage: project_detect [OPTIONS] [DIRECTORY]

Analyzes a directory to detect project type, framework, language, and key files.

Arguments:
  DIRECTORY     Directory to analyze (default: current directory)

Options:
  -h, --help    Show this help message
  -p, --pretty  Pretty-print JSON output

Output Fields:
  language        Primary programming language (typescript, python, rust, etc.)
  framework       Framework detected (nextjs, fastapi, express, etc.)
  package_manager Package manager (bun, npm, poetry, cargo, etc.)
  build_system    Build system (turbo, vite, cargo, make, etc.)
  entry_points    Array of main entry point files
  config_files    Array of configuration files found
  test_framework  Testing framework (vitest, jest, pytest, etc.)
  linter          Linting tool (eslint, ruff, clippy, etc.)
  formatter       Formatting tool (prettier, black, rustfmt, etc.)
  has_docker      Boolean indicating Docker presence
  has_ci          CI/CD system (github_actions, gitlab_ci, etc.) or false
  monorepo        Boolean indicating monorepo structure
  readme          README filename or null

Examples:
  project_detect                    # Analyze current directory
  project_detect /path/to/project   # Analyze specific directory
  project_detect -p .               # Pretty-print output

EOF
}

# =============================================================================
# CLI ENTRY POINT
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # Parse arguments
    pretty=false
    dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                _show_help
                exit 0
                ;;
            -p|--pretty)
                pretty=true
                shift
                ;;
            *)
                dir="$1"
                shift
                ;;
        esac
    done

    # Run detection
    output=$(project_detect "${dir:-.}")

    # Output result
    if $pretty; then
        json_pretty "$output"
    else
        printf '%s\n' "$output"
    fi
fi
