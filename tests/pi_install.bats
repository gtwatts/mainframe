#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(cd "$BATS_TEST_TMPDIR" && pwd -P)/pi-install-$BATS_TEST_NUMBER"
    TEST_HOME="$TEST_ROOT/home"
    TEST_AGENT_DIR="$TEST_ROOT/agent"
    TEST_PYTHON=/usr/bin/python3
    if [[ ! -x "$TEST_PYTHON" ]]; then
        TEST_PYTHON=/bin/python3
    fi

    /bin/mkdir -m 700 "$TEST_ROOT"
    /bin/mkdir -m 700 "$TEST_HOME"
    /bin/mkdir -m 700 "$TEST_AGENT_DIR"
    export HOME="$TEST_HOME"
    export MAINFRAME_PI_AGENT_DIR="$TEST_AGENT_DIR"
    unset PI_CODING_AGENT_DIR MAINFRAME_PI_YES MAINFRAME_YES _MAINFRAME_PI_DISCOVERY_PATH
    # shellcheck source=../lib/pi.sh
    source "$PROJECT_ROOT/lib/pi.sh"
}

settings_mode() {
    local path="$1"
    /usr/bin/stat -c '%a' "$path" 2>/dev/null ||
        /usr/bin/stat -f '%Lp' "$path" 2>/dev/null
}

output_value() {
    local wanted="$1" line
    while IFS= read -r line; do
        case "$line" in
            "$wanted"=*) printf '%s\n' "${line#*=}"; return 0 ;;
        esac
    done <<< "$output"
    return 1
}

status_from_project() {
    local project="$1"
    shift
    cd "$project" || return 1
    mainframe_pi_status "$@"
}

install_from_project() {
    local project="$1"
    shift
    cd "$project" || return 1
    mainframe_pi_install "$@"
}

remove_from_project() {
    local project="$1"
    shift
    cd "$project" || return 1
    mainframe_pi_remove "$@"
}

write_manager_receipt() {
    local source="$1"
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/.mainframe-pi-receipt.json" "$source" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({
        "schema_version": 1,
        "manager": "@gtwatts/mainframe-pi",
        "package_source": sys.argv[2],
    }, handle, indent=2)
    handle.write("\n")
PY
    /bin/chmod 600 "$TEST_AGENT_DIR/.mainframe-pi-receipt.json"
}

write_migration_fixture() {
    /bin/mkdir -m 700 "$TEST_AGENT_DIR/extensions"
    /bin/mkdir -m 700 "$TEST_AGENT_DIR/skills"
    /bin/mkdir -m 700 "$TEST_AGENT_DIR/skills/mainframe"
    printf 'legacy extension\n' > "$TEST_AGENT_DIR/extensions/mainframe.ts"
    printf '%s\n' '---' 'name: legacy-mainframe' '---' > "$TEST_AGENT_DIR/skills/mainframe/SKILL.md"
    /bin/chmod 600 "$TEST_AGENT_DIR/extensions/mainframe.ts"
    /bin/chmod 600 "$TEST_AGENT_DIR/skills/mainframe/SKILL.md"
    /bin/chmod 700 "$TEST_AGENT_DIR/skills/mainframe"

    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" "$PROJECT_ROOT" "$TEST_AGENT_DIR" <<'PY'
import json
import sys

path, root, agent_dir = sys.argv[1:4]
document = {
    "defaultModel": "test-model",
    "nested": {"preserve": [1, {"two": True}]},
    "packages": [
        "npm:unrelated-package",
        root,
        {"source": root, "skills": []},
    ],
    "extensions": [
        "extensions/mainframe.ts",
        "./extensions/mainframe.ts",
        f"{agent_dir}/extensions/mainframe.ts",
        "+extensions/mainframe.ts",
        "extensions/*.ts",
        "!extensions/mainframe.ts",
        "extensions/mainframe.ts.disabled",
        "/opt/example/other.ts",
    ],
    "skills": ["~/.codex/skills"],
}

with open(path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=4)
    handle.write("\n")
PY
    /bin/chmod 640 "$TEST_AGENT_DIR/settings.json"
}

write_fake_pi() {
    local package_name="$1" package_version="$2"
    local suffix="${package_version//[^A-Za-z0-9._-]/_}"
    local package_root="$TEST_ROOT/fake-pi-package-$suffix"
    local bin_dir="$TEST_ROOT/fake-pi-bin-$suffix"

    /bin/mkdir -m 700 "$package_root" "$package_root/dist" "$bin_dir"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf executed > "${MAINFRAME_PI_TEST_EXECUTION_MARKER:?}"' \
        'exit 99' > "$package_root/dist/cli.js"
    /bin/chmod 700 "$package_root/dist/cli.js"
    "$TEST_PYTHON" - "$package_root/package.json" "$package_name" "$package_version" <<'PY'
import json
import sys

path, name, version = sys.argv[1:4]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({"name": name, "version": version, "bin": {"pi": "dist/cli.js"}}, handle)
    handle.write("\n")
PY
    /bin/chmod 600 "$package_root/package.json"
    /bin/ln -s "$package_root/dist/cli.js" "$bin_dir/pi"
    export MAINFRAME_PI_TEST_EXECUTION_MARKER="$TEST_ROOT/pi-was-executed"
    export PATH="$bin_dir:/usr/bin:/bin"
}

@test "status is read-only and supports stable key-value and JSON output" {
    local before after
    before="$(/usr/bin/find "$TEST_AGENT_DIR" -mindepth 1 -maxdepth 3 -print | /usr/bin/sort)"

    run mainframe_pi_status

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"agent_dir=$TEST_AGENT_DIR"* ]]
    [[ "$output" == *"mainframe_root=$PROJECT_ROOT"* ]]
    [[ "$output" == *'package_active=false'* ]]
    [[ "$output" == *'package_duplicates=0'* ]]
    [[ "$output" == *'legacy_precedence_collision=false'* ]]
    [[ "$output" == *'project_extension_present=false'* ]]
    [[ "$output" == *'project_skill_present=false'* ]]
    [[ "$output" == *'project_precedence_collision=false'* ]]
    [[ "$output" == *'restart_needed=false'* ]]
    [[ "$output" == *'state=not-installed'* ]]

    after="$(/usr/bin/find "$TEST_AGENT_DIR" -mindepth 1 -maxdepth 3 -print | /usr/bin/sort)"
    [[ "$after" == "$before" ]]

    run mainframe_pi_status --json

    [[ "$status" -eq 0 ]]
    "$TEST_PYTHON" - "$output" "$TEST_AGENT_DIR" "$PROJECT_ROOT" <<'PY'
import json
import sys

document = json.loads(sys.argv[1])
assert document["agent_dir"] == sys.argv[2]
assert document["mainframe_root"] == sys.argv[3]
assert document["package_active"] is False
assert document["state"] == "not-installed"
PY
}

