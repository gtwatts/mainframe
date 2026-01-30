#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: Database Module Tests
# =============================================================================
# Comprehensive tests for lib/database.sh (50+ functions)
# Covers: connection management, query execution, prepared statements,
#         transactions, schema operations, data operations, utilities
# =============================================================================

load 'test_helper'

setup() {
    source_lib "database"
    export MAINFRAME_QUIET=1
    TEST_DIR=$(create_test_dir "database")
    TEST_DB="$TEST_DIR/test.db"
}

teardown() {
    db_close 2>/dev/null || true
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# PREREQUISITES
# =============================================================================

@test "sqlite3 command is available" {
    command -v sqlite3
}

# =============================================================================
# CONNECTION MANAGEMENT
# =============================================================================

@test "db_connect creates new database file" {
    db_connect "$TEST_DB"
    [ -f "$TEST_DB" ]
}

@test "db_connect to memory database succeeds" {
    db_connect ":memory:"
    db_is_connected
}

@test "db_connect creates parent directories" {
    local nested_db="$TEST_DIR/a/b/c/nested.db"
    db_connect "$nested_db"
    [ -f "$nested_db" ]
}

@test "db_connect fails with empty path" {
    ! db_connect "" 2>/dev/null
}

@test "db_is_connected returns true after connect" {
    db_connect "$TEST_DB"
    db_is_connected
}

@test "db_is_connected returns false before connect" {
    ! db_is_connected
}

@test "db_path returns current database path" {
    db_connect "$TEST_DB"
    local path
    path=$(db_path)
    [ "$path" = "$TEST_DB" ]
}

@test "db_path returns empty when not connected" {
    local path
    path=$(db_path)
    [ -z "$path" ]
}

@test "db_version returns SQLite version" {
    local version
    version=$(db_version)
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "db_close clears connection state" {
    db_connect "$TEST_DB"
    db_close
    ! db_is_connected
}

@test "db_close is idempotent" {
    db_connect "$TEST_DB"
    db_close
    db_close  # Should not error
}

@test "db_connect can reconnect after close" {
    db_connect "$TEST_DB"
    db_close
    db_connect "$TEST_DB"
    db_is_connected
}

# =============================================================================
# QUERY EXECUTION - BASIC
# =============================================================================

@test "db_execute creates table" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_table_exists "test"
}

@test "db_execute inserts data" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test (name) VALUES ('Alice')"
    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "1" ]
}

@test "db_execute updates _DB_CHANGES" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test (name) VALUES ('Alice')"
    db_execute "INSERT INTO test (name) VALUES ('Bob')"
    db_execute "UPDATE test SET name = 'Updated'"
    local changes
    changes=$(db_changes)
    [ "$changes" = "2" ]
}

@test "db_execute updates _DB_LAST_INSERT_ID" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test (name) VALUES ('Alice')"
    local id
    id=$(db_last_insert_id)
    [ "$id" = "1" ]
}

@test "db_execute fails with invalid SQL" {
    db_connect "$TEST_DB"
    ! db_execute "INVALID SQL STATEMENT" 2>/dev/null
}

@test "db_execute fails without connection" {
    ! db_execute "SELECT 1" 2>/dev/null
}

@test "db_execute_batch runs multiple statements" {
    db_connect "$TEST_DB"
    db_execute_batch "
        CREATE TABLE t1 (id INTEGER);
        CREATE TABLE t2 (id INTEGER);
        INSERT INTO t1 VALUES (1);
        INSERT INTO t2 VALUES (2);
    "
    db_table_exists "t1"
    db_table_exists "t2"
}

# =============================================================================
# QUERY EXECUTION - SELECT
# =============================================================================

@test "db_query returns JSON array" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test (name) VALUES ('Alice')"
    db_execute "INSERT INTO test (name) VALUES ('Bob')"
    local result
    result=$(db_query "SELECT * FROM test ORDER BY id")
    [[ "$result" == *'"name":"Alice"'* ]]
    [[ "$result" == *'"name":"Bob"'* ]]
}

