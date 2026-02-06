#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/tirith_ecosystem.sh - Supply Chain Security
# =============================================================================
# Description: Detects supply chain risks in package management, container
#              registries, Git repositories, and Web3 endpoints.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_TIRITH_ECOSYSTEM_LOADED:-}" ]] && return 0
readonly _MAINFRAME_TIRITH_ECOSYSTEM_LOADED=1

# =============================================================================
# SHARED STATE INITIALIZATION
# =============================================================================

# Initialize shared tirith state if the function exists (defined in tirith_inject.sh)
if declare -f _tirith_init_state &>/dev/null; then
    _tirith_init_state
fi

# =============================================================================
# CONSTANTS
# =============================================================================

# Trusted container registries
readonly -a _TIRITH_TRUSTED_REGISTRIES=(
    "docker.io" "index.docker.io" "registry.hub.docker.com"
    "ghcr.io" "gcr.io" "us-docker.pkg.dev" "europe-docker.pkg.dev"
    "quay.io" "registry.access.redhat.com" "registry.redhat.io"
    "mcr.microsoft.com" "public.ecr.aws"
    "registry.gitlab.com" "docker.elastic.co" "registry.k8s.io"
)

# PyPI domains
readonly -a _TIRITH_PYPI_DOMAINS=(
    "pypi.org" "files.pythonhosted.org" "pypi.python.org"
)

# npm registries
readonly -a _TIRITH_NPM_REGISTRIES=(
    "registry.npmjs.org" "registry.yarnpkg.com" "npm.pkg.github.com"
)

# Popular GitHub repos for typosquat detection
readonly -a _TIRITH_POPULAR_REPOS=(
    "torvalds/linux" "microsoft/vscode" "facebook/react"
    "tensorflow/tensorflow" "golang/go" "rust-lang/rust"
    "nodejs/node" "python/cpython" "apple/swift"
    "kubernetes/kubernetes" "docker/docker-ce" "ansible/ansible"
    "hashicorp/terraform" "grafana/grafana" "prometheus/prometheus"
)

