#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/database.sh - SQLite Database Interface
# =============================================================================
# Description: Pure bash wrapper around sqlite3 CLI providing connection
#              management, prepared statement emulation, transactions,
#              schema operations, and USOP-compliant JSON output.
# Version: 1.0.0
# Requires: Bash 4.0+, sqlite3 CLI
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_DATABASE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_DATABASE_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Current database connection state
_DB_CURRENT_PATH=""
_DB_CONNECTED=0
_DB_TRANSACTION_ACTIVE=0
_DB_LAST_INSERT_ID=0
_DB_CHANGES=0

# Prepared statement storage (associative arrays)
declare -gA _DB_PREPARED_STATEMENTS
declare -gA _DB_PREPARED_BINDINGS

# Prepared statement counter for unique IDs
_DB_STMT_COUNTER=0

# SQLite pragmas for performance and safety
# Note: WAL mode cannot be used with :memory: databases
# PRAGMA outputs are suppressed by redirecting to /dev/null via _db_apply_pragmas
# These pragmas are applied at connection time and also prefixed to each command
# since we use separate sqlite3 processes for each operation.
MAINFRAME_DB_PRAGMAS="${MAINFRAME_DB_PRAGMAS:-PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;}"

# Pragmas that must be applied before every statement (per-connection settings)
# Note: These must not produce output, so we select from them
_DB_EXEC_PRAGMAS="PRAGMA foreign_keys=ON;"

# Flag for whether WAL mode was applied (not possible for :memory:)
_DB_WAL_MODE=0

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Internal logging
_db_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[database] %s: %s\n' "${level}" "$*" >&2
    fi
}

# @pre: _DB_CURRENT_PATH is set
# @post: pragmas applied to database, WAL mode set for file-based DBs
# @idempotent: yes
# @returns: 0 on success
#
# Apply pragmas to the database. Handles WAL mode specially since
# it cannot be used with :memory: databases and outputs the mode name.
_db_apply_pragmas() {
    local db_path="$1"

    # Apply base pragmas (these don't produce output)
    sqlite3 "$db_path" "$MAINFRAME_DB_PRAGMAS" >/dev/null 2>&1

    # Apply WAL mode only for file-based databases
    # WAL mode outputs "wal" which we must suppress
    if [[ "$db_path" != ":memory:" ]]; then
        sqlite3 "$db_path" "PRAGMA journal_mode=WAL;" >/dev/null 2>&1
        _DB_WAL_MODE=1
    else
        _DB_WAL_MODE=0
    fi

    return 0
}

# @pre: none
# @post: returns 0 if sqlite3 available, 1 otherwise
# @idempotent: yes
_db_check_sqlite() {
    if ! command -v sqlite3 &>/dev/null; then
        _db_log error "sqlite3 command not found"
        return 1
    fi
    return 0
}

# @pre: _DB_CONNECTED == 1
# @post: returns 0 if connected, emits error and returns 1 otherwise
# @idempotent: yes
_db_require_connection() {
    if [[ "$_DB_CONNECTED" -ne 1 ]]; then
        _db_log error "no database connection"
        return 1
    fi
    return 0
}

# @pre: value is a string
# @post: returns escaped string safe for SQL literals
# @idempotent: yes
# @returns: escaped string via stdout
#
# Escape a string for safe use in SQL. Doubles single quotes and handles
# special characters. This provides basic SQL injection protection.
_db_escape_string() {
    local value="$1"
    # Double single quotes for SQL escaping
    value="${value//\'/\'\'}"
    printf '%s' "$value"
}

# @pre: identifier is a string
# @post: returns quoted identifier safe for SQL
# @idempotent: yes
# @returns: quoted identifier via stdout
#
# Quote an identifier (table name, column name) for safe use in SQL.
# Uses double quotes per SQL standard.
_db_quote_identifier() {
    local identifier="$1"
    # Escape any existing double quotes
    identifier="${identifier//\"/\"\"}"
    printf '"%s"' "$identifier"
}

# =============================================================================
# CONNECTION MANAGEMENT
# =============================================================================

# @pre: path is a valid filesystem path or :memory:
# @post: database file created if not exists, connection state set
# @idempotent: yes - reconnecting to same DB is safe
# @returns: 0 on success, 1 on failure
#
# Open or create a SQLite database file. Sets up the connection state
# and applies default pragmas for performance and safety.
#
# Usage: db_connect "/path/to/database.db"
# Usage: db_connect ":memory:"  # In-memory database
# Example: db_connect "$HOME/.myapp/data.db"
db_connect() {
    local db_path="$1"

    # Contract: path required
    if [[ -z "$db_path" ]]; then
        _db_log error "db_connect: database path required"
        return 1
    fi

    # Check sqlite3 availability
    _db_check_sqlite || return 1

    # Handle :memory: special case
    if [[ "$db_path" != ":memory:" ]]; then
        # Ensure parent directory exists
        local parent_dir
        parent_dir="${db_path%/*}"
        if [[ "$parent_dir" != "$db_path" ]] && [[ ! -d "$parent_dir" ]]; then
            if ! mkdir -p "$parent_dir" 2>/dev/null; then
                _db_log error "db_connect: cannot create directory $parent_dir"
                return 1
            fi
        fi
    fi

    # Test connection and apply pragmas
    if ! sqlite3 "$db_path" "SELECT 1;" >/dev/null 2>&1; then
        _db_log error "db_connect: failed to open database $db_path"
        return 1
    fi

    # Apply pragmas (handles WAL mode for file-based DBs)
    _db_apply_pragmas "$db_path"

    # Set connection state
    _DB_CURRENT_PATH="$db_path"
    _DB_CONNECTED=1
    _DB_TRANSACTION_ACTIVE=0
    _DB_LAST_INSERT_ID=0
    _DB_CHANGES=0

    _db_log debug "db_connect: connected to $db_path"
    return 0
}

# @pre: database is connected
# @post: connection state cleared, any active transaction rolled back
# @idempotent: yes - closing closed connection is no-op
# @returns: 0 always
#
# Close the current database connection. Rolls back any active transaction.
#
# Usage: db_close
db_close() {
    if [[ "$_DB_TRANSACTION_ACTIVE" -eq 1 ]]; then
        _db_log warn "db_close: rolling back active transaction"
        db_transaction_rollback 2>/dev/null
    fi

    _DB_CURRENT_PATH=""
    _DB_CONNECTED=0
    _DB_TRANSACTION_ACTIVE=0
    _DB_LAST_INSERT_ID=0
    _DB_CHANGES=0
    _DB_WAL_MODE=0

    # Clear prepared statements and temp files
    for stmt_id in "${!_DB_PREPARED_STATEMENTS[@]}"; do
        local stmt_file="${TMPDIR:-/tmp}/.mainframe_db_stmt_${stmt_id}_$$"
        local bindings_file="${TMPDIR:-/tmp}/.mainframe_db_bind_${stmt_id}_$$"
        rm -f "$stmt_file" "$bindings_file" 2>/dev/null
    done
    # Also clean up any orphaned temp files from this process
    rm -f "${TMPDIR:-/tmp}/.mainframe_db_stmt_"*"_$$" 2>/dev/null
    rm -f "${TMPDIR:-/tmp}/.mainframe_db_bind_"*"_$$" 2>/dev/null
    # Clean up transaction file if exists
    rm -f "${TMPDIR:-/tmp}/.mainframe_db_txn_$$" 2>/dev/null

    _DB_PREPARED_STATEMENTS=()
    _DB_PREPARED_BINDINGS=()
    _DB_STMT_COUNTER=0

    _db_log debug "db_close: connection closed"
    return 0
}

# @pre: none
# @post: none (read-only check)
# @idempotent: yes
# @returns: 0 if connected, 1 if not
#
# Check if a database connection is active.
#
# Usage: db_is_connected && echo "Connected"
db_is_connected() {
    [[ "$_DB_CONNECTED" -eq 1 ]]
}

# @pre: database is connected
# @post: none (read-only)
# @idempotent: yes
# @returns: current database path via stdout, or empty if not connected
#
# Get the path of the currently connected database.
#
# Usage: local path=$(db_path)
db_path() {
    printf '%s' "$_DB_CURRENT_PATH"
}

# @pre: sqlite3 available
# @post: none (read-only)
# @idempotent: yes
# @returns: SQLite version string via stdout
#
# Get the SQLite version.
#
# Usage: local version=$(db_version)
db_version() {
    _db_check_sqlite || return 1
    sqlite3 :memory: "SELECT sqlite_version();"
}