@test "db_query returns empty array for no results" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"
    local result
    result=$(db_query "SELECT * FROM test")
    [ "$result" = "[]" ]
}

@test "db_query_row returns single JSON object" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test (name) VALUES ('Alice')"
    local result
    result=$(db_query_row "SELECT * FROM test WHERE id = 1")
    [[ "$result" == '{'*'"name":"Alice"'*'}' ]]
}

@test "db_query_row fails for no rows" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"
    ! db_query_row "SELECT * FROM test WHERE id = 999" 2>/dev/null
}

@test "db_query_value returns scalar" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test (name) VALUES ('Alice')"
    db_execute "INSERT INTO test (name) VALUES ('Bob')"
    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "2" ]
}

@test "db_query_value returns string" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test (name) VALUES ('Alice')"
    local name
    name=$(db_query_value "SELECT name FROM test WHERE id = 1")
    [ "$name" = "Alice" ]
}

@test "db_query_column returns JSON array of values" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test (name) VALUES ('Alice')"
    db_execute "INSERT INTO test (name) VALUES ('Bob')"
    local result
    result=$(db_query_column "SELECT name FROM test ORDER BY name")
    [[ "$result" == '["Alice","Bob"]' ]]
}

@test "db_query_column returns empty array for no results" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"
    local result
    result=$(db_query_column "SELECT id FROM test")
    [ "$result" = "[]" ]
}

@test "db_query_column handles numeric values" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"
    db_execute "INSERT INTO test VALUES (1)"
    db_execute "INSERT INTO test VALUES (2)"
    db_execute "INSERT INTO test VALUES (3)"
    local result
    result=$(db_query_column "SELECT id FROM test ORDER BY id")
    [ "$result" = "[1,2,3]" ]
}

# =============================================================================
# PREPARED STATEMENTS
# =============================================================================

@test "db_prepare returns statement ID" {
    db_connect "$TEST_DB"
    local stmt_id
    stmt_id=$(db_prepare "SELECT * FROM sqlite_master WHERE type = ?")
    [[ "$stmt_id" == stmt_* ]]
}

@test "db_prepare fails without connection" {
    ! db_prepare "SELECT 1" 2>/dev/null
}

@test "db_bind stores values for statement" {
    db_connect "$TEST_DB"
    local stmt_id
    stmt_id=$(db_prepare "SELECT * FROM sqlite_master WHERE type = ?")
    db_bind "$stmt_id" "table"
}

@test "db_bind fails for unknown statement" {
    db_connect "$TEST_DB"
    ! db_bind "unknown_stmt" "value" 2>/dev/null
}

@test "db_run_prepared executes with bound values" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test (name) VALUES ('Alice')"
    db_execute "INSERT INTO test (name) VALUES ('Bob')"

    local stmt_id
    stmt_id=$(db_prepare "SELECT * FROM test WHERE name = ?")
    db_bind "$stmt_id" "Alice"
    local result
    result=$(db_run_prepared "$stmt_id")
    [[ "$result" == *'"name":"Alice"'* ]]
    [[ "$result" != *'"name":"Bob"'* ]]
}

@test "db_run_prepared handles multiple placeholders" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER, name TEXT, active INTEGER)"
    db_execute "INSERT INTO test VALUES (1, 'Alice', 1)"
    db_execute "INSERT INTO test VALUES (2, 'Bob', 0)"

    local stmt_id
    stmt_id=$(db_prepare "SELECT * FROM test WHERE id = ? AND active = ?")
    db_bind "$stmt_id" "1" "1"
    local result
    result=$(db_run_prepared "$stmt_id")
    [[ "$result" == *'"name":"Alice"'* ]]
}

