#!/usr/bin/env bash
# =============================================================================
# MAINFRAME recoverable uninstaller
# =============================================================================

set -euo pipefail

MAINFRAME_INSTALL_DIR="${MAINFRAME_INSTALL_DIR:-$HOME/.mainframe}"
MAINFRAME_BIN_DIR="${MAINFRAME_BIN_DIR:-$HOME/.local/bin}"
MAINFRAME_BEGIN_MARKER="# >>> MAINFRAME >>>"
MAINFRAME_END_MARKER="# <<< MAINFRAME <<<"
MAINFRAME_BASH_LOGIN_BEGIN_MARKER="# >>> MAINFRAME BASH LOGIN >>>"
MAINFRAME_BASH_LOGIN_END_MARKER="# <<< MAINFRAME BASH LOGIN <<<"

DRY_RUN=false
PURGE=false
PURGE_STATE=false
SHELL_CONFIG_OVERRIDE=""
RUN_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUNTIME_MANIFEST_ERROR=""
declare -a RUNTIME_MANAGED_PATHS=("")
declare -a RUNTIME_MANAGED_HASHES=("")

info() {
    printf '[MAINFRAME] %s\n' "$*"
}

warn() {
    printf '[MAINFRAME warning] %s\n' "$*" >&2
}

die() {
    printf '[MAINFRAME error] %s\n' "$*" >&2
    exit 1
}

show_help() {
    cat <<'EOF'
MAINFRAME recoverable uninstaller

Usage: uninstall.sh [options]

By default, this removes only MAINFRAME's exact managed shell blocks and owned
CLI symlink, then moves the installation to a timestamped backup beside it.

Options:
  --dry-run              Print intended changes without modifying anything
  --purge                Delete verified runtime files; preserve other in-root data
  --purge-state          With --purge, delete all in-root data as well
  --dir DIR              Installation directory (default: ~/.mainframe)
  --bin DIR              CLI link directory (default: ~/.local/bin)
  --shell-config FILE    Inspect only this shell profile for MAINFRAME blocks
  -h, --help             Show this help

Environment variables:
  MAINFRAME_INSTALL_DIR  Override installation directory
  MAINFRAME_BIN_DIR      Override CLI link directory
EOF
}

canonical_path() {
    local path="$1" parent base
    [[ "$path" == /* ]] || path="$PWD/$path"

    while [[ "$path" != "/" && "$path" == */ ]]; do
        path="${path%/}"
    done
    if [[ "$path" == "/" ]]; then
        printf '/\n'
        return 0
    fi

    parent="$(dirname "$path")"
    base="$(basename "$path")"
    [[ "$base" != "." && "$base" != ".." ]] || return 1
    [[ -d "$parent" ]] || return 1
    printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$base"
}

next_available_path() {
    local candidate="$1" suffix=0
    while [[ -e "$candidate" || -L "$candidate" ]]; do
        suffix=$((suffix + 1))
        candidate="$1.$suffix"
    done
    printf '%s\n' "$candidate"
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        return 127
    fi
}

runtime_relative_path_is_safe() {
    local path="$1"
    case "$path" in
        ""|/*|*/|*//*|.|..|./*|../*|*/.|*/..|*/./*|*/../*|*\\*) return 1 ;;
    esac
    [[ "$path" != *$'\r'* && "$path" != *$'\t'* ]]
}