@test "trusted Homebrew package roots validate from the private keg boundary" {
    local shared_prefix keg_root required source relative
    shared_prefix="$TEST_ROOT/homebrew-prefix"
    keg_root="$shared_prefix/Cellar/mainframe/10.2.0/libexec"
    /bin/mkdir -m 775 "$shared_prefix"
    /bin/mkdir -m 775 "$shared_prefix/Cellar"
    /bin/mkdir -m 755 "$shared_prefix/Cellar/mainframe"
    /bin/mkdir -m 755 "$shared_prefix/Cellar/mainframe/10.2.0"
    /bin/mkdir -m 755 "$keg_root"

    for relative in \
        VERSION \
        package.json \
        config/pi-compatibility.json \
        security/gate-rules.json \
        security/gate-normalizer.mjs \
        skills/pi/SKILL.md \
        skills/pi/extensions/mainframe.ts \
        lib/pi_restore.sh; do
        source="$PROJECT_ROOT/$relative"
        required="$keg_root/$relative"
        /bin/mkdir -m 755 -p "${required%/*}"
        /bin/cp -p "$source" "$required"
    done

    _MAINFRAME_PI_ROOT="$keg_root"
    _MAINFRAME_PI_HOMEBREW_SOURCE_ACTIVE=true
    run _mainframe_pi_validate_package_root
    [[ "$status" -eq 0 ]]

    _MAINFRAME_PI_HOMEBREW_SOURCE_ACTIVE=false
    run _mainframe_pi_validate_package_root
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'unsafe ownership, permissions, or symlink ancestry'* ]]

    _MAINFRAME_PI_HOMEBREW_SOURCE_ACTIVE=true
    /bin/chmod 775 "$keg_root"
    run _mainframe_pi_validate_package_root
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'unsafe ownership, permissions, or symlink ancestry'* ]]

    run rg -n --fixed-strings -- \
        'trusted package-manager boundary' "$PROJECT_ROOT/SECURITY.md" \
        "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/docs/ONBOARDING.md" \
        "$PROJECT_ROOT/packaging/homebrew/README.md"
    [[ "$status" -eq 0 ]]
    [[ "$(printf '%s\n' "$output" | wc -l | tr -d '[:space:]')" -eq 4 ]]
}

@test "status reports project-local precedence collisions and install never migrates project files" {
    local project original_settings before_project after_project
    project="$TEST_ROOT/project"
    /bin/mkdir -m 700 "$project"
    /bin/mkdir -m 700 "$project/.pi"
    /bin/mkdir -m 700 "$project/.pi/extensions"
    /bin/mkdir -m 700 "$project/.pi/skills"
    /bin/mkdir -m 700 "$project/.pi/skills/mainframe"
    printf 'project extension\n' > "$project/.pi/extensions/mainframe.ts"
    printf '%s\n' '---' 'name: project-mainframe' '---' > "$project/.pi/skills/mainframe/SKILL.md"
    /bin/chmod 600 "$project/.pi/extensions/mainframe.ts"
    /bin/chmod 600 "$project/.pi/skills/mainframe/SKILL.md"
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" "$PROJECT_ROOT" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({"packages": [sys.argv[2]], "unrelated": {"keep": True}}, handle)
    handle.write("\n")
PY
    /bin/chmod 600 "$TEST_AGENT_DIR/settings.json"
    original_settings="$(<"$TEST_AGENT_DIR/settings.json")"
    before_project="$(/usr/bin/find "$project/.pi" -mindepth 1 -maxdepth 5 -print | /usr/bin/sort)"

    run status_from_project "$project"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"project_dir=$project"* ]]
    [[ "$output" == *'package_active=true'* ]]
    [[ "$output" == *'project_extension_present=true'* ]]
    [[ "$output" == *'project_skill_present=true'* ]]
    [[ "$output" == *'project_precedence_collision=true'* ]]
    [[ "$output" == *'restart_needed=true'* ]]
    [[ "$output" == *'state=project-collision'* ]]

    run install_from_project "$project" --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'would_leave_project_extension=true'* ]]
    [[ "$output" == *'would_leave_project_skill=true'* ]]
    [[ "$output" == *'blocked_by_project_legacy=true'* ]]
    [[ "$output" == *'next_apply_command=none'* ]]
    [[ "$output" == *'next_reload_instruction=none'* ]]
    [[ "$output" == *'next_verify_command=none'* ]]

    run install_from_project "$project" --yes
    [[ "$status" -eq 77 ]]
    [[ "$output" == *'require separate project authorization'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original_settings" ]]
    after_project="$(/usr/bin/find "$project/.pi" -mindepth 1 -maxdepth 5 -print | /usr/bin/sort)"
    [[ "$after_project" == "$before_project" ]]
    [[ "$(<"$project/.pi/extensions/mainframe.ts")" == 'project extension' ]]
    [[ -f "$project/.pi/skills/mainframe/SKILL.md" ]]
    [[ -z "$(/usr/bin/find "$TEST_AGENT_DIR" -maxdepth 1 -name '.mainframe-pi-backup-*' -print)" ]]
}

@test "agent directory resolution prefers the test override then Pi then fake HOME" {
    local alternate from_home
    alternate="$TEST_ROOT/alternate-agent"
    from_home="$TEST_HOME/.pi/agent"
    /bin/mkdir -m 700 "$alternate"
    /bin/mkdir -m 700 "$TEST_HOME/.pi"
    /bin/mkdir -m 700 "$from_home"

    export PI_CODING_AGENT_DIR="$alternate"
    run mainframe_pi_status
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"agent_dir=$TEST_AGENT_DIR"* ]]

    unset MAINFRAME_PI_AGENT_DIR
    run mainframe_pi_status
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"agent_dir=$alternate"* ]]

    unset PI_CODING_AGENT_DIR
    run mainframe_pi_status
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"agent_dir=$from_home"* ]]
}

@test "status detects active packages, duplicates, legacy precedence, and restart need" {
    write_migration_fixture

    run mainframe_pi_status

    [[ "$status" -eq 0 ]]
    [[ "$output" == *'package_active=true'* ]]
    [[ "$output" == *'package_entries=2'* ]]
    [[ "$output" == *'package_canonical_entries=1'* ]]
    [[ "$output" == *'package_bare_string_entries=1'* ]]
    [[ "$output" == *'package_duplicates=1'* ]]
    [[ "$output" == *'legacy_extension_present=true'* ]]
    [[ "$output" == *'legacy_skill_present=true'* ]]
    [[ "$output" == *'legacy_extension_settings_entries=4'* ]]
    [[ "$output" == *'legacy_precedence_collision=true'* ]]
    [[ "$output" == *'restart_needed=true'* ]]
    [[ "$output" == *'state=duplicate'* ]]
}

@test "relative Pi package sources are recognized then canonicalized to the absolute root" {
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" "$PROJECT_ROOT" "$TEST_AGENT_DIR" <<'PY'
import json
import os
import sys

settings, root, agent_dir = sys.argv[1:4]
with open(settings, "w", encoding="utf-8") as handle:
    json.dump({"packages": [os.path.relpath(root, agent_dir)]}, handle)
    handle.write("\n")
PY
    /bin/chmod 600 "$TEST_AGENT_DIR/settings.json"

    run mainframe_pi_status
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'package_active=true'* ]]
    [[ "$output" == *'package_entries=1'* ]]
    [[ "$output" == *'package_canonical_entries=0'* ]]
    [[ "$output" == *'restart_needed=true'* ]]
    [[ "$output" == *'state=noncanonical'* ]]

    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=true'* ]]
    [[ "$output" == *'restore_available=false'* ]]
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" "$PROJECT_ROOT" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    assert json.load(handle)["packages"] == [sys.argv[2]]
PY
}