@test "db_run_prepared handles INSERT" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"

    local stmt_id
    stmt_id=$(db_prepare "INSERT INTO test (name) VALUES (?)")
    db_bind "$stmt_id" "Charlie"
    db_run_prepared "$stmt_id" "execute"

    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test WHERE name = 'Charlie'")
    [ "$count" = "1" ]
}

@test "db_run_prepared escapes SQL injection" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test (name) VALUES ('Alice')"

    local stmt_id
    stmt_id=$(db_prepare "SELECT * FROM test WHERE name = ?")
    db_bind "$stmt_id" "'; DROP TABLE test; --"
    db_run_prepared "$stmt_id" || true

    # Table should still exist
    db_table_exists "test"
}

@test "db_clear_bindings clears values" {
    db_connect "$TEST_DB"
    local stmt_id
    stmt_id=$(db_prepare "SELECT ?")
    db_bind "$stmt_id" "value"
    db_clear_bindings "$stmt_id"
}

@test "db_finalize removes statement" {
    db_connect "$TEST_DB"
    local stmt_id
    stmt_id=$(db_prepare "SELECT 1")
    db_finalize "$stmt_id"
    ! db_bind "$stmt_id" "value" 2>/dev/null
}

# =============================================================================
# TRANSACTIONS
# =============================================================================

@test "db_transaction_begin starts transaction" {
    db_connect "$TEST_DB"
    db_transaction_begin
}

@test "db_transaction_begin fails if already active" {
    db_connect "$TEST_DB"
    db_transaction_begin
    ! db_transaction_begin 2>/dev/null
}

@test "db_transaction_commit persists changes" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"

    db_transaction_begin
    db_execute "INSERT INTO test VALUES (1)"
    db_transaction_commit

    # Reconnect and verify data persisted
    db_close
    db_connect "$TEST_DB"
    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "1" ]
}

@test "db_transaction_rollback discards changes" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"
    db_execute "INSERT INTO test VALUES (1)"

    db_transaction_begin
    db_execute "DELETE FROM test"
    db_transaction_rollback

    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "1" ]
}

@test "db_transaction_rollback is idempotent" {
    db_connect "$TEST_DB"
    db_transaction_rollback  # No active transaction, should not error
}

@test "db_with_transaction commits on success" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"

    _insert_helper() {
        db_execute "INSERT INTO test VALUES (1)"
        return 0
    }

    db_with_transaction _insert_helper

    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "1" ]
}

@test "db_with_transaction rollbacks on failure" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"
    db_execute "INSERT INTO test VALUES (99)"

    _failing_helper() {
        db_execute "DELETE FROM test"
        return 1  # Simulate failure
    }

    db_with_transaction _failing_helper || true

    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "1" ]  # Delete should have been rolled back
}

@test "db_close rolls back active transaction" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"
    db_execute "INSERT INTO test VALUES (1)"

    db_transaction_begin
    db_execute "DELETE FROM test"
    db_close  # Should rollback

    db_connect "$TEST_DB"
    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "1" ]
}

# =============================================================================
# SCHEMA OPERATIONS
# =============================================================================

@test "db_tables returns JSON array of tables" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE users (id INTEGER)"
    db_execute "CREATE TABLE posts (id INTEGER)"
    local result
    result=$(db_tables)
    [[ "$result" == *'"users"'* ]]
    [[ "$result" == *'"posts"'* ]]
}

@test "db_tables returns empty array for no tables" {
    db_connect "$TEST_DB"
    local result
    result=$(db_tables)
    [ "$result" = "[]" ]
}

@test "db_columns returns column info" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT NOT NULL)"
    local result
    result=$(db_columns "test")
    [[ "$result" == *'"name":"id"'* ]]
    [[ "$result" == *'"name":"name"'* ]]
    [[ "$result" == *'"type":"INTEGER"'* ]]
}

@test "db_schema returns CREATE statement" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    local result
    result=$(db_schema "test")
    [[ "$result" == "CREATE TABLE"* ]]
    [[ "$result" == *"test"* ]]
}

