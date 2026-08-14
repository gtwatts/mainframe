#!/usr/bin/env bash
# =============================================================================
# MAINFRAME verified release upgrader
# =============================================================================
# Replaces one receipt-backed release installation with an explicitly selected
# release archive. The current runtime must be byte-identical to its installed
# checksum inventory. Unmanaged in-root state is copied into the staged runtime
# only after collision, type, and stability checks. The old installation is
# retained as a recoverable sibling backup.
# =============================================================================

set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )) || \
   (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4 )); then
    printf '[MAINFRAME upgrade error] Bash 4.4+ is required (found %s).\n' \
        "${BASH_VERSION:-unknown}" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
MAINFRAME_ROOT="${MAINFRAME_ROOT:-$DEFAULT_ROOT}"
MAINFRAME_RELEASE_BASE_URL="${MAINFRAME_RELEASE_BASE_URL:-https://github.com/gtwatts/mainframe/releases/download}"
RECEIPT_NAME=".mainframe-install-receipt.json"

TARGET_VERSION=""
ALLOW_DOWNGRADE=false
DRY_RUN=false
CONFIRM_AGENTS_STOPPED=false
RECOVER=false
RECOVERY_JOURNAL=""
WORKSPACE=""
LOCK_DIR=""
LOCK_OWNED=false
JOURNAL=""
TRANSACTION_DIR=""
BACKUP_DIR=""
FAILED_DIR=""
RECOVERY_SCRIPT=""
INTERNAL_TESTING_AUTHORIZED=false
STAGED_IDENTITY=""
ACTIVE_CANDIDATE_OWNED=false
PLACEMENT_IN_PROGRESS=false
MISPLACED_CANDIDATE=""
MISPLACED_CANDIDATE_DIR=""
CURRENT_ROOT_IDENTITY=""
BACKUP_OWNED=false
CURRENT_UPGRADER_SHA=""

declare -a LOADED_MANAGED_PATHS=("")
declare -a LOADED_MANAGED_HASHES=("")
declare -a CURRENT_MANAGED_PATHS=("")
declare -a STATE_PATHS=("")
declare -a STATE_TYPES=("")
declare -a STATE_MODES=("")
declare -a STATE_HASHES=("")

info() {
    printf '[MAINFRAME upgrade] %s\n' "$*"
}

warn() {
    printf '[MAINFRAME upgrade warning] %s\n' "$*" >&2
}

durability_barrier() {
    sync || die "Filesystem durability barrier failed"
}

die() {
    printf '[MAINFRAME upgrade error] %s\n' "$*" >&2
    exit 1
}

show_help() {
    cat <<'EOF'
MAINFRAME verified release upgrade

Usage:
  mainframe upgrade --version X.Y.Z [options]
  mainframe upgrade --recover [--journal PATH]

Options:
  --version VERSION      Exact stable release version to install (required)
  --allow-downgrade      Permit a target older than the installed version
  --dry-run              Download, verify, and stage without replacing anything
  --confirm-agents-stopped
                         Confirm no agent/runtime process is using this install
  --recover              Roll back an interrupted transaction
  --journal PATH         Exact recovery journal (required if install root is absent)
  -h, --help             Show this help

The command supports receipt-backed release-archive installations. Homebrew
and source-checkout installations retain their package-manager/source workflow.
The current runtime must match its installed SHA256SUMS inventory. Unmanaged
state is preserved only when every path is regular, collision-free, and stable
during staging. Because current AWM writers do not share the upgrade lock, an
actual cutover requires an explicit confirmation that agents are stopped. The
previous installation remains in a private sibling transaction directory.
EOF
}