# =============================================================================
# QUERY EXECUTION
# =============================================================================

# @pre: database is connected, sql is valid SELECT statement
# @post: query executed, results returned as JSON array
# @idempotent: yes (for SELECT statements)
# @returns: 0 on success with JSON array via stdout, 1 on failure
#
# Execute a SELECT query and return results as a JSON array of objects.
# Each row becomes a JSON object with column names as keys.
#
# Usage: db_query "SELECT * FROM users WHERE active = 1"
# Usage: local users=$(db_query "SELECT id, name FROM users")
# Output: [{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}]
db_query() {
    local sql="$1"

    _db_require_connection || return 1

    if [[ -z "$sql" ]]; then
        _db_log error "db_query: SQL statement required"
        return 1
    fi

    # Execute query with JSON output mode
    local result
    if ! result=$(sqlite3 -json "$_DB_CURRENT_PATH" "$sql" 2>&1); then
        _db_log error "db_query: $result"
        return 1
    fi

    # Handle empty result (sqlite3 -json returns nothing for empty result set)
    if [[ -z "$result" ]]; then
        printf '[]'
    else
        printf '%s' "$result"
    fi

    return 0
}

# @pre: database is connected, sql is valid INSERT/UPDATE/DELETE
# @post: statement executed, _DB_CHANGES and _DB_LAST_INSERT_ID updated
# @idempotent: no - modifies database
# @returns: 0 on success, 1 on failure
#
# Execute an INSERT, UPDATE, or DELETE statement.
# Updates the internal counters for changes() and last_insert_rowid().
# If a transaction is active, statements are batched for execution at commit.
#
# Usage: db_execute "INSERT INTO users (name) VALUES ('Alice')"
# Usage: db_execute "UPDATE users SET active = 0 WHERE id = 5"
db_execute() {
    local sql="$1"

    _db_require_connection || return 1

    if [[ -z "$sql" ]]; then
        _db_log error "db_execute: SQL statement required"
        return 1
    fi

    # If transaction is active, batch the statement for later execution
    if [[ "$_DB_TRANSACTION_ACTIVE" -eq 1 && -n "$_DB_TRANSACTION_FILE" ]]; then
        # Ensure statement ends with semicolon
        local stmt="$sql"
        [[ "${stmt}" != *";" ]] && stmt="${stmt};"
        printf '%s\n' "$stmt" >> "$_DB_TRANSACTION_FILE"
        _db_log debug "db_execute: batched: $stmt"
        return 0
    fi

    # Execute immediately and capture changes/last_insert_id
    # Prefix with required pragmas (foreign keys must be enabled per-connection)
    local output
    if ! output=$(sqlite3 "$_DB_CURRENT_PATH" "$_DB_EXEC_PRAGMAS $sql; SELECT changes(), last_insert_rowid();" 2>&1); then
        _db_log error "db_execute: $output"
        return 1
    fi

    # Parse output: "changes|last_insert_rowid"
    if [[ "$output" =~ ^([0-9]+)\|([0-9]+)$ ]]; then
        _DB_CHANGES="${BASH_REMATCH[1]}"
        _DB_LAST_INSERT_ID="${BASH_REMATCH[2]}"
    fi

    _db_log debug "db_execute: $sql (changes=$_DB_CHANGES)"
    return 0
}

# @pre: database is connected
# @post: all statements executed
# @idempotent: no - modifies database
# @returns: 0 on success, 1 on failure
#
# Execute multiple SQL statements as a batch. All statements run in
# a single sqlite3 invocation for efficiency.
# If a transaction is active, statements are added to the batch.
#
# Usage: db_execute_batch "INSERT INTO t1 VALUES (1); INSERT INTO t1 VALUES (2);"
db_execute_batch() {
    local sql="$1"

    _db_require_connection || return 1

    if [[ -z "$sql" ]]; then
        _db_log error "db_execute_batch: SQL statements required"
        return 1
    fi

    # If transaction is active, batch the statements
    if [[ "$_DB_TRANSACTION_ACTIVE" -eq 1 && -n "$_DB_TRANSACTION_FILE" ]]; then
        # Ensure statements end with semicolon
        local stmt="$sql"
        [[ "${stmt}" != *";" ]] && stmt="${stmt};"
        printf '%s\n' "$stmt" >> "$_DB_TRANSACTION_FILE"
        _db_log debug "db_execute_batch: batched statements"
        return 0
    fi

    local output
    if ! output=$(sqlite3 "$_DB_CURRENT_PATH" "$sql" 2>&1); then
        _db_log error "db_execute_batch: $output"
        return 1
    fi

    _db_log debug "db_execute_batch: executed batch"
    return 0
}

# @pre: database is connected, sql returns exactly one row
# @post: query executed
# @idempotent: yes
# @returns: 0 on success with JSON object via stdout, 1 on failure or no rows
#
# Execute a query expecting a single row result. Returns a JSON object
# (not an array). Returns error if query returns zero or multiple rows.
#
# Usage: local user=$(db_query_row "SELECT * FROM users WHERE id = 1")
# Output: {"id":1,"name":"Alice","active":true}
db_query_row() {
    local sql="$1"

    _db_require_connection || return 1

    if [[ -z "$sql" ]]; then
        _db_log error "db_query_row: SQL statement required"
        return 1
    fi

    local result
    if ! result=$(sqlite3 -json "$_DB_CURRENT_PATH" "$sql" 2>&1); then
        _db_log error "db_query_row: $result"
        return 1
    fi

    # Parse JSON array and extract first element
    if [[ -z "$result" || "$result" == "[]" ]]; then
        _db_log error "db_query_row: no rows returned"
        return 1
    fi

    # Remove array brackets and get first object
    # JSON array: [{...},{...}] -> {...}
    local trimmed="${result#\[}"
    trimmed="${trimmed%\]}"

    # Handle case of multiple rows (find first complete object)
    local depth=0
    local in_string=false
    local prev_char=""
    local i char
    local first_obj=""

    for ((i=0; i<${#trimmed}; i++)); do
        char="${trimmed:i:1}"
        first_obj+="$char"

        if $in_string; then
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '"') in_string=true ;;
                '{') ((depth++)) ;;
                '}')
                    ((depth--))
                    if [[ $depth -eq 0 ]]; then
                        break
                    fi
                    ;;
            esac
        fi
        prev_char="$char"
    done

    printf '%s' "$first_obj"
    return 0
}

# @pre: database is connected, sql returns scalar value
# @post: query executed
# @idempotent: yes
# @returns: 0 on success with scalar value via stdout, 1 on failure
#
# Execute a query expecting a single scalar value (one row, one column).
# Returns just the value without JSON wrapping.
#
# Usage: local count=$(db_query_value "SELECT COUNT(*) FROM users")
# Usage: local name=$(db_query_value "SELECT name FROM users WHERE id = 1")
db_query_value() {
    local sql="$1"

    _db_require_connection || return 1

    if [[ -z "$sql" ]]; then
        _db_log error "db_query_value: SQL statement required"
        return 1
    fi

    local result
    if ! result=$(sqlite3 "$_DB_CURRENT_PATH" "$sql" 2>&1); then
        _db_log error "db_query_value: $result"
        return 1
    fi

    printf '%s' "$result"
    return 0
}