@test "real install requires same-command yes and rejects inherited authorization" {
    local original
    write_migration_fixture
    original="$(<"$TEST_AGENT_DIR/settings.json")"

    run mainframe_pi_install
    [[ "$status" -eq 77 ]]
    [[ "$output" == *'requires explicit same-command confirmation: --yes'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original" ]]
    [[ -f "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]

    export MAINFRAME_PI_YES=1
    run mainframe_pi_install --yes
    [[ "$status" -eq 77 ]]
    [[ "$output" == *'inherited authorization is not accepted'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original" ]]
    [[ -f "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]

    unset MAINFRAME_PI_YES
    export MAINFRAME_YES=1
    run mainframe_pi_install --yes
    [[ "$status" -eq 77 ]]
    [[ "$output" == *'inherited authorization is not accepted'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original" ]]
}

@test "dry-run needs no confirmation and performs absolutely no mutation" {
    local original before after
    write_migration_fixture
    original="$(<"$TEST_AGENT_DIR/settings.json")"
    before="$(/usr/bin/find "$TEST_AGENT_DIR" -mindepth 1 -maxdepth 5 -print | /usr/bin/sort)"
    export MAINFRAME_PI_YES=1

    run mainframe_pi_install --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *'action=install'* ]]
    [[ "$output" == *'dry_run=true'* ]]
    [[ "$output" == *'would_change=true'* ]]
    [[ "$output" == *'would_quarantine_extension=true'* ]]
    [[ "$output" == *'would_quarantine_skill=true'* ]]
    [[ "$output" == *'would_remove_legacy_extension_settings_entries=4'* ]]
    [[ "$output" == *"would_set_package_source=$PROJECT_ROOT"* ]]
    [[ "$output" == *'restart_needed_after_install=true'* ]]
    [[ "$output" == *'next_apply_command=mainframe pi install --yes'* ]]
    [[ "$output" == *'next_reload_instruction=Use /reload in Pi, or restart Pi.'* ]]
    [[ "$output" == *'next_verify_command=/mainframe doctor'* ]]

    after="$(/usr/bin/find "$TEST_AGENT_DIR" -mindepth 1 -maxdepth 5 -print | /usr/bin/sort)"
    [[ "$after" == "$before" ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original" ]]
    [[ -f "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]
    [[ -d "$TEST_AGENT_DIR/skills/mainframe" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-install.lock" ]]
}

@test "install quarantines legacy resources and preserves unrelated Pi settings" {
    local original backup_dir backup_mode before_backups after_backups
    write_migration_fixture
    original="$(<"$TEST_AGENT_DIR/settings.json")"
    before_backups="$(/usr/bin/find "$TEST_AGENT_DIR" -maxdepth 1 -name '.mainframe-pi-backup-*' -print | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"

    run mainframe_pi_install --yes

    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=true'* ]]
    [[ "$output" == *'settings_updated=true'* ]]
    [[ "$output" == *'restore_available=true'* ]]
    [[ "$output" == *'restart_needed=true'* ]]
    backup_dir="$(output_value backup_dir)"
    [[ "$backup_dir" == "$TEST_AGENT_DIR"/.mainframe-pi-backup-* ]]
    [[ -d "$backup_dir" && ! -L "$backup_dir" ]]
    backup_mode="$(settings_mode "$backup_dir")"
    [[ "$backup_mode" == 700 ]]
    [[ ! -e "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]
    [[ ! -e "$TEST_AGENT_DIR/skills/mainframe" ]]
    [[ "$(<"$backup_dir/extensions/mainframe.ts")" == 'legacy extension' ]]
    [[ -f "$backup_dir/skills/mainframe/SKILL.md" ]]
    [[ "$(<"$backup_dir/settings.json.before")" == "$original" ]]
    [[ "$(settings_mode "$TEST_AGENT_DIR/settings.json")" == 640 ]]

    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" "$PROJECT_ROOT" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    document = json.load(handle)
root = sys.argv[2]
assert document["defaultModel"] == "test-model"
assert document["nested"] == {"preserve": [1, {"two": True}]}
assert document["skills"] == ["~/.codex/skills"]
assert document["packages"] == ["npm:unrelated-package", root]
assert document["extensions"] == [
    "extensions/*.ts",
    "!extensions/mainframe.ts",
    "extensions/mainframe.ts.disabled",
    "/opt/example/other.ts",
]
PY

    run mainframe_pi_status
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'package_active=true'* ]]
    [[ "$output" == *'package_entries=1'* ]]
    [[ "$output" == *'package_duplicates=0'* ]]
    [[ "$output" == *'legacy_precedence_collision=false'* ]]
    [[ "$output" == *'restart_needed=false'* ]]
    [[ "$output" == *'state=ready'* ]]

    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=false'* ]]
    [[ "$output" == *'backup_dir=none'* ]]
    [[ "$output" == *'restart_needed=false'* ]]
    after_backups="$(/usr/bin/find "$TEST_AGENT_DIR" -maxdepth 1 -name '.mainframe-pi-backup-*' -print | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"
    [[ "$after_backups" == "$((before_backups + 1))" ]]
}

@test "late verification failure rolls settings and both legacy resources back" {
    local original original_mode backup_dir
    write_migration_fixture
    original="$(<"$TEST_AGENT_DIR/settings.json")"
    original_mode="$(settings_mode "$TEST_AGENT_DIR/settings.json")"
    _mainframe_pi_verify_installed_state() { return 1; }

    run mainframe_pi_install --yes

    [[ "$status" -eq 1 ]]
    [[ "$output" == *'rollback=complete'* ]]
    backup_dir="${output##*backup_dir=}"
    backup_dir="${backup_dir%%$'\n'*}"
    [[ "$backup_dir" == "$TEST_AGENT_DIR"/.mainframe-pi-backup-* ]]
    [[ -d "$backup_dir" ]]
    [[ -f "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]
    [[ -f "$TEST_AGENT_DIR/skills/mainframe/SKILL.md" ]]
    [[ "$(<"$TEST_AGENT_DIR/extensions/mainframe.ts")" == 'legacy extension' ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original" ]]
    [[ "$(settings_mode "$TEST_AGENT_DIR/settings.json")" == "$original_mode" ]]
    [[ -f "$backup_dir/settings.json.before" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-receipt.json" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-install.lock" ]]
}

@test "malformed or non-private manager receipts fail closed without touching settings" {
    local original
    printf '{not-json\n' > "$TEST_AGENT_DIR/.mainframe-pi-receipt.json"
    /bin/chmod 600 "$TEST_AGENT_DIR/.mainframe-pi-receipt.json"
    printf '{"packages": ["npm:keep"]}\n' > "$TEST_AGENT_DIR/settings.json"
    /bin/chmod 600 "$TEST_AGENT_DIR/settings.json"
    original="$(<"$TEST_AGENT_DIR/settings.json")"

    run mainframe_pi_install --yes
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'invalid Mainframe Pi manager receipt'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original" ]]

    write_manager_receipt "$PROJECT_ROOT"
    /bin/chmod 640 "$TEST_AGENT_DIR/.mainframe-pi-receipt.json"
    run mainframe_pi_remove --yes
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'must be a private mode-600 file'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original" ]]
}

@test "symlinked agent or legacy paths and unsafe permissions fail closed" {
    local target linked external
    target="$TEST_ROOT/real-agent"
    linked="$TEST_ROOT/linked-agent"
    external="$TEST_ROOT/outside-mainframe.ts"
    /bin/mkdir -m 700 "$target"
    /bin/ln -s "$target" "$linked"
    export MAINFRAME_PI_AGENT_DIR="$linked"

    run mainframe_pi_status
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'unsafe ownership, permissions, or symlink ancestry'* ]]
    [[ ! -e "$target/settings.json" ]]

    export MAINFRAME_PI_AGENT_DIR="$TEST_AGENT_DIR"
    /bin/mkdir -m 700 "$TEST_AGENT_DIR/extensions"
    printf 'outside\n' > "$external"
    /bin/chmod 600 "$external"
    /bin/ln -s "$external" "$TEST_AGENT_DIR/extensions/mainframe.ts"
    run mainframe_pi_install --yes
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'legacy Pi extension is unsafe'* ]]
    [[ "$(<"$external")" == outside ]]
    [[ ! -e "$TEST_AGENT_DIR/settings.json" ]]

    /bin/unlink "$TEST_AGENT_DIR/extensions/mainframe.ts"
    /bin/chmod 777 "$TEST_AGENT_DIR"
    run mainframe_pi_install --yes
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'unsafe ownership, permissions, or symlink ancestry'* ]]
    [[ ! -e "$TEST_AGENT_DIR/settings.json" ]]
}

@test "dot-segment escape and malformed or hard-linked settings are never rewritten" {
    local original hardlink
    export MAINFRAME_PI_AGENT_DIR="$TEST_ROOT/agent/../agent"
    run mainframe_pi_install --yes
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'absolute path without dot segments'* ]]

    export MAINFRAME_PI_AGENT_DIR="$TEST_AGENT_DIR"
    printf '{not-json\n' > "$TEST_AGENT_DIR/settings.json"
    /bin/chmod 600 "$TEST_AGENT_DIR/settings.json"
    original="$(<"$TEST_AGENT_DIR/settings.json")"
    run mainframe_pi_install --yes
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'invalid Pi settings.json'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original" ]]

    /bin/unlink "$TEST_AGENT_DIR/settings.json"
    printf '{"packages": []}\n' > "$TEST_AGENT_DIR/settings.json"
    /bin/chmod 600 "$TEST_AGENT_DIR/settings.json"
    hardlink="$TEST_ROOT/settings-hardlink.json"
    /bin/ln "$TEST_AGENT_DIR/settings.json" "$hardlink"
    run mainframe_pi_install --yes
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'singly linked user-owned regular file'* ]]
    [[ "$(<"$hardlink")" == '{"packages": []}' ]]
}

@test "fixed Python execution ignores PATH shims and exported functions" {
    local marker fake_bin
    marker="$TEST_ROOT/python-ran"
    fake_bin="$TEST_ROOT/fake-bin"
    /bin/mkdir -m 700 "$fake_bin"
    printf '#!/bin/sh\nprintf poisoned > %s\nexit 99\n' "$marker" > "$fake_bin/python3"
    /bin/chmod 700 "$fake_bin/python3"
    python3() { printf 'function-poisoned\n' > "$marker"; return 99; }
    export -f python3
    export PATH="$fake_bin:$PATH"
    export PYTHONSTARTUP="$fake_bin/python3"
    export PYTHONPATH="$fake_bin"

    run mainframe_pi_status

    [[ "$status" -eq 0 ]]
    [[ "$output" == *'state=not-installed'* ]]
    [[ ! -e "$marker" ]]
}

@test "an existing private transaction lock blocks install without mutation" {
    /bin/mkdir -m 700 "$TEST_AGENT_DIR/.mainframe-pi-install.lock"

    run mainframe_pi_install --yes

    [[ "$status" -eq 75 ]]
    [[ "$output" == *'another Pi integration install is active'* ]]
    [[ ! -e "$TEST_AGENT_DIR/settings.json" ]]
    [[ -d "$TEST_AGENT_DIR/.mainframe-pi-install.lock" ]]
}

@test "install revalidates its authenticated package source after taking the lock" {
    local source_probe="$TEST_ROOT/package-source-observed"

    _mainframe_pi_select_package_source() {
        if [[ -e "$source_probe" ]]; then
            _mainframe_pi_error 'authenticated package source changed after lifecycle lock'
            return 1
        fi
        printf 'observed\n' > "$source_probe"
        _MAINFRAME_PI_PACKAGE_SOURCE="$_MAINFRAME_PI_ROOT"
        _MAINFRAME_PI_HOMEBREW_SOURCE_ACTIVE=false
    }

    run mainframe_pi_install --yes

    [[ "$status" -eq 1 ]]
    [[ "$output" == *'authenticated package source changed after lifecycle lock'* ]]
    [[ -f "$source_probe" ]]
    [[ ! -e "$TEST_AGENT_DIR/settings.json" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-receipt.json" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-install.lock" ]]
}

@test "CLI exposes Pi status, help, JSON, and fail-closed argument handling" {
    run "$PROJECT_ROOT/bin/mainframe" pi status
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"agent_dir=$TEST_AGENT_DIR"* ]]
    [[ "$output" == *'state=not-installed'* ]]

    run "$PROJECT_ROOT/bin/mainframe" pi status --json
    [[ "$status" -eq 0 ]]
    "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys

document = json.loads(sys.argv[1])
assert document["state"] == "not-installed"
assert document["package_active"] is False
PY

    run "$PROJECT_ROOT/bin/mainframe" pi --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'Usage: mainframe pi <status|doctor|install|remove|restore>'* ]]

    run "$PROJECT_ROOT/bin/mainframe" pi doctor --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'Usage: mainframe pi doctor [--json]'* ]]

    run "$PROJECT_ROOT/bin/mainframe" pi doctor --json --json
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'duplicate --json'* ]]

    run "$PROJECT_ROOT/bin/mainframe" pi unsupported
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'Unknown Pi command: unsupported'* ]]
}