is_stable_semver() {
    [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

compare_decimal_component() {
    local left="$1" right="$2"
    local LC_ALL=C
    if (( ${#left} < ${#right} )); then printf '%s\n' -1; return; fi
    if (( ${#left} > ${#right} )); then printf '%s\n' 1; return; fi
    if [[ "$left" == "$right" ]]; then printf '%s\n' 0; return; fi
    if [[ "$left" < "$right" ]]; then printf '%s\n' -1; else printf '%s\n' 1; fi
}

semver_compare() {
    local left="$1" right="$2" result index
    local -a left_parts=() right_parts=()

    IFS=. read -r -a left_parts <<< "$left"
    IFS=. read -r -a right_parts <<< "$right"
    for index in 0 1 2; do
        result="$(compare_decimal_component "${left_parts[$index]}" "${right_parts[$index]}")"
        if [[ "$result" != "0" ]]; then
            printf '%s\n' "$result"
            return
        fi
    done
    printf '%s\n' 0
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

path_mode() {
    local path="$1" value=""
    value="$(stat -c '%a' "$path" 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-7]{3,4}$ ]]; then printf '%s\n' "$value"; return; fi
    value="$(stat -f '%Lp' "$path" 2>/dev/null || true)"
    [[ "$value" =~ ^[0-7]{3,4}$ ]] && printf '%s\n' "$value"
}

path_device() {
    local path="$1" value=""
    value="$(stat -c '%d' "$path" 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-9]+$ ]]; then printf '%s\n' "$value"; return; fi
    value="$(stat -f '%d' "$path" 2>/dev/null || true)"
    [[ "$value" =~ ^[0-9]+$ ]] && printf '%s\n' "$value"
}

path_identity() {
    local path="$1" value=""
    value="$(stat -c '%d:%i' "$path" 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-9]+:[0-9]+$ ]]; then printf '%s\n' "$value"; return; fi
    value="$(stat -f '%d:%i' "$path" 2>/dev/null || true)"
    [[ "$value" =~ ^[0-9]+:[0-9]+$ ]] && printf '%s\n' "$value"
}

directory_matches_identity() {
    local path="$1" expected="$2"
    [[ -n "$expected" && -d "$path" && ! -L "$path" && \
       "$(path_identity "$path")" == "$expected" ]]
}

next_available_path() {
    local original="$1" candidate="$1" suffix=0
    while [[ -e "$candidate" || -L "$candidate" ]]; do
        suffix=$((suffix + 1))
        candidate="$original.$suffix"
    done
    printf '%s\n' "$candidate"
}

relative_path_is_safe() {
    local path="$1"
    case "$path" in
        ""|/*|*/|*//*|.|..|./*|../*|*/.|*/..|*/./*|*/../*|*\\*) return 1 ;;
    esac
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *$'\t'* ]]
}

path_has_symlink_ancestor() {
    local root="$1" relative="$2" component index
    local parent="$root"
    local -a components=()
    IFS='/' read -r -a components <<< "$relative"
    for ((index = 0; index < ${#components[@]} - 1; index++)); do
        component="${components[$index]}"
        parent="$parent/$component"
        [[ -L "$parent" ]] && return 0
        [[ -d "$parent" ]] || return 1
    done
    return 1
}

manifest_contains() {
    local wanted="$1" existing
    for existing in "${LOADED_MANAGED_PATHS[@]}"; do
        [[ -n "$existing" ]] || continue
        [[ "$existing" == "$wanted" ]] && return 0
    done
    return 1
}

loaded_manifest_hash_for() {
    local wanted="$1" index
    for ((index = 1; index < ${#LOADED_MANAGED_PATHS[@]}; index++)); do
        if [[ "${LOADED_MANAGED_PATHS[$index]}" == "$wanted" ]]; then
            printf '%s\n' "${LOADED_MANAGED_HASHES[$index]}"
            return 0
        fi
    done
    return 1
}

current_manifest_contains() {
    local wanted="$1" existing
    for existing in "${CURRENT_MANAGED_PATHS[@]}"; do
        [[ -n "$existing" ]] || continue
        [[ "$existing" == "$wanted" ]] && return 0
    done
    return 1
}

current_directory_is_managed_structure() {
    local directory="$1" existing
    for existing in "${CURRENT_MANAGED_PATHS[@]}"; do
        [[ -n "$existing" ]] || continue
        case "$existing" in
            "$directory"/*) return 0 ;;
        esac
    done
    return 1
}

current_path_is_inside_managed_structure() {
    local relative="$1" ancestor
    [[ "$relative" == */* ]] || return 1
    ancestor="${relative%/*}"
    while [[ -n "$ancestor" && "$ancestor" != "." ]]; do
        current_directory_is_managed_structure "$ancestor" && return 0
        [[ "$ancestor" == */* ]] || break
        ancestor="${ancestor%/*}"
    done
    return 1
}

load_and_verify_manifest() {
    local root="$1" require_exact="$2"
    local manifest="$root/SHA256SUMS"
    local line expected relative existing actual line_number=0 required path paths_file

    LOADED_MANAGED_PATHS=("")
    LOADED_MANAGED_HASHES=("")
    [[ -f "$manifest" && ! -L "$manifest" ]] || \
        die "A regular SHA256SUMS inventory is required: $manifest"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        case "$line" in
            ""|'#'*) continue ;;
        esac
        (( ${#line} >= 67 )) || die "Malformed SHA256SUMS record at line $line_number"
        expected="${line:0:64}"
        relative="${line:66}"
        if [[ ! "$expected" =~ ^[0-9a-f]{64}$ || "${line:64:2}" != "  " ]] ||
           ! relative_path_is_safe "$relative" || [[ "$relative" == "SHA256SUMS" ]]; then
            die "Malformed or unsafe SHA256SUMS record at line $line_number"
        fi
        for existing in "${LOADED_MANAGED_PATHS[@]}"; do
            [[ -n "$existing" ]] || continue
            [[ "$existing" != "$relative" ]] || \
                die "Duplicate SHA256SUMS path at line $line_number: $relative"
        done
        LOADED_MANAGED_PATHS+=("$relative")
        LOADED_MANAGED_HASHES+=("$expected")
    done < "$manifest"

    (( ${#LOADED_MANAGED_PATHS[@]} > 1 )) || die "SHA256SUMS contains no runtime files"
    for required in VERSION lib/common.sh bin/mainframe get-mainframe.sh scripts/upgrade-release.sh; do
        manifest_contains "$required" || die "SHA256SUMS omits required runtime path: $required"
    done

    for ((line_number = 1; line_number < ${#LOADED_MANAGED_PATHS[@]}; line_number++)); do
        relative="${LOADED_MANAGED_PATHS[$line_number]}"
        expected="${LOADED_MANAGED_HASHES[$line_number]}"
        path="$root/$relative"
        [[ -f "$path" && ! -L "$path" ]] || die "Managed runtime file is missing or non-regular: $relative"
        path_has_symlink_ancestor "$root" "$relative" && \
            die "Managed runtime path has a symbolic-link ancestor: $relative"
        actual="$(sha256_file "$path")" || die "No SHA-256 implementation is available"
        [[ "$actual" == "$expected" ]] || die "Managed runtime file was modified: $relative"
    done

    if [[ "$require_exact" == "true" ]]; then
        paths_file="$(mktemp "${TMPDIR:-/tmp}/mainframe-manifest-paths.XXXXXX")"
        if ! find "$root" -xdev -mindepth 1 -print0 > "$paths_file"; then
            rm -f -- "$paths_file"
            die "Could not enumerate the staged payload"
        fi
        while IFS= read -r -d '' path; do
            relative="${path#"$root/"}"
            [[ "$relative" != "$path" ]] || die "Could not derive staged payload path"
            relative_path_is_safe "$relative" || die "Staged payload contains an unsafe path: $relative"
            if [[ -L "$path" ]]; then
                die "Staged payload contains a symbolic link: $relative"
            elif [[ -d "$path" ]]; then
                continue
            elif [[ -f "$path" ]]; then
                case "$relative" in
                    SHA256SUMS) continue ;;
                esac
                manifest_contains "$relative" || die "Staged payload file is absent from SHA256SUMS: $relative"
            else
                die "Staged payload contains a special file: $relative"
            fi
        done < "$paths_file"
        rm -f -- "$paths_file"
    fi
}

read_single_line() {
    local file="$1" value
    value="$(awk 'NR == 1 { print; next } { exit 2 }' "$file")" || return 1
    printf '%s\n' "$value"
}

validate_checksum_record() {
    local checksum_file="$1" expected_name="$2"
    local line line_count digest
    line_count="$(awk 'END { print NR + 0 }' "$checksum_file")" || return 1
    [[ "$line_count" == "1" ]] || die "Release checksum must contain exactly one record"
    IFS= read -r line < "$checksum_file" || [[ -n "$line" ]]
    digest="${line%% *}"
    if [[ ${#digest} -ne 64 || "$digest" == *[!0-9a-f]* ]]; then
        die "Release checksum is not a lowercase SHA-256 record"
    fi
    [[ "$line" == "$digest  $expected_name" ]] || \
        die "Release checksum does not name the exact asset: $expected_name"
    printf '%s\n' "$digest"
}

archive_member_is_safe() {
    local member="$1"
    case "$member" in
        ""|.|..|/*|./*|../*|*/./*|*/.|*/../*|*/..|*//*|-*) return 1 ;;
    esac
    case "$member" in
        *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/@+=-]*) return 1 ;;
    esac
    return 0
}

validate_release_archive() {
    local archive="$1" members_file="$2" verbose_file="$3"
    local member listing entry_type member_count=0 verbose_count=0
    local has_version=0 has_installer=0 has_cli=0 has_manifest=0 has_upgrader=0

    env -u TAR_OPTIONS tar -tzf "$archive" > "$members_file" || \
        die "Release asset is not a readable gzip-compressed archive"
    env -u TAR_OPTIONS tar -tvzf "$archive" > "$verbose_file" || \
        die "Release archive metadata could not be inspected"
    while IFS= read -r member || [[ -n "$member" ]]; do
        member_count=$((member_count + 1))
        archive_member_is_safe "$member" || die "Release archive contains an unsafe member path: $member"
        case "$member" in
            "$RECEIPT_NAME") die "Release archive must not contain a machine-local install receipt" ;;
            VERSION) has_version=1 ;;
            install.sh) has_installer=1 ;;
            bin/mainframe) has_cli=1 ;;
            SHA256SUMS) has_manifest=1 ;;
            scripts/upgrade-release.sh) has_upgrader=1 ;;
        esac
    done < "$members_file"
    (( member_count > 0 )) || die "Release archive is empty"
    awk '!seen[$0]++ { next } { exit 1 }' "$members_file" || \
        die "Release archive contains duplicate member paths"

    while IFS= read -r listing || [[ -n "$listing" ]]; do
        verbose_count=$((verbose_count + 1))
        entry_type="${listing%"${listing#?}"}"
        case "$entry_type" in
            -|d) ;;
            *) die "Release archive links and special entries are not allowed" ;;
        esac
    done < "$verbose_file"
    [[ "$verbose_count" -eq "$member_count" ]] || die "Release archive member metadata is ambiguous"
    (( has_version && has_installer && has_cli && has_manifest && has_upgrader )) || \
        die "Release archive is missing a required runtime or upgrade file"
}

canonical_existing_root() {
    local requested="$1" parent base canonical home_root=""
    [[ -n "$requested" ]] || return 1
    [[ "$requested" == /* ]] || requested="$PWD/$requested"
    while [[ "$requested" != "/" && "$requested" == */ ]]; do requested="${requested%/}"; done
    parent="$(dirname "$requested")"
    base="$(basename "$requested")"
    [[ "$base" != "." && "$base" != ".." && -d "$parent" ]] || return 1
    canonical="$(cd "$parent" && pwd -P)/$base"
    [[ -d "$canonical" && ! -L "$canonical" ]] || return 1
    if [[ -n "${HOME:-}" && -d "$HOME" ]]; then
        home_root="$(cd "$HOME" && pwd -P)"
    fi
    case "$canonical" in
        ""|/|"$home_root") return 1 ;;
    esac
    printf '%s\n' "$canonical"
}

load_receipt() {
    local root="$1" mode root_mode manifest_digest
    local receipt="$root/$RECEIPT_NAME"

    [[ -f "$receipt" && ! -L "$receipt" ]] || \
        die "This installation has no regular release receipt; reinstall one verified release before using transactional upgrade"
    root_mode="$(path_mode "$root")"
    [[ "$root_mode" == "700" ]] || \
        die "Receipt-backed install root must have private mode 700 (found ${root_mode:-unknown})"
    mode="$(path_mode "$receipt")"
    [[ "$mode" == "600" ]] || die "Release receipt must have mode 600: $receipt"
    jq -e '
      type == "object" and
      (keys | sort) == ["archive_sha256", "bin_dir", "cli_link", "install_dir", "install_method", "installed_at", "manifest_sha256", "schema_version", "version"] and
      .schema_version == 1 and .install_method == "release-archive" and
      (.version | type == "string" and test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")) and
      (.archive_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      (.manifest_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      (.install_dir | type == "string" and startswith("/") and (test("[[:cntrl:]]") | not)) and
      (.bin_dir | type == "string" and startswith("/") and (test("[[:cntrl:]]") | not)) and
      (.cli_link | type == "string" and startswith("/") and (test("[[:cntrl:]]") | not)) and
      (.installed_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    ' "$receipt" >/dev/null || die "Release receipt is malformed or has unsupported fields"

    RECEIPT_VERSION="$(jq -r '.version' "$receipt")"
    RECEIPT_MANIFEST_SHA="$(jq -r '.manifest_sha256' "$receipt")"
    RECEIPT_INSTALL_DIR="$(jq -r '.install_dir' "$receipt")"
    RECEIPT_BIN_DIR="$(jq -r '.bin_dir' "$receipt")"
    RECEIPT_CLI_LINK="$(jq -r '.cli_link' "$receipt")"
    [[ "$RECEIPT_INSTALL_DIR" == "$root" ]] || die "Release receipt install path does not match the active runtime"
    [[ -d "$RECEIPT_BIN_DIR" && ! -L "$RECEIPT_BIN_DIR" ]] || die "Receipt bin directory is missing or symbolic-linked"
    [[ "$RECEIPT_CLI_LINK" == "$RECEIPT_BIN_DIR/mainframe" ]] || die "Release receipt CLI path does not match its bin directory"
    [[ -L "$RECEIPT_CLI_LINK" ]] || die "Receipt bin directory does not contain the owned MAINFRAME symlink"
    [[ "$(readlink "$RECEIPT_CLI_LINK")" == "$root/bin/mainframe" ]] || \
        die "Installed CLI symlink no longer targets this MAINFRAME runtime"
    manifest_digest="$(sha256_file "$root/SHA256SUMS")" || die "No SHA-256 implementation is available"
    [[ "$manifest_digest" == "$RECEIPT_MANIFEST_SHA" ]] || die "Installed SHA256SUMS no longer matches the release receipt"
}

write_receipt() {
    local root="$1" version="$2" archive_sha="$3" bin_dir="$4"
    local manifest_sha tmp
    local receipt="$root/$RECEIPT_NAME"
    manifest_sha="$(sha256_file "$root/SHA256SUMS")" || die "Could not hash the staged SHA256SUMS"
    tmp="$(mktemp "$root/.mainframe-install-receipt.XXXXXX")"
    jq -n \
        --arg version "$version" \
        --arg archive_sha256 "$archive_sha" \
        --arg manifest_sha256 "$manifest_sha" \
        --arg install_dir "$MAINFRAME_ROOT" \
        --arg bin_dir "$bin_dir" \
        --arg cli_link "$bin_dir/mainframe" \
        --arg installed_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '{schema_version: 1, install_method: "release-archive", version: $version,
          archive_sha256: $archive_sha256, manifest_sha256: $manifest_sha256,
          install_dir: $install_dir, bin_dir: $bin_dir, cli_link: $cli_link,
          installed_at: $installed_at}' > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$receipt"
}

build_state_inventory() {
    local root="$1" output="$2" path relative type mode digest
    local unsorted="$output.unsorted"
    local paths_file="$output.paths"
    local root_device path_device_value
    STATE_PATHS=("")
    STATE_TYPES=("")
    STATE_MODES=("")
    STATE_HASHES=("")
    : > "$unsorted"

    root_device="$(path_device "$root")"
    [[ -n "$root_device" ]] || die "Could not identify the install filesystem"
    if ! find "$root" -xdev -mindepth 1 -print0 > "$paths_file"; then
        rm -f -- "$paths_file" "$unsorted"
        die "Could not enumerate in-root state"
    fi

    while IFS= read -r -d '' path; do
        relative="${path#"$root/"}"
        [[ "$relative" != "$path" ]] || die "Could not derive state path"
        relative_path_is_safe "$relative" || die "In-root state contains an unsafe path: $relative"
        case "$relative" in
            SHA256SUMS|"$RECEIPT_NAME") continue ;;
        esac
        path_device_value="$(path_device "$path")"
        [[ -n "$path_device_value" ]] || die "Could not identify state filesystem: $relative"
        [[ "$path_device_value" == "$root_device" ]] || \
            die "In-root state crosses a nested mount; unmount it before upgrade: $relative"
        if [[ -L "$path" ]]; then
            die "In-root state contains a symbolic link; move it outside the install root before upgrade: $relative"
        elif [[ -d "$path" ]]; then
            current_directory_is_managed_structure "$relative" && continue
            current_path_is_inside_managed_structure "$relative" && \
                die "Unmanaged state is inside a managed runtime surface: $relative"
            type=directory
            digest=-
        elif [[ -f "$path" ]]; then
            current_manifest_contains "$relative" && continue
            current_path_is_inside_managed_structure "$relative" && \
                die "Unmanaged state is inside a managed runtime surface: $relative"
            [[ ! -x "$path" ]] || \
                die "Unmanaged executable state is not eligible for automatic preservation: $relative"
            type="file"
            digest="$(sha256_file "$path")" || die "Could not hash in-root state: $relative"
        else
            die "In-root state contains a special file; stop its owner or move it before upgrade: $relative"
        fi
        mode="$(path_mode "$path")"
        [[ "$mode" =~ ^[0-7]{3,4}$ ]] || die "Could not read state permissions: $relative"
        STATE_PATHS+=("$relative")
        STATE_TYPES+=("$type")
        STATE_MODES+=("$mode")
        STATE_HASHES+=("$digest")
        printf '%s\t%s\t%s\t%s\n' "$type" "$mode" "$digest" "$relative" >> "$unsorted"
    done < "$paths_file"
    LC_ALL=C sort "$unsorted" > "$output"
    rm -f -- "$unsorted" "$paths_file"
}

preflight_state_collisions() {
    local staged_root="$1" index relative target parent
    for ((index = 1; index < ${#STATE_PATHS[@]}; index++)); do
        relative="${STATE_PATHS[$index]}"
        target="$staged_root/$relative"
        if [[ "${STATE_TYPES[$index]}" == "directory" ]]; then
            [[ ! -e "$target" && ! -L "$target" ]] || \
                die "State directory collides with a new runtime path: $relative"
        else
            [[ ! -e "$target" && ! -L "$target" ]] || \
                die "State file collides with a new runtime path: $relative"
            parent="$(dirname "$target")"
            while [[ "$parent" != "$staged_root" ]]; do
                if [[ -e "$parent" || -L "$parent" ]]; then
                    [[ -d "$parent" && ! -L "$parent" ]] || \
                        die "State path has a new-runtime parent collision: $relative"
                fi
                parent="$(dirname "$parent")"
            done
        fi
    done
}

copy_state_snapshot() {
    local source_root="$1" staged_root="$2" index relative source target mode actual
    for ((index = 1; index < ${#STATE_PATHS[@]}; index++)); do
        relative="${STATE_PATHS[$index]}"
        source="$source_root/$relative"
        target="$staged_root/$relative"
        mode="${STATE_MODES[$index]}"
        if [[ "${STATE_TYPES[$index]}" == "directory" ]]; then
            mkdir -p "$target"
            chmod "$mode" "$target"
        else
            mkdir -p "$(dirname "$target")"
            cp -p "$source" "$target"
            actual="$(sha256_file "$target")" || die "Could not verify staged state: $relative"
            [[ "$actual" == "${STATE_HASHES[$index]}" ]] || die "Staged state copy mismatch: $relative"
        fi
    done
}

write_journal() {
    local state="$1" tmp
    tmp="$(mktemp "$(dirname "$JOURNAL")/.mainframe-upgrade-journal.XXXXXX")"
    jq -n \
        --arg state "$state" --arg install_dir "$MAINFRAME_ROOT" \
        --arg transaction_dir "$TRANSACTION_DIR" --arg backup_dir "$BACKUP_DIR" \
        --arg failed_dir "$FAILED_DIR" --arg workspace_dir "$WORKSPACE" \
        --arg staged_dir "$STAGED_ROOT" --arg recovery_script "$RECOVERY_SCRIPT" \
        --arg staged_identity "$STAGED_IDENTITY" --arg current_identity "$CURRENT_ROOT_IDENTITY" \
        --arg current_version "$CURRENT_VERSION" --arg target_version "$TARGET_VERSION" \
        '{schema_version: 2, state: $state, install_dir: $install_dir,
          transaction_dir: $transaction_dir, backup_dir: $backup_dir,
          failed_dir: $failed_dir, workspace_dir: $workspace_dir,
          staged_dir: $staged_dir, staged_identity: $staged_identity,
          current_identity: $current_identity,
          recovery_script: $recovery_script,
          current_version: $current_version, target_version: $target_version}' > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$JOURNAL"
    durability_barrier
}

cleanup_lock() {
    local owner_pid=""
    if [[ "$LOCK_OWNED" == "true" && -f "$LOCK_DIR" && ! -L "$LOCK_DIR" ]]; then
        owner_pid="$(read_single_line "$LOCK_DIR" 2>/dev/null || true)"
        if [[ "$owner_pid" == "$$" ]]; then rm -f -- "$LOCK_DIR"; fi
    fi
    LOCK_OWNED=false
}

acquire_lock() {
    local allow_stale="${1:-false}" owner_pid="" owner_tmp="" cleanup_guard mode _attempt
    local owner_identity="" lock_identity="" link_status=1
    cleanup_guard="$LOCK_DIR.cleanup"

    for _attempt in 1 2 3; do
        owner_tmp="$(mktemp "$(dirname "$LOCK_DIR")/.mainframe-upgrade-owner.XXXXXX")"
        printf '%s\n' "$$" > "$owner_tmp"
        chmod 600 "$owner_tmp"
        owner_identity="$(path_identity "$owner_tmp")"
        [[ -n "$owner_identity" ]] || die "Could not identify the prepared upgrade-lock owner record"
        link_status=1
        if ln "$owner_tmp" "$LOCK_DIR" 2>/dev/null; then link_status=0; fi
        if [[ "$link_status" -eq 0 ]]; then
            lock_identity="$(path_identity "$LOCK_DIR")"
            if [[ -f "$LOCK_DIR" && ! -L "$LOCK_DIR" && \
                  -n "$lock_identity" && "$lock_identity" == "$owner_identity" ]]; then
                rm -f -- "$owner_tmp"
                LOCK_OWNED=true
                return
            fi
            rm -f -- "$owner_tmp"
            die "Upgrade lock publication did not create the exact regular lock path: $LOCK_DIR"
        fi
        rm -f -- "$owner_tmp"

        [[ -f "$LOCK_DIR" && ! -L "$LOCK_DIR" ]] || \
            die "Upgrade lock is not a regular file: $LOCK_DIR"
        mode="$(path_mode "$LOCK_DIR")"
        [[ "$mode" == "600" ]] || die "Upgrade lock has unsafe mode: $LOCK_DIR"
        owner_pid="$(read_single_line "$LOCK_DIR" 2>/dev/null || true)"
        [[ "$owner_pid" =~ ^[1-9][0-9]*$ ]] || die "Upgrade lock owner is malformed: $LOCK_DIR"
        if kill -0 "$owner_pid" 2>/dev/null; then
            die "Upgrade process $owner_pid still owns the lock"
        fi

        # Serialize dead-owner reclamation. This guard is never auto-broken;
        # a crash in this tiny recovery window therefore fails closed.
        mkdir "$cleanup_guard" 2>/dev/null || \
            die "Another process is inspecting the stale upgrade lock: $cleanup_guard"
        if [[ -f "$LOCK_DIR" && ! -L "$LOCK_DIR" && \
              "$(read_single_line "$LOCK_DIR" 2>/dev/null || true)" == "$owner_pid" ]] && \
           ! kill -0 "$owner_pid" 2>/dev/null; then
            rm -f -- "$LOCK_DIR"
            if [[ "$allow_stale" != "true" ]]; then
                warn "Clearing a crash-orphaned upgrade lock; staged directories are retained for inspection"
            fi
        fi
        rmdir "$cleanup_guard" 2>/dev/null || \
            die "Could not release stale-lock inspection guard: $cleanup_guard"
    done
    die "Could not acquire upgrade lock after stale-owner recovery"
}

cleanup_workspace() {
    local parent base
    [[ -n "$WORKSPACE" && -d "$WORKSPACE" ]] || return 0
    parent="$(dirname "$MAINFRAME_ROOT")"
    base="$(basename "$MAINFRAME_ROOT")"
    case "$WORKSPACE" in
        "$parent/.${base}.upgrade-stage."*) rm -rf -- "$WORKSPACE" ;;
        *) warn "Leaving unexpected workspace path unchanged: $WORKSPACE" ;;
    esac
}

cleanup_on_exit() {
    local status=$?
    local rollback_ok=true candidate_path="" candidate_destination=""
    local backup_identity="" restored_identity="" nested_backup=""
    trap - EXIT
    set +e
    if [[ "$status" -ne 0 && "$BACKUP_OWNED" == "true" && -n "$BACKUP_DIR" ]] && \
       directory_matches_identity "$BACKUP_DIR" "$CURRENT_ROOT_IDENTITY"; then
        backup_identity="$(path_identity "$BACKUP_DIR")"
        if [[ "$ACTIVE_CANDIDATE_OWNED" == "true" ]] && \
           directory_matches_identity "$MAINFRAME_ROOT" "$STAGED_IDENTITY"; then
            candidate_path="$MAINFRAME_ROOT"
            candidate_destination="$FAILED_DIR"
        elif [[ "$PLACEMENT_IN_PROGRESS" == "true" ]] && \
             directory_matches_identity "$MAINFRAME_ROOT" "$STAGED_IDENTITY"; then
            candidate_path="$MAINFRAME_ROOT"
            candidate_destination="$FAILED_DIR"
        elif [[ -n "$MISPLACED_CANDIDATE" ]] && \
             directory_matches_identity "$MISPLACED_CANDIDATE" "$STAGED_IDENTITY"; then
            candidate_path="$MISPLACED_CANDIDATE"
            candidate_destination="$MISPLACED_CANDIDATE_DIR"
        fi
        if [[ -n "$candidate_path" ]]; then
            if [[ ! -e "$candidate_destination" && ! -L "$candidate_destination" ]]; then
                mv -- "$candidate_path" "$candidate_destination" || rollback_ok=false
            else
                rollback_ok=false
                warn "Automatic rollback destination already exists: $candidate_destination"
            fi
        fi
        if [[ -e "$MAINFRAME_ROOT" || -L "$MAINFRAME_ROOT" ]]; then
            rollback_ok=false
            warn "Install path no longer contains the transaction-owned candidate; leaving it untouched"
        fi
        if [[ "$rollback_ok" == "true" && ! -e "$MAINFRAME_ROOT" && ! -L "$MAINFRAME_ROOT" ]]; then
            mv -- "$BACKUP_DIR" "$MAINFRAME_ROOT" || rollback_ok=false
            if [[ "$rollback_ok" == "true" ]] && \
               ! directory_matches_identity "$MAINFRAME_ROOT" "$backup_identity"; then
                nested_backup="$MAINFRAME_ROOT/$(basename "$BACKUP_DIR")"
                if directory_matches_identity "$nested_backup" "$backup_identity" && \
                   [[ ! -e "$BACKUP_DIR" && ! -L "$BACKUP_DIR" ]]; then
                    mv -- "$nested_backup" "$BACKUP_DIR" || true
                fi
                rollback_ok=false
                warn "Rollback placement did not restore the exact backup directory; no runtime code was executed"
            fi
        fi
        if [[ "$rollback_ok" == "true" ]]; then
            restored_identity="$(path_identity "$MAINFRAME_ROOT")"
            sync >/dev/null 2>&1 || warn "Rollback completed but its durability barrier failed"
            if (
                set -e
                directory_matches_identity "$MAINFRAME_ROOT" "$restored_identity"
                load_receipt "$MAINFRAME_ROOT"
                load_and_verify_manifest "$MAINFRAME_ROOT" false
                [[ "$(read_single_line "$MAINFRAME_ROOT/VERSION")" == "$CURRENT_VERSION" ]]
                directory_matches_identity "$MAINFRAME_ROOT" "$restored_identity"
                verify_runtime_health "$MAINFRAME_ROOT" "$CURRENT_VERSION"
                directory_matches_identity "$MAINFRAME_ROOT" "$restored_identity"
            ) >/dev/null 2>&1; then
                warn "Interrupted upgrade restored and verified the previous installation"
                rm -f -- "$JOURNAL"
                sync >/dev/null 2>&1 || warn "Journal removal durability barrier failed"
            else
                rollback_ok=false
                warn "The previous directory was restored but failed integrity or health verification; journal retained for recovery"
            fi
        else
            warn "Automatic rollback failed; use the printed recovery command and keep the transaction directory intact"
        fi
    fi
    if [[ "$rollback_ok" == "true" ]]; then cleanup_workspace; fi
    cleanup_lock
    exit "$status"
}

run_failpoint() {
    local name="$1"
    if [[ -n "${MAINFRAME_UPGRADE_FAILPOINT:-}" && \
          "$INTERNAL_TESTING_AUTHORIZED" != "true" ]]; then
        die "Upgrade failpoints are disabled outside a private internal-test fixture"
    fi
    case "${MAINFRAME_UPGRADE_FAILPOINT:-}" in
        "$name") die "Injected upgrade failure at $name" ;;
        "kill-$name") kill -KILL "$$" ;;
    esac
}

internal_testing_enabled() {
    local marker="$MAINFRAME_ROOT/.mainframe-internal-test-mode" expected
    [[ "${MAINFRAME_INTERNAL_TESTING:-}" == "1" ]] || return 1
    current_manifest_contains ".mainframe-internal-test-mode" || return 1
    [[ -f "$marker" && ! -L "$marker" && "$(path_mode "$marker")" == "600" ]] || return 1
    expected="MAINFRAME_INTERNAL_TESTING:$MAINFRAME_ROOT"
    [[ "$(read_single_line "$marker" 2>/dev/null || true)" == "$expected" ]]
}

absolute_path_is_safe() {
    local path="$1"
    [[ "$path" == /* && "$path" != "/" && "$path" != *$'\n'* && \
       "$path" != *$'\r'* && "$path" != *$'\t'* ]]
}

canonical_regular_file() {
    local requested="$1" parent base
    parent="$(dirname "$requested")"
    base="$(basename "$requested")"
    [[ -d "$parent" ]] || return 1
    parent="$(cd "$parent" && pwd -P)" || return 1
    requested="$parent/$base"
    [[ -f "$requested" && ! -L "$requested" ]] || return 1
    printf '%s\n' "$requested"
}

recover_interrupted_upgrade() {
    local journal install_dir install_dir_raw parent requested_parent base expected_journal mode state
    local transaction_dir transaction_dir_raw backup_dir failed_dir workspace_dir workspace_dir_raw staged_dir recovery_script
    local staged_identity current_identity
    local current_version target_version recovered_journal timestamp active_version home_root=""
    local backup_identity="" active_identity="" restored_identity="" nested_backup=""

    for required_command in jq awk mv chmod mkdir rm rmdir mktemp ln sync; do
        command -v "$required_command" >/dev/null 2>&1 || \
            die "Required recovery command is unavailable: $required_command"
    done

    if [[ -z "$RECOVERY_JOURNAL" ]]; then
        MAINFRAME_ROOT="$(canonical_existing_root "$MAINFRAME_ROOT")" || \
            die "--journal PATH is required when the canonical install root is absent"
        parent="$(dirname "$MAINFRAME_ROOT")"
        base="$(basename "$MAINFRAME_ROOT")"
        RECOVERY_JOURNAL="$parent/.${base}.upgrade-journal.json"
    fi
    absolute_path_is_safe "$RECOVERY_JOURNAL" || die "Recovery journal path is unsafe"
    journal="$(canonical_regular_file "$RECOVERY_JOURNAL")" || \
        die "Recovery journal is missing, non-regular, or symbolic-linked: $RECOVERY_JOURNAL"
    mode="$(path_mode "$journal")"
    [[ "$mode" == "600" ]] || die "Recovery journal must have mode 600: $journal"

    jq -e '
      type == "object" and
      (keys | sort) == ["backup_dir", "current_identity", "current_version", "failed_dir", "install_dir", "recovery_script", "schema_version", "staged_dir", "staged_identity", "state", "target_version", "transaction_dir", "workspace_dir"] and
      .schema_version == 2 and
      (.state == "prepared" or .state == "old-moved" or .state == "new-active") and
      ([.install_dir, .transaction_dir, .backup_dir, .failed_dir, .workspace_dir, .staged_dir, .recovery_script] |
        all(type == "string" and startswith("/") and (test("[[:cntrl:]]") | not))) and
      ([.current_version, .target_version] |
        all(type == "string" and test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))) and
      ([.staged_identity, .current_identity] |
        all(type == "string" and test("^[0-9]+:[0-9]+$")))
    ' "$journal" >/dev/null || die "Recovery journal is malformed or has unsupported fields"

    state="$(jq -r '.state' "$journal")"
    install_dir_raw="$(jq -r '.install_dir' "$journal")"
    transaction_dir_raw="$(jq -r '.transaction_dir' "$journal")"
    backup_dir="$(jq -r '.backup_dir' "$journal")"
    failed_dir="$(jq -r '.failed_dir' "$journal")"
    workspace_dir_raw="$(jq -r '.workspace_dir' "$journal")"
    staged_dir="$(jq -r '.staged_dir' "$journal")"
    staged_identity="$(jq -r '.staged_identity' "$journal")"
    current_identity="$(jq -r '.current_identity' "$journal")"
    recovery_script="$(jq -r '.recovery_script' "$journal")"
    current_version="$(jq -r '.current_version' "$journal")"
    target_version="$(jq -r '.target_version' "$journal")"

    requested_parent="$(dirname "$install_dir_raw")"
    base="$(basename "$install_dir_raw")"
    parent="$requested_parent"
    [[ "$base" != "." && "$base" != ".." && -d "$parent" ]] || die "Recovery install path is unsafe"
    parent="$(cd "$parent" && pwd -P)" || die "Recovery install parent is unavailable"
    install_dir="$parent/$base"
    [[ "$install_dir_raw" == "$install_dir" ]] || \
        die "Recovery install path is not canonical or has a symbolic-link ancestor"
    if [[ -n "${HOME:-}" && -d "$HOME" ]]; then
        home_root="$(cd "$HOME" && pwd -P)"
    fi
    case "$install_dir" in
        ""|/|"$home_root") die "Recovery install path is an unsafe broad target" ;;
    esac
    expected_journal="$parent/.${base}.upgrade-journal.json"
    [[ "$journal" == "$expected_journal" ]] || die "Recovery journal is not owned by its install path"
    transaction_dir="$(canonical_existing_root "$transaction_dir_raw")" || \
        die "Recovery transaction directory is missing or unsafe"
    [[ "$transaction_dir" == "$transaction_dir_raw" && "$(dirname "$transaction_dir")" == "$parent" ]] || \
        die "Recovery transaction path is not canonical or sibling-owned"
    case "$(basename "$transaction_dir")" in
        ".${base}.upgrade-transaction."*) ;;
        *) die "Recovery transaction path is outside the owned sibling namespace" ;;
    esac
    [[ "$backup_dir" == "$transaction_dir/previous" ]] || die "Recovery backup path is not transaction-owned"
    [[ "$failed_dir" == "$transaction_dir/failed-candidate" ]] || die "Recovery failed-candidate path is not transaction-owned"
    [[ "$recovery_script" == "$transaction_dir/recover-upgrade.sh" ]] || die "Recovery entrypoint is malformed"
    if [[ -e "$recovery_script" || -L "$recovery_script" ]]; then
        [[ -f "$recovery_script" && ! -L "$recovery_script" ]] || die "Recorded recovery entrypoint is unsafe"
    else
        warn "Recorded recovery entrypoint is absent; continuing with the explicitly invoked updater"
    fi

    [[ "$(dirname "$workspace_dir_raw")" == "$parent" ]] || \
        die "Recovery workspace path is not sibling-owned"
    case "$(basename "$workspace_dir_raw")" in
        ".${base}.upgrade-stage."*) ;;
        *) die "Recovery workspace path is outside the owned sibling namespace" ;;
    esac
    workspace_dir="$workspace_dir_raw"
    if [[ -e "$workspace_dir" || -L "$workspace_dir" ]]; then
        [[ "$(canonical_existing_root "$workspace_dir")" == "$workspace_dir" ]] || \
            die "Recovery workspace path is not canonical or is symbolic-linked"
    else
        warn "Recorded staging workspace is absent; the transaction backup remains sufficient for rollback"
    fi
    [[ "$staged_dir" == "$workspace_dir/runtime" ]] || die "Recovery staged path is malformed"
    if [[ -e "$install_dir" || -L "$install_dir" ]]; then
        [[ -d "$install_dir" && ! -L "$install_dir" ]] || die "Recovery install path is not a regular directory"
    fi
    if [[ -e "$backup_dir" || -L "$backup_dir" ]]; then
        [[ -d "$backup_dir" && ! -L "$backup_dir" ]] || die "Recovery backup is not a regular directory"
        directory_matches_identity "$backup_dir" "$current_identity" || \
            die "Recovery backup does not match the transaction-owned previous runtime"
    fi

    MAINFRAME_ROOT="$install_dir"
    LOCK_DIR="$parent/.${base}.upgrade.lock"
    acquire_lock true
    trap cleanup_lock EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    info "Recovering interrupted $current_version -> $target_version transaction (journal state: $state)"
    if [[ -d "$backup_dir" && ! -L "$backup_dir" ]]; then
        backup_identity="$(path_identity "$backup_dir")"
        [[ -n "$backup_identity" ]] || die "Could not identify the recovery backup directory"
        if [[ -e "$install_dir" || -L "$install_dir" ]]; then
            directory_matches_identity "$install_dir" "$staged_identity" || \
                die "Active install path does not match the transaction-owned candidate; leaving it untouched"
            [[ ! -e "$failed_dir" && ! -L "$failed_dir" ]] || \
                die "Cannot preserve the active candidate because $failed_dir already exists"
            active_identity="$(path_identity "$install_dir")"
            [[ -n "$active_identity" ]] || die "Could not identify the active recovery candidate"
            mv -- "$install_dir" "$failed_dir"
            directory_matches_identity "$failed_dir" "$active_identity" || \
                die "Recovery could not preserve the exact active candidate"
        fi
        [[ ! -e "$install_dir" && ! -L "$install_dir" ]] || \
            die "Recovery install path was recreated before backup placement; leaving it untouched"
        mv -- "$backup_dir" "$install_dir"
        if ! directory_matches_identity "$install_dir" "$backup_identity"; then
            nested_backup="$install_dir/$(basename "$backup_dir")"
            if directory_matches_identity "$nested_backup" "$backup_identity" && \
               [[ ! -e "$backup_dir" && ! -L "$backup_dir" ]]; then
                mv -- "$nested_backup" "$backup_dir" || true
            fi
            die "Recovery did not restore the exact backup directory; no runtime code was executed"
        fi
        restored_identity="$backup_identity"
        durability_barrier
        info "Restored the previous runtime and preserved any active candidate in $failed_dir"
    elif [[ -d "$install_dir" && ! -L "$install_dir" ]]; then
        directory_matches_identity "$install_dir" "$current_identity" || \
            die "Active install path does not match the transaction-owned previous runtime; leaving it untouched"
        restored_identity="$(path_identity "$install_dir")"
        [[ -n "$restored_identity" ]] || die "Could not identify the recovered runtime directory"
        info "The previous runtime is already present; no directory move was required"
    else
        die "Neither a recoverable backup nor an active install root exists"
    fi

    directory_matches_identity "$install_dir" "$restored_identity" || \
        die "Recovered runtime identity changed before verification"
    load_receipt "$install_dir"
    load_and_verify_manifest "$install_dir" false
    active_version="$(read_single_line "$install_dir/VERSION")" || \
        die "Recovered VERSION must contain exactly one line"
    [[ "$active_version" == "$current_version" ]] || \
        die "Recovered runtime version is $active_version, expected $current_version"
    directory_matches_identity "$install_dir" "$restored_identity" || \
        die "Recovered runtime identity changed before health verification"
    verify_runtime_health "$install_dir" "$current_version"
    directory_matches_identity "$install_dir" "$restored_identity" || \
        die "Recovered runtime identity changed during health verification"

    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    recovered_journal="$(next_available_path "$journal.recovered-$timestamp")"
    mv -- "$journal" "$recovered_journal"
    durability_barrier
    info "Recovery verified MAINFRAME v$current_version"
    info "Retained recovery evidence: $recovered_journal"
    info "Retained transaction directory: $transaction_dir"
    cleanup_lock
    trap - EXIT
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                [[ $# -ge 2 && -n "$2" ]] || die "--version requires X.Y.Z"
                [[ -z "$TARGET_VERSION" ]] || die "--version may be passed only once"
                TARGET_VERSION="$2"
                shift 2
                ;;
            --version=*)
                [[ -z "$TARGET_VERSION" ]] || die "--version may be passed only once"
                TARGET_VERSION="${1#*=}"
                shift
                ;;
            --allow-downgrade) ALLOW_DOWNGRADE=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --confirm-agents-stopped) CONFIRM_AGENTS_STOPPED=true; shift ;;
            --recover) RECOVER=true; shift ;;
            --journal)
                [[ $# -ge 2 && -n "$2" ]] || die "--journal requires an absolute path"
                [[ -z "$RECOVERY_JOURNAL" ]] || die "--journal may be passed only once"
                RECOVERY_JOURNAL="$2"
                shift 2
                ;;
            --journal=*)
                [[ -z "$RECOVERY_JOURNAL" ]] || die "--journal may be passed only once"
                RECOVERY_JOURNAL="${1#*=}"
                shift
                ;;
            -h|--help) show_help; exit 0 ;;
            *) die "Unknown upgrade option: $1" ;;
        esac
    done
    if [[ "$RECOVER" == "true" ]]; then
        [[ -z "$TARGET_VERSION" && "$ALLOW_DOWNGRADE" == "false" && "$DRY_RUN" == "false" && \
           "$CONFIRM_AGENTS_STOPPED" == "false" ]] || \
            die "--recover cannot be combined with version, downgrade, dry-run, or quiescence options"
        return
    fi
    [[ -z "$RECOVERY_JOURNAL" ]] || die "--journal is valid only with --recover"
    [[ -n "$TARGET_VERSION" ]] || die "An explicit --version X.Y.Z is required"
    is_stable_semver "$TARGET_VERSION" || die "Upgrade version must be stable SemVer: $TARGET_VERSION"
}

verify_runtime_health() {
    local root="$1" expected_version="$2" reported_version version_output

    [[ -x "$root/bin/mainframe" && ! -L "$root/bin/mainframe" ]] || \
        die "Runtime CLI is not a regular executable: $root/bin/mainframe"
    version_output="$(env MAINFRAME_VERSION= MAINFRAME_ROOT="$root" \
        "$BASH" "$root/bin/mainframe" version)" || \
        die "Runtime version command failed for v$expected_version"
    reported_version="${version_output%%$'\n'*}"
    [[ "$reported_version" == "MAINFRAME v$expected_version" ]] || \
        die "Runtime reported '$reported_version' instead of MAINFRAME v$expected_version"
    env MAINFRAME_VERSION= MAINFRAME_ROOT="$root" \
        "$BASH" "$root/bin/mainframe" doctor >/dev/null 2>&1 || \
        die "Runtime doctor failed for v$expected_version"
}

main() {
    local parent base comparison asset_name release_url archive checksum_file
    local members_file verbose_file expected_sha actual_sha embedded_version
    local before_inventory after_inventory backup_inventory state_files=0 state_dirs=0 index
    local copied_sha source_sha current_root_mode nested_backup nested_restore
    local -a curl_args=(--disable -fsSL)

    parse_args "$@"
    if [[ "$RECOVER" == "true" ]]; then
        recover_interrupted_upgrade
        return
    fi
    for required_command in env curl tar jq find awk sort cmp mktemp mv cp chmod ln sync; do
        command -v "$required_command" >/dev/null 2>&1 || die "Required command is unavailable: $required_command"
    done
    MAINFRAME_ROOT="$(canonical_existing_root "$MAINFRAME_ROOT")" || die "Unsafe or missing MAINFRAME_ROOT"
    CURRENT_ROOT_IDENTITY="$(path_identity "$MAINFRAME_ROOT")"
    [[ -n "$CURRENT_ROOT_IDENTITY" ]] || die "Could not identify the active install root"
    current_root_mode="$(path_mode "$MAINFRAME_ROOT")"
    [[ "$current_root_mode" == "700" ]] || \
        die "Receipt-backed install root must have private mode 700 (found ${current_root_mode:-unknown})"
    parent="$(dirname "$MAINFRAME_ROOT")"
    base="$(basename "$MAINFRAME_ROOT")"
    LOCK_DIR="$parent/.${base}.upgrade.lock"
    JOURNAL="$parent/.${base}.upgrade-journal.json"
    [[ ! -e "$JOURNAL" && ! -L "$JOURNAL" ]] || \
        die "An incomplete upgrade journal exists: $JOURNAL (run mainframe upgrade --recover)"
    acquire_lock false
    trap cleanup_on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    load_receipt "$MAINFRAME_ROOT"
    CURRENT_VERSION="$(read_single_line "$MAINFRAME_ROOT/VERSION")" || die "Installed VERSION must contain exactly one line"
    [[ "$CURRENT_VERSION" == "$RECEIPT_VERSION" ]] || die "Installed VERSION does not match the release receipt"
    load_and_verify_manifest "$MAINFRAME_ROOT" false
    CURRENT_MANAGED_PATHS=("${LOADED_MANAGED_PATHS[@]}")
    CURRENT_UPGRADER_SHA="$(loaded_manifest_hash_for scripts/upgrade-release.sh)" || \
        die "Current manifest does not bind the trusted release upgrader"
    if internal_testing_enabled; then INTERNAL_TESTING_AUTHORIZED=true; fi
    if [[ -n "${MAINFRAME_UPGRADE_FAILPOINT:-}" && \
          "$INTERNAL_TESTING_AUTHORIZED" != "true" ]]; then
        die "Upgrade failpoints are disabled outside a private internal-test fixture"
    fi

    comparison="$(semver_compare "$TARGET_VERSION" "$CURRENT_VERSION")"
    if [[ "$comparison" == "0" ]]; then
        verify_runtime_health "$MAINFRAME_ROOT" "$CURRENT_VERSION"
        info "MAINFRAME v$TARGET_VERSION is already installed"
        exit 0
    fi
    if [[ "$comparison" == "-1" && "$ALLOW_DOWNGRADE" != "true" ]]; then
        die "Refusing downgrade from v$CURRENT_VERSION to v$TARGET_VERSION without --allow-downgrade"
    fi
    if [[ "$DRY_RUN" != "true" && "$CONFIRM_AGENTS_STOPPED" != "true" ]]; then
        die "Stop agents using this installation, then rerun with --confirm-agents-stopped"
    fi

    WORKSPACE="$(mktemp -d "$parent/.${base}.upgrade-stage.XXXXXX")"
    STAGED_ROOT="$WORKSPACE/runtime"
    mkdir -p "$STAGED_ROOT"
    chmod 700 "$STAGED_ROOT"
    asset_name="mainframe-${TARGET_VERSION}.tar.gz"
    if [[ "${MAINFRAME_RELEASE_BASE_URL%/}" != \
          "https://github.com/gtwatts/mainframe/releases/download" && \
          "$INTERNAL_TESTING_AUTHORIZED" != "true" ]]; then
        die "Custom release origins are disabled outside a private manifest-bound internal-test fixture"
    fi
    release_url="${MAINFRAME_RELEASE_BASE_URL%/}/v${TARGET_VERSION}"
    case "$release_url" in
        https://*) curl_args+=(--proto '=https' --tlsv1.2) ;;
        file://*)
            [[ "$INTERNAL_TESTING_AUTHORIZED" == "true" ]] || \
                die "file:// release sources are disabled outside a private internal-test fixture"
            ;;
        *) die "Release base URL must use HTTPS (file:// is reserved for local verification)" ;;
    esac
    archive="$WORKSPACE/$asset_name"
    checksum_file="$archive.sha256"
    members_file="$WORKSPACE/archive-members.txt"
    verbose_file="$WORKSPACE/archive-verbose.txt"

    info "Downloading MAINFRAME v$TARGET_VERSION release archive"
    curl "${curl_args[@]}" "$release_url/$asset_name" -o "$archive"
    curl "${curl_args[@]}" "$release_url/$asset_name.sha256" -o "$checksum_file"
    expected_sha="$(validate_checksum_record "$checksum_file" "$asset_name")"
    actual_sha="$(sha256_file "$archive")" || die "No SHA-256 implementation is available"
    [[ "$actual_sha" == "$expected_sha" ]] || die "Release archive SHA-256 verification failed"
    validate_release_archive "$archive" "$members_file" "$verbose_file"
    env -u TAR_OPTIONS tar -xzf "$archive" -C "$STAGED_ROOT" || \
        die "Verified release archive could not be extracted"
    [[ ! -e "$STAGED_ROOT/$RECEIPT_NAME" && ! -L "$STAGED_ROOT/$RECEIPT_NAME" ]] || \
        die "Release payload contains a machine-local install receipt"
    load_and_verify_manifest "$STAGED_ROOT" true
    [[ -x "$STAGED_ROOT/install.sh" && -x "$STAGED_ROOT/bin/mainframe" && \
       -x "$STAGED_ROOT/scripts/upgrade-release.sh" ]] || \
        die "Release installer, CLI, and next-version upgrader must be executable"
    embedded_version="$(read_single_line "$STAGED_ROOT/VERSION")" || die "Release VERSION must contain exactly one line"
    [[ "$embedded_version" == "$TARGET_VERSION" ]] || \
        die "Release VERSION ($embedded_version) does not match requested version ($TARGET_VERSION)"

    before_inventory="$WORKSPACE/state-before.tsv"
    after_inventory="$WORKSPACE/state-after.tsv"
    backup_inventory="$WORKSPACE/state-backup.tsv"
    build_state_inventory "$MAINFRAME_ROOT" "$before_inventory"
    for ((index = 1; index < ${#STATE_PATHS[@]}; index++)); do
        if [[ "${STATE_TYPES[$index]}" == "file" ]]; then
            state_files=$((state_files + 1))
        else
            state_dirs=$((state_dirs + 1))
        fi
    done
    preflight_state_collisions "$STAGED_ROOT"
    copy_state_snapshot "$MAINFRAME_ROOT" "$STAGED_ROOT"
    build_state_inventory "$MAINFRAME_ROOT" "$after_inventory"
    cmp -s "$before_inventory" "$after_inventory" || \
        die "In-root state changed during staging; stop active agents and retry"
    write_receipt "$STAGED_ROOT" "$TARGET_VERSION" "$actual_sha" "$RECEIPT_BIN_DIR"
    STAGED_IDENTITY="$(path_identity "$STAGED_ROOT")"
    [[ -n "$STAGED_IDENTITY" ]] || die "Could not identify the verified staged runtime"
    run_failpoint after-staging-before-journal

    directory_matches_identity "$MAINFRAME_ROOT" "$CURRENT_ROOT_IDENTITY" || \
        die "Active install root identity changed before transaction preparation"
    load_receipt "$MAINFRAME_ROOT"
    load_and_verify_manifest "$MAINFRAME_ROOT" false
    [[ "$(read_single_line "$MAINFRAME_ROOT/VERSION")" == "$CURRENT_VERSION" ]] || \
        die "Active runtime VERSION changed before transaction preparation"
    directory_matches_identity "$MAINFRAME_ROOT" "$CURRENT_ROOT_IDENTITY" || \
        die "Active install root identity changed during transaction preparation"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run verified v$TARGET_VERSION and staged $state_files state files plus $state_dirs state directories"
        info "Would retain the current v$CURRENT_VERSION installation as a recoverable sibling backup"
        exit 0
    fi

    TRANSACTION_DIR="$(mktemp -d "$parent/.${base}.upgrade-transaction.XXXXXX")"
    BACKUP_DIR="$TRANSACTION_DIR/previous"
    FAILED_DIR="$TRANSACTION_DIR/failed-candidate"
    MISPLACED_CANDIDATE_DIR="$TRANSACTION_DIR/misplaced-candidate"
    RECOVERY_SCRIPT="$TRANSACTION_DIR/recover-upgrade.sh"
    cp -p "$SCRIPT_DIR/upgrade-release.sh" "$RECOVERY_SCRIPT"
    chmod 700 "$RECOVERY_SCRIPT"
    source_sha="$(sha256_file "$SCRIPT_DIR/upgrade-release.sh")" || die "Could not hash the trusted recovery updater"
    copied_sha="$(sha256_file "$RECOVERY_SCRIPT")" || die "Could not hash the copied recovery updater"
    [[ "$source_sha" == "$CURRENT_UPGRADER_SHA" ]] || \
        die "Trusted recovery updater changed after manifest verification"
    [[ "$copied_sha" == "$CURRENT_UPGRADER_SHA" ]] || die "Recovery updater copy failed manifest verification"
    durability_barrier
    write_journal prepared
    printf '[MAINFRAME upgrade] Crash recovery command: %q %q --recover --journal %q\n' \
        "$BASH" "$RECOVERY_SCRIPT" "$JOURNAL"
    directory_matches_identity "$MAINFRAME_ROOT" "$CURRENT_ROOT_IDENTITY" || \
        die "Active install root identity changed before cutover"
    load_receipt "$MAINFRAME_ROOT"
    load_and_verify_manifest "$MAINFRAME_ROOT" false
    [[ "$(read_single_line "$MAINFRAME_ROOT/VERSION")" == "$CURRENT_VERSION" ]] || \
        die "Active runtime VERSION changed before cutover"
    directory_matches_identity "$MAINFRAME_ROOT" "$CURRENT_ROOT_IDENTITY" || \
        die "Active install root identity changed during final verification"
    run_failpoint before-old-move
    mv -- "$MAINFRAME_ROOT" "$BACKUP_DIR"
    if ! directory_matches_identity "$BACKUP_DIR" "$CURRENT_ROOT_IDENTITY"; then
        nested_backup="$BACKUP_DIR/$(basename "$MAINFRAME_ROOT")"
        if directory_matches_identity "$nested_backup" "$CURRENT_ROOT_IDENTITY" && \
           [[ ! -e "$MAINFRAME_ROOT" && ! -L "$MAINFRAME_ROOT" ]]; then
            mv -- "$nested_backup" "$MAINFRAME_ROOT"
            if ! directory_matches_identity "$MAINFRAME_ROOT" "$CURRENT_ROOT_IDENTITY"; then
                nested_restore="$MAINFRAME_ROOT/$(basename "$nested_backup")"
                if directory_matches_identity "$nested_restore" "$CURRENT_ROOT_IDENTITY" && \
                   [[ ! -e "$nested_backup" && ! -L "$nested_backup" ]]; then
                    mv -- "$nested_restore" "$nested_backup" || true
                fi
                die "Could not safely restore the previous runtime after backup-destination substitution"
            fi
            durability_barrier
            load_receipt "$MAINFRAME_ROOT"
            load_and_verify_manifest "$MAINFRAME_ROOT" false
            [[ "$(read_single_line "$MAINFRAME_ROOT/VERSION")" == "$CURRENT_VERSION" ]] || \
                die "Restored runtime VERSION changed after backup-destination substitution"
            directory_matches_identity "$MAINFRAME_ROOT" "$CURRENT_ROOT_IDENTITY" || \
                die "Restored runtime identity changed after backup-destination substitution"
            verify_runtime_health "$MAINFRAME_ROOT" "$CURRENT_VERSION"
            directory_matches_identity "$MAINFRAME_ROOT" "$CURRENT_ROOT_IDENTITY" || \
                die "Restored runtime identity changed during health verification"
            rm -f -- "$JOURNAL"
            durability_barrier
            warn "Left the substituted backup destination unchanged for inspection: $BACKUP_DIR"
            die "Backup destination was substituted; restored and verified the previous installation"
        fi
        die "Cutover did not preserve the exact previous runtime as its backup"
    fi
    BACKUP_OWNED=true
    durability_barrier
    run_failpoint after-old-move
    write_journal old-moved

    [[ "$(sha256_file "$BACKUP_DIR/SHA256SUMS")" == "$RECEIPT_MANIFEST_SHA" ]] || \
        die "Backup manifest no longer matches the verified release receipt"
    load_and_verify_manifest "$BACKUP_DIR" false
    [[ "$(read_single_line "$BACKUP_DIR/VERSION")" == "$CURRENT_VERSION" ]] || \
        die "Backup runtime VERSION changed during cutover"
    directory_matches_identity "$BACKUP_DIR" "$CURRENT_ROOT_IDENTITY" || \
        die "Backup runtime identity changed during cutover"
    build_state_inventory "$BACKUP_DIR" "$backup_inventory"
    cmp -s "$after_inventory" "$backup_inventory" || \
        die "In-root state changed at transaction time"

    run_failpoint before-new-active
    directory_matches_identity "$STAGED_ROOT" "$STAGED_IDENTITY" || \
        die "Verified staged runtime identity changed before cutover"
    [[ ! -e "$MAINFRAME_ROOT" && ! -L "$MAINFRAME_ROOT" ]] || \
        die "Install path was recreated during cutover; leaving it untouched"
    PLACEMENT_IN_PROGRESS=true
    mv -- "$STAGED_ROOT" "$MAINFRAME_ROOT"
    if ! directory_matches_identity "$MAINFRAME_ROOT" "$STAGED_IDENTITY"; then
        MISPLACED_CANDIDATE="$MAINFRAME_ROOT/$(basename "$STAGED_ROOT")"
        PLACEMENT_IN_PROGRESS=false
        die "Cutover did not activate the exact staged runtime; no candidate code was executed"
    fi
    ACTIVE_CANDIDATE_OWNED=true
    PLACEMENT_IN_PROGRESS=false
    durability_barrier
    run_failpoint after-new-active
    write_journal new-active
    run_failpoint after-new-journal

    directory_matches_identity "$MAINFRAME_ROOT" "$STAGED_IDENTITY" || \
        die "Activated runtime identity changed before verification"
    load_receipt "$MAINFRAME_ROOT"
    load_and_verify_manifest "$MAINFRAME_ROOT" false
    embedded_version="$(read_single_line "$MAINFRAME_ROOT/VERSION")" || \
        die "Activated VERSION must contain exactly one line"
    [[ "$embedded_version" == "$TARGET_VERSION" ]] || die "Activated runtime VERSION changed during cutover"
    directory_matches_identity "$MAINFRAME_ROOT" "$STAGED_IDENTITY" || \
        die "Activated runtime identity changed before health verification"
    verify_runtime_health "$MAINFRAME_ROOT" "$TARGET_VERSION"
    directory_matches_identity "$MAINFRAME_ROOT" "$STAGED_IDENTITY" || \
        die "Activated runtime identity changed during health verification"
    run_failpoint after-health

    rm -f -- "$JOURNAL"
    durability_barrier
    info "Upgraded MAINFRAME from v$CURRENT_VERSION to v$TARGET_VERSION"
    info "Preserved $state_files state files and $state_dirs private state directories"
    info "Previous installation backup: $BACKUP_DIR"
    info "The backup is a point-in-time copy; later state is not merged into a manual rollback"
}

main "$@"
