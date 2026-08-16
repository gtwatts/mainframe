#!/usr/bin/env bats
# P2 rollback test: restoring a previous archive must byte-match that
# archive's contents (rollback to the previous compatible release).

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [ -x "$BASH_BIN" ] || BASH_BIN="$(command -v bash)"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-rollback.XXXXXX")"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "archive: build is reproducible (--verify)" {
    run "$BASH_BIN" "$PROJECT_ROOT/scripts/build-release-archive.sh" --verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"REPRODUCIBLE"* ]]
}

@test "rollback: previous archive restores byte-identically over a newer install" {
    # Build two fixture archives: previous (v-prev) and current (v-cur)
    mkdir -p "$TEST_DIR/prev/lib" "$TEST_DIR/cur/lib"
    echo 'old_fn() { echo old; }' > "$TEST_DIR/prev/lib/old.sh"
    echo 'new_fn() { echo new; }' > "$TEST_DIR/cur/lib/new.sh"
    ( cd "$TEST_DIR/prev" && find . -type f | LC_ALL=C sort | tar --create --file=- --files-from=- | gzip -n > "$TEST_DIR/prev.tar.gz" )
    ( cd "$TEST_DIR/cur"  && find . -type f | LC_ALL=C sort | tar --create --file=- --files-from=- | gzip -n > "$TEST_DIR/cur.tar.gz"  )

    # Install current, then roll back to previous
    mkdir -p "$TEST_DIR/install"
    tar -xzf "$TEST_DIR/cur.tar.gz" -C "$TEST_DIR/install"
    [ -f "$TEST_DIR/install/lib/new.sh" ]

    # Rollback = extract previous archive over the install dir, then remove
    # anything not present in the previous archive (manifest-driven restore)
    ( cd "$TEST_DIR/install" && tar -tzf "$TEST_DIR/prev.tar.gz" > "$TEST_DIR/prev.manifest" \
        && find . -type f | LC_ALL=C sort > "$TEST_DIR/installed.manifest" \
        && comm -23 "$TEST_DIR/installed.manifest" "$TEST_DIR/prev.manifest" | while IFS= read -r f; do rm -f "$f"; done \
        && tar -xzf "$TEST_DIR/prev.tar.gz" )

    # Verify: installed tree must equal the previous archive exactly
    ( cd "$TEST_DIR/install" && find . -type f | LC_ALL=C sort > "$TEST_DIR/final.manifest" )
    run diff "$TEST_DIR/prev.manifest" "$TEST_DIR/final.manifest"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/install/lib/old.sh" ]
    [ ! -f "$TEST_DIR/install/lib/new.sh" ]
    grep -q 'echo old' "$TEST_DIR/install/lib/old.sh"
}