# @pre: database is connected
# @post: query executed
# @idempotent: yes
# @returns: 0 on success with JSON array of values via stdout, 1 on failure
#
# Execute a query and return a single column as a JSON array of values.
# Only the first column is returned if multiple columns selected.
#
# Usage: local ids=$(db_query_column "SELECT id FROM users")
# Output: [1,2,3,4,5]
db_query_column() {
    local sql="$1"

    _db_require_connection || return 1

    if [[ -z "$sql" ]]; then
        _db_log error "db_query_column: SQL statement required"
        return 1
    fi

    local result
    if ! result=$(sqlite3 "$_DB_CURRENT_PATH" "$sql" 2>&1); then
        _db_log error "db_query_column: $result"
        return 1
    fi

    # Convert newline-separated values to JSON array
    if [[ -z "$result" ]]; then
        printf '[]'
        return 0
    fi

    # Build JSON array, detecting types
    local first=true
    printf '['
    while IFS= read -r line; do
        $first || printf ','
        first=false

        # Type detection
        if [[ -z "$line" || "$line" == "null" ]]; then
            printf 'null'
        elif [[ "$line" =~ ^-?[0-9]+$ ]]; then
            printf '%s' "$line"
        elif [[ "$line" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
            printf '%s' "$line"
        else
            # String - escape and quote
            local escaped
            escaped=$(_db_escape_string "$line")
            escaped="${escaped//\\/\\\\}"
            escaped="${escaped//\"/\\\"}"
            escaped="${escaped//$'\n'/\\n}"
            escaped="${escaped//$'\t'/\\t}"
            escaped="${escaped//$'\r'/\\r}"
            printf '"%s"' "$escaped"
        fi
    done <<< "$result"
    printf ']'

    return 0
}

# =============================================================================
# PREPARED STATEMENTS (Emulated)
# =============================================================================

# @pre: database is connected
# @post: statement stored in _DB_PREPARED_STATEMENTS
# @idempotent: no - creates new statement each call
# @returns: statement ID via stdout, or empty on failure
#
# Prepare a SQL statement with ? placeholders for later binding and execution.
# This emulates prepared statements by storing the SQL and replacing
# placeholders at execution time.
#
# Usage: local stmt_id=$(db_prepare "SELECT * FROM users WHERE id = ? AND active = ?")
#
# Note: This function uses a two-step process to work around subshell limitations.
# The statement is stored using a pre-generated ID before returning.
db_prepare() {
    local sql="$1"

    _db_require_connection || return 1

    if [[ -z "$sql" ]]; then
        _db_log error "db_prepare: SQL statement required"
        return 1
    fi

    # Generate unique statement ID first
    ((_DB_STMT_COUNTER++))
    local stmt_id="stmt_$_DB_STMT_COUNTER"

    # Store the statement in global arrays
    # Note: Since this is called in a subshell when used as $(db_prepare ...),
    # we store the SQL encoded in a temp file that db_bind reads
    local stmt_file="${TMPDIR:-/tmp}/.mainframe_db_stmt_${stmt_id}_$$"
    printf '%s' "$sql" > "$stmt_file"

    printf '%s' "$stmt_id"
    return 0
}

# @pre: none
# @post: statement registered in global arrays
# @idempotent: yes
# @returns: 0 on success
#
# Internal helper to load a prepared statement from temp storage
_db_load_stmt() {
    local stmt_id="$1"
    local stmt_file="${TMPDIR:-/tmp}/.mainframe_db_stmt_${stmt_id}_$$"

    if [[ -f "$stmt_file" ]]; then
        _DB_PREPARED_STATEMENTS[$stmt_id]=$(cat "$stmt_file")
        _DB_PREPARED_BINDINGS[$stmt_id]=""
        # Don't remove file yet - might be used again
        return 0
    fi

    return 1
}

# @pre: stmt_id is valid prepared statement
# @post: bindings stored for statement
# @idempotent: no - replaces previous bindings
# @returns: 0 on success, 1 on failure
#
# Bind values to a prepared statement. Values are provided in order
# corresponding to ? placeholders. Values are automatically escaped.
#
# Usage: db_bind "$stmt_id" "1" "true"
# Usage: db_bind "$stmt_id" "$user_id" "$active_status"
db_bind() {
    local stmt_id="$1"
    shift

    if [[ -z "$stmt_id" ]]; then
        _db_log error "db_bind: statement ID required"
        return 1
    fi

    # Try to load from temp file if not in memory (due to subshell from db_prepare)
    if [[ -z "${_DB_PREPARED_STATEMENTS[$stmt_id]:-}" ]]; then
        _db_load_stmt "$stmt_id" || {
            _db_log error "db_bind: unknown statement $stmt_id"
            return 1
        }
    fi

    # Store bindings - use newline-separated for simplicity and file storage
    # Each line is one binding value
    local bindings_file="${TMPDIR:-/tmp}/.mainframe_db_bind_${stmt_id}_$$"
    : > "$bindings_file"  # Create/truncate
    for value in "$@"; do
        printf '%s\n' "$value" >> "$bindings_file"
    done

    _DB_PREPARED_BINDINGS[$stmt_id]="$bindings_file"
    return 0
}

# @pre: stmt_id is valid prepared statement with bindings
# @post: statement executed with bound values
# @idempotent: depends on statement type
# @returns: 0 on success, 1 on failure; output depends on statement type
#
# Execute a prepared statement with its bound values. For SELECT statements,
# returns JSON array. For INSERT/UPDATE/DELETE, returns nothing but updates
# internal change counters.
#
# Usage: local result=$(db_run_prepared "$stmt_id")
db_run_prepared() {
    local stmt_id="$1"
    local is_query="${2:-auto}"  # auto, query, or execute

    if [[ -z "$stmt_id" ]]; then
        _db_log error "db_run_prepared: statement ID required"
        return 1
    fi

    # Try to load from temp file if not in memory
    if [[ -z "${_DB_PREPARED_STATEMENTS[$stmt_id]:-}" ]]; then
        _db_load_stmt "$stmt_id" || {
            _db_log error "db_run_prepared: unknown statement $stmt_id"
            return 1
        }
    fi

    local sql="${_DB_PREPARED_STATEMENTS[$stmt_id]}"
    local bindings_ref="${_DB_PREPARED_BINDINGS[$stmt_id]}"

    # Replace ? placeholders with bound values
    # Bindings are stored in a file (one per line) or a file path
    local values=()
    local bindings_file="${TMPDIR:-/tmp}/.mainframe_db_bind_${stmt_id}_$$"

    # Check if bindings_ref is a file path or inline value
    if [[ -f "$bindings_file" ]]; then
        # Read bindings from file (one per line)
        while IFS= read -r line; do
            values+=("$line")
        done < "$bindings_file"
    elif [[ -f "$bindings_ref" ]]; then
        # bindings_ref itself is a file path
        while IFS= read -r line; do
            values+=("$line")
        done < "$bindings_ref"
    fi

    # Replace each ? with the corresponding escaped value
    local final_sql="$sql"
    local i=0
    while [[ "$final_sql" == *"?"* && $i -lt ${#values[@]} ]]; do
        local value="${values[$i]}"
        local escaped

        # Type detection for proper SQL formatting
        if [[ -z "$value" || "$value" == "null" || "$value" == "NULL" ]]; then
            escaped="NULL"
        elif [[ "$value" =~ ^-?[0-9]+$ ]]; then
            escaped="$value"
        elif [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
            escaped="$value"
        elif [[ "$value" == "true" || "$value" == "TRUE" ]]; then
            escaped="1"
        elif [[ "$value" == "false" || "$value" == "FALSE" ]]; then
            escaped="0"
        else
            escaped="'$(_db_escape_string "$value")'"
        fi

        # Replace first ? only
        final_sql="${final_sql/\?/$escaped}"
        i=$((i + 1))
    done

    # Detect query type if auto
    if [[ "$is_query" == "auto" ]]; then
        local sql_upper="${sql^^}"
        if [[ "$sql_upper" =~ ^[[:space:]]*SELECT ]]; then
            is_query="query"
        else
            is_query="execute"
        fi
    fi

    # Execute appropriately
    if [[ "$is_query" == "query" ]]; then
        db_query "$final_sql"
    else
        db_execute "$final_sql"
    fi
}

# @pre: stmt_id is valid prepared statement
# @post: bindings cleared
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Clear the bound values for a prepared statement.
#
# Usage: db_clear_bindings "$stmt_id"
db_clear_bindings() {
    local stmt_id="$1"

    if [[ -z "$stmt_id" ]]; then
        _db_log error "db_clear_bindings: statement ID required"
        return 1
    fi

    # Try to load from temp file if not in memory
    if [[ -z "${_DB_PREPARED_STATEMENTS[$stmt_id]:-}" ]]; then
        _db_load_stmt "$stmt_id" || {
            _db_log error "db_clear_bindings: unknown statement $stmt_id"
            return 1
        }
    fi

    # Clear bindings file
    local bindings_file="${TMPDIR:-/tmp}/.mainframe_db_bind_${stmt_id}_$$"
    rm -f "$bindings_file" 2>/dev/null

    _DB_PREPARED_BINDINGS[$stmt_id]=""
    return 0
}

# @pre: stmt_id is valid prepared statement
# @post: statement removed from storage
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Finalize (destroy) a prepared statement.
#
# Usage: db_finalize "$stmt_id"
db_finalize() {
    local stmt_id="$1"

    if [[ -z "$stmt_id" ]]; then
        _db_log error "db_finalize: statement ID required"
        return 1
    fi

    unset "_DB_PREPARED_STATEMENTS[$stmt_id]"
    unset "_DB_PREPARED_BINDINGS[$stmt_id]"

    # Clean up temp files
    local stmt_file="${TMPDIR:-/tmp}/.mainframe_db_stmt_${stmt_id}_$$"
    local bindings_file="${TMPDIR:-/tmp}/.mainframe_db_bind_${stmt_id}_$$"
    rm -f "$stmt_file" "$bindings_file" 2>/dev/null

    return 0
}

# =============================================================================
# TRANSACTIONS
# =============================================================================

# Transaction batch file for collecting statements
_DB_TRANSACTION_FILE=""

# @pre: database is connected, no active transaction
# @post: transaction started, batch file created
# @idempotent: no - fails if transaction already active
# @returns: 0 on success, 1 on failure
#
# Begin a database transaction. All subsequent operations will be
# grouped until commit or rollback.
#
# Note: Due to SQLite CLI limitations, transactions are implemented by
# batching statements into a temp file and executing them all at commit time.
#
# Usage: db_transaction_begin
db_transaction_begin() {
    _db_require_connection || return 1

    if [[ "$_DB_TRANSACTION_ACTIVE" -eq 1 ]]; then
        _db_log error "db_transaction_begin: transaction already active"
        return 1
    fi

    # Create temp file for batching statements
    _DB_TRANSACTION_FILE="${TMPDIR:-/tmp}/.mainframe_db_txn_$$"
    # Start with required pragmas (must be before BEGIN)
    printf '%s\nBEGIN TRANSACTION;\n' "$_DB_EXEC_PRAGMAS" > "$_DB_TRANSACTION_FILE"

    _DB_TRANSACTION_ACTIVE=1
    _db_log debug "db_transaction_begin: transaction started"
    return 0
}

# @pre: database is connected, transaction is active
# @post: transaction committed, _DB_TRANSACTION_ACTIVE cleared
# @idempotent: no - fails if no active transaction
# @returns: 0 on success, 1 on failure
#
# Commit the current transaction. All changes since BEGIN are persisted.
#
# Usage: db_transaction_commit
db_transaction_commit() {
    _db_require_connection || return 1

    if [[ "$_DB_TRANSACTION_ACTIVE" -ne 1 ]]; then
        _db_log error "db_transaction_commit: no active transaction"
        return 1
    fi

    # Add COMMIT to batch and execute all at once
    printf 'COMMIT;\n' >> "$_DB_TRANSACTION_FILE"

    local output
    if ! output=$(sqlite3 "$_DB_CURRENT_PATH" < "$_DB_TRANSACTION_FILE" 2>&1); then
        _db_log error "db_transaction_commit: $output"
        rm -f "$_DB_TRANSACTION_FILE"
        _DB_TRANSACTION_FILE=""
        _DB_TRANSACTION_ACTIVE=0
        return 1
    fi

    rm -f "$_DB_TRANSACTION_FILE"
    _DB_TRANSACTION_FILE=""
    _DB_TRANSACTION_ACTIVE=0
    _db_log debug "db_transaction_commit: transaction committed"
    return 0
}

# @pre: database is connected, transaction is active
# @post: transaction rolled back, _DB_TRANSACTION_ACTIVE cleared
# @idempotent: yes - rolling back when no transaction is no-op
# @returns: 0 on success, 1 on failure
#
# Rollback the current transaction. All changes since BEGIN are discarded.
#
# Usage: db_transaction_rollback
db_transaction_rollback() {
    _db_require_connection || return 1

    if [[ "$_DB_TRANSACTION_ACTIVE" -ne 1 ]]; then
        _db_log warn "db_transaction_rollback: no active transaction"
        return 0
    fi

    # Simply discard the batch file - never execute the statements
    rm -f "$_DB_TRANSACTION_FILE"
    _DB_TRANSACTION_FILE=""
    _DB_TRANSACTION_ACTIVE=0
    _db_log debug "db_transaction_rollback: transaction rolled back"
    return 0
}

# @pre: database is connected
# @post: command executed in transaction, committed on success, rolled back on failure
# @idempotent: depends on the command
# @returns: command's return code
#
# Execute a command within a transaction. Automatically commits on success
# or rolls back on failure. Supports nested calls by detecting existing transactions.
#
# Usage: db_with_transaction "db_execute 'INSERT INTO users (name) VALUES (\"Alice\")'"
# Usage: db_with_transaction my_function arg1 arg2
db_with_transaction() {
    _db_require_connection || return 1

    local nested=0
    if [[ "$_DB_TRANSACTION_ACTIVE" -eq 1 ]]; then
        nested=1
    else
        db_transaction_begin || return 1
    fi

    # Execute the command
    local rc=0
    "$@" || rc=$?

    if [[ $nested -eq 0 ]]; then
        if [[ $rc -eq 0 ]]; then
            db_transaction_commit || return 1
        else
            db_transaction_rollback
        fi
    fi

    return $rc
}

# =============================================================================
# SCHEMA OPERATIONS
# =============================================================================

# @pre: database is connected
# @post: none (read-only)
# @idempotent: yes
# @returns: 0 on success with JSON array of table names, 1 on failure
#
# List all tables in the database.
#
# Usage: local tables=$(db_tables)
# Output: ["users","posts","comments"]
db_tables() {
    _db_require_connection || return 1

    local result
    if ! result=$(sqlite3 "$_DB_CURRENT_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;" 2>&1); then
        _db_log error "db_tables: $result"
        return 1
    fi

    # Convert to JSON array
    if [[ -z "$result" ]]; then
        printf '[]'
        return 0
    fi

    printf '['
    local first=true
    while IFS= read -r table; do
        $first || printf ','
        first=false
        printf '"%s"' "$table"
    done <<< "$result"
    printf ']'

    return 0
}

# @pre: database is connected, table exists
# @post: none (read-only)
# @idempotent: yes
# @returns: 0 on success with JSON array of column info, 1 on failure
#
# Get column information for a table. Returns JSON array with objects
# containing: cid, name, type, notnull, dflt_value, pk.
#
# Usage: local cols=$(db_columns "users")
# Output: [{"cid":0,"name":"id","type":"INTEGER","notnull":0,"dflt_value":null,"pk":1},...]
db_columns() {
    local table="$1"

    _db_require_connection || return 1

    if [[ -z "$table" ]]; then
        _db_log error "db_columns: table name required"
        return 1
    fi

    # Use PRAGMA table_info which returns: cid, name, type, notnull, dflt_value, pk
    local quoted_table
    quoted_table=$(_db_quote_identifier "$table")

    local result
    if ! result=$(sqlite3 -json "$_DB_CURRENT_PATH" "PRAGMA table_info($quoted_table);" 2>&1); then
        _db_log error "db_columns: $result"
        return 1
    fi

    if [[ -z "$result" ]]; then
        printf '[]'
    else
        printf '%s' "$result"
    fi

    return 0
}

# @pre: database is connected, table exists
# @post: none (read-only)
# @idempotent: yes
# @returns: 0 on success with CREATE statement via stdout, 1 on failure
#
# Get the CREATE statement for a table.
#
# Usage: local schema=$(db_schema "users")
# Output: CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)
db_schema() {
    local table="$1"

    _db_require_connection || return 1

    if [[ -z "$table" ]]; then
        _db_log error "db_schema: table name required"
        return 1
    fi

    local escaped_table
    escaped_table=$(_db_escape_string "$table")

    local result
    if ! result=$(sqlite3 "$_DB_CURRENT_PATH" "SELECT sql FROM sqlite_master WHERE type='table' AND name='$escaped_table';" 2>&1); then
        _db_log error "db_schema: $result"
        return 1
    fi

    if [[ -z "$result" ]]; then
        _db_log error "db_schema: table $table not found"
        return 1
    fi

    printf '%s' "$result"
    return 0
}

# @pre: database is connected
# @post: none (read-only)
# @idempotent: yes
# @returns: 0 if table exists, 1 if not
#
# Check if a table exists in the database.
#
# Usage: db_table_exists "users" && echo "Table exists"
db_table_exists() {
    local table="$1"

    _db_require_connection || return 1

    if [[ -z "$table" ]]; then
        _db_log error "db_table_exists: table name required"
        return 1
    fi

    local escaped_table
    escaped_table=$(_db_escape_string "$table")

    local count
    count=$(sqlite3 "$_DB_CURRENT_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$escaped_table';" 2>/dev/null)

    [[ "$count" == "1" ]]
}

# @pre: database is connected, schema_json is valid
# @post: table created
# @idempotent: no (use IF NOT EXISTS in schema for idempotency)
# @returns: 0 on success, 1 on failure
#
# Create a table from a JSON schema definition. The schema format:
# {
#   "name": "table_name",
#   "columns": [
#     {"name": "id", "type": "INTEGER", "primary_key": true},
#     {"name": "email", "type": "TEXT", "not_null": true, "unique": true},
#     {"name": "created_at", "type": "TEXT", "default": "CURRENT_TIMESTAMP"}
#   ],
#   "if_not_exists": true
# }
#
# Usage: db_create_table "$schema_json"
db_create_table() {
    local schema_json="$1"

    _db_require_connection || return 1

    if [[ -z "$schema_json" ]]; then
        _db_log error "db_create_table: schema JSON required"
        return 1
    fi

    # Parse JSON schema (basic parsing without jq dependency)
    # Extract table name
    local table_name=""
    if [[ "$schema_json" =~ \"name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        table_name="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$table_name" ]]; then
        _db_log error "db_create_table: table name required in schema"
        return 1
    fi

    # Check for if_not_exists flag
    local if_not_exists=""
    if [[ "$schema_json" =~ \"if_not_exists\"[[:space:]]*:[[:space:]]*true ]]; then
        if_not_exists="IF NOT EXISTS "
    fi

    # Extract columns array (simplified parsing)
    # This is a simplified parser - for complex schemas, use jq
    local columns_sql=""
    local in_columns=false
    local brace_depth=0
    local current_col=""

    # Simple state machine to parse columns
    local i char prev=""
    local columns_part=""

    # Find columns array content
    if [[ "$schema_json" =~ \"columns\"[[:space:]]*:[[:space:]]*\[([^\]]+)\] ]]; then
        columns_part="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$columns_part" ]]; then
        _db_log error "db_create_table: columns array required in schema"
        return 1
    fi

    # Parse each column definition
    local first_col=true
    while [[ "$columns_part" =~ \{([^}]+)\} ]]; do
        local col_def="${BASH_REMATCH[1]}"
        columns_part="${columns_part#*\}}"

        # Extract column properties
        local col_name="" col_type="" col_pk="" col_notnull="" col_unique="" col_default=""

        if [[ "$col_def" =~ \"name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            col_name="${BASH_REMATCH[1]}"
        fi
        if [[ "$col_def" =~ \"type\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            col_type="${BASH_REMATCH[1]}"
        fi
        if [[ "$col_def" =~ \"primary_key\"[[:space:]]*:[[:space:]]*true ]]; then
            col_pk="PRIMARY KEY"
        fi
        if [[ "$col_def" =~ \"not_null\"[[:space:]]*:[[:space:]]*true ]]; then
            col_notnull="NOT NULL"
        fi
        if [[ "$col_def" =~ \"unique\"[[:space:]]*:[[:space:]]*true ]]; then
            col_unique="UNIQUE"
        fi
        if [[ "$col_def" =~ \"default\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            col_default="DEFAULT ${BASH_REMATCH[1]}"
        elif [[ "$col_def" =~ \"default\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            col_default="DEFAULT ${BASH_REMATCH[1]}"
        fi

        if [[ -n "$col_name" && -n "$col_type" ]]; then
            $first_col || columns_sql+=", "
            first_col=false
            columns_sql+="$(_db_quote_identifier "$col_name") $col_type"
            [[ -n "$col_pk" ]] && columns_sql+=" $col_pk"
            [[ -n "$col_notnull" ]] && columns_sql+=" $col_notnull"
            [[ -n "$col_unique" ]] && columns_sql+=" $col_unique"
            [[ -n "$col_default" ]] && columns_sql+=" $col_default"
        fi
    done

    if [[ -z "$columns_sql" ]]; then
        _db_log error "db_create_table: no valid columns found"
        return 1
    fi

    local create_sql="CREATE TABLE ${if_not_exists}$(_db_quote_identifier "$table_name") ($columns_sql);"

    db_execute "$create_sql"
}

# @pre: database is connected, table exists
# @post: table dropped
# @idempotent: yes (with safety=false or IF EXISTS)
# @returns: 0 on success, 1 on failure
#
# Drop a table from the database. By default, requires explicit confirmation
# via the safety parameter to prevent accidental drops.
#
# Usage: db_drop_table "temp_data" true  # safety=true bypasses check
# Usage: db_drop_table "users"           # fails without safety=true
db_drop_table() {
    local table="$1"
    local safety="${2:-false}"

    _db_require_connection || return 1

    if [[ -z "$table" ]]; then
        _db_log error "db_drop_table: table name required"
        return 1
    fi

    if [[ "$safety" != "true" && "$safety" != "1" ]]; then
        _db_log error "db_drop_table: safety check failed - pass 'true' as second argument to confirm"
        return 1
    fi

    local quoted_table
    quoted_table=$(_db_quote_identifier "$table")

    db_execute "DROP TABLE IF EXISTS $quoted_table;"
}

# @pre: database is connected, table and columns exist
# @post: index created
# @idempotent: no (use unique index name)
# @returns: 0 on success, 1 on failure
#
# Create an index on a table.
#
# Usage: db_index_create "users" "idx_users_email" "email"
# Usage: db_index_create "users" "idx_users_name_active" "name,active" true  # unique
db_index_create() {
    local table="$1"
    local index_name="$2"
    local columns="$3"
    local unique="${4:-false}"

    _db_require_connection || return 1

    if [[ -z "$table" || -z "$index_name" || -z "$columns" ]]; then
        _db_log error "db_index_create: table, index_name, and columns required"
        return 1
    fi

    local unique_clause=""
    [[ "$unique" == "true" || "$unique" == "1" ]] && unique_clause="UNIQUE "

    local quoted_table quoted_index
    quoted_table=$(_db_quote_identifier "$table")
    quoted_index=$(_db_quote_identifier "$index_name")

    # Handle multiple columns
    local quoted_columns=""
    local IFS=','
    local first=true
    for col in $columns; do
        # Trim whitespace
        col="${col#"${col%%[![:space:]]*}"}"
        col="${col%"${col##*[![:space:]]}"}"
        $first || quoted_columns+=", "
        first=false
        quoted_columns+="$(_db_quote_identifier "$col")"
    done

    db_execute "CREATE ${unique_clause}INDEX IF NOT EXISTS $quoted_index ON $quoted_table ($quoted_columns);"
}

# @pre: database is connected
# @post: none (read-only)
# @idempotent: yes
# @returns: 0 on success with JSON array of index info, 1 on failure
#
# List all indexes in the database, optionally filtered by table.
#
# Usage: local indexes=$(db_index_list)
# Usage: local indexes=$(db_index_list "users")
# Output: [{"name":"idx_users_email","table":"users","unique":1},...]
db_index_list() {
    local table="${1:-}"

    _db_require_connection || return 1

    local where_clause=""
    if [[ -n "$table" ]]; then
        local escaped_table
        escaped_table=$(_db_escape_string "$table")
        where_clause="AND tbl_name = '$escaped_table'"
    fi

    local sql="SELECT name, tbl_name as \"table\", CASE WHEN sql LIKE '%UNIQUE%' THEN 1 ELSE 0 END as \"unique\" FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%' $where_clause ORDER BY name;"

    local result
    if ! result=$(sqlite3 -json "$_DB_CURRENT_PATH" "$sql" 2>&1); then
        _db_log error "db_index_list: $result"
        return 1
    fi

    if [[ -z "$result" ]]; then
        printf '[]'
    else
        printf '%s' "$result"
    fi

    return 0
}

# =============================================================================
# DATA OPERATIONS
# =============================================================================

# @pre: database is connected, table exists
# @post: row inserted, _DB_LAST_INSERT_ID updated
# @idempotent: no
# @returns: 0 on success, 1 on failure
#
# Insert a single row into a table. Values are provided as key=value pairs.
# Values are automatically escaped and typed.
#
# Usage: db_insert "users" "name=Alice" "email=alice@example.com" "active:bool=true"
# Type hints: :string, :number, :bool, :null
db_insert() {
    local table="$1"
    shift

    _db_require_connection || return 1

    if [[ -z "$table" ]]; then
        _db_log error "db_insert: table name required"
        return 1
    fi

    if [[ $# -eq 0 ]]; then
        _db_log error "db_insert: at least one column=value pair required"
        return 1
    fi

    local columns=""
    local values=""
    local first=true

    for pair in "$@"; do
        local key type value

        # Parse key:type=value or key=value
        if [[ "$pair" =~ ^([^:=]+):([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
        elif [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="auto"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        $first || { columns+=", "; values+=", "; }
        first=false

        columns+="$(_db_quote_identifier "$key")"

        # Format value based on type
        case "$type" in
            string)
                values+="'$(_db_escape_string "$value")'"
                ;;
            number|int|integer|float)
                if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
                    values+="$value"
                else
                    values+="NULL"
                fi
                ;;
            bool|boolean)
                case "${value,,}" in
                    true|1|yes|on) values+="1" ;;
                    false|0|no|off) values+="0" ;;
                    *) values+="NULL" ;;
                esac
                ;;
            null)
                values+="NULL"
                ;;
            auto|*)
                # Auto-detect type
                if [[ -z "$value" || "$value" == "null" || "$value" == "NULL" ]]; then
                    values+="NULL"
                elif [[ "$value" =~ ^-?[0-9]+$ ]]; then
                    values+="$value"
                elif [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
                    values+="$value"
                elif [[ "${value,,}" == "true" ]]; then
                    values+="1"
                elif [[ "${value,,}" == "false" ]]; then
                    values+="0"
                else
                    values+="'$(_db_escape_string "$value")'"
                fi
                ;;
        esac
    done

    local quoted_table
    quoted_table=$(_db_quote_identifier "$table")

    db_execute "INSERT INTO $quoted_table ($columns) VALUES ($values);"
}

# @pre: database is connected, table exists, json_array is valid
# @post: multiple rows inserted
# @idempotent: no
# @returns: 0 on success with count of inserted rows, 1 on failure
#
# Insert multiple rows from a JSON array of objects. All objects must have
# the same keys (columns).
#
# Usage: db_insert_many "users" '[{"name":"Alice"},{"name":"Bob"}]'
db_insert_many() {
    local table="$1"
    local json_array="$2"

    _db_require_connection || return 1

    if [[ -z "$table" || -z "$json_array" ]]; then
        _db_log error "db_insert_many: table and JSON array required"
        return 1
    fi

    # Parse JSON array (simplified)
    if [[ ! "$json_array" =~ ^\[ ]]; then
        _db_log error "db_insert_many: invalid JSON array"
        return 1
    fi

    local count=0
    local in_transaction=0

    # Start transaction if not already in one
    if [[ "$_DB_TRANSACTION_ACTIVE" -eq 0 ]]; then
        db_transaction_begin || return 1
        in_transaction=1
    fi

    # Process each object in array
    local depth=0
    local in_string=false
    local prev_char=""
    local current_obj=""
    local i char

    for ((i=0; i<${#json_array}; i++)); do
        char="${json_array:i:1}"

        if $in_string; then
            current_obj+="$char"
            if [[ "$char" == '"' && "$prev_char" != '\' ]]; then
                in_string=false
            fi
        else
            case "$char" in
                '"')
                    in_string=true
                    current_obj+="$char"
                    ;;
                '{')
                    ((depth++))
                    current_obj+="$char"
                    ;;
                '}')
                    ((depth--))
                    current_obj+="$char"
                    if [[ $depth -eq 0 && -n "$current_obj" ]]; then
                        # Process this object
                        if _db_insert_from_json "$table" "$current_obj"; then
                            ((count++))
                        fi
                        current_obj=""
                    fi
                    ;;
                *)
                    if [[ $depth -gt 0 ]]; then
                        current_obj+="$char"
                    fi
                    ;;
            esac
        fi
        prev_char="$char"
    done

    if [[ $in_transaction -eq 1 ]]; then
        db_transaction_commit || {
            db_transaction_rollback
            return 1
        }
    fi

    printf '%d' "$count"
    return 0
}

# Internal helper to insert a single JSON object
_db_insert_from_json() {
    local table="$1"
    local json_obj="$2"

    local columns=""
    local values=""
    local first=true

    # Parse key-value pairs from JSON object
    local key value
    while [[ "$json_obj" =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|[0-9.-]+|true|false|null) ]]; do
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        # Remove matched portion to continue parsing
        json_obj="${json_obj/${BASH_REMATCH[0]}/}"

        $first || { columns+=", "; values+=", "; }
        first=false

        columns+="$(_db_quote_identifier "$key")"

        # Format value
        if [[ "$value" == "null" ]]; then
            values+="NULL"
        elif [[ "$value" == "true" ]]; then
            values+="1"
        elif [[ "$value" == "false" ]]; then
            values+="0"
        elif [[ "$value" =~ ^\"(.*)\"$ ]]; then
            values+="'$(_db_escape_string "${BASH_REMATCH[1]}")'"
        else
            values+="$value"
        fi
    done

    if [[ -z "$columns" ]]; then
        return 1
    fi

    local quoted_table
    quoted_table=$(_db_quote_identifier "$table")

    sqlite3 "$_DB_CURRENT_PATH" "INSERT INTO $quoted_table ($columns) VALUES ($values);" 2>/dev/null
}

# @pre: database is connected, table exists
# @post: matching rows updated
# @idempotent: depends on values
# @returns: 0 on success, 1 on failure
#
# Update rows in a table matching a condition.
#
# Usage: db_update "users" "WHERE id = 1" "name=Alice Updated" "active:bool=false"
db_update() {
    local table="$1"
    local where_clause="$2"
    shift 2

    _db_require_connection || return 1

    if [[ -z "$table" ]]; then
        _db_log error "db_update: table name required"
        return 1
    fi

    if [[ -z "$where_clause" ]]; then
        _db_log error "db_update: WHERE clause required (use 'WHERE 1=1' to update all)"
        return 1
    fi

    if [[ $# -eq 0 ]]; then
        _db_log error "db_update: at least one column=value pair required"
        return 1
    fi

    local set_clause=""
    local first=true

    for pair in "$@"; do
        local key type value

        # Parse key:type=value or key=value
        if [[ "$pair" =~ ^([^:=]+):([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
        elif [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="auto"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        $first || set_clause+=", "
        first=false

        set_clause+="$(_db_quote_identifier "$key") = "

        # Format value based on type (same logic as insert)
        case "$type" in
            string)
                set_clause+="'$(_db_escape_string "$value")'"
                ;;
            number|int|integer|float)
                if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
                    set_clause+="$value"
                else
                    set_clause+="NULL"
                fi
                ;;
            bool|boolean)
                case "${value,,}" in
                    true|1|yes|on) set_clause+="1" ;;
                    false|0|no|off) set_clause+="0" ;;
                    *) set_clause+="NULL" ;;
                esac
                ;;
            null)
                set_clause+="NULL"
                ;;
            auto|*)
                if [[ -z "$value" || "$value" == "null" || "$value" == "NULL" ]]; then
                    set_clause+="NULL"
                elif [[ "$value" =~ ^-?[0-9]+$ ]]; then
                    set_clause+="$value"
                elif [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
                    set_clause+="$value"
                elif [[ "${value,,}" == "true" ]]; then
                    set_clause+="1"
                elif [[ "${value,,}" == "false" ]]; then
                    set_clause+="0"
                else
                    set_clause+="'$(_db_escape_string "$value")'"
                fi
                ;;
        esac
    done

    local quoted_table
    quoted_table=$(_db_quote_identifier "$table")

    db_execute "UPDATE $quoted_table SET $set_clause $where_clause;"
}

# @pre: database is connected, table exists
# @post: matching rows deleted
# @idempotent: yes (deleting already-deleted rows is no-op)
# @returns: 0 on success, 1 on failure
#
# Delete rows from a table matching a condition.
#
# Usage: db_delete "users" "WHERE id = 5"
# Usage: db_delete "sessions" "WHERE expires_at < datetime('now')"
db_delete() {
    local table="$1"
    local where_clause="$2"

    _db_require_connection || return 1

    if [[ -z "$table" ]]; then
        _db_log error "db_delete: table name required"
        return 1
    fi

    if [[ -z "$where_clause" ]]; then
        _db_log error "db_delete: WHERE clause required (use 'WHERE 1=1' to delete all)"
        return 1
    fi

    local quoted_table
    quoted_table=$(_db_quote_identifier "$table")

    db_execute "DELETE FROM $quoted_table $where_clause;"
}

# @pre: database is connected, table exists with unique constraint
# @post: row inserted or updated
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Insert a row, or update it if a conflict occurs on a unique constraint.
# Requires SQLite 3.24.0+ (2018-06-04) for UPSERT support.
#
# Usage: db_upsert "users" "email" "email=alice@example.com" "name=Alice" "login_count:number=1"
# The second argument is the conflict column(s).
db_upsert() {
    local table="$1"
    local conflict_column="$2"
    shift 2

    _db_require_connection || return 1

    if [[ -z "$table" || -z "$conflict_column" ]]; then
        _db_log error "db_upsert: table and conflict column required"
        return 1
    fi

    if [[ $# -eq 0 ]]; then
        _db_log error "db_upsert: at least one column=value pair required"
        return 1
    fi

    local columns=""
    local values=""
    local update_clause=""
    local first=true

    for pair in "$@"; do
        local key type value

        if [[ "$pair" =~ ^([^:=]+):([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
        elif [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            type="auto"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        $first || { columns+=", "; values+=", "; update_clause+=", "; }
        first=false

        local quoted_key
        quoted_key=$(_db_quote_identifier "$key")
        columns+="$quoted_key"

        local formatted_value
        # Format value based on type
        case "$type" in
            string)
                formatted_value="'$(_db_escape_string "$value")'"
                ;;
            number|int|integer|float)
                if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
                    formatted_value="$value"
                else
                    formatted_value="NULL"
                fi
                ;;
            bool|boolean)
                case "${value,,}" in
                    true|1|yes|on) formatted_value="1" ;;
                    false|0|no|off) formatted_value="0" ;;
                    *) formatted_value="NULL" ;;
                esac
                ;;
            null)
                formatted_value="NULL"
                ;;
            auto|*)
                if [[ -z "$value" || "$value" == "null" || "$value" == "NULL" ]]; then
                    formatted_value="NULL"
                elif [[ "$value" =~ ^-?[0-9]+$ ]]; then
                    formatted_value="$value"
                elif [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
                    formatted_value="$value"
                elif [[ "${value,,}" == "true" ]]; then
                    formatted_value="1"
                elif [[ "${value,,}" == "false" ]]; then
                    formatted_value="0"
                else
                    formatted_value="'$(_db_escape_string "$value")'"
                fi
                ;;
        esac

        values+="$formatted_value"
        update_clause+="$quoted_key = excluded.$quoted_key"
    done

    local quoted_table quoted_conflict
    quoted_table=$(_db_quote_identifier "$table")
    quoted_conflict=$(_db_quote_identifier "$conflict_column")

    db_execute "INSERT INTO $quoted_table ($columns) VALUES ($values) ON CONFLICT($quoted_conflict) DO UPDATE SET $update_clause;"
}

# @pre: database is connected, table exists
# @post: none (read-only)
# @idempotent: yes
# @returns: count via stdout
#
# Count rows in a table, optionally with a WHERE clause.
#
# Usage: local count=$(db_count "users")
# Usage: local active=$(db_count "users" "WHERE active = 1")
db_count() {
    local table="$1"
    local where_clause="${2:-}"

    _db_require_connection || return 1

    if [[ -z "$table" ]]; then
        _db_log error "db_count: table name required"
        return 1
    fi

    local quoted_table
    quoted_table=$(_db_quote_identifier "$table")

    db_query_value "SELECT COUNT(*) FROM $quoted_table $where_clause;"
}

# =============================================================================
# UTILITIES
# =============================================================================

# @pre: value is a string
# @post: none
# @idempotent: yes
# @returns: escaped string safe for SQL literals
#
# Escape a string for safe use in SQL. This is the public interface
# to the internal escaping function.
#
# Usage: local safe=$(db_escape "O'Brien")
# Output: O''Brien
db_escape() {
    local value="$1"
    _db_escape_string "$value"
}

# @pre: identifier is a string
# @post: none
# @idempotent: yes
# @returns: quoted identifier safe for SQL
#
# Quote an identifier (table/column name) for safe use in SQL.
#
# Usage: local quoted=$(db_quote "user name")
# Output: "user name"
db_quote() {
    local identifier="$1"
    _db_quote_identifier "$identifier"
}

# @pre: database is connected
# @post: backup file created
# @idempotent: yes - overwrites existing backup
# @returns: 0 on success, 1 on failure
#
# Backup the database to a file using SQLite's backup API.
#
# Usage: db_backup "/path/to/backup.db"
db_backup() {
    local backup_path="$1"

    _db_require_connection || return 1

    if [[ -z "$backup_path" ]]; then
        _db_log error "db_backup: backup path required"
        return 1
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir="${backup_path%/*}"
    if [[ "$parent_dir" != "$backup_path" ]] && [[ ! -d "$parent_dir" ]]; then
        if ! mkdir -p "$parent_dir" 2>/dev/null; then
            _db_log error "db_backup: cannot create directory $parent_dir"
            return 1
        fi
    fi

    if ! sqlite3 "$_DB_CURRENT_PATH" ".backup '$backup_path'" 2>/dev/null; then
        _db_log error "db_backup: backup failed"
        return 1
    fi

    _db_log debug "db_backup: backed up to $backup_path"
    return 0
}

# @pre: backup_path is valid SQLite database
# @post: current database restored from backup
# @idempotent: no - destructive operation
# @returns: 0 on success, 1 on failure
#
# Restore the database from a backup file.
# WARNING: This replaces the current database content.
#
# Usage: db_restore "/path/to/backup.db"
db_restore() {
    local backup_path="$1"

    _db_require_connection || return 1

    if [[ -z "$backup_path" ]]; then
        _db_log error "db_restore: backup path required"
        return 1
    fi

    if [[ ! -f "$backup_path" ]]; then
        _db_log error "db_restore: backup file not found: $backup_path"
        return 1
    fi

    if ! sqlite3 "$_DB_CURRENT_PATH" ".restore '$backup_path'" 2>/dev/null; then
        _db_log error "db_restore: restore failed"
        return 1
    fi

    _db_log debug "db_restore: restored from $backup_path"
    return 0
}

# @pre: database is connected
# @post: database file optimized
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Optimize the database by running VACUUM. This rebuilds the database
# file, reclaiming unused space and defragmenting.
#
# Usage: db_vacuum
db_vacuum() {
    _db_require_connection || return 1

    if ! sqlite3 "$_DB_CURRENT_PATH" "VACUUM;" 2>/dev/null; then
        _db_log error "db_vacuum: vacuum failed"
        return 1
    fi

    _db_log debug "db_vacuum: database vacuumed"
    return 0
}

# @pre: database is connected
# @post: none (read-only check)
# @idempotent: yes
# @returns: 0 if database is ok, 1 if integrity issues found
#
# Verify database integrity using SQLite's integrity_check pragma.
#
# Usage: db_integrity_check && echo "Database OK"
db_integrity_check() {
    _db_require_connection || return 1

    local result
    result=$(sqlite3 "$_DB_CURRENT_PATH" "PRAGMA integrity_check;" 2>/dev/null)

    if [[ "$result" != "ok" ]]; then
        _db_log error "db_integrity_check: $result"
        return 1
    fi

    _db_log debug "db_integrity_check: database OK"
    return 0
}

# @pre: database has performed an INSERT
# @post: none (read-only)
# @idempotent: yes
# @returns: last insert rowid via stdout
#
# Get the rowid of the last INSERT operation.
#
# Usage: local id=$(db_last_insert_id)
db_last_insert_id() {
    printf '%d' "$_DB_LAST_INSERT_ID"
}

# @pre: database has performed an INSERT/UPDATE/DELETE
# @post: none (read-only)
# @idempotent: yes
# @returns: number of changed rows via stdout
#
# Get the number of rows changed by the last INSERT/UPDATE/DELETE.
#
# Usage: local count=$(db_changes)
db_changes() {
    printf '%d' "$_DB_CHANGES"
}

# =============================================================================
# ADVANCED QUERIES
# =============================================================================

# @pre: database is connected
# @post: query executed with pagination
# @idempotent: yes
# @returns: JSON object with data, page, limit, total, pages
#
# Execute a paginated query. Returns JSON with metadata.
#
# Usage: db_paginate "SELECT * FROM users" 1 10
# Output: {"data":[...],"page":1,"limit":10,"total":100,"pages":10}
db_paginate() {
    local base_sql="$1"
    local page="${2:-1}"
    local limit="${3:-20}"

    _db_require_connection || return 1

    if [[ -z "$base_sql" ]]; then
        _db_log error "db_paginate: SQL statement required"
        return 1
    fi

    # Calculate offset
    local offset=$(( (page - 1) * limit ))

    # Get total count (wrap query)
    local count_sql="SELECT COUNT(*) FROM ($base_sql)"
    local total
    total=$(db_query_value "$count_sql") || return 1

    # Get paginated data
    local paginated_sql="$base_sql LIMIT $limit OFFSET $offset"
    local data
    data=$(db_query "$paginated_sql") || return 1

    # Calculate total pages
    local pages=$(( (total + limit - 1) / limit ))

    # Build response JSON
    printf '{"data":%s,"page":%d,"limit":%d,"total":%d,"pages":%d}' \
        "$data" "$page" "$limit" "$total" "$pages"

    return 0
}

# @pre: database is connected, table and column exist
# @post: none (read-only)
# @idempotent: yes
# @returns: JSON array of distinct values
#
# Get distinct values from a column.
#
# Usage: local statuses=$(db_distinct "orders" "status")
# Output: ["pending","shipped","delivered"]
db_distinct() {
    local table="$1"
    local column="$2"
    local where_clause="${3:-}"

    _db_require_connection || return 1

    if [[ -z "$table" || -z "$column" ]]; then
        _db_log error "db_distinct: table and column required"
        return 1
    fi

    local quoted_table quoted_column
    quoted_table=$(_db_quote_identifier "$table")
    quoted_column=$(_db_quote_identifier "$column")

    db_query_column "SELECT DISTINCT $quoted_column FROM $quoted_table $where_clause ORDER BY $quoted_column;"
}

# @pre: database is connected
# @post: none (read-only)
# @idempotent: yes
# @returns: JSON object with database statistics
#
# Get database statistics including size, table count, and row counts.
#
# Usage: local stats=$(db_stats)
# Output: {"size_bytes":12345,"tables":5,"total_rows":1000}
db_stats() {
    _db_require_connection || return 1

    local size_bytes=0
    if [[ "$_DB_CURRENT_PATH" != ":memory:" && -f "$_DB_CURRENT_PATH" ]]; then
        size_bytes=$(stat -c%s "$_DB_CURRENT_PATH" 2>/dev/null || stat -f%z "$_DB_CURRENT_PATH" 2>/dev/null || echo 0)
    fi

    local table_count
    table_count=$(sqlite3 "$_DB_CURRENT_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';" 2>/dev/null)

    local page_count page_size
    page_count=$(sqlite3 "$_DB_CURRENT_PATH" "PRAGMA page_count;" 2>/dev/null)
    page_size=$(sqlite3 "$_DB_CURRENT_PATH" "PRAGMA page_size;" 2>/dev/null)

    printf '{"size_bytes":%d,"tables":%d,"page_count":%d,"page_size":%d}' \
        "$size_bytes" "$table_count" "$page_count" "$page_size"

    return 0
}

# =============================================================================
# MIGRATION SUPPORT
# =============================================================================

# @pre: database is connected
# @post: migrations table created if not exists
# @idempotent: yes
# @returns: 0 on success
#
# Initialize the migrations tracking table.
#
# Usage: db_migrations_init
db_migrations_init() {
    _db_require_connection || return 1

    db_execute "CREATE TABLE IF NOT EXISTS _migrations (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        applied_at TEXT DEFAULT (datetime('now'))
    );"
}

# @pre: database is connected, migrations initialized
# @post: none (read-only)
# @idempotent: yes
# @returns: JSON array of applied migration names
#
# List applied migrations.
#
# Usage: local applied=$(db_migrations_applied)
db_migrations_applied() {
    _db_require_connection || return 1

    db_query_column "SELECT name FROM _migrations ORDER BY id;"
}

# @pre: database is connected, migrations initialized
# @post: migration applied and recorded
# @idempotent: yes (skips if already applied)
# @returns: 0 on success, 1 on failure
#
# Apply a migration if not already applied.
#
# Usage: db_migration_apply "001_create_users" "CREATE TABLE users (id INTEGER PRIMARY KEY);"
db_migration_apply() {
    local name="$1"
    local sql="$2"

    _db_require_connection || return 1

    if [[ -z "$name" || -z "$sql" ]]; then
        _db_log error "db_migration_apply: name and SQL required"
        return 1
    fi

    # Check if already applied
    local escaped_name
    escaped_name=$(_db_escape_string "$name")
    local count
    count=$(db_query_value "SELECT COUNT(*) FROM _migrations WHERE name = '$escaped_name';") || return 1

    if [[ "$count" -gt 0 ]]; then
        _db_log debug "db_migration_apply: $name already applied"
        return 0
    fi

    # Apply migration in transaction
    db_with_transaction _db_migration_apply_inner "$name" "$sql"
}

_db_migration_apply_inner() {
    local name="$1"
    local sql="$2"

    # Execute migration SQL
    db_execute_batch "$sql" || return 1

    # Record migration
    db_insert "_migrations" "name=$name"
}

# =============================================================================
# NAMEREF VARIANTS (High-Performance)
# =============================================================================

# @pre: database is connected
# @post: result stored in variable
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Execute a query and store result in a variable (avoids subshell overhead).
#
# Usage: db_query_v result "SELECT * FROM users"
db_query_v() {
    local -n __dqv_out=$1
    local sql="$2"

    _db_require_connection || return 1

    if [[ -z "$sql" ]]; then
        _db_log error "db_query_v: SQL statement required"
        return 1
    fi

    local result
    if ! result=$(sqlite3 -json "$_DB_CURRENT_PATH" "$sql" 2>&1); then
        _db_log error "db_query_v: $result"
        return 1
    fi

    if [[ -z "$result" ]]; then
        __dqv_out='[]'
    else
        __dqv_out="$result"
    fi

    return 0
}

# @pre: database is connected
# @post: result stored in variable
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Execute a scalar query and store result in a variable.
#
# Usage: db_query_value_v result "SELECT COUNT(*) FROM users"
db_query_value_v() {
    local -n __dqvv_out=$1
    local sql="$2"

    _db_require_connection || return 1

    if [[ -z "$sql" ]]; then
        _db_log error "db_query_value_v: SQL statement required"
        return 1
    fi

    local result
    if ! result=$(sqlite3 "$_DB_CURRENT_PATH" "$sql" 2>&1); then
        _db_log error "db_query_value_v: $result"
        return 1
    fi

    __dqvv_out="$result"
    return 0
}

# @pre: database is connected
# @post: result stored in variable
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Get table list and store in variable.
#
# Usage: db_tables_v result
db_tables_v() {
    local -n __dtv_out=$1

    _db_require_connection || return 1

    local result
    if ! result=$(sqlite3 "$_DB_CURRENT_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;" 2>&1); then
        _db_log error "db_tables_v: $result"
        return 1
    fi

    if [[ -z "$result" ]]; then
        __dtv_out='[]'
        return 0
    fi

    __dtv_out='['
    local first=true
    while IFS= read -r table; do
        $first || __dtv_out+=','
        first=false
        __dtv_out+="\"$table\""
    done <<< "$result"
    __dtv_out+=']'

    return 0
}

# @pre: database is connected
# @post: result stored in variable
# @idempotent: yes
# @returns: count in variable
#
# Get row count and store in variable.
#
# Usage: db_count_v result "users" "WHERE active = 1"
db_count_v() {
    local -n __dcv_out=$1
    local table="$2"
    local where_clause="${3:-}"

    _db_require_connection || return 1

    if [[ -z "$table" ]]; then
        _db_log error "db_count_v: table name required"
        return 1
    fi

    local quoted_table
    quoted_table=$(_db_quote_identifier "$table")

    local result
    if ! result=$(sqlite3 "$_DB_CURRENT_PATH" "SELECT COUNT(*) FROM $quoted_table $where_clause;" 2>&1); then
        _db_log error "db_count_v: $result"
        return 1
    fi

    __dcv_out="$result"
    return 0
}
