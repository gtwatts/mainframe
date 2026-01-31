#!/usr/bin/env bash
# =============================================================================
# MAINFRAME Installation Script
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
#                                        - GI Joe Filecard, 1986
# =============================================================================
# Usage: curl -fsSL https://raw.githubusercontent.com/mainframe-cli/mainframe/main/install.sh | bash
# Or:    ./install.sh [options]
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

MAINFRAME_REPO="${MAINFRAME_REPO:-https://github.com/mainframe-cli/mainframe.git}"
MAINFRAME_BRANCH="${MAINFRAME_BRANCH:-main}"
MAINFRAME_INSTALL_DIR="${MAINFRAME_INSTALL_DIR:-$HOME/.mainframe}"
MAINFRAME_BIN_DIR="${MAINFRAME_BIN_DIR:-$HOME/.local/bin}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

info() {
    printf "${BLUE}[INTEL]${NC} %s\n" "$*"
}

success() {
    printf "${GREEN}[MISSION COMPLETE]${NC} %s\n" "$*"
}

warn() {
    printf "${YELLOW}[CAUTION]${NC} %s\n" "$*" >&2
}

error() {
    printf "${RED}[ABORT]${NC} %s\n" "$*" >&2
}

die() {
    error "$*"
    exit 1
}

command_exists() {
    command -v "$1" &>/dev/null
}

# =============================================================================
# DEPENDENCY CHECKS
# =============================================================================

check_dependencies() {
    info "Scanning for required components..."

    local missing=()

    # Required
    command_exists bash || missing+=("bash 4.4+")
    command_exists git || missing+=("git")
    command_exists curl || missing+=("curl")

    # Recommended (with warnings)
    command_exists jq || warn "jq not found - some operations will have reduced capability"
    command_exists rg || warn "ripgrep not found - falling back to standard grep"

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
        printf "\n"
        printf "Install them with:\n"
        printf "  Ubuntu/Debian: sudo apt install ${missing[*]}\n"
        printf "  macOS:         brew install ${missing[*]}\n"
        printf "  Fedora:        sudo dnf install ${missing[*]}\n"
        exit 1
    fi

    # Check Bash version
    local bash_version="${BASH_VERSION%%(*}"
    local bash_major="${bash_version%%.*}"
    local bash_minor="${bash_version#*.}"
    bash_minor="${bash_minor%%.*}"

    if [[ "$bash_major" -lt 4 ]] || [[ "$bash_major" -eq 4 && "$bash_minor" -lt 4 ]]; then
        die "Bash 4.4+ required (found: $BASH_VERSION)"
    fi

    success "All systems go"
}

# =============================================================================
# INSTALLATION
# =============================================================================

install_mainframe() {
    info "Deploying MAINFRAME to $MAINFRAME_INSTALL_DIR..."

    # Remove existing installation
    if [[ -d "$MAINFRAME_INSTALL_DIR" ]]; then
        warn "Existing installation found at $MAINFRAME_INSTALL_DIR"
        if [[ "${MAINFRAME_FORCE:-}" == "1" ]]; then
            rm -rf "$MAINFRAME_INSTALL_DIR"
        else
            printf "Remove existing installation? [y/N] "
            read -r response
            if [[ "$response" =~ ^[Yy] ]]; then
                rm -rf "$MAINFRAME_INSTALL_DIR"
            else
                die "Installation cancelled"
            fi
        fi
    fi

    # Clone repository
    git clone --depth 1 --branch "$MAINFRAME_BRANCH" "$MAINFRAME_REPO" "$MAINFRAME_INSTALL_DIR" || die "Failed to clone repository"

    success "Repository deployed"

    # Create bin directory
    mkdir -p "$MAINFRAME_BIN_DIR"

    # Create symlink to main entry point
    ln -sf "$MAINFRAME_INSTALL_DIR/mainframe" "$MAINFRAME_BIN_DIR/mainframe"

    # Make scripts executable
    find "$MAINFRAME_INSTALL_DIR/scripts" -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
    chmod +x "$MAINFRAME_INSTALL_DIR/mainframe"
    chmod +x "$MAINFRAME_INSTALL_DIR/hooks/dispatcher.sh" 2>/dev/null || true

    success "Operations installed"
}

# =============================================================================
# SHELL CONFIGURATION
# =============================================================================