# Web3 RPC providers
readonly -a _TIRITH_WEB3_PROVIDERS=(
    "infura.io" "alchemy.com" "moralis.io" "quicknode.com"
    "chainstack.com" "getblock.io" "ankr.com"
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# _tirith_extract_docker_registry IMAGE
# Extract registry hostname from a Docker image reference.
# Returns empty string for Docker Hub images (no registry prefix).
_tirith_extract_docker_registry() {
    local image="$1"
    # Remove tag/digest
    image="${image%%:*}"
    image="${image%%@*}"
    # Check if first component looks like a registry (has a dot)
    local first="${image%%/*}"
    if [[ "$first" == *"."* ]] || [[ "$first" == *":"* ]]; then
        printf '%s' "$first"
    fi
    # No registry prefix = Docker Hub
}

# _tirith_extract_host_from_url URL
# Extract the hostname from a URL. Uses parse_url if available,
# otherwise falls back to inline extraction.
_tirith_extract_host_from_url() {
    local url="$1"

    # Try parse_url from parsers.sh if loaded
    if declare -f parse_url &>/dev/null; then
        local parsed
        parsed=$(parse_url "$url")
        # Extract host field from JSON (simple bash extraction)
        if [[ "$parsed" == *'"host":"'* ]]; then
            local host="${parsed#*\"host\":\"}"
            host="${host%%\"*}"
            printf '%s' "$host"
            return 0
        fi
    fi

    # Inline fallback: strip scheme, userinfo, port, path
    local stripped="$url"
    stripped="${stripped#*://}"
    stripped="${stripped%%/*}"
    stripped="${stripped%%\?*}"
    stripped="${stripped%%#*}"
    stripped="${stripped#*@}"
    stripped="${stripped%%:*}"
    printf '%s' "$stripped"
}

# _tirith_array_contains VALUE ARRAY_ELEMENTS...
# Check if a value exists in the given array elements.
# Returns 0 if found, 1 if not.
_tirith_array_contains() {
    local needle="$1"
    shift
    local element
    for element in "$@"; do
        [[ "$element" == "$needle" ]] && return 0
    done
    return 1
}

# =============================================================================
# RULE 1: DOCKER UNTRUSTED REGISTRY
# =============================================================================

# tirith_check_docker_registry CMD [SOURCE]
# Detect docker pull, docker run, or FROM in Dockerfiles using untrusted
# container registries. Docker Hub images without a registry prefix
# (e.g. nginx:latest) are considered safe.
# Severity: medium | Rule: DockerUntrustedRegistry
# Returns: 0 if finding detected, 1 if clean
tirith_check_docker_registry() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    local image=""

    # Match: docker pull IMAGE
    if [[ "$cmd" =~ docker[[:space:]]+pull[[:space:]]+([^[:space:]]+) ]]; then
        image="${BASH_REMATCH[1]}"
    # Match: docker run [OPTIONS] IMAGE (skip flags starting with -)
    elif [[ "$cmd" =~ docker[[:space:]]+run[[:space:]] ]]; then
        # Extract the image: skip all --flag and --flag=value tokens
        local -a tokens
        read -ra tokens <<< "$cmd"
        local skip_next=false
        local past_run=false
        for token in "${tokens[@]}"; do
            if [[ "$past_run" == false ]]; then
                [[ "$token" == "run" ]] && past_run=true
                continue
            fi
            if [[ "$skip_next" == true ]]; then
                skip_next=false
                continue
            fi
            # Skip flags
            if [[ "$token" == --*=* ]]; then
                continue
            elif [[ "$token" == --* ]]; then
                # Some flags take a value as the next token
                case "$token" in
                    --name|--network|--volume|-v|--env|-e|--publish|-p|--workdir|-w|--user|-u|--entrypoint|--hostname|-h|--mount|--label|-l|--cpus|--memory|-m|--platform|--pull|--restart|--runtime|--shm-size|--stop-signal|--stop-timeout|--tmpfs|--ulimit|--device|--add-host|--blkio-weight|--cap-add|--cap-drop|--cgroup-parent|--cidfile|--cpu-period|--cpu-quota|--cpu-rt-period|--cpu-rt-runtime|--cpu-shares|--cpuset-cpus|--cpuset-mems|--detach-keys|--dns|--dns-option|--dns-search|--domainname|--expose|--gpus|--group-add|--health-cmd|--health-interval|--health-retries|--health-start-period|--health-timeout|--init|--ip|--ip6|--ipc|--isolation|--kernel-memory|--link|--link-local-ip|--log-driver|--log-opt|--mac-address|--memory-reservation|--memory-swap|--memory-swappiness|--oom-kill-disable|--oom-score-adj|--pid|--pids-limit|--security-opt|--storage-opt|--sysctl|--userns|--uts|--volume-driver|--volumes-from)
                        skip_next=true
                        ;;
                esac
                continue
            elif [[ "$token" == -* ]]; then
                # Short flags like -d, -i, -t or combined -dit
                # Check if next needs a value (single char flags with args)
                case "$token" in
                    -v|-e|-p|-w|-u|-h|-m|-l)
                        skip_next=true
                        ;;
                esac
                continue
            fi
            # First non-flag token after 'run' is the image
            image="$token"
            break
        done
    # Match: FROM IMAGE in Dockerfile
    elif [[ "$cmd" =~ ^[[:space:]]*FROM[[:space:]]+([^[:space:]]+) ]]; then
        image="${BASH_REMATCH[1]}"
        # Skip FROM scratch (special Docker keyword)
        [[ "$image" == "scratch" ]] && return 1
    fi

    [[ -z "$image" ]] && return 1

    # Extract registry from image reference
    local registry
    registry=$(_tirith_extract_docker_registry "$image")

    # No registry prefix means Docker Hub - that is trusted
    [[ -z "$registry" ]] && return 1

    # Check against trusted registries
    if ! _tirith_array_contains "$registry" "${_TIRITH_TRUSTED_REGISTRIES[@]}"; then
        _tirith_add_finding "$source" "medium" "DockerUntrustedRegistry" \
            "Untrusted container registry '${registry}' in image '${image}'"
        return 0
    fi

    return 1
}

# =============================================================================
# RULE 2: PIP URL INSTALL
# =============================================================================