load_runtime_manifest() {
    local manifest="$MAINFRAME_INSTALL_DIR/SHA256SUMS"
    local line expected relative existing line_number=0 required

    RUNTIME_MANIFEST_ERROR=""
    RUNTIME_MANAGED_PATHS=("")
    RUNTIME_MANAGED_HASHES=("")

    if [[ -L "$manifest" || ! -f "$manifest" ]]; then
        RUNTIME_MANIFEST_ERROR="safe runtime purge requires a regular SHA256SUMS inventory"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        case "$line" in
            ""|'#'*) continue ;;
        esac
        if (( ${#line} < 67 )); then
            RUNTIME_MANIFEST_ERROR="invalid SHA256SUMS record at line $line_number"
            return 1
        fi
        expected="${line:0:64}"
        relative="${line:66}"
        if [[ ! "$expected" =~ ^[0-9a-f]{64}$ || "${line:64:2}" != "  " ]] ||
           ! runtime_relative_path_is_safe "$relative" ||
           [[ "$relative" == "SHA256SUMS" ]]; then
            RUNTIME_MANIFEST_ERROR="invalid SHA256SUMS record at line $line_number"
            return 1
        fi
        for existing in "${RUNTIME_MANAGED_PATHS[@]}"; do
            [[ -n "$existing" ]] || continue
            if [[ "$existing" == "$relative" ]]; then
                RUNTIME_MANIFEST_ERROR="duplicate SHA256SUMS path at line $line_number"
                return 1
            fi
        done
        RUNTIME_MANAGED_PATHS+=("$relative")
        RUNTIME_MANAGED_HASHES+=("$expected")
    done < "$manifest"

    (( ${#RUNTIME_MANAGED_PATHS[@]} > 1 )) || {
        RUNTIME_MANIFEST_ERROR="SHA256SUMS contains no runtime files"
        return 1
    }
    for required in VERSION lib/common.sh bin/mainframe; do
        existing=false
        for relative in "${RUNTIME_MANAGED_PATHS[@]}"; do
            [[ -n "$relative" ]] || continue
            [[ "$relative" == "$required" ]] && existing=true
        done
        if [[ "$existing" != "true" ]]; then
            RUNTIME_MANIFEST_ERROR="SHA256SUMS omits required runtime path: $required"
            return 1
        fi
    done
}

runtime_path_has_symlink_ancestor() {
    local root="$1" relative="$2" component
    local parent="$root"
    local -a components=()
    local index

    IFS='/' read -r -a components <<< "$relative"
    for ((index = 0; index < ${#components[@]} - 1; index++)); do
        component="${components[$index]}"
        parent="$parent/$component"
        [[ -L "$parent" ]] && return 0
        [[ -d "$parent" ]] || return 1
    done
    return 1
}

purge_runtime_preserving_data() {
    local preserved_root path relative expected actual parent directory
    local removed_files=0 managed_index
    local -a managed_directories=()
    local progress

    preserved_root="$(next_available_path "$MAINFRAME_INSTALL_DIR.state-preserved-$RUN_TIMESTAMP")"
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Would remove only byte-identical SHA256SUMS-owned runtime files"
        info "Would preserve all unmanaged or modified in-root data at $preserved_root"
        return 0
    fi

    mv -- "$MAINFRAME_INSTALL_DIR" "$preserved_root"
    info "Moved the installation to a recoverable state-classification path: $preserved_root"

    for ((managed_index = 1; managed_index < ${#RUNTIME_MANAGED_PATHS[@]}; managed_index++)); do
        relative="${RUNTIME_MANAGED_PATHS[$managed_index]}"
        path="$preserved_root/$relative"
        parent="$(dirname "$relative")"
        while [[ "$parent" != "." && "$parent" != "/" ]]; do
            managed_directories+=("$parent")
            parent="$(dirname "$parent")"
        done

        [[ -f "$path" && ! -L "$path" ]] || continue
        runtime_path_has_symlink_ancestor "$preserved_root" "$relative" && continue
        expected="${RUNTIME_MANAGED_HASHES[$managed_index]}"
        actual="$(sha256_file "$path")" || {
            warn "Could not hash managed runtime file; preserving it: $relative"
            continue
        }
        [[ "$actual" == "$expected" ]] || continue
        rm -f -- "$path"
        removed_files=$((removed_files + 1))
    done

    rm -f -- "$preserved_root/SHA256SUMS"

    progress=true
    while [[ "$progress" == "true" ]]; do
        progress=false
        for directory in "${managed_directories[@]}"; do
            path="$preserved_root/$directory"
            if [[ -d "$path" && ! -L "$path" ]] && rmdir -- "$path" 2>/dev/null; then
                progress=true
            fi
        done
    done

    if rmdir -- "$preserved_root" 2>/dev/null; then
        info "Irreversibly deleted $removed_files verified runtime files; no unmanaged or modified in-root data was present"
    else
        info "Irreversibly deleted $removed_files verified runtime files"
        info "Preserved all unmanaged or modified in-root data at $preserved_root"
        info "Review that directory and move any state you want to keep before deleting it."
    fi
}

validate_install_target() {
    local target="$1" canonical_home
    canonical_home="$(cd "$HOME" && pwd -P)"

    case "$target" in
        ""|/|"$canonical_home")
            die "Refusing unsafe installation target: ${target:-<empty>}"
            ;;
    esac

    if [[ -L "$target" ]]; then
        die "Refusing a symlinked installation target: $target"
    fi
    [[ -e "$target" ]] || return 1
    [[ -d "$target" ]] || die "Installation target is not a directory: $target"

    # Purge and backup operations are allowed only for a recognizable
    # MAINFRAME installation. This prevents a misspelled --dir from turning
    # into a broad move or recursive deletion.
    if [[ ! -f "$target/VERSION" || \
          ! -f "$target/lib/common.sh" || \
          ! -f "$target/bin/mainframe" ]]; then
        die "Target does not look like a MAINFRAME installation: $target"
    fi
    return 0
}

profile_mode() {
    local file="$1" mode=""
    mode="$(stat -c '%a' "$file" 2>/dev/null || true)"
    if [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
        printf '%s\n' "$mode"
        return 0
    fi
    mode="$(stat -f '%Lp' "$file" 2>/dev/null || true)"
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] && printf '%s\n' "$mode"
}

managed_profile_state() {
    local file="$1"

    if [[ ! -e "$file" && ! -L "$file" ]]; then
        printf 'absent\n'
        return 0
    fi
    if [[ -L "$file" || ! -f "$file" ]]; then
        printf 'unsafe\n'
        return 0
    fi

    awk \
        -v runtime_begin="$MAINFRAME_BEGIN_MARKER" \
        -v runtime_end="$MAINFRAME_END_MARKER" \
        -v login_begin="$MAINFRAME_BASH_LOGIN_BEGIN_MARKER" \
        -v login_end="$MAINFRAME_BASH_LOGIN_END_MARKER" '
        BEGIN {
            inside = ""
            runtime_count = 0
            login_count = 0
            found = 0
            invalid = 0
        }
        $0 == runtime_begin {
            found = 1
            runtime_count++
            if (inside != "" || runtime_count > 1) invalid = 1
            inside = "runtime"
            next
        }
        $0 == login_begin {
            found = 1
            login_count++
            if (inside != "" || login_count > 1) invalid = 1
            inside = "login"
            next
        }
        $0 == runtime_end {
            found = 1
            if (inside != "runtime") invalid = 1
            inside = ""
            next
        }
        $0 == login_end {
            found = 1
            if (inside != "login") invalid = 1
            inside = ""
            next
        }
        END {
            if (inside != "" || invalid) print "malformed"
            else if (found) print "valid"
            else print "absent"
        }
    ' "$file"
}

remove_profile_blocks() {
    local file="$1" tmp mode backup state
    [[ -f "$file" || -L "$file" ]] || return 0

    state="$(managed_profile_state "$file")"
    if [[ "$state" == "unsafe" ]]; then
        warn "Skipping symlinked shell profile (edit it manually): $file"
        return 0
    fi
    if [[ "$state" == "malformed" ]]; then
        warn "Malformed MAINFRAME marker block; leaving profile unchanged: $file"
        return 0
    fi
    [[ "$state" == "valid" ]] || return 0

    tmp="$(mktemp "$(dirname "$file")/.mainframe-uninstall.XXXXXX")"
    awk \
        -v runtime_begin="$MAINFRAME_BEGIN_MARKER" \
        -v runtime_end="$MAINFRAME_END_MARKER" \
        -v login_begin="$MAINFRAME_BASH_LOGIN_BEGIN_MARKER" \
        -v login_end="$MAINFRAME_BASH_LOGIN_END_MARKER" '
        $0 == runtime_begin { inside = "runtime"; next }
        $0 == login_begin { inside = "login"; next }
        inside == "runtime" && $0 == runtime_end { inside = ""; next }
        inside == "login" && $0 == login_end { inside = ""; next }
        inside == "" { print }
    ' "$file" > "$tmp"

    if [[ "$DRY_RUN" == "true" ]]; then
        rm -f -- "$tmp"
        info "Would remove the exact MAINFRAME marker block(s) from $file"
        return 0
    fi

    mode="$(profile_mode "$file")"
    [[ -z "$mode" ]] || chmod "$mode" "$tmp"
    backup="$(next_available_path "$file.mainframe-backup-$RUN_TIMESTAMP")"
    cp -p "$file" "$backup"
    mv "$tmp" "$file"
    info "Removed MAINFRAME marker block(s) from $file"
    info "Shell profile backup: $backup"
}

remove_owned_cli_link() {
    local link="$MAINFRAME_BIN_DIR/mainframe"
    [[ -L "$link" ]] || {
        if [[ -e "$link" ]]; then
            warn "Leaving non-symlink CLI path unchanged: $link"
        fi
        return 0
    }

    if [[ "$(readlink "$link")" != "$MAINFRAME_INSTALL_DIR/bin/mainframe" ]]; then
        warn "Leaving CLI symlink with a different target unchanged: $link"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Would remove owned CLI symlink $link"
    else
        rm -f -- "$link"
        info "Removed owned CLI symlink $link"
    fi
}

process_shell_profiles() {
    local profile
    local profiles=()

    if [[ -n "$SHELL_CONFIG_OVERRIDE" ]]; then
        profiles+=("$SHELL_CONFIG_OVERRIDE")
    else
        profiles+=(
            "$HOME/.bashrc"
            "$HOME/.bash_profile"
            "$HOME/.bash_login"
            "$HOME/.profile"
            "$HOME/.zshrc"
            "$HOME/.config/fish/config.fish"
        )
    fi

    for profile in "${profiles[@]}"; do
        profile="$(canonical_path "$profile" 2>/dev/null || printf '%s' "$profile")"
        remove_profile_blocks "$profile"
    done
}

warn_project_integrations() {
    local awm_path="$MAINFRAME_INSTALL_DIR/awm"
    local mapping

    warn "Machine-level uninstall does not know project paths; project hook files are not removed."
    warn "Deactivate each onboarded project before uninstall to avoid stranded fail-closed hooks."

    if [[ -L "$awm_path" ]]; then
        warn "Default AWM path is a symlink; MAINFRAME will not follow it. Its external target remains."
        return 0
    fi

    [[ -d "$awm_path/projects" ]] || return 0
    for mapping in "$awm_path"/projects/*.json; do
        [[ -f "$mapping" ]] || continue
        warn "Private AWM project mappings exist, but MAINFRAME intentionally does not store their project paths."
        return 0
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --purge)
            PURGE=true
            shift
            ;;
        --purge-state)
            PURGE_STATE=true
            shift
            ;;
        --dir)
            [[ $# -ge 2 ]] || die "--dir requires a value"
            [[ -n "$2" && "$2" != --* ]] || die "--dir requires a path value"
            MAINFRAME_INSTALL_DIR="$2"
            shift 2
            ;;
        --bin)
            [[ $# -ge 2 ]] || die "--bin requires a value"
            [[ -n "$2" && "$2" != --* ]] || die "--bin requires a path value"
            MAINFRAME_BIN_DIR="$2"
            shift 2
            ;;
        --shell-config)
            [[ $# -ge 2 ]] || die "--shell-config requires a value"
            [[ -n "$2" && "$2" != --* ]] || die "--shell-config requires a path value"
            SHELL_CONFIG_OVERRIDE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

if [[ "$PURGE_STATE" == "true" && "$PURGE" != "true" ]]; then
    die "--purge-state requires --purge"
fi

MAINFRAME_INSTALL_DIR="$(canonical_path "$MAINFRAME_INSTALL_DIR")" || \
    die "Installation parent directory does not exist: $(dirname "$MAINFRAME_INSTALL_DIR")"
if canonical_bin_dir="$(canonical_path "$MAINFRAME_BIN_DIR" 2>/dev/null)"; then
    MAINFRAME_BIN_DIR="$canonical_bin_dir"
elif [[ "$MAINFRAME_BIN_DIR" != /* ]]; then
    MAINFRAME_BIN_DIR="$PWD/$MAINFRAME_BIN_DIR"
fi

install_present=false
if validate_install_target "$MAINFRAME_INSTALL_DIR"; then
    install_present=true
fi

if [[ "$install_present" == "true" &&
      "$PURGE" == "true" && "$PURGE_STATE" != "true" ]]; then
    load_runtime_manifest || die "$RUNTIME_MANIFEST_ERROR; use the default recoverable uninstall instead"
fi

warn_project_integrations
process_shell_profiles
remove_owned_cli_link

if [[ "$install_present" != "true" ]]; then
    info "No installation found at $MAINFRAME_INSTALL_DIR"
    exit 0
fi

if [[ "$PURGE" == "true" ]]; then
    if [[ "$PURGE_STATE" != "true" ]]; then
        purge_runtime_preserving_data
    else
        awm_state_is_external=false
        [[ -L "$MAINFRAME_INSTALL_DIR/awm" ]] && awm_state_is_external=true
        if [[ "$DRY_RUN" == "true" ]]; then
            if [[ "$awm_state_is_external" == "true" ]]; then
                info "Would irreversibly delete validated installation $MAINFRAME_INSTALL_DIR without following or deleting external symlinked AWM state"
            else
                info "Would irreversibly delete validated installation $MAINFRAME_INSTALL_DIR, including default AWM state and all other in-root data"
            fi
        else
            rm -rf -- "$MAINFRAME_INSTALL_DIR"
            if [[ "$awm_state_is_external" == "true" ]]; then
                info "Irreversibly deleted validated installation $MAINFRAME_INSTALL_DIR; external symlinked AWM state was not followed or deleted"
            else
                info "Irreversibly deleted validated installation $MAINFRAME_INSTALL_DIR, including default AWM state and all other in-root data"
            fi
        fi
    fi
else
    backup_path="$(next_available_path "$MAINFRAME_INSTALL_DIR.uninstalled-$RUN_TIMESTAMP")"
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Would move installation to recoverable backup $backup_path"
    else
        mv "$MAINFRAME_INSTALL_DIR" "$backup_path"
        info "Moved installation to recoverable backup $backup_path"
        info "Restore installation with: mv \"$backup_path\" \"$MAINFRAME_INSTALL_DIR\""
        info "Restore CLI link with: ln -s \"$MAINFRAME_INSTALL_DIR/bin/mainframe\" \"$MAINFRAME_BIN_DIR/mainframe\""
        info "Restore any shell profile from the profile backup path printed above."
    fi
fi
