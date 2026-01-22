#!/usr/bin/env bash
# =============================================================================
# Basher package manifest for MAINFRAME
# =============================================================================
# See: https://github.com/basherpm/basher
#
# Installation: basher install gtwatts/mainframe
# =============================================================================

BASHER_PACKAGE_NAME="mainframe"
BASHER_PACKAGE_VERSION="3.0.0"

# Installation hook - runs after basher clones the repo
basher_install() {
    # Determine installation directory
    local install_dir="${BASHER_PACKAGES_PATH}/gtwatts/mainframe"

    # Detect shell configuration file
    local profile="${HOME}/.bashrc"
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ -f "${HOME}/.zshrc" ]]; then
        profile="${HOME}/.zshrc"
    fi

    # Add MAINFRAME to shell profile if not already present
    if ! grep -q "MAINFRAME_ROOT" "$profile" 2>/dev/null; then
        cat >> "$profile" << EOF

# MAINFRAME - Bash Superpowers for AI Coding Assistants
# Installed via: basher install gtwatts/mainframe
export MAINFRAME_ROOT="$install_dir"
source "\$MAINFRAME_ROOT/lib/common.sh"
EOF
        echo "[MAINFRAME] Added to $profile"
    else
        echo "[MAINFRAME] Already configured in $profile"
    fi

    echo ""
    echo "==================================================================="
    echo "  MAINFRAME installed successfully!"
    echo "==================================================================="
    echo ""
    echo "  Restart your shell or run:"
    echo "    source $profile"
    echo ""
    echo "  Then verify with:"
    echo "    mainframe doctor"
    echo ""
    echo "  Functions available: 1,100+"
    echo "  Documentation: https://github.com/gtwatts/mainframe"
    echo "==================================================================="
}

# Uninstall hook
basher_uninstall() {
    echo ""
    echo "==================================================================="
    echo "  MAINFRAME uninstalled"
    echo "==================================================================="
    echo ""
    echo "  To complete removal, edit your shell profile and remove:"
    echo ""
    echo "    export MAINFRAME_ROOT=..."
    echo "    source \"\$MAINFRAME_ROOT/lib/common.sh\""
    echo ""
    echo "==================================================================="
}