@test "Pi doctor reports exact certified host separately from disk and live activation" {
    write_fake_pi '@earendil-works/pi-coding-agent' '0.84.2'
    _mainframe_pi_platform_tuple() { printf '%s\n' 'Darwin-arm64-none'; }

    run mainframe_pi_doctor --json
    [[ "$status" -eq 2 ]]
    "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys

document = json.loads(sys.argv[1])
assert document["pi"]["executed"] is False
assert document["pi"]["identity_consistent"] is True
assert document["compatibility"]["support"] == "certified"
assert document["integration"]["disk_state"] == "not-installed"
assert document["integration"]["runtime_activation"] == "unverified"
assert document["overall"] == {
    "state": "setup-required",
    "ready": False,
    "reason_codes": ["pi-disk-not-installed"],
}
PY
    [[ ! -e "$MAINFRAME_PI_TEST_EXECUTION_MARKER" ]]

    run "$PROJECT_ROOT/bin/mainframe" pi doctor --json
    [[ "$status" -eq 2 ]]
    "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys

document = json.loads(sys.argv[1])
assert document["pi"]["identity_consistent"] is True
assert document["pi"]["package"] == "@earendil-works/pi-coding-agent"
assert document["pi"]["version"] == "0.84.2"
assert document["pi"]["executed"] is False
assert document["overall"]["ready"] is False
PY
    [[ ! -e "$MAINFRAME_PI_TEST_EXECUTION_MARKER" ]]

    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    run mainframe_pi_doctor --json
    [[ "$status" -eq 2 ]]
    "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys

document = json.loads(sys.argv[1])
assert document["compatibility"]["support"] == "certified"
assert document["integration"]["disk_state"] == "ready"
assert document["integration"]["configured_active"] is True
assert document["overall"]["state"] == "activation-unverified"
assert document["overall"]["ready"] is False
assert [item["command"] for item in document["actions"]] == ["/reload", "/mainframe doctor"]
PY
    [[ ! -e "$MAINFRAME_PI_TEST_EXECUTION_MARKER" ]]
}