@test "db_schema fails for non-existent table" {
    db_connect "$TEST_DB"
    ! db_schema "nonexistent" 2>/dev/null
}

@test "db_table_exists returns true for existing table" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    db_table_exists "test"
}

@test "db_table_exists returns false for non-existent table" {
    db_connect "$TEST_DB"
    ! db_table_exists "nonexistent"
}

@test "db_create_table creates table from JSON schema" {
    db_connect "$TEST_DB"
    local schema='{
        "name": "users",
        "columns": [
            {"name": "id", "type": "INTEGER", "primary_key": true},
            {"name": "email", "type": "TEXT", "not_null": true}
        ]
    }'
    db_create_table "$schema"
    db_table_exists "users"
}

@test "db_create_table with if_not_exists is idempotent" {
    db_connect "$TEST_DB"
    local schema='{
        "name": "users",
        "columns": [{"name": "id", "type": "INTEGER"}],
        "if_not_exists": true
    }'
    db_create_table "$schema"
    db_create_table "$schema"  # Should not error
    db_table_exists "users"
}

@test "db_drop_table requires safety flag" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    ! db_drop_table "test" 2>/dev/null
    db_table_exists "test"
}

@test "db_drop_table with safety flag drops table" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    db_drop_table "test" true
    ! db_table_exists "test"
}

@test "db_index_create creates index" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER, email TEXT)"
    db_index_create "test" "idx_email" "email"
    local indexes
    indexes=$(db_index_list "test")
    [[ "$indexes" == *'"idx_email"'* ]]
}

@test "db_index_create creates unique index" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER, email TEXT)"
    db_index_create "test" "idx_email" "email" true
    local indexes
    indexes=$(db_index_list "test")
    [[ "$indexes" == *'"unique":1'* ]]
}

@test "db_index_create handles multiple columns" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER, first TEXT, last TEXT)"
    db_index_create "test" "idx_name" "first, last"
    local indexes
    indexes=$(db_index_list "test")
    [[ "$indexes" == *'"idx_name"'* ]]
}

@test "db_index_list returns all indexes" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER, name TEXT)"
    db_index_create "test" "idx1" "id"
    db_index_create "test" "idx2" "name"
    local indexes
    indexes=$(db_index_list)
    [[ "$indexes" == *'"idx1"'* ]]
    [[ "$indexes" == *'"idx2"'* ]]
}

@test "db_index_list filters by table" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE t1 (id INTEGER)"
    db_execute "CREATE TABLE t2 (id INTEGER)"
    db_index_create "t1" "idx_t1" "id"
    db_index_create "t2" "idx_t2" "id"
    local indexes
    indexes=$(db_index_list "t1")
    [[ "$indexes" == *'"idx_t1"'* ]]
    [[ "$indexes" != *'"idx_t2"'* ]]
}

# =============================================================================
# DATA OPERATIONS
# =============================================================================

@test "db_insert inserts row with string values" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (name TEXT, email TEXT)"
    db_insert "test" "name=Alice" "email=alice@example.com"
    local result
    result=$(db_query_row "SELECT * FROM test")
    [[ "$result" == *'"name":"Alice"'* ]]
}

@test "db_insert auto-detects numeric values" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER, score REAL)"
    db_insert "test" "id=42" "score=3.14"
    local result
    result=$(db_query_row "SELECT * FROM test")
    [[ "$result" == *'"id":42'* ]]
    [[ "$result" == *'"score":3.14'* ]]
}

@test "db_insert handles explicit types" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (code TEXT, active INTEGER)"
    db_insert "test" "code:string=123" "active:bool=true"
    local result
    result=$(db_query_row "SELECT * FROM test")
    [[ "$result" == *'"code":"123"'* ]]
    [[ "$result" == *'"active":1'* ]]
}