setup_shell() {
    info "Configuring shell integration..."

    local shell_config=""
    local shell_name=""

    # Detect shell
    case "${SHELL:-/bin/bash}" in
        */bash)
            shell_name="bash"
            if [[ -f "$HOME/.bashrc" ]]; then
                shell_config="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                shell_config="$HOME/.bash_profile"
            fi
            ;;
        */zsh)
            shell_name="zsh"
            shell_config="$HOME/.zshrc"
            ;;
        */fish)
            shell_name="fish"
            shell_config="$HOME/.config/fish/config.fish"
            ;;
        *)
            warn "Unknown shell, skipping shell configuration"
            return 0
            ;;
    esac

    if [[ -z "$shell_config" ]]; then
        warn "Could not find shell configuration file"
        return 0
    fi

    # Check if already configured
    if grep -q "MAINFRAME_ROOT" "$shell_config" 2>/dev/null; then
        info "Shell already configured"
        return 0
    fi

    # Add configuration
    local config_block
    if [[ "$shell_name" == "fish" ]]; then
        config_block="
# MAINFRAME CLI Toolkit - \"Knowing your shell is half the battle.\"
set -gx MAINFRAME_ROOT \"$MAINFRAME_INSTALL_DIR\"
set -gx PATH \"\$MAINFRAME_BIN_DIR\" \$PATH
"
    else
        config_block="
# MAINFRAME CLI Toolkit - \"Knowing your shell is half the battle.\"
export MAINFRAME_ROOT=\"$MAINFRAME_INSTALL_DIR\"
export PATH=\"$MAINFRAME_BIN_DIR:\$PATH\"