# tirith_check_pip_url_install CMD [SOURCE]
# Detect pip install from URLs rather than PyPI. Flags direct URL installs
# (https://, http://, git+https://) and --index-url pointing to non-PyPI
# domains. Normal PyPI installs (pip install package-name) are not flagged.
# Severity: medium | Rule: PipUrlInstall
# Returns: 0 if finding detected, 1 if clean
tirith_check_pip_url_install() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    # Must contain pip install
    if [[ ! "$cmd" =~ pip[3]?[[:space:]]+install ]]; then
        return 1
    fi

    # Check for direct URL install: pip install https://... or git+https://...
    if [[ "$cmd" =~ pip[3]?[[:space:]]+install[[:space:]]+(.*) ]]; then
        local args="${BASH_REMATCH[1]}"

        # Check for git+ URL installs first (git+https:// contains https://)
        if [[ "$args" =~ (git\+https?://[^[:space:]]+) ]]; then
            local url="${BASH_REMATCH[1]}"
            _tirith_add_finding "$source" "medium" "PipUrlInstall" \
                "pip install from git URL '${url}' bypasses PyPI"
            return 0
        fi

        # Check for direct URL-based installs
        if [[ "$args" =~ (https?://[^[:space:]]+) ]]; then
            local url="${BASH_REMATCH[1]}"
            _tirith_add_finding "$source" "medium" "PipUrlInstall" \
                "pip install from URL '${url}' bypasses PyPI"
            return 0
        fi

        # Check for --index-url pointing to non-PyPI domain
        if [[ "$args" =~ --index-url[[:space:]]+([^[:space:]]+) ]] || \
           [[ "$args" =~ --extra-index-url[[:space:]]+([^[:space:]]+) ]] || \
           [[ "$args" =~ -i[[:space:]]+([^[:space:]]+) ]]; then
            local index_url="${BASH_REMATCH[1]}"
            local index_host
            index_host=$(_tirith_extract_host_from_url "$index_url")

            if ! _tirith_array_contains "$index_host" "${_TIRITH_PYPI_DOMAINS[@]}"; then
                _tirith_add_finding "$source" "medium" "PipUrlInstall" \
                    "pip --index-url points to non-PyPI domain '${index_host}'"
                return 0
            fi
        fi
    fi

    return 1
}

# =============================================================================
# RULE 3: NPM URL INSTALL
# =============================================================================

# tirith_check_npm_url_install CMD [SOURCE]
# Detect npm install from URLs or git repos. Flags direct URL installs
# (https://..., git+..., github:user/repo) and npm config set registry
# pointing to non-standard registries. Normal npm installs are not flagged.
# Severity: medium | Rule: NpmUrlInstall
# Returns: 0 if finding detected, 1 if clean
tirith_check_npm_url_install() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    # Check for npm config set registry to non-standard registries
    if [[ "$cmd" =~ npm[[:space:]]+config[[:space:]]+set[[:space:]]+registry[[:space:]]+([^[:space:]]+) ]]; then
        local registry_url="${BASH_REMATCH[1]}"
        local registry_host
        registry_host=$(_tirith_extract_host_from_url "$registry_url")

        if ! _tirith_array_contains "$registry_host" "${_TIRITH_NPM_REGISTRIES[@]}"; then
            _tirith_add_finding "$source" "medium" "NpmUrlInstall" \
                "npm registry set to non-standard host '${registry_host}'"
            return 0
        fi
    fi

    # Must contain npm install (or npm i)
    if [[ ! "$cmd" =~ npm[[:space:]]+(install|i|add)[[:space:]] ]]; then
        return 1
    fi

    # Extract what comes after npm install
    if [[ "$cmd" =~ npm[[:space:]]+(install|i|add)[[:space:]]+(.*) ]]; then
        local args="${BASH_REMATCH[2]}"

        # Check for git+ protocol first (git+https:// contains https://)
        if [[ "$args" =~ (git\+[^[:space:]]+) ]]; then
            local url="${BASH_REMATCH[1]}"
            _tirith_add_finding "$source" "medium" "NpmUrlInstall" \
                "npm install from git URL '${url}' bypasses registry"
            return 0
        fi

        # Check for direct URL-based installs
        if [[ "$args" =~ (https?://[^[:space:]]+) ]]; then
            local url="${BASH_REMATCH[1]}"
            _tirith_add_finding "$source" "medium" "NpmUrlInstall" \
                "npm install from URL '${url}' bypasses registry"
            return 0
        fi

        # Check for github:user/repo shorthand
        if [[ "$args" =~ github:([^[:space:]]+) ]]; then
            local repo="${BASH_REMATCH[1]}"
            _tirith_add_finding "$source" "medium" "NpmUrlInstall" \
                "npm install from GitHub shorthand 'github:${repo}' bypasses registry"
            return 0
        fi
    fi

    return 1
}

# =============================================================================
# RULE 4: WEB3 RPC ENDPOINT
# =============================================================================

# tirith_check_web3_rpc CMD [SOURCE]
# Detect hardcoded Web3 RPC endpoints in commands. Looks for URLs containing
# known web3 provider domains and common RPC path patterns with hex API keys.
# Severity: low | Rule: Web3RpcEndpoint
# Returns: 0 if finding detected, 1 if clean
tirith_check_web3_rpc() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    # Check for known web3 provider domains in URLs
    local provider
    for provider in "${_TIRITH_WEB3_PROVIDERS[@]}"; do
        if [[ "$cmd" == *"$provider"* ]]; then
            _tirith_add_finding "$source" "low" "Web3RpcEndpoint" \
                "Web3 RPC provider '${provider}' detected in command"
            return 0
        fi
    done

    # Check for common RPC path patterns with hex API keys
    # Matches: /v1/abc123def, /v2/0xabc, /v3/deadbeef etc.
    if [[ "$cmd" =~ https?://[^[:space:]]+/v[1-3]/[0-9a-fA-F]{8,} ]]; then
        _tirith_add_finding "$source" "low" "Web3RpcEndpoint" \
            "Possible Web3 RPC endpoint with API key detected"
        return 0
    fi

    return 1
}

# =============================================================================
# RULE 5: WEB3 ADDRESS IN URL
# =============================================================================

# tirith_check_web3_address CMD [SOURCE]
# Detect Ethereum-style addresses (0x followed by 40 hex chars) in commands.
# This is informational -- flags hardcoded blockchain addresses.
# Severity: low | Rule: Web3AddressInUrl
# Returns: 0 if finding detected, 1 if clean
tirith_check_web3_address() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    # Match 0x followed by exactly 40 hex characters
    if [[ "$cmd" =~ 0x[0-9a-fA-F]{40} ]]; then
        local address="${BASH_REMATCH[0]}"
        _tirith_add_finding "$source" "low" "Web3AddressInUrl" \
            "Ethereum-style address '${address}' detected in command"
        return 0
    fi

    return 1
}

# =============================================================================
# RULE 6: GIT TYPOSQUAT
# =============================================================================

# tirith_check_git_typosquat CMD [SOURCE]
# Detect git clone with potentially typosquatted repository names. Extracts
# org/repo from the clone URL and compares against popular repos using
# levenshtein_distance from fuzzy.sh. Flags repos with edit distance 1-2
# from a popular repo (close but not exact match).
# Severity: medium | Rule: GitTyposquat
# Returns: 0 if finding detected, 1 if clean
tirith_check_git_typosquat() {
    local cmd="$1"
    local source="${2:-command}"

    [[ -z "$cmd" ]] && return 1

    # levenshtein_distance must be available (from fuzzy.sh)
    if ! declare -f levenshtein_distance &>/dev/null; then
        return 1
    fi

    # Must contain git clone
    if [[ ! "$cmd" =~ git[[:space:]]+clone[[:space:]] ]]; then
        return 1
    fi

    # Extract the URL from git clone
    local clone_url=""
    if [[ "$cmd" =~ git[[:space:]]+clone[[:space:]]+(--[^[:space:]]+[[:space:]]+)*([^[:space:]]+) ]]; then
        clone_url="${BASH_REMATCH[2]}"
    fi

    [[ -z "$clone_url" ]] && return 1

    # Extract org/repo from the URL
    # Handles: https://github.com/org/repo.git, git@github.com:org/repo.git
    local org_repo=""

    # HTTPS style: https://github.com/org/repo[.git]
    if [[ "$clone_url" =~ github\.com/([^/]+/[^/[:space:]]+) ]]; then
        org_repo="${BASH_REMATCH[1]}"
    # SSH style: git@github.com:org/repo[.git]
    elif [[ "$clone_url" =~ github\.com:([^/]+/[^/[:space:]]+) ]]; then
        org_repo="${BASH_REMATCH[1]}"
    else
        # Not a GitHub URL, skip
        return 1
    fi

    # Remove .git suffix
    org_repo="${org_repo%.git}"

    # Convert to lowercase for comparison
    local org_repo_lower="${org_repo,,}"

    # Compare against popular repos
    local popular dist
    for popular in "${_TIRITH_POPULAR_REPOS[@]}"; do
        local popular_lower="${popular,,}"

        # Skip exact matches
        [[ "$org_repo_lower" == "$popular_lower" ]] && continue

        dist=$(levenshtein_distance "$org_repo_lower" "$popular_lower")

        if (( dist >= 1 && dist <= 2 )); then
            _tirith_add_finding "$source" "medium" "GitTyposquat" \
                "Repository '${org_repo}' is suspiciously similar to '${popular}' (edit distance: ${dist})"
            return 0
        fi
    done

    return 1
}

# =============================================================================
# COMPOSITE SCANNER
# =============================================================================

# tirith_scan_ecosystem CMD [SOURCE]
# Run all 6 ecosystem security checks on the input command.
# Returns: 0 if any findings detected, 1 if clean
tirith_scan_ecosystem() {
    local cmd="$1"
    local source="${2:-command}"
    local found=1

    tirith_check_docker_registry "$cmd" "$source"   && found=0
    tirith_check_pip_url_install "$cmd" "$source"    && found=0
    tirith_check_npm_url_install "$cmd" "$source"    && found=0
    tirith_check_web3_rpc "$cmd" "$source"           && found=0
    tirith_check_web3_address "$cmd" "$source"       && found=0
    tirith_check_git_typosquat "$cmd" "$source"      && found=0

    return "$found"
}