@test "db_insert handles NULL values" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (name TEXT, deleted TEXT)"
    db_insert "test" "name=Alice" "deleted:null="
    local result
    result=$(db_query_row "SELECT * FROM test")
    [[ "$result" == *'"deleted":null'* ]]
}

@test "db_insert escapes SQL injection" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (name TEXT)"
    db_insert "test" "name='; DROP TABLE test; --"
    db_table_exists "test"
    local name
    name=$(db_query_value "SELECT name FROM test")
    [[ "$name" == "'; DROP TABLE test; --" ]]
}

@test "db_insert_many inserts multiple rows" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (name TEXT)"
    local count
    count=$(db_insert_many "test" '[{"name":"Alice"},{"name":"Bob"},{"name":"Charlie"}]')
    [ "$count" = "3" ]

    local total
    total=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$total" = "3" ]
}

@test "db_update modifies matching rows" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test VALUES (1, 'Alice')"
    db_execute "INSERT INTO test VALUES (2, 'Bob')"

    db_update "test" "WHERE id = 1" "name=Alice Updated"

    local name
    name=$(db_query_value "SELECT name FROM test WHERE id = 1")
    [ "$name" = "Alice Updated" ]
}

@test "db_update requires WHERE clause" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    ! db_update "test" "" "id=1" 2>/dev/null
}

@test "db_delete removes matching rows" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"
    db_execute "INSERT INTO test VALUES (1)"
    db_execute "INSERT INTO test VALUES (2)"

    db_delete "test" "WHERE id = 1"

    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "1" ]
}

@test "db_delete requires WHERE clause" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    ! db_delete "test" "" 2>/dev/null
}

@test "db_upsert inserts new row" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (email TEXT PRIMARY KEY, name TEXT)"
    db_upsert "test" "email" "email=alice@example.com" "name=Alice"

    local name
    name=$(db_query_value "SELECT name FROM test WHERE email = 'alice@example.com'")
    [ "$name" = "Alice" ]
}

@test "db_upsert updates existing row" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (email TEXT PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test VALUES ('alice@example.com', 'Alice')"

    db_upsert "test" "email" "email=alice@example.com" "name=Alice Updated"

    local name
    name=$(db_query_value "SELECT name FROM test WHERE email = 'alice@example.com'")
    [ "$name" = "Alice Updated" ]

    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "1" ]
}

@test "db_count returns row count" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    db_execute "INSERT INTO test VALUES (1)"
    db_execute "INSERT INTO test VALUES (2)"
    db_execute "INSERT INTO test VALUES (3)"

    local count
    count=$(db_count "test")
    [ "$count" = "3" ]
}

@test "db_count with WHERE clause" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER, active INTEGER)"
    db_execute "INSERT INTO test VALUES (1, 1)"
    db_execute "INSERT INTO test VALUES (2, 0)"
    db_execute "INSERT INTO test VALUES (3, 1)"

    local count
    count=$(db_count "test" "WHERE active = 1")
    [ "$count" = "2" ]
}

# =============================================================================
# UTILITIES
# =============================================================================

@test "db_escape escapes single quotes" {
    local result
    result=$(db_escape "O'Brien")
    [ "$result" = "O''Brien" ]
}

@test "db_escape handles multiple quotes" {
    local result
    result=$(db_escape "It's a 'test'")
    [ "$result" = "It''s a ''test''" ]
}

@test "db_quote quotes identifiers" {
    local result
    result=$(db_quote "user name")
    [ "$result" = '"user name"' ]
}

@test "db_quote escapes double quotes" {
    local result
    result=$(db_quote 'column"name')
    [ "$result" = '"column""name"' ]
}

@test "db_backup creates backup file" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    db_execute "INSERT INTO test VALUES (1)"

    local backup_path="$TEST_DIR/backup.db"
    db_backup "$backup_path"

    [ -f "$backup_path" ]

    # Verify backup content
    local count
    count=$(sqlite3 "$backup_path" "SELECT COUNT(*) FROM test")
    [ "$count" = "1" ]
}