# MAINFRAME completions
[[ -f \"\$MAINFRAME_ROOT/completions/mainframe.$shell_name\" ]] && source \"\$MAINFRAME_ROOT/completions/mainframe.$shell_name\"
"
    fi

    printf "\n%s\n" "$config_block" >> "$shell_config"
    success "Shell configuration added to $shell_config"
}

# =============================================================================
# CLAUDE CODE INTEGRATION
# =============================================================================

setup_claude_code() {
    info "Setting up Claude Code integration..."

    local claude_settings="$HOME/.config/claude/settings.json"

    if [[ ! -f "$claude_settings" ]]; then
        info "Claude Code settings not found, skipping integration"
        return 0
    fi

    # Check if jq is available
    if ! command_exists jq; then
        warn "jq not found, skipping Claude Code integration"
        return 0
    fi

    # Backup existing settings
    cp "$claude_settings" "${claude_settings}.bak"

    # Add hook configuration
    local tmp_file
    tmp_file=$(mktemp)

    jq --arg hook "$MAINFRAME_INSTALL_DIR/hooks/dispatcher.sh" \
       '.hooks.preCommand = ($hook + " pre-command") |
        .hooks.postCommand = ($hook + " post-command") |
        .hooks.contextProvider = ($hook + " context")' \
       "$claude_settings" > "$tmp_file"

    if [[ -s "$tmp_file" ]]; then
        mv "$tmp_file" "$claude_settings"
        success "Claude Code integration configured"
    else
        rm -f "$tmp_file"
        warn "Failed to update Claude Code settings"
    fi
}

# =============================================================================
# POST-INSTALL
# =============================================================================

post_install() {
    # Create default config if it doesn't exist
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mainframe"
    mkdir -p "$config_dir"

    if [[ ! -f "$config_dir/mainframe.conf" ]] && [[ -f "$MAINFRAME_INSTALL_DIR/config/mainframe.conf.example" ]]; then
        cp "$MAINFRAME_INSTALL_DIR/config/mainframe.conf.example" "$config_dir/mainframe.conf"
        success "Configuration created at $config_dir/mainframe.conf"
    fi
}

# =============================================================================
# AI DISCOVERY SETUP
# =============================================================================

setup_ai_discovery() {
    info "Configuring AI tool discovery..."

    # Source the AI discovery library
    if [[ -f "$MAINFRAME_INSTALL_DIR/lib/ai_discovery.sh" ]]; then
        export MAINFRAME_ROOT="$MAINFRAME_INSTALL_DIR"
        source "$MAINFRAME_INSTALL_DIR/lib/ai_discovery.sh"

        # Run the full discovery setup
        mainframe_ai_discovery_setup_universal
        mainframe_ai_discovery_setup_claude
        mainframe_ai_discovery_setup_cursor
        mainframe_ai_discovery_setup_aider

        success "AI coding tools will now auto-detect MAINFRAME capabilities"
    else
        warn "AI discovery library not found, skipping"
    fi
}

# =============================================================================
# VERIFY INSTALLATION
# =============================================================================

verify_installation() {
    info "Verifying deployment..."

    # Check main entry point
    if [[ ! -x "$MAINFRAME_INSTALL_DIR/mainframe" ]]; then
        die "Main entry point not executable"
    fi

    # Check libraries
    for lib in common.sh config.sh args.sh; do
        if [[ ! -f "$MAINFRAME_INSTALL_DIR/lib/$lib" ]]; then
            die "Library missing: $lib"
        fi
    done

    # Test basic functionality
    if ! "$MAINFRAME_INSTALL_DIR/mainframe" --version &>/dev/null; then
        die "MAINFRAME failed to run"
    fi

    success "Deployment verified"
}

# =============================================================================
# PRINT SUMMARY
# =============================================================================

print_summary() {
    printf "\n"
    cat << 'EOF'
    __  ______    _____   ________  ___    __  _________
   /  |/  /   |  /  _/ | / / ____/ / _ \  /  |/  / ____/
  / /|_/ / /| |  / //  |/ / /_    / , _/ / /|_/ / __/
 / /  / / ___ |_/ // /|  / __/   / /| | / /  / / /___
/_/  /_/_/  |_/___/_/ |_/_/     /_/ |_|/_/  /_/_____/

EOF
    printf "${GREEN}${BOLD}MAINFRAME deployed successfully!${NC}\n"
    printf "\n"
    printf "Installation directory: ${BLUE}$MAINFRAME_INSTALL_DIR${NC}\n"
    printf "Binary location:        ${BLUE}$MAINFRAME_BIN_DIR/mainframe${NC}\n"
    printf "\n"
    printf "To get started:\n"
    printf "  1. Restart your shell or run: ${YELLOW}source ~/.bashrc${NC}\n"
    printf "  2. Verify installation:       ${YELLOW}mainframe --version${NC}\n"
    printf "  3. See available operations:  ${YELLOW}mainframe list${NC}\n"
    printf "  4. Get help:                  ${YELLOW}mainframe help${NC}\n"
    printf "\n"
    printf "${BOLD}AI Tool Integration:${NC}\n"
    printf "  MAINFRAME is now auto-discoverable by AI coding tools!\n"
    printf "  Claude Code, Cursor, Aider, and others will automatically\n"
    printf "  know MAINFRAME capabilities are available in ANY project.\n"
    printf "\n"
    printf "  Check status: ${YELLOW}mainframe ai-discovery status${NC}\n"
    printf "\n"
    printf "Documentation: https://github.com/mainframe-cli/mainframe\n"
    printf "\n"
    printf "${BOLD}YO JOE!${NC}\n"
    printf "\n"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

show_help() {
    cat << EOF
MAINFRAME Installation Script
"Mainframe can make a computer do anything short of tap dance."

Usage: $0 [options]

Options:
  -h, --help          Show this help message
  -d, --dir DIR       Install directory (default: ~/.mainframe)
  -b, --bin DIR       Binary directory (default: ~/.local/bin)
  --branch BRANCH     Git branch to install (default: main)
  --no-shell          Skip shell configuration
  --no-claude         Skip Claude Code integration
  --no-ai-discovery   Skip AI tool discovery setup
  --force             Force reinstall without prompting

Environment Variables:
  MAINFRAME_INSTALL_DIR  Override install directory
  MAINFRAME_BIN_DIR      Override binary directory
  MAINFRAME_BRANCH       Override git branch
  MAINFRAME_FORCE        Set to 1 for non-interactive install
EOF
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local skip_shell=false
    local skip_claude=false
    local skip_ai_discovery=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dir)
                MAINFRAME_INSTALL_DIR="$2"
                shift 2
                ;;
            -b|--bin)
                MAINFRAME_BIN_DIR="$2"
                shift 2
                ;;
            --branch)
                MAINFRAME_BRANCH="$2"
                shift 2
                ;;
            --no-shell)
                skip_shell=true
                shift
                ;;
            --no-claude)
                skip_claude=true
                shift
                ;;
            --no-ai-discovery)
                skip_ai_discovery=true
                shift
                ;;
            --force)
                export MAINFRAME_FORCE=1
                shift
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    printf "${BOLD}${BLUE}"
    cat << 'EOF'
    __  ______    _____   ________  ___    __  _________
   /  |/  /   |  /  _/ | / / ____/ / _ \  /  |/  / ____/
  / /|_/ / /| |  / //  |/ / /_    / , _/ / /|_/ / __/
 / /  / / ___ |_/ // /|  / __/   / /| | / /  / / /___
/_/  /_/_/  |_/___/_/ |_/_/     /_/ |_|/_/  /_/_____/

EOF
    printf "       GI Joe Computer Specialist - 1986\n"
    printf "${NC}\n"

    check_dependencies
    install_mainframe

    [[ "$skip_shell" != "true" ]] && setup_shell
    [[ "$skip_claude" != "true" ]] && setup_claude_code
    [[ "$skip_ai_discovery" != "true" ]] && setup_ai_discovery

    post_install
    verify_installation
    print_summary
}

main "$@"
