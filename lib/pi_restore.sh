#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/pi_restore.sh - Exact post-install Pi migration recovery
# =============================================================================
# This file is loaded lazily by mainframe_pi_restore in lib/pi.sh. It restores
# only a private backup produced by a completed legacy-to-package migration.
# It is deliberately not a general backup browser or project-resource restore.
# =============================================================================

[[ -n "${_MAINFRAME_PI_RESTORE_LOADED:-}" ]] && return 0
_MAINFRAME_PI_RESTORE_LOADED=1

_mainframe_pi_restore_engine() {
    local agent_dir="$1" backup_dir="$2" backup_id="$3" operation="$4" lock_dir="${5:-none}"

    _mainframe_pi_python \
        "$agent_dir" "$backup_dir" "$backup_id" \
        "$_MAINFRAME_PI_ROOT" "$_MAINFRAME_PI_PACKAGE_SOURCE" \
        "${HOME:-}" "$operation" "$lock_dir" "$EUID" <<'PY'
import hashlib
import json
import os
import re
import shutil
import signal
import stat
import struct
import sys
import tempfile

(
    agent_dir,
    backup_dir,
    backup_id,
    package_root,
    package_source,
    home_dir,
    operation,
    lock_dir,
) = sys.argv[1:9]
expected_uid = int(sys.argv[9])

if operation not in {"inspect", "apply"}:
    raise SystemExit("invalid Pi restore operation")
if not re.fullmatch(r"\.mainframe-pi-backup-[0-9]{8}T[0-9]{6}Z\.[A-Za-z0-9]{6}", backup_id):
    raise SystemExit("invalid Pi restore backup ID")
if backup_dir != os.path.join(agent_dir, backup_id):
    raise SystemExit("Pi restore backup escaped the agent directory")

MAX_FILES = 2000
MAX_BYTES = 32 * 1024 * 1024
SAFE_WRITE_MASK = 0o7022


def fsync_directory(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def metadata(path, *, directory=None, exact_mode=None):
    value = os.lstat(path)
    if stat.S_ISLNK(value.st_mode):
        raise RuntimeError(f"symbolic link is not allowed: {path}")
    if directory is True and not stat.S_ISDIR(value.st_mode):
        raise RuntimeError(f"directory required: {path}")
    if directory is False and not stat.S_ISREG(value.st_mode):
        raise RuntimeError(f"regular file required: {path}")
    if directory is None and not (stat.S_ISDIR(value.st_mode) or stat.S_ISREG(value.st_mode)):
        raise RuntimeError(f"unsupported file type: {path}")
    if value.st_uid != expected_uid:
        raise RuntimeError(f"unexpected owner: {path}")
    mode = stat.S_IMODE(value.st_mode)
    if mode & SAFE_WRITE_MASK:
        raise RuntimeError(f"unsafe permissions: {path}")
    if exact_mode is not None and mode != exact_mode:
        raise RuntimeError(f"unexpected mode: {path}")
    if stat.S_ISREG(value.st_mode) and value.st_nlink != 1:
        raise RuntimeError(f"hard-linked file is not allowed: {path}")
    return value


def read_regular(path, *, max_bytes=MAX_BYTES, exact_mode=None):
    before = metadata(path, directory=False, exact_mode=exact_mode)
    if before.st_size > max_bytes:
        raise RuntimeError(f"file is too large: {path}")
    with open(path, "rb") as handle:
        raw = handle.read(max_bytes + 1)
        after = os.fstat(handle.fileno())
    if len(raw) > max_bytes:
        raise RuntimeError(f"file is too large: {path}")
    if (before.st_dev, before.st_ino, before.st_size) != (after.st_dev, after.st_ino, after.st_size):
        raise RuntimeError(f"file changed while it was read: {path}")
    return raw, stat.S_IMODE(before.st_mode)


def write_all(descriptor, raw):
    view = memoryview(raw)
    offset = 0
    while offset < len(view):
        written = os.write(descriptor, view[offset:])
        if written <= 0:
            raise OSError("short write while preparing Pi restore data")
        offset += written


def verify_descriptor_bytes(descriptor, expected):
    position = os.lseek(descriptor, 0, os.SEEK_CUR)
    try:
        os.lseek(descriptor, 0, os.SEEK_SET)
        remaining = len(expected)
        digest = hashlib.sha256()
        while remaining:
            chunk = os.read(descriptor, min(1024 * 1024, remaining))
            if not chunk:
                raise RuntimeError("prepared Pi restore data was truncated")
            digest.update(chunk)
            remaining -= len(chunk)
        if os.read(descriptor, 1):
            raise RuntimeError("prepared Pi restore data has unexpected trailing bytes")
        if digest.digest() != hashlib.sha256(expected).digest():
            raise RuntimeError("prepared Pi restore data failed its digest check")
    finally:
        os.lseek(descriptor, position, os.SEEK_SET)


def walk_manifest(root, *, include_root=True):
    entries = []
    total_bytes = 0
    total_files = 0
    root = os.path.normpath(root)
    metadata(root, directory=True)
    stack = [(root, ".")]
    while stack:
        current, relative = stack.pop()
        current_metadata = metadata(current, directory=True)
        if include_root or relative != ".":
            entries.append((relative, "directory", stat.S_IMODE(current_metadata.st_mode), 0, b""))
        children = list(os.scandir(current))
        children.sort(key=lambda item: os.fsencode(item.name), reverse=True)
        for child in children:
            child_path = os.path.join(current, child.name)
            child_relative = child.name if relative == "." else f"{relative}/{child.name}"
            child_metadata = metadata(child_path)
            if stat.S_ISDIR(child_metadata.st_mode):
                stack.append((child_path, child_relative))
                continue
            raw, mode = read_regular(child_path)
            total_files += 1
            total_bytes += len(raw)
            if total_files > MAX_FILES or total_bytes > MAX_BYTES:
                raise RuntimeError("Pi restore backup tree exceeds safe limits")
            entries.append((child_relative, "file", mode, len(raw), hashlib.sha256(raw).digest()))
    entries.sort(key=lambda entry: os.fsencode(entry[0]))
    return entries


def manifest_digest(entries):
    digest = hashlib.sha256()
    for relative, entry_type, mode, size, content_digest in entries:
        encoded = os.fsencode(relative)
        digest.update(struct.pack(">I", len(encoded)))
        digest.update(encoded)
        digest.update(b"D" if entry_type == "directory" else b"F")
        digest.update(struct.pack(">IQ", mode, size))
        digest.update(content_digest)
    return digest.hexdigest()


def file_signature(path):
    raw, mode = read_regular(path)
    return mode, hashlib.sha256(raw).hexdigest(), raw


def tree_signature(path):
    return manifest_digest(walk_manifest(path))


def validate_backup():
    root_metadata = metadata(backup_dir, directory=True, exact_mode=0o700)
    if os.path.realpath(os.path.dirname(backup_dir)) != os.path.realpath(agent_dir):
        raise RuntimeError("Pi restore backup is not directly under the agent directory")
    allowed = {
        "settings.json.before",
        "settings.mode",
        "manager-receipt.absent",
        "extensions",
        "skills",
    }
    names = set(os.listdir(backup_dir))
    if names != allowed:
        raise RuntimeError("Pi restore backup has an unsupported or incomplete shape")
    extensions_dir = os.path.join(backup_dir, "extensions")
    skills_dir = os.path.join(backup_dir, "skills")
    metadata(extensions_dir, directory=True, exact_mode=0o700)
    metadata(skills_dir, directory=True, exact_mode=0o700)
    if set(os.listdir(extensions_dir)) != {"mainframe.ts"}:
        raise RuntimeError("Pi restore extension backup has an unsupported shape")
    if set(os.listdir(skills_dir)) != {"mainframe"}:
        raise RuntimeError("Pi restore skill backup has an unsupported shape")
    marker_raw, _ = read_regular(os.path.join(backup_dir, "manager-receipt.absent"), exact_mode=0o600)
    if marker_raw:
        raise RuntimeError("Pi restore receipt-absence marker is not empty")
    settings_raw, _ = read_regular(os.path.join(backup_dir, "settings.json.before"), exact_mode=0o600)
    mode_raw, _ = read_regular(os.path.join(backup_dir, "settings.mode"), exact_mode=0o600)
    try:
        saved_mode_text = mode_raw.decode("ascii")
    except UnicodeError as error:
        raise RuntimeError(f"invalid saved settings mode: {error}")
    if not re.fullmatch(r"[0-7]{3,4}\n", saved_mode_text):
        raise RuntimeError("invalid saved settings mode")
    saved_mode = int(saved_mode_text.strip(), 8)
    if saved_mode & SAFE_WRITE_MASK:
        raise RuntimeError("saved settings mode is unsafe")
    extension_path = os.path.join(extensions_dir, "mainframe.ts")
    skill_path = os.path.join(skills_dir, "mainframe")
    extension_mode, extension_digest, _ = file_signature(extension_path)
    skill_digest = tree_signature(skill_path)
    entries = walk_manifest(backup_dir, include_root=False)
    return {
        "settings_raw": settings_raw,
        "settings_mode": saved_mode,
        "extension_path": extension_path,
        "extension_mode": extension_mode,
        "extension_digest": extension_digest,
        "skill_path": skill_path,
        "skill_digest": skill_digest,
        "backup_sha256": manifest_digest(entries),
        "root_dev": root_metadata.st_dev,
        "root_ino": root_metadata.st_ino,
    }


def recheck_backup(snapshot):
    value = metadata(backup_dir, directory=True, exact_mode=0o700)
    if (value.st_dev, value.st_ino) != (snapshot["root_dev"], snapshot["root_ino"]):
        raise RuntimeError("Pi restore backup directory identity changed")
    if manifest_digest(walk_manifest(backup_dir, include_root=False)) != snapshot["backup_sha256"]:
        raise RuntimeError("Pi restore backup changed after validation")


def source_string(entry):
    if isinstance(entry, str):
        return entry
    if isinstance(entry, dict) and isinstance(entry.get("source"), str):
        return entry["source"]
    raise RuntimeError("invalid Pi settings: package entries must be strings or objects with a string source")


def local_path(source, base, *, resolve_links=True):
    source = source.strip()
    if source.startswith(("npm:", "git:")) or re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", source):
        return None
    if source == "~" or source.startswith("~/"):
        if not home_dir:
            return None
        source = home_dir + source[1:]
    if not os.path.isabs(source):
        source = os.path.join(base, source)
    source = os.path.normpath(os.path.abspath(source))
    return os.path.realpath(source) if resolve_links else source


def exact_legacy_extension(entry):
    entry = entry.strip()
    if not entry or entry[0] in "!-" or any(char in entry for char in "*?[]"):
        return False
    if entry.startswith("+"):
        entry = entry[1:]
    legacy = os.path.normpath(os.path.join(agent_dir, "extensions", "mainframe.ts"))
    return local_path(entry, agent_dir) == legacy


def settings_documents(settings_raw):
    try:
        before = json.loads(settings_raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"invalid backed-up Pi settings: {error}")
    if not isinstance(before, dict):
        raise RuntimeError("invalid backed-up Pi settings: top-level value must be an object")
    packages = before.get("packages", [])
    extensions = before.get("extensions", [])
    if not isinstance(packages, list):
        raise RuntimeError("invalid backed-up Pi settings: packages must be an array")
    for entry in packages:
        source_string(entry)
    if not isinstance(extensions, list) or not all(isinstance(item, str) for item in extensions):
        raise RuntimeError("invalid backed-up Pi settings: extensions must be an array of strings")
    if not any(exact_legacy_extension(entry) for entry in extensions):
        raise RuntimeError("backup is not a recognized legacy Mainframe migration")
    after = json.loads(json.dumps(before))
    after["packages"] = [
        entry for entry in packages
        if local_path(source_string(entry), agent_dir) != package_root
    ]
    after["packages"].append(package_source)
    if "extensions" in after:
        after["extensions"] = [entry for entry in extensions if not exact_legacy_extension(entry)]
    post_raw = (json.dumps(after, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    receipt_raw = (json.dumps({
        "schema_version": 1,
        "manager": "@gtwatts/mainframe-pi",
        "package_source": package_source,
    }, indent=2) + "\n").encode("utf-8")
    return post_raw, receipt_raw


def path_state(path, expected_kind, expected):
    if not os.path.lexists(path):
        return "absent"
    try:
        if expected_kind == "file":
            mode, digest, _ = file_signature(path)
            return "exact" if (mode, digest) == expected else "diverged"
        return "exact" if tree_signature(path) == expected else "diverged"
    except (OSError, RuntimeError):
        return "diverged"


def current_phase(snapshot, post_raw, receipt_raw):
    settings_path = os.path.join(agent_dir, "settings.json")
    receipt_path = os.path.join(agent_dir, ".mainframe-pi-receipt.json")
    extension_path = os.path.join(agent_dir, "extensions", "mainframe.ts")
    skill_path = os.path.join(agent_dir, "skills", "mainframe")
    current_settings, current_mode = read_regular(settings_path)
    if current_mode != snapshot["settings_mode"]:
        raise RuntimeError("current Pi settings mode diverged from the migration snapshot")
    settings_state = (
        "post" if current_settings == post_raw
        else "target" if current_settings == snapshot["settings_raw"]
        else "diverged"
    )
    if os.path.lexists(receipt_path):
        current_receipt, receipt_mode = read_regular(receipt_path, exact_mode=0o600)
        receipt_state = "current" if current_receipt == receipt_raw else "diverged"
    else:
        receipt_state = "absent"
    extension_state = path_state(
        extension_path,
        "file",
        (snapshot["extension_mode"], snapshot["extension_digest"]),
    )
    skill_state = path_state(skill_path, "tree", snapshot["skill_digest"])
    states = (settings_state, receipt_state, extension_state, skill_state)
    phases = {
        ("post", "current", "absent", "absent"): "ready",
        ("post", "current", "absent", "exact"): "skill-restored",
        ("post", "current", "exact", "exact"): "resources-restored",
        ("target", "current", "exact", "exact"): "settings-restored",
        ("target", "absent", "exact", "exact"): "complete",
    }
    phase = phases.get(states)
    if phase is None:
        raise RuntimeError(
            "Pi restore state diverged from every validated recovery phase "
            f"(settings={settings_state}, receipt={receipt_state}, "
            f"extension={extension_state}, skill={skill_state})"
        )
    return phase


def validate_destination_parents():
    identities = {}
    for label, path in (
        ("agent", agent_dir),
        ("extensions", os.path.join(agent_dir, "extensions")),
        ("skills", os.path.join(agent_dir, "skills")),
    ):
        value = metadata(path, directory=True)
        identities[label] = (value.st_dev, value.st_ino)
    return identities


def recheck_destination_parents(expected):
    current = validate_destination_parents()
    if current != expected:
        raise RuntimeError("Pi restore destination ancestry changed during recovery")


def copy_regular_atomic(source, destination, mode, expected_digest):
    parent = os.path.dirname(destination)
    descriptor, temporary = tempfile.mkstemp(prefix=".mainframe-pi-restore.", dir=parent)
    try:
        raw, source_mode = read_regular(source)
        if source_mode != mode:
            raise RuntimeError("restore source mode changed")
        if hashlib.sha256(raw).hexdigest() != expected_digest:
            raise RuntimeError("restore source content changed")
        os.fchmod(descriptor, mode)
        write_all(descriptor, raw)
        verify_descriptor_bytes(descriptor, raw)
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        if os.path.lexists(destination):
            raise RuntimeError(f"restore destination appeared: {destination}")
        os.replace(temporary, destination)
        fsync_directory(parent)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if os.path.exists(temporary):
            os.unlink(temporary)


def copy_tree_contents(source, destination):
    source_mode = stat.S_IMODE(metadata(source, directory=True).st_mode)
    os.mkdir(destination, source_mode)
    os.chmod(destination, source_mode, follow_symlinks=False)
    for entry in sorted(os.scandir(source), key=lambda item: os.fsencode(item.name)):
        source_path = os.path.join(source, entry.name)
        destination_path = os.path.join(destination, entry.name)
        value = metadata(source_path)
        if stat.S_ISDIR(value.st_mode):
            copy_tree_contents(source_path, destination_path)
        else:
            raw, mode = read_regular(source_path)
            descriptor = os.open(destination_path, os.O_RDWR | os.O_CREAT | os.O_EXCL, mode)
            try:
                os.fchmod(descriptor, mode)
                write_all(descriptor, raw)
                verify_descriptor_bytes(descriptor, raw)
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
    fsync_directory(destination)


def copy_tree_atomic(source, destination, expected_digest):
    parent = os.path.dirname(destination)
    temporary = tempfile.mkdtemp(prefix=".mainframe-pi-skill-restore.", dir=parent)
    try:
        os.rmdir(temporary)
        copy_tree_contents(source, temporary)
        if tree_signature(temporary) != expected_digest:
            raise RuntimeError("prepared skill restore did not match its validated backup")
        if os.path.lexists(destination):
            raise RuntimeError(f"restore destination appeared: {destination}")
        os.replace(temporary, destination)
        fsync_directory(parent)
    finally:
        if os.path.exists(temporary):
            shutil.rmtree(temporary)


def replace_regular_bytes(path, expected_raw, next_raw, mode):
    current_raw, current_mode = read_regular(path)
    if current_raw != expected_raw or current_mode != mode:
        raise RuntimeError(f"refusing to replace a changed file: {path}")
    descriptor, temporary = tempfile.mkstemp(prefix=".mainframe-pi-restore.", dir=os.path.dirname(path))
    try:
        os.fchmod(descriptor, mode)
        write_all(descriptor, next_raw)
        verify_descriptor_bytes(descriptor, next_raw)
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(temporary, path)
        fsync_directory(os.path.dirname(path))
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if os.path.exists(temporary):
            os.unlink(temporary)


def write_regular_absent(path, raw, mode):
    if os.path.lexists(path):
        raise RuntimeError(f"restore target unexpectedly exists: {path}")
    descriptor, temporary = tempfile.mkstemp(prefix=".mainframe-pi-rollback.", dir=os.path.dirname(path))
    try:
        os.fchmod(descriptor, mode)
        write_all(descriptor, raw)
        verify_descriptor_bytes(descriptor, raw)
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(temporary, path)
        fsync_directory(os.path.dirname(path))
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if os.path.exists(temporary):
            os.unlink(temporary)


def journal_write(phase, snapshot):
    path = os.path.join(lock_dir, "restore-journal.json")
    document = {
        "schema_version": 1,
        "operation": "restore",
        "backup_id": backup_id,
        "backup_sha256": snapshot["backup_sha256"],
        "package_source": package_source,
        "phase": phase,
        "pid": os.getpid(),
    }
    raw = (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")
    descriptor, temporary = tempfile.mkstemp(prefix=".restore-journal.", dir=lock_dir)
    try:
        os.fchmod(descriptor, 0o600)
        write_all(descriptor, raw)
        verify_descriptor_bytes(descriptor, raw)
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(temporary, path)
        fsync_directory(lock_dir)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if os.path.exists(temporary):
            os.unlink(temporary)


def journal_open(snapshot):
    path = os.path.join(lock_dir, "restore-journal.json")
    if not os.path.exists(path):
        journal_write("prepared", snapshot)
        return
    raw, _ = read_regular(path, max_bytes=16 * 1024, exact_mode=0o600)
    try:
        document = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"invalid Pi restore journal: {error}")
    required = {"schema_version", "operation", "backup_id", "backup_sha256", "package_source", "phase", "pid"}
    if not isinstance(document, dict) or set(document) != required:
        raise RuntimeError("invalid Pi restore journal schema")
    if (
        document["schema_version"] != 1
        or document["operation"] != "restore"
        or document["backup_id"] != backup_id
        or document["backup_sha256"] != snapshot["backup_sha256"]
        or document["package_source"] != package_source
        or document["phase"] not in {
            "prepared", "skill-restored", "resources-restored", "settings-restored", "complete", "rollback-incomplete"
        }
        or not isinstance(document["pid"], int)
        or document["pid"] <= 0
    ):
        raise RuntimeError("Pi restore journal does not authenticate this recovery request")
    previous_pid = document["pid"]
    if previous_pid != os.getpid():
        try:
            os.kill(previous_pid, 0)
        except ProcessLookupError:
            pass
        except PermissionError:
            raise RuntimeError("another Pi restore process owns the lifecycle lock")
        else:
            raise RuntimeError("another Pi restore process is still active")
    journal_write(document["phase"], snapshot)


def journal_remove():
    path = os.path.join(lock_dir, "restore-journal.json")
    if os.path.lexists(path):
        metadata(path, directory=False, exact_mode=0o600)
        os.unlink(path)
        fsync_directory(lock_dir)


snapshot = validate_backup()
destination_parents = validate_destination_parents()
post_settings, current_receipt = settings_documents(snapshot["settings_raw"])
phase = current_phase(snapshot, post_settings, current_receipt)

if operation == "inspect":
    changed = phase != "complete"
    print("action=restore")
    print("dry_run=true")
    print(f"would_change={'true' if changed else 'false'}")
    print(f"agent_dir={agent_dir}")
    print(f"backup_id={backup_id}")
    print(f"backup_dir={backup_dir}")
    print(f"backup_sha256={snapshot['backup_sha256']}")
    print(f"current_phase={phase}")
    print("target_state=pre-install-snapshot")
    print(f"would_restore_settings={'false' if phase in {'settings-restored', 'complete'} else 'true'}")
    print(f"would_remove_manager_receipt={'false' if phase == 'complete' else 'true'}")
    print(f"would_restore_extension={'true' if phase in {'ready', 'skill-restored'} else 'false'}")
    print(f"would_restore_skill={'true' if phase == 'ready' else 'false'}")
    print("backup_preserved=true")
    print(f"restart_needed_after_restore={'true' if changed else 'false'}")
    print(f"next_apply_command={'mainframe pi restore --backup-id ' + backup_id + ' --yes' if changed else 'none'}")
    print("next_reload_instruction=Restart Pi after restore before testing the recovered integration." if changed else "next_reload_instruction=none")
    print("next_verify_command=mainframe pi status" if changed else "next_verify_command=none")
    raise SystemExit(0)

metadata(lock_dir, directory=True, exact_mode=0o700)
journal_open(snapshot)
initial_phase = phase
settings_path = os.path.join(agent_dir, "settings.json")
receipt_path = os.path.join(agent_dir, ".mainframe-pi-receipt.json")
extension_path = os.path.join(agent_dir, "extensions", "mainframe.ts")
skill_path = os.path.join(agent_dir, "skills", "mainframe")


class RestoreSignal(RuntimeError):
    pass


def signal_handler(signum, _frame):
    raise RestoreSignal(f"Pi restore interrupted by signal {signum}")


for signal_name in ("SIGINT", "SIGTERM", "SIGHUP"):
    if hasattr(signal, signal_name):
        signal.signal(getattr(signal, signal_name), signal_handler)


def rollback_to_ready():
    rollback_phase = current_phase(snapshot, post_settings, current_receipt)
    if rollback_phase == "complete":
        write_regular_absent(receipt_path, current_receipt, 0o600)
        rollback_phase = current_phase(snapshot, post_settings, current_receipt)
    if rollback_phase == "settings-restored":
        replace_regular_bytes(settings_path, snapshot["settings_raw"], post_settings, snapshot["settings_mode"])
        rollback_phase = current_phase(snapshot, post_settings, current_receipt)
    if rollback_phase == "resources-restored":
        if path_state(extension_path, "file", (snapshot["extension_mode"], snapshot["extension_digest"])) != "exact":
            raise RuntimeError("refusing to remove a changed restored extension during rollback")
        os.unlink(extension_path)
        fsync_directory(os.path.dirname(extension_path))
        rollback_phase = current_phase(snapshot, post_settings, current_receipt)
    if rollback_phase == "skill-restored":
        if path_state(skill_path, "tree", snapshot["skill_digest"]) != "exact":
            raise RuntimeError("refusing to remove a changed restored skill during rollback")
        shutil.rmtree(skill_path)
        fsync_directory(os.path.dirname(skill_path))
    if current_phase(snapshot, post_settings, current_receipt) != "ready":
        raise RuntimeError("Pi restore rollback did not return to the exact package-ready state")


try:
    recheck_backup(snapshot)
    recheck_destination_parents(destination_parents)
    phase = current_phase(snapshot, post_settings, current_receipt)
    if phase == "ready":
        recheck_destination_parents(destination_parents)
        copy_tree_atomic(snapshot["skill_path"], skill_path, snapshot["skill_digest"])
        phase = current_phase(snapshot, post_settings, current_receipt)
        journal_write(phase, snapshot)
    if phase == "skill-restored":
        recheck_destination_parents(destination_parents)
        copy_regular_atomic(
            snapshot["extension_path"],
            extension_path,
            snapshot["extension_mode"],
            snapshot["extension_digest"],
        )
        phase = current_phase(snapshot, post_settings, current_receipt)
        journal_write(phase, snapshot)
    if phase == "resources-restored":
        replace_regular_bytes(settings_path, post_settings, snapshot["settings_raw"], snapshot["settings_mode"])
        phase = current_phase(snapshot, post_settings, current_receipt)
        journal_write(phase, snapshot)
    if phase == "settings-restored":
        raw, mode = read_regular(receipt_path, exact_mode=0o600)
        if raw != current_receipt or mode != 0o600:
            raise RuntimeError("refusing to remove a changed Pi manager receipt")
        os.unlink(receipt_path)
        fsync_directory(agent_dir)
        phase = current_phase(snapshot, post_settings, current_receipt)
        journal_write(phase, snapshot)
    if phase != "complete":
        raise RuntimeError(f"Pi restore stopped at an unexpected phase: {phase}")
    journal_remove()
except BaseException as error:
    try:
        rollback_to_ready()
        journal_remove()
        print(f"MAINFRAME Pi: restore failed; rollback=complete; backup_dir={backup_dir}", file=sys.stderr)
    except BaseException as rollback_error:
        try:
            journal_write("rollback-incomplete", snapshot)
        except BaseException:
            pass
        print(
            "MAINFRAME Pi: restore failed; rollback=incomplete; "
            f"recovery_backup={backup_dir}; error={error}; rollback_error={rollback_error}",
            file=sys.stderr,
        )
    raise SystemExit(1)

changed = initial_phase != "complete"
print("action=restore")
print("dry_run=false")
print(f"changed={'true' if changed else 'false'}")
print(f"agent_dir={agent_dir}")
print(f"backup_id={backup_id}")
print(f"backup_dir={backup_dir}")
print(f"backup_sha256={snapshot['backup_sha256']}")
print(f"settings_restored={'true' if changed else 'false'}")
print(f"receipt_removed={'true' if changed else 'false'}")
print(f"extension_restored={'true' if changed else 'false'}")
print(f"skill_restored={'true' if changed else 'false'}")
print("backup_preserved=true")
print("state=pre-install-snapshot")
print(f"restart_needed={'true' if changed else 'false'}")
print("reload_hint=Restart Pi before testing the restored integration." if changed else "reload_hint=none")
PY
}

_mainframe_pi_restore_command() {
    local dry_run=false approved=false backup_id='' mode_seen=false agent_dir backup_dir
    local status_text lock_dir lock_created=false arg

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --backup-id)
                [[ -z "$backup_id" ]] || { _mainframe_pi_error 'duplicate --backup-id'; return 64; }
                shift
                [[ $# -gt 0 ]] || { _mainframe_pi_error '--backup-id requires a value'; return 64; }
                backup_id="$1"
                ;;
            --dry-run)
                [[ "$mode_seen" == false ]] || { _mainframe_pi_error 'choose exactly one of --dry-run or --yes'; return 64; }
                dry_run=true
                mode_seen=true
                ;;
            --yes)
                [[ "$mode_seen" == false ]] || { _mainframe_pi_error 'choose exactly one of --dry-run or --yes'; return 64; }
                approved=true
                mode_seen=true
                ;;
            -h|--help) _mainframe_pi_usage_restore; return 0 ;;
            *) _mainframe_pi_error "unknown restore option: $arg"; _mainframe_pi_usage_restore >&2; return 64 ;;
        esac
        shift
    done

    [[ "$mode_seen" == true ]] || {
        _mainframe_pi_error 'restore requires exactly one of --dry-run or --yes'
        return 64
    }
    [[ -n "$backup_id" ]] || { _mainframe_pi_error 'restore requires --backup-id'; return 64; }
    [[ "$backup_id" =~ ^\.mainframe-pi-backup-[0-9]{8}T[0-9]{6}Z\.[A-Za-z0-9]{6}$ ]] || {
        _mainframe_pi_error 'restore backup ID must be the exact basename emitted by a Mainframe Pi install'
        return 64
    }
    if [[ "$approved" == true ]] &&
       [[ -n "${MAINFRAME_PI_YES+x}" || -n "${MAINFRAME_YES+x}" ]]; then
        _mainframe_pi_error 'inherited authorization is not accepted; unset it and pass --yes on this command'
        return 77
    fi

    agent_dir="$(_mainframe_pi_agent_dir)" || {
        _mainframe_pi_error 'Pi agent directory must be an absolute path without dot segments or control characters'
        return 64
    }
    _mainframe_pi_preflight "$agent_dir" || return 1
    _mainframe_pi_restore_validate_destination_parents "$agent_dir" || return 1
    backup_dir="$agent_dir/$backup_id"
    status_text="$(_mainframe_pi_collect_status "$agent_dir" kv)" || return 1
    if _mainframe_pi_project_blocked "$status_text"; then
        _mainframe_pi_error 'project-local Mainframe Pi resources or package settings require separate project authorization; no project or user files were changed'
        return 77
    fi

    if [[ "$dry_run" == true ]]; then
        _mainframe_pi_restore_engine "$agent_dir" "$backup_dir" "$backup_id" inspect
        return $?
    fi

    lock_dir="$agent_dir/.mainframe-pi-install.lock"
    if /bin/mkdir -m 700 "$lock_dir" 2>/dev/null; then
        lock_created=true
    elif [[ -d "$lock_dir" && ! -L "$lock_dir" && -f "$lock_dir/restore-journal.json" ]]; then
        lock_created=false
    else
        _mainframe_pi_error "another Pi integration lifecycle operation is active or left an unauthenticated lock: $lock_dir"
        return 75
    fi

    if ! _mainframe_pi_validate_mutation_targets "$agent_dir" ||
       ! _mainframe_pi_restore_validate_destination_parents "$agent_dir" ||
       ! status_text="$(_mainframe_pi_collect_status "$agent_dir" kv)"; then
        [[ "$lock_created" == false ]] || /bin/rmdir -- "$lock_dir" 2>/dev/null || true
        return 1
    fi
    if _mainframe_pi_project_blocked "$status_text"; then
        [[ "$lock_created" == false ]] || /bin/rmdir -- "$lock_dir" 2>/dev/null || true
        _mainframe_pi_error 'project-local Mainframe Pi resources or package settings appeared during restore; no project or user files were changed'
        return 77
    fi

    if _mainframe_pi_restore_engine "$agent_dir" "$backup_dir" "$backup_id" apply "$lock_dir"; then
        /bin/rmdir -- "$lock_dir" 2>/dev/null || {
            _mainframe_pi_error "restore succeeded but the private lifecycle lock could not be removed: $lock_dir"
            return 0
        }
        return 0
    fi
    /bin/rmdir -- "$lock_dir" 2>/dev/null || true
    return 1
}

_mainframe_pi_restore_validate_destination_parents() {
    local agent_dir="$1" resource_parent

    for resource_parent in "$agent_dir/extensions" "$agent_dir/skills"; do
        if [[ ! -d "$resource_parent" || -L "$resource_parent" ]] ||
           ! _mainframe_pi_validate_directory_chain "$resource_parent" user; then
            _mainframe_pi_error "Pi restore destination parent is unsafe or missing: $resource_parent"
            return 1
        fi
    done
    return 0
}