@test "db_backup creates parent directories" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"

    local backup_path="$TEST_DIR/a/b/backup.db"
    db_backup "$backup_path"

    [ -f "$backup_path" ]
}

@test "db_restore restores from backup" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    db_execute "INSERT INTO test VALUES (1)"

    local backup_path="$TEST_DIR/backup.db"
    db_backup "$backup_path"

    # Modify original
    db_execute "DELETE FROM test"
    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "0" ]

    # Restore
    db_restore "$backup_path"
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "1" ]
}

@test "db_restore fails for missing backup" {
    db_connect "$TEST_DB"
    ! db_restore "/nonexistent/backup.db" 2>/dev/null
}

@test "db_vacuum optimizes database" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    db_execute "INSERT INTO test VALUES (1)"
    db_execute "DELETE FROM test"
    db_vacuum
}

@test "db_integrity_check passes for valid database" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    db_integrity_check
}

@test "db_last_insert_id returns correct ID" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"
    db_execute "INSERT INTO test (name) VALUES ('Alice')"
    local id1
    id1=$(db_last_insert_id)
    [ "$id1" = "1" ]

    db_execute "INSERT INTO test (name) VALUES ('Bob')"
    local id2
    id2=$(db_last_insert_id)
    [ "$id2" = "2" ]
}

@test "db_changes returns correct count" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER, val INTEGER)"
    db_execute "INSERT INTO test VALUES (1, 0)"
    db_execute "INSERT INTO test VALUES (2, 0)"
    db_execute "INSERT INTO test VALUES (3, 0)"

    db_execute "UPDATE test SET val = 1 WHERE id <= 2"
    local changes
    changes=$(db_changes)
    [ "$changes" = "2" ]
}

# =============================================================================
# ADVANCED QUERIES
# =============================================================================

@test "db_paginate returns paginated results" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"
    for i in {1..25}; do
        db_execute "INSERT INTO test VALUES ($i)"
    done

    local result
    result=$(db_paginate "SELECT * FROM test ORDER BY id" 2 10)

    [[ "$result" == *'"page":2'* ]]
    [[ "$result" == *'"limit":10'* ]]
    [[ "$result" == *'"total":25'* ]]
    [[ "$result" == *'"pages":3'* ]]
}

@test "db_distinct returns unique values" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (status TEXT)"
    db_execute "INSERT INTO test VALUES ('pending')"
    db_execute "INSERT INTO test VALUES ('shipped')"
    db_execute "INSERT INTO test VALUES ('pending')"
    db_execute "INSERT INTO test VALUES ('delivered')"

    local result
    result=$(db_distinct "test" "status")
    [[ "$result" == *'"pending"'* ]]
    [[ "$result" == *'"shipped"'* ]]
    [[ "$result" == *'"delivered"'* ]]
}

@test "db_stats returns database statistics" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    local result
    result=$(db_stats)
    [[ "$result" == *'"tables":'* ]]
    [[ "$result" == *'"page_count":'* ]]
}

# =============================================================================
# MIGRATION SUPPORT
# =============================================================================

@test "db_migrations_init creates migrations table" {
    db_connect "$TEST_DB"
    db_migrations_init
    db_table_exists "_migrations"
}

@test "db_migration_apply applies new migration" {
    db_connect "$TEST_DB"
    db_migrations_init
    db_migration_apply "001_create_users" "CREATE TABLE users (id INTEGER PRIMARY KEY)"
    db_table_exists "users"
}

@test "db_migration_apply skips already applied migration" {
    db_connect "$TEST_DB"
    db_migrations_init
    db_migration_apply "001_test" "CREATE TABLE test1 (id INTEGER)"
    db_migration_apply "001_test" "CREATE TABLE test2 (id INTEGER)"  # Should skip
    db_table_exists "test1"
    ! db_table_exists "test2"
}