@test "Pi doctor labels the exact legacy Pi host LIMITED and exposes its RPC Bash gap" {
    write_fake_pi '@mariozechner/pi-coding-agent' '0.73.1'
    _mainframe_pi_platform_tuple() { printf '%s\n' 'Darwin-arm64-none'; }
    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]

    run mainframe_pi_doctor --json
    [[ "$status" -eq 2 ]]
    "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys

document = json.loads(sys.argv[1])
assert document["overall"]["state"] == "limited"
assert document["overall"]["ready"] is False
assert document["compatibility"]["support"] == "limited"
assert document["compatibility"]["capabilities"]["rpc_user_bash_gate"] == "not-observable"
assert document["compatibility"]["limitations"]
assert any(action["code"] == "upgrade-pi-for-full-coverage" for action in document["actions"])
PY
    [[ ! -e "$MAINFRAME_PI_TEST_EXECUTION_MARKER" ]]
}

@test "Pi doctor fails closed for an unknown Pi version or an uncertified platform" {
    write_fake_pi '@earendil-works/pi-coding-agent' '0.84.3'
    _mainframe_pi_platform_tuple() { printf '%s\n' 'Darwin-arm64-none'; }
    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]

    run mainframe_pi_doctor --json
    [[ "$status" -eq 2 ]]
    "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys

document = json.loads(sys.argv[1])
assert document["compatibility"]["known"] is False
assert document["compatibility"]["support"] == "unverified"
assert document["overall"]["state"] == "compatibility-unverified"
assert document["overall"]["ready"] is False
assert "READY" not in document["overall"]["state"].upper()
PY

    run mainframe_pi_doctor
    [[ "$status" -eq 2 ]]
    [[ "$output" == *'Compatibility:     UNVERIFIED'* ]]
    [[ "$output" == *'Disk state:        CANONICAL'* ]]
    [[ "$output" != *'READY'* ]]

    write_fake_pi '@earendil-works/pi-coding-agent' '0.84.2'
    _mainframe_pi_platform_tuple() { printf '%s\n' 'Linux-x86_64-glibc'; }
    run mainframe_pi_doctor --json
    [[ "$status" -eq 2 ]]
    "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys

document = json.loads(sys.argv[1])
assert document["platform"]["tuple"] == "Linux-x86_64-glibc"
assert document["compatibility"]["support"] == "unverified"
assert document["overall"]["ready"] is False
PY
    [[ ! -e "$MAINFRAME_PI_TEST_EXECUTION_MARKER" ]]
}

@test "Pi doctor reports a missing shell-visible Pi executable without mutation" {
    local before after
    PATH=/usr/bin:/bin
    _mainframe_pi_platform_tuple() { printf '%s\n' 'Darwin-arm64-none'; }
    before="$(/usr/bin/find "$TEST_AGENT_DIR" -mindepth 1 -maxdepth 4 -print | /usr/bin/sort)"

    run mainframe_pi_doctor --json
    [[ "$status" -eq 2 ]]
    "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys

document = json.loads(sys.argv[1])
assert document["overall"]["state"] == "pi-not-found"
assert document["overall"]["ready"] is False
assert document["pi"]["cli_state"] == "not-found"
assert document["pi"]["executed"] is False
PY
    after="$(/usr/bin/find "$TEST_AGENT_DIR" -mindepth 1 -maxdepth 4 -print | /usr/bin/sort)"
    [[ "$after" == "$before" ]]
}

@test "Pi doctor explains an uninitialized agent directory without creating it" {
    write_fake_pi '@earendil-works/pi-coding-agent' '0.84.2'
    _mainframe_pi_platform_tuple() { printf '%s\n' 'Darwin-arm64-none'; }
    /bin/rmdir "$TEST_AGENT_DIR"

    run mainframe_pi_doctor --json
    [[ "$status" -eq 2 ]]
    "$TEST_PYTHON" - "$output" <<'PY'
import json
import sys

document = json.loads(sys.argv[1])
assert document["integration"]["disk_state"] == "not-initialized"
assert document["overall"]["state"] == "setup-required"
assert document["actions"][0]["code"] == "initialize-pi"
assert document["actions"][0]["command"] == "pi"
PY
    [[ ! -e "$TEST_AGENT_DIR" ]]
    [[ ! -e "$MAINFRAME_PI_TEST_EXECUTION_MARKER" ]]
}

@test "symlink aliases dedupe by realpath and filtered package objects are replaced by one bare canonical source" {
    local alias
    alias="$TEST_ROOT/mainframe-alias"
    /bin/ln -s "$PROJECT_ROOT" "$alias"
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" "$alias" "$PROJECT_ROOT" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({
        "packages": [
            sys.argv[2],
            {"source": sys.argv[3], "autoload": False, "extensions": [], "skills": []},
        ],
        "unrelated": "preserve",
    }, handle)
    handle.write("\n")
PY
    /bin/chmod 600 "$TEST_AGENT_DIR/settings.json"

    run mainframe_pi_status
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'package_entries=2'* ]]
    [[ "$output" == *'package_canonical_entries=0'* ]]
    [[ "$output" == *'package_bare_string_entries=1'* ]]
    [[ "$output" == *'state=duplicate'* ]]

    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=true'* ]]
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" "$PROJECT_ROOT" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    document = json.load(handle)
assert document == {"packages": [sys.argv[2]], "unrelated": "preserve"}, document
PY
    [[ -f "$TEST_AGENT_DIR/.mainframe-pi-receipt.json" ]]
    [[ "$(settings_mode "$TEST_AGENT_DIR/.mainframe-pi-receipt.json")" == 600 ]]

    run mainframe_pi_status
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'package_canonical_entries=1'* ]]
    [[ "$output" == *'manager_receipt_current=true'* ]]
    [[ "$output" == *'state=ready'* ]]
}

@test "receipted prior missing root is replaced without removing an unrelated same-name checkout" {
    local prior unrelated
    prior="$TEST_ROOT/old-install/mainframe"
    unrelated="$TEST_ROOT/unrelated/mainframe"
    /bin/mkdir -m 700 "$TEST_ROOT/unrelated"
    /bin/mkdir -m 700 "$unrelated"
    write_manager_receipt "$prior"
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" "$prior" "$unrelated" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({"packages": [sys.argv[2], sys.argv[3]], "keep": True}, handle)
    handle.write("\n")
PY
    /bin/chmod 600 "$TEST_AGENT_DIR/settings.json"

    run mainframe_pi_status
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'receipt_only_entries=1'* ]]
    [[ "$output" == *'state=upgrade-needed'* ]]

    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" "$PROJECT_ROOT" "$unrelated" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    document = json.load(handle)
assert document["packages"] == [sys.argv[3], sys.argv[2]], document
assert document["keep"] is True
PY
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/.mainframe-pi-receipt.json" "$PROJECT_ROOT" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    assert json.load(handle)["package_source"] == sys.argv[2]
PY
}

