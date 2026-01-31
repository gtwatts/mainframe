#!/usr/bin/env bash
# =============================================================================
# MAINFRAME Quick Installer
# =============================================================================
# One-liner installation:
#   curl -fsSL https://raw.githubusercontent.com/gtwatts/mainframe/main/get-mainframe.sh | bash
#
# Or with custom location:
#   curl -fsSL https://raw.githubusercontent.com/gtwatts/mainframe/main/get-mainframe.sh | MAINFRAME_DIR=~/my-mainframe bash
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
MAINFRAME_REPO="https://github.com/gtwatts/mainframe.git"
MAINFRAME_DIR="${MAINFRAME_DIR:-$HOME/.mainframe}"

echo ""
echo -e "${BOLD}${BLUE}"
cat << 'BANNER'
    __  ______    _____   ________  ___    __  _________
   /  |/  /   |  /  _/ | / / ____/ / _ \  /  |/  / ____/
  / /|_/ / /| |  / //  |/ / /_    / , _/ / /|_/ / __/
 / /  / / ___ |_/ // /|  / __/   / /| | / /  / / /___
/_/  /_/_/  |_/___/_/ |_/_/     /_/ |_|/_/  /_/_____/

BANNER
echo -e "${NC}"
echo -e "${BOLD}Pure Bash Standard Library - 4,000+ Functions${NC}"
echo ""

# Check for bash 4.4+
check_bash() {
    local bash_version="${BASH_VERSION%%(*}"
    local bash_major="${bash_version%%.*}"
    local bash_minor="${bash_version#*.}"
    bash_minor="${bash_minor%%.*}"

    if [[ "$bash_major" -lt 4 ]] || [[ "$bash_major" -eq 4 && "$bash_minor" -lt 4 ]]; then
        echo -e "${RED}Error: Bash 4.4+ required (found: $BASH_VERSION)${NC}"
        echo ""
        echo "Install newer bash:"
        echo "  macOS: brew install bash"
        echo "  Ubuntu: sudo apt install bash"
        exit 1
    fi
}

# Check for git
check_git() {
    if ! command -v git &>/dev/null; then
        echo -e "${RED}Error: git is required${NC}"
        echo ""
        echo "Install git:"
        echo "  macOS: xcode-select --install"
        echo "  Ubuntu: sudo apt install git"
        exit 1
    fi
}

# Main installation
install_mainframe() {
    echo -e "${BLUE}[1/4]${NC} Checking requirements..."
    check_bash
    check_git
    echo -e "${GREEN}      Requirements OK${NC}"

    echo -e "${BLUE}[2/4]${NC} Downloading MAINFRAME..."
    if [[ -d "$MAINFRAME_DIR" ]]; then
        echo -e "${YELLOW}      Existing installation found, updating...${NC}"
        cd "$MAINFRAME_DIR" && git pull --quiet
    else
        git clone --depth 1 --quiet "$MAINFRAME_REPO" "$MAINFRAME_DIR"
    fi
    echo -e "${GREEN}      Downloaded to $MAINFRAME_DIR${NC}"

    echo -e "${BLUE}[3/4]${NC} Configuring shell..."
    local shell_config=""
    case "${SHELL:-/bin/bash}" in
        */bash) shell_config="$HOME/.bashrc" ;;
        */zsh)  shell_config="$HOME/.zshrc" ;;
        *)      shell_config="" ;;
    esac

    if [[ -n "$shell_config" ]] && [[ -f "$shell_config" ]]; then
        if ! grep -q "MAINFRAME_ROOT" "$shell_config" 2>/dev/null; then
            cat >> "$shell_config" << SHELL
# MAINFRAME - Pure Bash Standard Library
export MAINFRAME_ROOT="$MAINFRAME_DIR"
export MAINFRAME_AI_ENABLED=1
SHELL
            echo -e "${GREEN}      Added to $shell_config${NC}"
        else
            echo -e "${GREEN}      Already configured in $shell_config${NC}"
        fi
    else
        echo -e "${YELLOW}      Manual setup needed (unknown shell)${NC}"
    fi

    echo -e "${BLUE}[4/4]${NC} Setting up AI discovery..."
    export MAINFRAME_ROOT="$MAINFRAME_DIR"
    if [[ -f "$MAINFRAME_DIR/lib/ai_discovery.sh" ]]; then
        source "$MAINFRAME_DIR/lib/ai_discovery.sh"
        mainframe_ai_discovery_setup_universal >/dev/null 2>&1 || true
        mainframe_ai_discovery_setup_claude >/dev/null 2>&1 || true
        echo -e "${GREEN}      AI tools will auto-detect MAINFRAME${NC}"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}Installation complete!${NC}"
    echo ""
    echo -e "Next steps:"
    echo -e "  1. Restart your shell or run: ${YELLOW}source $shell_config${NC}"
    echo -e "  2. Test it: ${YELLOW}source \"\$MAINFRAME_ROOT/lib/common.sh\" && uuid${NC}"
    echo ""
    echo -e "In your scripts, add this line at the top:"
    echo -e "  ${YELLOW}source \"\${MAINFRAME_ROOT:-\$HOME/.mainframe}/lib/common.sh\"${NC}"
    echo ""
    echo -e "Documentation: ${BLUE}$MAINFRAME_DIR/CHEATSHEET.md${NC}"
    echo ""
}

install_mainframe