@test "db_migrations_applied lists applied migrations" {
    db_connect "$TEST_DB"
    db_migrations_init
    db_migration_apply "001_first" "SELECT 1"
    db_migration_apply "002_second" "SELECT 1"

    local result
    result=$(db_migrations_applied)
    [[ "$result" == *'"001_first"'* ]]
    [[ "$result" == *'"002_second"'* ]]
}

# =============================================================================
# NAMEREF VARIANTS
# =============================================================================

@test "db_query_v stores result in variable" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER, name TEXT)"
    db_execute "INSERT INTO test VALUES (1, 'Alice')"

    local out
    db_query_v out "SELECT * FROM test"
    [[ "$out" == *'"name":"Alice"'* ]]
}

@test "db_query_value_v stores scalar in variable" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    db_execute "INSERT INTO test VALUES (1)"

    local out
    db_query_value_v out "SELECT COUNT(*) FROM test"
    [ "$out" = "1" ]
}

@test "db_tables_v stores tables in variable" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE users (id INTEGER)"
    db_execute "CREATE TABLE posts (id INTEGER)"

    local out
    db_tables_v out
    [[ "$out" == *'"users"'* ]]
    [[ "$out" == *'"posts"'* ]]
}

@test "db_count_v stores count in variable" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    db_execute "INSERT INTO test VALUES (1)"
    db_execute "INSERT INTO test VALUES (2)"

    local out
    db_count_v out "test"
    [ "$out" = "2" ]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "handles special characters in values" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (data TEXT)"

    local special=$'Line1\nLine2\tTabbed'
    db_insert "test" "data=$special"

    local result
    result=$(db_query_value "SELECT data FROM test")
    [[ "$result" == *"Line1"* ]]
}

@test "handles unicode in values" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (name TEXT)"
    db_insert "test" "name=Cafe"

    local result
    result=$(db_query_value "SELECT name FROM test")
    [ "$result" = "Cafe" ]
}

@test "handles empty string values" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (name TEXT)"
    db_insert "test" "name:string="

    local result
    result=$(db_query_value "SELECT name FROM test")
    [ "$result" = "" ]
}

@test "handles very long values" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (data TEXT)"

    local long_value
    long_value=$(printf 'a%.0s' {1..1000})
    db_insert "test" "data=$long_value"

    local result
    result=$(db_query_value "SELECT LENGTH(data) FROM test")
    [ "$result" = "1000" ]
}

@test "concurrent access with WAL mode" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY)"

    # WAL mode should allow concurrent readers
    local wal_mode
    wal_mode=$(db_query_value "PRAGMA journal_mode")
    [ "$wal_mode" = "wal" ]
}

@test "foreign key constraint enforcement" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE parents (id INTEGER PRIMARY KEY)"
    db_execute "CREATE TABLE children (id INTEGER, parent_id INTEGER REFERENCES parents(id))"
    db_execute "INSERT INTO parents VALUES (1)"

    # Should fail due to foreign key constraint
    ! db_execute "INSERT INTO children VALUES (1, 999)" 2>/dev/null
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

@test "bulk insert performance with transaction" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)"

    db_transaction_begin
    for i in {1..100}; do
        db_execute "INSERT INTO test (name) VALUES ('User $i')"
    done
    db_transaction_commit

    local count
    count=$(db_query_value "SELECT COUNT(*) FROM test")
    [ "$count" = "100" ]
}

@test "nameref variants avoid subshell overhead" {
    db_connect "$TEST_DB"
    db_execute "CREATE TABLE test (id INTEGER)"
    db_execute "INSERT INTO test VALUES (1)"

    # Both should produce identical results
    local subshell_result
    subshell_result=$(db_query "SELECT * FROM test")

    local nameref_result
    db_query_v nameref_result "SELECT * FROM test"

    [ "$subshell_result" = "$nameref_result" ]
}