@test "project package override or delta is detected read-only and blocks user-scope mutation" {
    local project original_global original_project
    project="$TEST_ROOT/project-settings"
    /bin/mkdir -m 700 "$project"
    /bin/mkdir -m 700 "$project/.pi"
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" "$PROJECT_ROOT" <<'PY'
import json
import sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({"packages": [sys.argv[2]], "global": "keep"}, handle)
    handle.write("\n")
PY
    "$TEST_PYTHON" - "$project/.pi/settings.json" "$PROJECT_ROOT" <<'PY'
import json
import sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({
        "packages": [{"source": sys.argv[2], "autoload": False, "skills": []}],
        "project": "keep",
    }, handle)
    handle.write("\n")
PY
    /bin/chmod 600 "$TEST_AGENT_DIR/settings.json" "$project/.pi/settings.json"
    original_global="$(<"$TEST_AGENT_DIR/settings.json")"
    original_project="$(<"$project/.pi/settings.json")"

    run status_from_project "$project"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'project_settings_present=true'* ]]
    [[ "$output" == *'project_package_entries=1'* ]]
    [[ "$output" == *'project_package_delta_entries=1'* ]]
    [[ "$output" == *'project_precedence_collision=true'* ]]
    [[ "$output" == *'state=project-collision'* ]]

    run install_from_project "$project" --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'would_leave_project_package_entries=1'* ]]
    [[ "$output" == *'blocked_by_project_legacy=true'* ]]

    run install_from_project "$project" --yes
    [[ "$status" -eq 77 ]]
    [[ "$output" == *'package settings require separate project authorization'* ]]
    run remove_from_project "$project" --yes
    [[ "$status" -eq 77 ]]
    [[ "$output" == *'package settings require separate project authorization'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original_global" ]]
    [[ "$(<"$project/.pi/settings.json")" == "$original_project" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-receipt.json" ]]
}

@test "remove requires direct approval, preserves unrelated settings and backups, and is idempotent" {
    local original dry_before dry_after old_backup backup_count
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" <<'PY'
import json
import sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({"packages": ["npm:unrelated"], "nested": {"keep": True}}, handle)
    handle.write("\n")
PY
    /bin/chmod 640 "$TEST_AGENT_DIR/settings.json"
    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    old_backup="$(output_value backup_dir)"
    [[ -d "$old_backup" ]]

    original="$(<"$TEST_AGENT_DIR/settings.json")"
    run mainframe_pi_remove
    [[ "$status" -eq 77 ]]
    [[ "$output" == *'remove requires explicit same-command confirmation'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original" ]]

    export MAINFRAME_PI_YES=1
    run mainframe_pi_remove --yes
    [[ "$status" -eq 77 ]]
    [[ "$output" == *'inherited authorization is not accepted'* ]]
    unset MAINFRAME_PI_YES

    dry_before="$(/usr/bin/find "$TEST_AGENT_DIR" -mindepth 1 -maxdepth 3 -print | /usr/bin/sort)"
    run mainframe_pi_remove --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'would_change=true'* ]]
    [[ "$output" == *'would_remove_managed_package_entries=1'* ]]
    [[ "$output" == *'would_remove_manager_receipt=true'* ]]
    [[ "$output" == *'would_preserve_backups=true'* ]]
    dry_after="$(/usr/bin/find "$TEST_AGENT_DIR" -mindepth 1 -maxdepth 3 -print | /usr/bin/sort)"
    [[ "$dry_after" == "$dry_before" ]]

    run mainframe_pi_remove --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=true'* ]]
    [[ "$output" == *'backups_preserved=true'* ]]
    [[ -d "$old_backup" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-receipt.json" ]]
    [[ "$(settings_mode "$TEST_AGENT_DIR/settings.json")" == 640 ]]
    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    assert json.load(handle) == {"packages": ["npm:unrelated"], "nested": {"keep": True}}
PY
    backup_count="$(/usr/bin/find "$TEST_AGENT_DIR" -maxdepth 1 -name '.mainframe-pi-backup-*' -print | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"

    run mainframe_pi_remove --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=false'* ]]
    [[ "$output" == *'backup_dir=none'* ]]
    [[ "$(/usr/bin/find "$TEST_AGENT_DIR" -maxdepth 1 -name '.mainframe-pi-backup-*' -print | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')" == "$backup_count" ]]
}

@test "remove verification failure rolls settings and private receipt back" {
    local original receipt_original
    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    original="$(<"$TEST_AGENT_DIR/settings.json")"
    receipt_original="$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")"
    _mainframe_pi_verify_removed_state() { return 1; }

    run mainframe_pi_remove --yes
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'rollback=complete'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original" ]]
    [[ "$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")" == "$receipt_original" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-install.lock" ]]
}

@test "remove shares the lifecycle lock with install and never mutates while locked" {
    local original receipt_original
    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    original="$(<"$TEST_AGENT_DIR/settings.json")"
    receipt_original="$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")"
    /bin/mkdir -m 700 "$TEST_AGENT_DIR/.mainframe-pi-install.lock"

    run mainframe_pi_remove --yes
    [[ "$status" -eq 75 ]]
    [[ "$output" == *'lifecycle operation is active'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original" ]]
    [[ "$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")" == "$receipt_original" ]]
}

@test "CLI Pi actions and shell completions expose doctor plus consent-gated detach and restore" {
    local bash_actions bash_options bash_doctor_options bash_restore_options
    local zsh_actions zsh_options zsh_doctor_options zsh_restore_options
    run "$PROJECT_ROOT/bin/mainframe" pi install --yes
    [[ "$status" -eq 0 ]]

    run "$PROJECT_ROOT/bin/mainframe" pi remove --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'action=remove'* ]]
    [[ "$output" == *'would_change=true'* ]]

    run "$PROJECT_ROOT/bin/mainframe" pi remove --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=true'* ]]

    bash_actions="$(bash -c '
        source "$1"
        COMP_WORDS=(mainframe pi "")
        COMP_CWORD=2
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" | LC_ALL=C sort -u)"
    [[ "$bash_actions" == *remove* && "$bash_actions" == *restore* && "$bash_actions" == *doctor* ]]
    bash_doctor_options="$(bash -c '
        source "$1"
        COMP_WORDS=(mainframe pi doctor "")
        COMP_CWORD=3
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" | LC_ALL=C sort -u)"
    [[ "$bash_doctor_options" == *--json* ]]
    bash_options="$(bash -c '
        source "$1"
        COMP_WORDS=(mainframe pi remove "")
        COMP_CWORD=3
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" | LC_ALL=C sort -u)"
    [[ "$bash_options" == *--dry-run* && "$bash_options" == *--yes* ]]
    bash_restore_options="$(bash -c '
        source "$1"
        COMP_WORDS=(mainframe pi restore "")
        COMP_CWORD=3
        _mainframe_completions
        printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$PROJECT_ROOT/completions/mainframe.bash" | LC_ALL=C sort -u)"
    [[ "$bash_restore_options" == *--backup-id* ]]
    [[ "$bash_restore_options" == *--dry-run* && "$bash_restore_options" == *--yes* ]]

    if command -v zsh >/dev/null 2>&1; then
        zsh_actions="$(zsh -f -c '
            compdef() { :; }
            _values() { shift; print -rl -- "$@"; }
            source "$1"
            words=(mainframe pi "")
            CURRENT=3
            _mainframe
        ' _ "$PROJECT_ROOT/completions/mainframe.zsh")"
        [[ "$zsh_actions" == *remove* && "$zsh_actions" == *restore* && "$zsh_actions" == *doctor* ]]
        zsh_doctor_options="$(zsh -f -c '
            compdef() { :; }
            _values() { :; }
            _arguments() {
                local spec
                for spec in "$@"; do
                    [[ "$spec" == \(*\)* ]] && spec="${spec#*)}"
                    print -r -- "${spec%%\[*}"
                done
            }
            source "$1"
            words=(mainframe pi doctor "")
            CURRENT=4
            _mainframe
        ' _ "$PROJECT_ROOT/completions/mainframe.zsh" | LC_ALL=C sort -u)"
        [[ "$zsh_doctor_options" == *--json* ]]
        zsh_options="$(zsh -f -c '
            compdef() { :; }
            _values() { :; }
            _arguments() {
                local spec
                for spec in "$@"; do
                    [[ "$spec" == \(*\)* ]] && spec="${spec#*)}"
                    print -r -- "${spec%%\[*}"
                done
            }
            source "$1"
            words=(mainframe pi remove "")
            CURRENT=4
            _mainframe
        ' _ "$PROJECT_ROOT/completions/mainframe.zsh" | LC_ALL=C sort -u)"
        [[ "$zsh_options" == *--dry-run* && "$zsh_options" == *--yes* ]]
        zsh_restore_options="$(zsh -f -c '
            compdef() { :; }
            _values() { :; }
            _arguments() {
                local spec
                for spec in "$@"; do
                    [[ "$spec" == \(*\)* ]] && spec="${spec#*)}"
                    print -r -- "${spec%%\[*}"
                done
            }
            source "$1"
            words=(mainframe pi restore "")
            CURRENT=4
            _mainframe
        ' _ "$PROJECT_ROOT/completions/mainframe.zsh" | LC_ALL=C sort -u)"
        [[ "$zsh_restore_options" == *--backup-id* ]]
        [[ "$zsh_restore_options" == *--dry-run* && "$zsh_restore_options" == *--yes* ]]
    fi
}

@test "uninstall guard refuses an attached exact or receipted package and clears after remove" {
    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]

    run _mainframe_pi_uninstall_guard
    [[ "$status" -eq 77 ]]
    [[ "$output" == *'refusing to uninstall while the Mainframe Pi package is attached'* ]]
    [[ "$output" == *'mainframe pi remove --dry-run'* ]]

    run mainframe_pi_remove --yes
    [[ "$status" -eq 0 ]]
    run _mainframe_pi_uninstall_guard
    [[ "$status" -eq 0 ]]
}

@test "CLI previews and completes the transactional Pi migration" {
    write_migration_fixture

    run "$PROJECT_ROOT/bin/mainframe" pi install --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'dry_run=true'* ]]
    [[ "$output" == *'would_quarantine_extension=true'* ]]
    [[ "$output" == *'next_apply_command=mainframe pi install --yes'* ]]
    [[ "$output" == *'next_verify_command=/mainframe doctor'* ]]
    [[ -f "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]

    run "$PROJECT_ROOT/bin/mainframe" pi install --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=true'* ]]
    [[ "$output" == *'restart_needed=true'* ]]
    [[ ! -e "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]
    [[ ! -e "$TEST_AGENT_DIR/skills/mainframe" ]]

    run "$PROJECT_ROOT/bin/mainframe" pi status
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'state=ready'* ]]

    [[ "$(<"$PROJECT_ROOT/skills/README.md")" == *'run `/mainframe doctor`'* ]]
}

@test "Pi restore validates one migration backup and exactly recovers the pre-install snapshot" {
    local original_settings original_extension original_skill original_mode
    local backup_dir backup_id backup_before backup_after installed_settings installed_receipt
    write_migration_fixture
    original_settings="$(<"$TEST_AGENT_DIR/settings.json")"
    original_extension="$(<"$TEST_AGENT_DIR/extensions/mainframe.ts")"
    original_skill="$(<"$TEST_AGENT_DIR/skills/mainframe/SKILL.md")"
    original_mode="$(settings_mode "$TEST_AGENT_DIR/settings.json")"

    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    backup_dir="$(output_value backup_dir)"
    backup_id="$(output_value backup_id)"
    [[ "$backup_dir" == "$TEST_AGENT_DIR/$backup_id" ]]
    [[ "$backup_id" =~ ^\.mainframe-pi-backup-[0-9]{8}T[0-9]{6}Z\.[A-Za-z0-9]{6}$ ]]
    installed_settings="$(<"$TEST_AGENT_DIR/settings.json")"
    installed_receipt="$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")"
    backup_before="$(
        /usr/bin/find "$backup_dir" -type f -print0 |
            /usr/bin/sort -z |
            /usr/bin/xargs -0 /usr/bin/shasum -a 256
    )"

    run mainframe_pi_restore --backup-id "$backup_id" --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'action=restore'* ]]
    [[ "$output" == *'dry_run=true'* ]]
    [[ "$output" == *'would_change=true'* ]]
    [[ "$output" == *'current_phase=ready'* ]]
    [[ "$output" == *"backup_id=$backup_id"* ]]
    [[ "$output" == *'backup_sha256='* ]]
    [[ "$output" == *"next_apply_command=mainframe pi restore --backup-id $backup_id --yes"* ]]
    [[ "$output" == *'next_verify_command=mainframe pi status'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$installed_settings" ]]
    [[ "$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")" == "$installed_receipt" ]]
    [[ ! -e "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]
    [[ ! -e "$TEST_AGENT_DIR/skills/mainframe" ]]

    run mainframe_pi_restore --backup-id "$backup_id" --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=true'* ]]
    [[ "$output" == *'settings_restored=true'* ]]
    [[ "$output" == *'receipt_removed=true'* ]]
    [[ "$output" == *'extension_restored=true'* ]]
    [[ "$output" == *'skill_restored=true'* ]]
    [[ "$output" == *'backup_preserved=true'* ]]
    [[ "$output" == *'state=pre-install-snapshot'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original_settings" ]]
    [[ "$(settings_mode "$TEST_AGENT_DIR/settings.json")" == "$original_mode" ]]
    [[ "$(<"$TEST_AGENT_DIR/extensions/mainframe.ts")" == "$original_extension" ]]
    [[ "$(<"$TEST_AGENT_DIR/skills/mainframe/SKILL.md")" == "$original_skill" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-receipt.json" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-install.lock" ]]
    backup_after="$(
        /usr/bin/find "$backup_dir" -type f -print0 |
            /usr/bin/sort -z |
            /usr/bin/xargs -0 /usr/bin/shasum -a 256
    )"
    [[ "$backup_after" == "$backup_before" ]]

    run mainframe_pi_restore --backup-id "$backup_id" --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=false'* ]]
    [[ "$output" == *'restart_needed=false'* ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$original_settings" ]]
}

@test "Pi restore rejects ambiguous consent, unsafe IDs, project overrides, and post-install drift" {
    local backup_id installed_settings installed_receipt project
    write_migration_fixture
    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    backup_id="$(output_value backup_id)"
    installed_settings="$(<"$TEST_AGENT_DIR/settings.json")"
    installed_receipt="$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")"

    run mainframe_pi_restore --backup-id "$backup_id"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'requires exactly one of --dry-run or --yes'* ]]

    run mainframe_pi_restore --backup-id "$backup_id" --dry-run --yes
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'choose exactly one'* ]]

    run mainframe_pi_restore --backup-id '../settings.json' --dry-run
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'exact basename'* ]]

    export MAINFRAME_PI_YES=1
    run mainframe_pi_restore --backup-id "$backup_id" --yes
    [[ "$status" -eq 77 ]]
    [[ "$output" == *'inherited authorization is not accepted'* ]]
    unset MAINFRAME_PI_YES

    project="$TEST_ROOT/project-override"
    /bin/mkdir -m 700 "$project" "$project/.pi" "$project/.pi/extensions"
    printf 'project override\n' > "$project/.pi/extensions/mainframe.ts"
    /bin/chmod 600 "$project/.pi/extensions/mainframe.ts"
    run install_from_project "$project" --dry-run
    [[ "$status" -eq 0 ]]
    run cd "$project"
    [[ "$status" -eq 0 ]]
    run bash -c 'cd "$1" && source "$2/lib/pi.sh" && mainframe_pi_restore --backup-id "$3" --dry-run' \
        _ "$project" "$PROJECT_ROOT" "$backup_id"
    [[ "$status" -eq 77 ]]
    [[ "$output" == *'project-local Mainframe Pi resources'* ]]

    "$TEST_PYTHON" - "$TEST_AGENT_DIR/settings.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    document = json.load(handle)
document["unrelated_after_install"] = True
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
    /bin/chmod 640 "$TEST_AGENT_DIR/settings.json"
    run mainframe_pi_restore --backup-id "$backup_id" --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'state diverged'* ]]
    [[ "$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")" == "$installed_receipt" ]]
    [[ ! -e "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]
    [[ ! -e "$TEST_AGENT_DIR/skills/mainframe" ]]
    [[ "$installed_settings" != "$(<"$TEST_AGENT_DIR/settings.json")" ]]
}

@test "Pi restore rejects symlinked or unsafe destination parents before any recovery write" {
    local backup_id installed_settings installed_receipt outside
    write_migration_fixture
    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    backup_id="$(output_value backup_id)"
    installed_settings="$(<"$TEST_AGENT_DIR/settings.json")"
    installed_receipt="$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")"

    outside="$TEST_ROOT/outside-restore-parent"
    /bin/mkdir -m 700 "$outside"
    /bin/mv "$TEST_AGENT_DIR/extensions" "$TEST_AGENT_DIR/extensions.real"
    /bin/ln -s "$outside" "$TEST_AGENT_DIR/extensions"
    run mainframe_pi_restore --backup-id "$backup_id" --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'Pi restore destination parent is unsafe or missing'* ]]
    [[ ! -e "$outside/mainframe.ts" ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$installed_settings" ]]
    [[ "$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")" == "$installed_receipt" ]]
    /bin/unlink "$TEST_AGENT_DIR/extensions"
    /bin/mv "$TEST_AGENT_DIR/extensions.real" "$TEST_AGENT_DIR/extensions"

    /bin/chmod 722 "$TEST_AGENT_DIR/skills"
    run mainframe_pi_restore --backup-id "$backup_id" --yes
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'Pi restore destination parent is unsafe or missing'* ]]
    /bin/chmod 700 "$TEST_AGENT_DIR/skills"
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-install.lock" ]]
    [[ ! -e "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]
    [[ ! -e "$TEST_AGENT_DIR/skills/mainframe" ]]
    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$installed_settings" ]]
    [[ "$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")" == "$installed_receipt" ]]
}

@test "Pi restore rolls an orderly failure back to exact ready state" {
    local backup_id installed_settings installed_receipt
    write_migration_fixture
    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    backup_id="$(output_value backup_id)"
    installed_settings="$(<"$TEST_AGENT_DIR/settings.json")"
    installed_receipt="$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")"

    /bin/chmod 500 "$TEST_AGENT_DIR/extensions"
    run mainframe_pi_restore --backup-id "$backup_id" --yes
    [[ "$status" -eq 1 ]]
    [[ "$output" == *'rollback=complete'* ]]
    /bin/chmod 700 "$TEST_AGENT_DIR/extensions"

    [[ "$(<"$TEST_AGENT_DIR/settings.json")" == "$installed_settings" ]]
    [[ "$(<"$TEST_AGENT_DIR/.mainframe-pi-receipt.json")" == "$installed_receipt" ]]
    [[ ! -e "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]
    [[ ! -e "$TEST_AGENT_DIR/skills/mainframe" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-install.lock" ]]

    run mainframe_pi_restore --backup-id "$backup_id" --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=true'* ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-receipt.json" ]]
    [[ -f "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]
    [[ -f "$TEST_AGENT_DIR/skills/mainframe/SKILL.md" ]]
}

@test "Pi restore preserves validated legacy modes under a restrictive caller umask" {
    local backup_id
    write_migration_fixture
    /bin/chmod 755 "$TEST_AGENT_DIR/skills/mainframe"
    /bin/chmod 644 "$TEST_AGENT_DIR/skills/mainframe/SKILL.md"
    /bin/chmod 644 "$TEST_AGENT_DIR/extensions/mainframe.ts"
    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    backup_id="$(output_value backup_id)"

    run /bin/bash -c 'umask 077; source "$1/lib/pi.sh"; mainframe_pi_restore --backup-id "$2" --yes' \
        _ "$PROJECT_ROOT" "$backup_id"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=true'* ]]
    [[ "$(settings_mode "$TEST_AGENT_DIR/skills/mainframe")" == 755 ]]
    [[ "$(settings_mode "$TEST_AGENT_DIR/skills/mainframe/SKILL.md")" == 644 ]]
    [[ "$(settings_mode "$TEST_AGENT_DIR/extensions/mainframe.ts")" == 644 ]]
}

@test "Pi restore resumes only a validated recognized interrupted phase" {
    local backup_dir backup_id backup_sha package_source
    write_migration_fixture
    run mainframe_pi_install --yes
    [[ "$status" -eq 0 ]]
    backup_dir="$(output_value backup_dir)"
    backup_id="$(output_value backup_id)"
    package_source="$(output_value package_source)"

    run mainframe_pi_restore --backup-id "$backup_id" --dry-run
    [[ "$status" -eq 0 ]]
    backup_sha="$(output_value backup_sha256)"
    [[ "$backup_sha" =~ ^[0-9a-f]{64}$ ]]

    /bin/cp -pR "$backup_dir/skills/mainframe" "$TEST_AGENT_DIR/skills/mainframe"
    /bin/mkdir -m 700 "$TEST_AGENT_DIR/.mainframe-pi-install.lock"
    "$TEST_PYTHON" - \
        "$TEST_AGENT_DIR/.mainframe-pi-install.lock/restore-journal.json" \
        "$backup_id" "$backup_sha" "$package_source" <<'PY'
import json
import sys

path, backup_id, backup_sha, package_source = sys.argv[1:5]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({
        "schema_version": 1,
        "operation": "restore",
        "backup_id": backup_id,
        "backup_sha256": backup_sha,
        "package_source": package_source,
        "phase": "skill-restored",
        "pid": 999999,
    }, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
    /bin/chmod 600 "$TEST_AGENT_DIR/.mainframe-pi-install.lock/restore-journal.json"

    run mainframe_pi_restore --backup-id "$backup_id" --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=true'* ]]
    [[ "$output" == *'state=pre-install-snapshot'* ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-install.lock" ]]
    [[ ! -e "$TEST_AGENT_DIR/.mainframe-pi-receipt.json" ]]
    [[ -f "$TEST_AGENT_DIR/extensions/mainframe.ts" ]]
    [[ -f "$TEST_AGENT_DIR/skills/mainframe/SKILL.md" ]]
}
