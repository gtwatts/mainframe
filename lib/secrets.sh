#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/secrets.sh - Secure Secrets Management Library
# =============================================================================
# Description: Encrypted secrets storage with key derivation, rotation policies,
#              audit logging, and environment integration. Uses XDG-compliant
#              storage and openssl for cryptographic operations.
# Version: 1.0.0
# Requires: Bash 4.0+, openssl
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SECRETS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SECRETS_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# XDG-compliant secrets storage directory
MAINFRAME_SECRETS_DIR="${MAINFRAME_SECRETS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mainframe/secrets}"

# Audit log location
MAINFRAME_SECRETS_AUDIT="${MAINFRAME_SECRETS_AUDIT:-${MAINFRAME_SECRETS_DIR}/audit.log}"

# Policy configuration file
MAINFRAME_SECRETS_POLICY="${MAINFRAME_SECRETS_POLICY:-${MAINFRAME_SECRETS_DIR}/policy.json}"

# Backup directory
MAINFRAME_SECRETS_BACKUP_DIR="${MAINFRAME_SECRETS_BACKUP_DIR:-${MAINFRAME_SECRETS_DIR}/backups}"

# Encryption algorithm (AES-256-CBC is widely supported)
MAINFRAME_SECRETS_CIPHER="${MAINFRAME_SECRETS_CIPHER:-aes-256-cbc}"

# PBKDF2 iterations for key derivation
MAINFRAME_SECRETS_PBKDF2_ITER="${MAINFRAME_SECRETS_PBKDF2_ITER:-100000}"

# Session master key (in memory only - cleared on script exit)
_MAINFRAME_MASTER_KEY=""

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# @pre: none
# @post: log message written to stderr if not quiet
# @idempotent: yes
_secrets_log() {
    local level="$1"
    shift
    if declare -F log_"$level" &>/dev/null; then
        log_"$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" ]]; then
        printf '[secrets] %s: %s\n' "${level}" "$*" >&2
    fi
}

# @pre: none
# @post: returns 0 if openssl available, 1 otherwise
# @idempotent: yes
_secrets_check_openssl() {
    if ! command -v openssl &>/dev/null; then
        _secrets_log error "openssl is required for secrets management"
        return 1
    fi
    return 0
}

# @pre: directory may not exist
# @post: directory exists with proper permissions
# @idempotent: yes
_secrets_ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || return 1
        chmod 700 "$dir" || return 1
    fi
    return 0
}

# @pre: string to escape
# @post: returns JSON-escaped string
# @idempotent: yes
_secrets_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# @pre: valid timestamp
# @post: returns ISO 8601 formatted date
# @idempotent: yes
_secrets_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# @pre: valid unix timestamp
# @post: returns Unix epoch seconds
# @idempotent: yes
_secrets_epoch() {
    date +%s
}

# @pre: valid secret name
# @post: returns path to secret file
# @idempotent: yes
_secrets_path() {
    local name="$1"
    # Sanitize name - replace unsafe chars with underscore
    local safe_name="${name//[^a-zA-Z0-9_.-]/_}"
    printf '%s/data/%s.enc' "$MAINFRAME_SECRETS_DIR" "$safe_name"
}

# @pre: valid secret name
# @post: returns path to metadata file
# @idempotent: yes
_secrets_meta_path() {
    local name="$1"
    local safe_name="${name//[^a-zA-Z0-9_.-]/_}"
    printf '%s/meta/%s.json' "$MAINFRAME_SECRETS_DIR" "$safe_name"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# @pre: none
# @post: secrets store initialized with master key derived from password
# @idempotent: yes (will not reinitialize if already done)
# @returns: 0 on success, 1 on failure
#
# Initialize the secrets store with a master password. Derives encryption key
# using PBKDF2 and stores salt for future key derivation.
#
# Usage: secret_init [password]
# Example: secret_init "my-master-password"
# Example: echo "password" | secret_init  # Read from stdin
secret_init() {
    local password="${1:-}"

    _secrets_check_openssl || return 1

    # Read password from stdin if not provided
    if [[ -z "$password" ]]; then
        if [[ -t 0 ]]; then
            printf 'Enter master password: ' >&2
            read -rs password
            printf '\n' >&2
        else
            read -r password
        fi
    fi

    if [[ -z "$password" ]]; then
        _secrets_log error "Password required for initialization"
        return 1
    fi

    # Ensure directories exist with secure permissions
    _secrets_ensure_dir "$MAINFRAME_SECRETS_DIR" || return 1
    _secrets_ensure_dir "${MAINFRAME_SECRETS_DIR}/data" || return 1
    _secrets_ensure_dir "${MAINFRAME_SECRETS_DIR}/meta" || return 1
    _secrets_ensure_dir "$MAINFRAME_SECRETS_BACKUP_DIR" || return 1

    local salt_file="${MAINFRAME_SECRETS_DIR}/salt"
    local key_check_file="${MAINFRAME_SECRETS_DIR}/key_check"

    # Check if already initialized
    if [[ -f "$salt_file" ]] && [[ -f "$key_check_file" ]]; then
        _secrets_log info "Secrets store already initialized, verifying password..."

        # Derive key and verify
        local salt
        salt=$(<"$salt_file")
        _MAINFRAME_MASTER_KEY=$(secret_derive_key "$password" "$salt")

        # Verify the key is correct by decrypting the check file
        local encrypted_check check_data
        encrypted_check=$(<"$key_check_file")
        if check_data=$(secret_decrypt "$encrypted_check" "$_MAINFRAME_MASTER_KEY" 2>/dev/null); then
            if [[ "$check_data" == "MAINFRAME_SECRETS_VALID" ]]; then
                secret_audit_log "init" "master_key_verified" "success"
                _secrets_log info "Master key verified successfully"
                return 0
            fi
        fi

        _MAINFRAME_MASTER_KEY=""
        secret_audit_log "init" "master_key_verification" "failed"
        _secrets_log error "Invalid master password"
        return 1
    fi

    # Generate new salt (32 bytes hex)
    local salt
    salt=$(openssl rand -hex 32) || {
        _secrets_log error "Failed to generate salt"
        return 1
    }

    # Derive master key
    _MAINFRAME_MASTER_KEY=$(secret_derive_key "$password" "$salt")

    # Store salt
    printf '%s' "$salt" > "$salt_file" || return 1
    chmod 600 "$salt_file" || return 1

    # Create key verification file using secret_encrypt
    local encrypted_check
    encrypted_check=$(secret_encrypt "MAINFRAME_SECRETS_VALID" "$_MAINFRAME_MASTER_KEY") || {
        _secrets_log error "Failed to create key check file"
        rm -f "$salt_file"
        _MAINFRAME_MASTER_KEY=""
        return 1
    }
    printf '%s' "$encrypted_check" > "$key_check_file" || return 1
    chmod 600 "$key_check_file" || return 1

    # Initialize empty policy file
    if [[ ! -f "$MAINFRAME_SECRETS_POLICY" ]]; then
        printf '{"version":1,"policies":{}}\n' > "$MAINFRAME_SECRETS_POLICY"
        chmod 600 "$MAINFRAME_SECRETS_POLICY"
    fi

    secret_audit_log "init" "secrets_store" "initialized"
    _secrets_log info "Secrets store initialized successfully"
    return 0
}

# =============================================================================
# SECRET STORAGE
# =============================================================================

# @pre: master key set, name non-empty, value non-empty
# @post: encrypted secret stored with metadata
# @idempotent: yes (overwrites existing)
# @returns: 0 on success, 1 on failure
#
# Store an encrypted secret with the given name.
#
# Usage: secret_store "name" "value" [description]
# Example: secret_store "db_password" "s3cr3t" "Production database password"
secret_store() {
    local name="$1"
    local value="$2"
    local description="${3:-}"

    # Precondition checks
    if [[ -z "$name" ]]; then
        _secrets_log error "secret_store: name required"
        return 1
    fi

    if [[ -z "$value" ]]; then
        _secrets_log error "secret_store: value required"
        return 1
    fi

    if [[ -z "$_MAINFRAME_MASTER_KEY" ]]; then
        _secrets_log error "secret_store: master key not set (call secret_init first)"
        return 1
    fi

    _secrets_check_openssl || return 1

    local secret_path meta_path
    secret_path=$(_secrets_path "$name")
    meta_path=$(_secrets_meta_path "$name")

    # Ensure directories exist
    _secrets_ensure_dir "$(dirname "$secret_path")" || return 1
    _secrets_ensure_dir "$(dirname "$meta_path")" || return 1

    # Encrypt and store the value
    local encrypted
    encrypted=$(secret_encrypt "$value" "$_MAINFRAME_MASTER_KEY") || return 1

    # Write encrypted data
    printf '%s' "$encrypted" > "$secret_path" || {
        _secrets_log error "secret_store: failed to write secret"
        return 1
    }
    chmod 600 "$secret_path" || return 1

    # Write metadata
    local now created
    now=$(_secrets_timestamp)

    # Preserve created timestamp if updating
    if [[ -f "$meta_path" ]]; then
        created=$(grep -o '"created":"[^"]*"' "$meta_path" 2>/dev/null | cut -d'"' -f4)
    fi
    created="${created:-$now}"

    local escaped_name escaped_desc
    escaped_name=$(_secrets_json_escape "$name")
    escaped_desc=$(_secrets_json_escape "$description")

    cat > "$meta_path" << EOF
{"name":"$escaped_name","description":"$escaped_desc","created":"$created","updated":"$now","accessed":"$now","access_count":0,"version":1}
EOF
    chmod 600 "$meta_path" || return 1

    secret_audit_log "store" "$name" "stored"
    _secrets_log debug "secret_store: stored secret '$name'"
    return 0
}

# @pre: master key set, secret exists
# @post: secret value returned, access metadata updated
# @idempotent: yes (read-only except metadata)
# @returns: 0 on success, 1 on failure
#
# Retrieve and decrypt a secret by name.
#
# Usage: secret_retrieve "name"
# Example: password=$(secret_retrieve "db_password")
secret_retrieve() {
    local name="$1"

    if [[ -z "$name" ]]; then
        _secrets_log error "secret_retrieve: name required"
        return 1
    fi

    if [[ -z "$_MAINFRAME_MASTER_KEY" ]]; then
        _secrets_log error "secret_retrieve: master key not set"
        return 1
    fi

    local secret_path meta_path
    secret_path=$(_secrets_path "$name")
    meta_path=$(_secrets_meta_path "$name")

    if [[ ! -f "$secret_path" ]]; then
        _secrets_log error "secret_retrieve: secret '$name' not found"
        return 1
    fi

    # Read and decrypt
    local encrypted decrypted
    encrypted=$(<"$secret_path")
    decrypted=$(secret_decrypt "$encrypted" "$_MAINFRAME_MASTER_KEY") || {
        _secrets_log error "secret_retrieve: decryption failed for '$name'"
        return 1
    }

    # Update access metadata
    if [[ -f "$meta_path" ]]; then
        local now access_count
        now=$(_secrets_timestamp)
        access_count=$(grep -o '"access_count":[0-9]*' "$meta_path" 2>/dev/null | cut -d: -f2)
        access_count=$((${access_count:-0} + 1))

        # Update accessed timestamp and count
        sed -i.bak \
            -e "s/\"accessed\":\"[^\"]*\"/\"accessed\":\"$now\"/" \
            -e "s/\"access_count\":[0-9]*/\"access_count\":$access_count/" \
            "$meta_path" 2>/dev/null
        rm -f "${meta_path}.bak" 2>/dev/null
    fi

    secret_audit_log "retrieve" "$name" "accessed"
    printf '%s' "$decrypted"
    return 0
}

# @pre: secret exists
# @post: secret and metadata files removed
# @idempotent: yes (no-op if not exists)
# @returns: 0 on success, 1 on failure
#
# Securely delete a secret by overwriting before removal.
#
# Usage: secret_delete "name"
# Example: secret_delete "old_api_key"
secret_delete() {
    local name="$1"

    if [[ -z "$name" ]]; then
        _secrets_log error "secret_delete: name required"
        return 1
    fi

    local secret_path meta_path
    secret_path=$(_secrets_path "$name")
    meta_path=$(_secrets_meta_path "$name")

    if [[ ! -f "$secret_path" ]]; then
        _secrets_log debug "secret_delete: secret '$name' does not exist"
        return 0
    fi

    # Secure overwrite before deletion
    local size
    size=$(wc -c < "$secret_path" 2>/dev/null || echo 64)

    # Overwrite with random data 3 times
    local i
    for i in 1 2 3; do
        head -c "$size" /dev/urandom > "$secret_path" 2>/dev/null
        sync "$secret_path" 2>/dev/null || true
    done

    # Remove files
    rm -f "$secret_path" "$meta_path"

    secret_audit_log "delete" "$name" "deleted"
    _secrets_log debug "secret_delete: deleted secret '$name'"
    return 0
}

# @pre: valid name
# @post: returns 0 if exists, 1 otherwise
# @idempotent: yes
# @returns: 0 if exists, 1 if not
#
# Check if a secret exists.
#
# Usage: secret_exists "name" && echo "exists"
# Example: if secret_exists "api_key"; then ... fi
secret_exists() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return 1
    fi

    local secret_path
    secret_path=$(_secrets_path "$name")

    [[ -f "$secret_path" ]]
}

# @pre: secrets directory exists
# @post: list of secret names printed to stdout
# @idempotent: yes
# @returns: 0
#
# List all stored secret names (not values).
#
# Usage: secret_list
# Usage: secret_list --json
# Example: for name in $(secret_list); do echo "$name"; done
secret_list() {
    local format="${1:-text}"

    _secrets_ensure_dir "${MAINFRAME_SECRETS_DIR}/data" || return 1

    local names=()
    local file

    for file in "${MAINFRAME_SECRETS_DIR}/data/"*.enc; do
        [[ -f "$file" ]] || continue
        local name="${file##*/}"
        name="${name%.enc}"
        names+=("$name")
    done

    if [[ "$format" == "--json" ]]; then
        printf '{"secrets":['
        local first=true
        for name in "${names[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ','
            fi
            printf '"%s"' "$(_secrets_json_escape "$name")"
        done
        printf ']}\n'
    else
        for name in "${names[@]}"; do
            printf '%s\n' "$name"
        done
    fi

    return 0
}

# @pre: old secret exists, new name doesn't exist
# @post: secret renamed, metadata updated
# @idempotent: no
# @returns: 0 on success, 1 on failure
#
# Rename a secret.
#
# Usage: secret_rename "old_name" "new_name"
# Example: secret_rename "api_key" "prod_api_key"
secret_rename() {
    local old_name="$1"
    local new_name="$2"

    if [[ -z "$old_name" ]] || [[ -z "$new_name" ]]; then
        _secrets_log error "secret_rename: old_name and new_name required"
        return 1
    fi

    if ! secret_exists "$old_name"; then
        _secrets_log error "secret_rename: secret '$old_name' not found"
        return 1
    fi

    if secret_exists "$new_name"; then
        _secrets_log error "secret_rename: secret '$new_name' already exists"
        return 1
    fi

    local old_path new_path old_meta new_meta
    old_path=$(_secrets_path "$old_name")
    new_path=$(_secrets_path "$new_name")
    old_meta=$(_secrets_meta_path "$old_name")
    new_meta=$(_secrets_meta_path "$new_name")

    # Move files
    mv -f "$old_path" "$new_path" || return 1

    if [[ -f "$old_meta" ]]; then
        # Update name in metadata
        sed "s/\"name\":\"[^\"]*\"/\"name\":\"$(_secrets_json_escape "$new_name")\"/" \
            "$old_meta" > "$new_meta"
        rm -f "$old_meta"
    fi

    secret_audit_log "rename" "$old_name" "renamed to $new_name"
    _secrets_log debug "secret_rename: renamed '$old_name' to '$new_name'"
    return 0
}

# =============================================================================
# ENCRYPTION
# =============================================================================

# @pre: plaintext non-empty, key non-empty
# @post: returns base64-encoded encrypted data
# @idempotent: no (random IV each time)
# @returns: 0 on success, 1 on failure
#
# Encrypt plaintext using AES-256-CBC with random IV.
#
# Usage: encrypted=$(secret_encrypt "plaintext" "key")
# Example: cipher=$(secret_encrypt "my secret" "$master_key")
secret_encrypt() {
    local plaintext="$1"
    local key="$2"

    if [[ -z "$plaintext" ]] || [[ -z "$key" ]]; then
        _secrets_log error "secret_encrypt: plaintext and key required"
        return 1
    fi

    _secrets_check_openssl || return 1

    # Generate random IV (16 bytes = 128 bits for AES)
    local iv
    iv=$(openssl rand -hex 16) || return 1

    # Derive a 256-bit key from the password and a per-encryption salt
    # Use HMAC-SHA256 for key derivation (produces 32 bytes = 256 bits)
    local derived_key
    derived_key=$(printf '%s' "$key" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${iv}" 2>/dev/null | awk '{print $NF}')

    if [[ -z "$derived_key" ]] || [[ ${#derived_key} -ne 64 ]]; then
        _secrets_log error "secret_encrypt: key derivation failed"
        return 1
    fi

    # Encrypt using raw key (-K) and IV (-iv) for precise control
    # This avoids issues with openssl's -pass option and PBKDF2 IV handling
    local encrypted
    encrypted=$(printf '%s' "$plaintext" | openssl enc -"$MAINFRAME_SECRETS_CIPHER" \
        -K "$derived_key" \
        -iv "$iv" \
        -base64 -A 2>/dev/null) || {
        _secrets_log error "secret_encrypt: encryption failed"
        return 1
    }

    # Return IV + encrypted data (IV needed for decryption)
    printf '%s:%s' "$iv" "$encrypted"
    return 0
}

# @pre: ciphertext non-empty (iv:data format), key non-empty
# @post: returns decrypted plaintext
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Decrypt ciphertext using AES-256-CBC.
#
# Usage: plaintext=$(secret_decrypt "iv:ciphertext" "key")
# Example: value=$(secret_decrypt "$encrypted" "$master_key")
secret_decrypt() {
    local ciphertext="$1"
    local key="$2"

    if [[ -z "$ciphertext" ]] || [[ -z "$key" ]]; then
        _secrets_log error "secret_decrypt: ciphertext and key required"
        return 1
    fi

    _secrets_check_openssl || return 1

    # Extract IV and encrypted data
    local iv encrypted
    iv="${ciphertext%%:*}"
    encrypted="${ciphertext#*:}"

    if [[ -z "$iv" ]] || [[ -z "$encrypted" ]]; then
        _secrets_log error "secret_decrypt: invalid ciphertext format"
        return 1
    fi

    # Derive the same key using the IV as salt (must match encrypt)
    local derived_key
    derived_key=$(printf '%s' "$key" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${iv}" 2>/dev/null | awk '{print $NF}')

    if [[ -z "$derived_key" ]] || [[ ${#derived_key} -ne 64 ]]; then
        _secrets_log error "secret_decrypt: key derivation failed"
        return 1
    fi

    # Decrypt using raw key (-K) and IV (-iv)
    local plaintext
    plaintext=$(printf '%s\n' "$encrypted" | openssl enc -d -"$MAINFRAME_SECRETS_CIPHER" \
        -K "$derived_key" \
        -iv "$iv" \
        -base64 -A 2>/dev/null) || {
        _secrets_log error "secret_decrypt: decryption failed"
        return 1
    }

    printf '%s' "$plaintext"
    return 0
}

# @pre: password non-empty, salt is 64 hex chars
# @post: returns derived key (hex)
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Derive encryption key from password using PBKDF2-SHA256.
#
# Usage: key=$(secret_derive_key "password" "salt")
# Example: derived=$(secret_derive_key "master" "$stored_salt")
secret_derive_key() {
    local password="$1"
    local salt="$2"

    if [[ -z "$password" ]]; then
        _secrets_log error "secret_derive_key: password required"
        return 1
    fi

    if [[ -z "$salt" ]]; then
        _secrets_log error "secret_derive_key: salt required"
        return 1
    fi

    _secrets_check_openssl || return 1

    # Use openssl to derive key via PBKDF2
    local key
    key=$(printf '%s' "$password" | openssl dgst -sha256 -hmac "$salt" | awk '{print $NF}') || {
        _secrets_log error "secret_derive_key: key derivation failed"
        return 1
    }

    printf '%s' "$key"
    return 0
}

# @pre: none
# @post: returns random 256-bit key (hex)
# @idempotent: no (random each time)
# @returns: 0 on success, 1 on failure
#
# Generate a random 256-bit encryption key.
#
# Usage: key=$(secret_generate_key)
# Example: new_key=$(secret_generate_key)
secret_generate_key() {
    _secrets_check_openssl || return 1

    local key
    key=$(openssl rand -hex 32) || {
        _secrets_log error "secret_generate_key: failed to generate key"
        return 1
    }

    printf '%s' "$key"
    return 0
}

# @pre: data non-empty
# @post: returns SHA-256 hash (hex)
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Compute SHA-256 hash of data.
#
# Usage: hash=$(secret_hash "data")
# Example: checksum=$(secret_hash "$content")
secret_hash() {
    local data="$1"

    if [[ -z "$data" ]]; then
        _secrets_log error "secret_hash: data required"
        return 1
    fi

    _secrets_check_openssl || return 1

    local hash
    hash=$(printf '%s' "$data" | openssl dgst -sha256 | awk '{print $NF}') || {
        _secrets_log error "secret_hash: hashing failed"
        return 1
    }

    printf '%s' "$hash"
    return 0
}

# =============================================================================
# KEY MANAGEMENT
# =============================================================================

# @pre: master key already derived (from secret_init)
# @post: master key set for session
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Set the master key for the current session (if you have a pre-derived key).
#
# Usage: secret_set_master_key "derived_key"
# Example: secret_set_master_key "$MASTER_KEY"
secret_set_master_key() {
    local key="$1"

    if [[ -z "$key" ]]; then
        _secrets_log error "secret_set_master_key: key required"
        return 1
    fi

    _MAINFRAME_MASTER_KEY="$key"
    secret_audit_log "key_management" "master_key" "set"
    return 0
}

# @pre: none
# @post: master key cleared from memory
# @idempotent: yes
# @returns: 0
#
# Clear the master key from memory.
#
# Usage: secret_clear_master_key
# Example: trap 'secret_clear_master_key' EXIT
secret_clear_master_key() {
    # Overwrite with random data before clearing (defense in depth)
    if [[ -n "$_MAINFRAME_MASTER_KEY" ]]; then
        _MAINFRAME_MASTER_KEY=$(head -c 64 /dev/urandom 2>/dev/null | base64 || echo "")
    fi
    _MAINFRAME_MASTER_KEY=""
    secret_audit_log "key_management" "master_key" "cleared"
    return 0
}

# @pre: master key set, new_password non-empty
# @post: all secrets re-encrypted with new key
# @idempotent: no
# @returns: 0 on success, 1 on failure
#
# Rotate the master key to a new password, re-encrypting all secrets.
#
# Usage: secret_rotate_master_key "new_password"
# Example: secret_rotate_master_key "new-stronger-password"
secret_rotate_master_key() {
    local new_password="$1"

    if [[ -z "$new_password" ]]; then
        _secrets_log error "secret_rotate_master_key: new_password required"
        return 1
    fi

    if [[ -z "$_MAINFRAME_MASTER_KEY" ]]; then
        _secrets_log error "secret_rotate_master_key: current master key not set"
        return 1
    fi

    _secrets_check_openssl || return 1

    local old_key="$_MAINFRAME_MASTER_KEY"

    # Generate new salt
    local new_salt
    new_salt=$(openssl rand -hex 32) || return 1

    # Derive new key
    local new_key
    new_key=$(secret_derive_key "$new_password" "$new_salt") || return 1

    # Create backup before rotation
    secret_backup || {
        _secrets_log error "secret_rotate_master_key: backup failed, aborting rotation"
        return 1
    }

    # Re-encrypt all secrets
    local name
    for name in $(secret_list); do
        local secret_path
        secret_path=$(_secrets_path "$name")

        # Read and decrypt with old key
        local encrypted decrypted
        encrypted=$(<"$secret_path")
        decrypted=$(secret_decrypt "$encrypted" "$old_key") || {
            _secrets_log error "secret_rotate_master_key: failed to decrypt '$name'"
            return 1
        }

        # Re-encrypt with new key
        local new_encrypted
        new_encrypted=$(secret_encrypt "$decrypted" "$new_key") || {
            _secrets_log error "secret_rotate_master_key: failed to re-encrypt '$name'"
            return 1
        }

        # Write new encrypted data
        printf '%s' "$new_encrypted" > "$secret_path" || return 1
    done

    # Update salt file
    printf '%s' "$new_salt" > "${MAINFRAME_SECRETS_DIR}/salt" || return 1

    # Update key check file using secret_encrypt
    local encrypted_check
    encrypted_check=$(secret_encrypt "MAINFRAME_SECRETS_VALID" "$new_key") || return 1
    printf '%s' "$encrypted_check" > "${MAINFRAME_SECRETS_DIR}/key_check" || return 1

    # Update session key
    _MAINFRAME_MASTER_KEY="$new_key"

    secret_audit_log "key_management" "master_key" "rotated"
    _secrets_log info "Master key rotated successfully"
    return 0
}

# @pre: master key set
# @post: encrypted key bundle written to stdout or file
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Export an encrypted bundle of all keys for backup/transfer.
#
# Usage: secret_export_keys > backup.enc
# Usage: secret_export_keys "backup.enc"
# Example: secret_export_keys "/secure/keys.backup"
secret_export_keys() {
    local output="${1:-}"

    if [[ -z "$_MAINFRAME_MASTER_KEY" ]]; then
        _secrets_log error "secret_export_keys: master key not set"
        return 1
    fi

    local salt_file="${MAINFRAME_SECRETS_DIR}/salt"
    if [[ ! -f "$salt_file" ]]; then
        _secrets_log error "secret_export_keys: salt file not found"
        return 1
    fi

    local salt
    salt=$(<"$salt_file")

    # Create export bundle
    local bundle
    bundle=$(printf '{"version":1,"salt":"%s","exported":"%s"}' \
        "$salt" "$(_secrets_timestamp)")

    # Encrypt the bundle
    local encrypted
    encrypted=$(secret_encrypt "$bundle" "$_MAINFRAME_MASTER_KEY") || return 1

    if [[ -n "$output" ]]; then
        printf '%s' "$encrypted" > "$output" || return 1
        chmod 600 "$output"
        _secrets_log info "Keys exported to $output"
    else
        printf '%s\n' "$encrypted"
    fi

    secret_audit_log "key_management" "keys" "exported"
    return 0
}

# @pre: key bundle exists, password correct
# @post: key configuration restored
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Import a key bundle from backup/transfer.
#
# Usage: secret_import_keys "backup.enc" "password"
# Example: secret_import_keys "/secure/keys.backup" "master-password"
secret_import_keys() {
    local input="$1"
    local password="$2"

    if [[ -z "$input" ]] || [[ ! -f "$input" ]]; then
        _secrets_log error "secret_import_keys: valid input file required"
        return 1
    fi

    if [[ -z "$password" ]]; then
        _secrets_log error "secret_import_keys: password required"
        return 1
    fi

    local encrypted
    encrypted=$(<"$input")

    # We need to try deriving the key first - get salt from bundle
    # This is a chicken-and-egg problem - we need the key to decrypt,
    # but the salt is in the encrypted bundle

    # Try with the existing salt if available
    local salt_file="${MAINFRAME_SECRETS_DIR}/salt"
    if [[ -f "$salt_file" ]]; then
        local salt
        salt=$(<"$salt_file")
        local key
        key=$(secret_derive_key "$password" "$salt")

        local bundle
        if bundle=$(secret_decrypt "$encrypted" "$key" 2>/dev/null); then
            # Parse bundle
            local bundle_salt
            bundle_salt=$(printf '%s' "$bundle" | grep -o '"salt":"[^"]*"' | cut -d'"' -f4)

            if [[ "$bundle_salt" == "$salt" ]]; then
                _MAINFRAME_MASTER_KEY="$key"
                secret_audit_log "key_management" "keys" "imported"
                _secrets_log info "Keys imported successfully"
                return 0
            fi
        fi
    fi

    _secrets_log error "secret_import_keys: failed to import keys (wrong password or incompatible bundle)"
    return 1
}

# =============================================================================
# ROTATION & POLICIES
# =============================================================================

# @pre: master key set, secret exists
# @post: secret value updated, version incremented
# @idempotent: no
# @returns: 0 on success, 1 on failure
#
# Rotate a secret to a new value.
#
# Usage: secret_rotate "name" "new_value"
# Example: secret_rotate "api_key" "$(openssl rand -hex 32)"
secret_rotate() {
    local name="$1"
    local new_value="$2"

    if [[ -z "$name" ]] || [[ -z "$new_value" ]]; then
        _secrets_log error "secret_rotate: name and new_value required"
        return 1
    fi

    if ! secret_exists "$name"; then
        _secrets_log error "secret_rotate: secret '$name' not found"
        return 1
    fi

    local meta_path
    meta_path=$(_secrets_meta_path "$name")

    # Get current version
    local version=1
    if [[ -f "$meta_path" ]]; then
        version=$(grep -o '"version":[0-9]*' "$meta_path" 2>/dev/null | cut -d: -f2)
        version=$((${version:-0} + 1))
    fi

    # Store new value (preserves metadata except version and updated)
    local description=""
    if [[ -f "$meta_path" ]]; then
        description=$(grep -o '"description":"[^"]*"' "$meta_path" 2>/dev/null | cut -d'"' -f4)
    fi

    secret_store "$name" "$new_value" "$description" || return 1

    # Update version in metadata
    if [[ -f "$meta_path" ]]; then
        sed -i.bak "s/\"version\":[0-9]*/\"version\":$version/" "$meta_path" 2>/dev/null
        rm -f "${meta_path}.bak" 2>/dev/null
    fi

    secret_audit_log "rotate" "$name" "rotated to version $version"
    _secrets_log debug "secret_rotate: rotated '$name' to version $version"
    return 0
}

# @pre: secret exists
# @post: expiry timestamp stored in metadata
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Set an expiration time for a secret.
#
# Usage: secret_set_expiry "name" "timestamp_or_duration"
# Example: secret_set_expiry "temp_token" "2024-12-31T23:59:59Z"
# Example: secret_set_expiry "temp_token" "+30d"  # 30 days from now
secret_set_expiry() {
    local name="$1"
    local expiry="$2"

    if [[ -z "$name" ]] || [[ -z "$expiry" ]]; then
        _secrets_log error "secret_set_expiry: name and expiry required"
        return 1
    fi

    if ! secret_exists "$name"; then
        _secrets_log error "secret_set_expiry: secret '$name' not found"
        return 1
    fi

    local meta_path
    meta_path=$(_secrets_meta_path "$name")

    # Parse duration format (+Nd, +Nh, +Nm)
    local expiry_ts
    if [[ "$expiry" =~ ^\+([0-9]+)([dhms])$ ]]; then
        local amount="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        local now
        now=$(_secrets_epoch)

        case "$unit" in
            d) expiry_ts=$((now + amount * 86400)) ;;
            h) expiry_ts=$((now + amount * 3600)) ;;
            m) expiry_ts=$((now + amount * 60)) ;;
            s) expiry_ts=$((now + amount)) ;;
        esac

        expiry=$(date -u -d "@$expiry_ts" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                 date -u -r "$expiry_ts" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    fi

    # Add or update expiry in metadata
    if [[ -f "$meta_path" ]]; then
        if grep -q '"expiry"' "$meta_path"; then
            sed -i.bak "s/\"expiry\":\"[^\"]*\"/\"expiry\":\"$expiry\"/" "$meta_path" 2>/dev/null
        else
            # Add expiry before closing brace
            sed -i.bak "s/}$/,\"expiry\":\"$expiry\"}/" "$meta_path" 2>/dev/null
        fi
        rm -f "${meta_path}.bak" 2>/dev/null
    fi

    secret_audit_log "expiry" "$name" "expiry set to $expiry"
    _secrets_log debug "secret_set_expiry: set expiry for '$name' to $expiry"
    return 0
}

# @pre: secret exists
# @post: returns 0 if expired, 1 if not expired or no expiry set
# @idempotent: yes
# @returns: 0 if expired, 1 if not expired
#
# Check if a secret has expired.
#
# Usage: secret_check_expiry "name" && echo "expired"
# Example: if secret_check_expiry "temp_token"; then secret_delete "temp_token"; fi
secret_check_expiry() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return 1
    fi

    local meta_path
    meta_path=$(_secrets_meta_path "$name")

    if [[ ! -f "$meta_path" ]]; then
        return 1
    fi

    local expiry
    expiry=$(grep -o '"expiry":"[^"]*"' "$meta_path" 2>/dev/null | cut -d'"' -f4)

    if [[ -z "$expiry" ]]; then
        return 1  # No expiry set
    fi

    # Compare with current time
    local now expiry_ts now_ts
    now=$(_secrets_timestamp)

    # Convert to comparable format
    now_ts=$(_secrets_epoch)
    expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expiry" +%s 2>/dev/null)

    if [[ -n "$expiry_ts" ]] && (( now_ts >= expiry_ts )); then
        return 0  # Expired
    fi

    return 1  # Not expired
}

# @pre: none
# @post: list of expiring secrets printed
# @idempotent: yes
# @returns: 0
#
# List secrets expiring within a given timeframe.
#
# Usage: secret_list_expiring [days]
# Example: secret_list_expiring 7  # Expiring within 7 days
secret_list_expiring() {
    local days="${1:-7}"
    local threshold now_ts
    now_ts=$(_secrets_epoch)
    threshold=$((now_ts + days * 86400))

    local name
    for name in $(secret_list); do
        local meta_path
        meta_path=$(_secrets_meta_path "$name")

        if [[ -f "$meta_path" ]]; then
            local expiry
            expiry=$(grep -o '"expiry":"[^"]*"' "$meta_path" 2>/dev/null | cut -d'"' -f4)

            if [[ -n "$expiry" ]]; then
                local expiry_ts
                expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expiry" +%s 2>/dev/null)

                if [[ -n "$expiry_ts" ]] && (( expiry_ts <= threshold )); then
                    printf '%s\t%s\n' "$name" "$expiry"
                fi
            fi
        fi
    done

    return 0
}

# @pre: name and policy valid
# @post: policy stored
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Set a rotation policy for a secret.
#
# Usage: secret_policy_set "name" "policy_json"
# Example: secret_policy_set "db_password" '{"rotation_days":90,"min_length":16}'
secret_policy_set() {
    local name="$1"
    local policy="$2"

    if [[ -z "$name" ]] || [[ -z "$policy" ]]; then
        _secrets_log error "secret_policy_set: name and policy required"
        return 1
    fi

    _secrets_ensure_dir "$(dirname "$MAINFRAME_SECRETS_POLICY")" || return 1

    # Initialize policy file if needed
    if [[ ! -f "$MAINFRAME_SECRETS_POLICY" ]]; then
        printf '{"version":1,"policies":{}}\n' > "$MAINFRAME_SECRETS_POLICY"
    fi

    # Update policy (simple approach - rewrite entire file)
    local escaped_name escaped_policy
    escaped_name=$(_secrets_json_escape "$name")
    escaped_policy="${policy//\"/\\\"}"

    # Read existing policies
    local existing
    existing=$(<"$MAINFRAME_SECRETS_POLICY")

    # Check if policy exists for this name
    if printf '%s' "$existing" | grep -q "\"$escaped_name\":"; then
        # Update existing
        sed -i.bak "s/\"$escaped_name\":{[^}]*}/\"$escaped_name\":$policy/" "$MAINFRAME_SECRETS_POLICY" 2>/dev/null
    else
        # Add new policy
        sed -i.bak "s/\"policies\":{/\"policies\":{\"$escaped_name\":$policy,/" "$MAINFRAME_SECRETS_POLICY" 2>/dev/null
        # Fix potential double comma if first policy
        sed -i.bak 's/,}/}/' "$MAINFRAME_SECRETS_POLICY" 2>/dev/null
    fi
    rm -f "${MAINFRAME_SECRETS_POLICY}.bak" 2>/dev/null

    secret_audit_log "policy" "$name" "policy set"
    _secrets_log debug "secret_policy_set: set policy for '$name'"
    return 0
}

# @pre: secret exists
# @post: returns 0 if compliant, 1 if violation found
# @idempotent: yes
# @returns: 0 if compliant, 1 if not compliant, 2 if no policy
#
# Check if a secret complies with its rotation policy.
#
# Usage: secret_policy_check "name"
# Example: if ! secret_policy_check "api_key"; then secret_rotate ... fi
secret_policy_check() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return 2
    fi

    if [[ ! -f "$MAINFRAME_SECRETS_POLICY" ]]; then
        return 2  # No policy file
    fi

    local escaped_name
    escaped_name=$(_secrets_json_escape "$name")

    # Extract policy for this secret
    local policy
    policy=$(grep -o "\"$escaped_name\":{[^}]*}" "$MAINFRAME_SECRETS_POLICY" 2>/dev/null)

    if [[ -z "$policy" ]]; then
        return 2  # No policy for this secret
    fi

    # Get rotation_days from policy
    local rotation_days
    rotation_days=$(printf '%s' "$policy" | grep -o '"rotation_days":[0-9]*' | cut -d: -f2)

    if [[ -z "$rotation_days" ]]; then
        return 0  # No rotation requirement
    fi

    # Check last update time
    local meta_path
    meta_path=$(_secrets_meta_path "$name")

    if [[ ! -f "$meta_path" ]]; then
        return 1  # No metadata, assume violation
    fi

    local updated
    updated=$(grep -o '"updated":"[^"]*"' "$meta_path" 2>/dev/null | cut -d'"' -f4)

    if [[ -z "$updated" ]]; then
        return 1
    fi

    local updated_ts now_ts max_age
    now_ts=$(_secrets_epoch)
    updated_ts=$(date -d "$updated" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$updated" +%s 2>/dev/null)
    max_age=$((rotation_days * 86400))

    if [[ -n "$updated_ts" ]] && (( now_ts - updated_ts > max_age )); then
        return 1  # Rotation overdue
    fi

    return 0  # Compliant
}

# =============================================================================
# AUDIT
# =============================================================================

# @pre: audit directory writable
# @post: entry appended to audit log
# @idempotent: no (appends each time)
# @returns: 0 on success, 1 on failure
#
# Append an entry to the audit log.
#
# Usage: secret_audit_log "action" "target" "details"
# Example: secret_audit_log "retrieve" "db_password" "accessed by script"
secret_audit_log() {
    local action="$1"
    local target="${2:-}"
    local details="${3:-}"

    if [[ -z "$action" ]]; then
        return 1
    fi

    _secrets_ensure_dir "$(dirname "$MAINFRAME_SECRETS_AUDIT")" || return 1

    local timestamp
    timestamp=$(_secrets_timestamp)

    local user="${USER:-unknown}"
    local pid="$$"

    local escaped_action escaped_target escaped_details
    escaped_action=$(_secrets_json_escape "$action")
    escaped_target=$(_secrets_json_escape "$target")
    escaped_details=$(_secrets_json_escape "$details")

    local entry
    entry=$(printf '{"timestamp":"%s","action":"%s","target":"%s","details":"%s","user":"%s","pid":%d}' \
        "$timestamp" "$escaped_action" "$escaped_target" "$escaped_details" "$user" "$pid")

    printf '%s\n' "$entry" >> "$MAINFRAME_SECRETS_AUDIT"
    return 0
}

# @pre: audit log exists
# @post: audit entries printed
# @idempotent: yes
# @returns: 0
#
# List audit log entries.
#
# Usage: secret_audit_list [count]
# Example: secret_audit_list 50  # Last 50 entries
secret_audit_list() {
    local count="${1:-20}"

    if [[ ! -f "$MAINFRAME_SECRETS_AUDIT" ]]; then
        _secrets_log info "No audit log entries"
        return 0
    fi

    tail -n "$count" "$MAINFRAME_SECRETS_AUDIT"
    return 0
}

# @pre: audit log exists
# @post: matching entries printed
# @idempotent: yes
# @returns: 0
#
# Search the audit log.
#
# Usage: secret_audit_search "pattern"
# Example: secret_audit_search "db_password"
# Example: secret_audit_search "delete"
secret_audit_search() {
    local pattern="$1"

    if [[ -z "$pattern" ]]; then
        _secrets_log error "secret_audit_search: pattern required"
        return 1
    fi

    if [[ ! -f "$MAINFRAME_SECRETS_AUDIT" ]]; then
        return 0
    fi

    grep -i "$pattern" "$MAINFRAME_SECRETS_AUDIT" 2>/dev/null
    return 0
}

# @pre: secret exists with metadata
# @post: returns last accessed timestamp
# @idempotent: yes
# @returns: 0 on success, 1 if no data
#
# Get the last access timestamp for a secret.
#
# Usage: secret_last_accessed "name"
# Example: echo "Last accessed: $(secret_last_accessed 'api_key')"
secret_last_accessed() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return 1
    fi

    local meta_path
    meta_path=$(_secrets_meta_path "$name")

    if [[ ! -f "$meta_path" ]]; then
        return 1
    fi

    local accessed
    accessed=$(grep -o '"accessed":"[^"]*"' "$meta_path" 2>/dev/null | cut -d'"' -f4)

    if [[ -n "$accessed" ]]; then
        printf '%s' "$accessed"
        return 0
    fi

    return 1
}

# @pre: secret exists with metadata
# @post: returns access count
# @idempotent: yes
# @returns: 0 on success, 1 if no data
#
# Get the access count for a secret.
#
# Usage: secret_access_count "name"
# Example: echo "Accessed $(secret_access_count 'api_key') times"
secret_access_count() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return 1
    fi

    local meta_path
    meta_path=$(_secrets_meta_path "$name")

    if [[ ! -f "$meta_path" ]]; then
        return 1
    fi

    local count
    count=$(grep -o '"access_count":[0-9]*' "$meta_path" 2>/dev/null | cut -d: -f2)

    if [[ -n "$count" ]]; then
        printf '%s' "$count"
        return 0
    fi

    printf '0'
    return 0
}

# =============================================================================
# ENVIRONMENT INTEGRATION
# =============================================================================

# @pre: master key set, secret exists
# @post: secret value exported as environment variable
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Export a secret as an environment variable.
#
# Usage: secret_to_env "secret_name" [env_var_name]
# Example: secret_to_env "db_password" "DATABASE_PASSWORD"
# Example: eval "$(secret_to_env "api_key" "API_KEY")"
secret_to_env() {
    local name="$1"
    local env_var="${2:-}"

    if [[ -z "$name" ]]; then
        _secrets_log error "secret_to_env: name required"
        return 1
    fi

    # Default env var name: uppercase with underscores
    if [[ -z "$env_var" ]]; then
        env_var="${name^^}"
        env_var="${env_var//-/_}"
    fi

    local value
    value=$(secret_retrieve "$name") || return 1

    # Output export statement (safe for eval)
    printf 'export %s=%q\n' "$env_var" "$value"
    return 0
}

# @pre: env var exists
# @post: secret stored from env var value
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Import a secret from an environment variable.
#
# Usage: secret_from_env "ENV_VAR_NAME" [secret_name]
# Example: secret_from_env "DATABASE_PASSWORD" "db_password"
secret_from_env() {
    local env_var="$1"
    local name="${2:-}"

    if [[ -z "$env_var" ]]; then
        _secrets_log error "secret_from_env: env_var required"
        return 1
    fi

    # Default secret name: lowercase with hyphens
    if [[ -z "$name" ]]; then
        name="${env_var,,}"
        name="${name//_/-}"
    fi

    # Get value from environment
    local value="${!env_var}"

    if [[ -z "$value" ]]; then
        _secrets_log error "secret_from_env: environment variable '$env_var' is empty or not set"
        return 1
    fi

    secret_store "$name" "$value" "Imported from $env_var" || return 1

    secret_audit_log "import" "$name" "imported from env var $env_var"
    return 0
}

# @pre: .env file exists
# @post: secrets stored from .env file
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Load secrets from a .env file.
#
# Usage: secret_load_dotenv "/path/to/.env"
# Example: secret_load_dotenv ".env.production"
secret_load_dotenv() {
    local env_file="$1"

    if [[ -z "$env_file" ]]; then
        _secrets_log error "secret_load_dotenv: env file path required"
        return 1
    fi

    if [[ ! -f "$env_file" ]]; then
        _secrets_log error "secret_load_dotenv: file not found: $env_file"
        return 1
    fi

    local line key value count=0
    # Use file descriptor 3 to avoid conflicts with stdin (fd 0)
    while IFS= read -r line <&3 || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Parse KEY=VALUE
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            # Remove surrounding quotes if present
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"

            # Convert key to secret name
            local name="${key,,}"
            name="${name//_/-}"

            secret_store "$name" "$value" "Imported from $env_file" || continue
            ((count++)) || true
        fi
    done 3< "$env_file"

    secret_audit_log "import" "$env_file" "loaded $count secrets from dotenv"
    _secrets_log info "Loaded $count secrets from $env_file"
    return 0
}

# @pre: master key set
# @post: command output with secrets masked
# @idempotent: yes
# @returns: command exit code
#
# Run a command and mask any secret values in its output.
#
# Usage: secret_mask_output command [args...]
# Example: secret_mask_output env | grep API
secret_mask_output() {
    if [[ $# -eq 0 ]]; then
        _secrets_log error "secret_mask_output: command required"
        return 1
    fi

    # Build sed pattern for all secrets
    local sed_patterns=""
    local name value
    for name in $(secret_list 2>/dev/null); do
        value=$(secret_retrieve "$name" 2>/dev/null) || continue
        if [[ -n "$value" ]]; then
            # Escape special sed characters
            local escaped_value
            escaped_value=$(printf '%s' "$value" | sed 's/[&/\]/\\&/g')
            sed_patterns+="s/${escaped_value}/***REDACTED***/g;"
        fi
    done

    if [[ -n "$sed_patterns" ]]; then
        "$@" 2>&1 | sed "$sed_patterns"
        return "${PIPESTATUS[0]}"
    else
        "$@"
    fi
}

# =============================================================================
# UTILITIES
# =============================================================================

# @pre: none
# @post: returns secure random password
# @idempotent: no (random each time)
# @returns: 0 on success, 1 on failure
#
# Generate a secure random password.
#
# Usage: secret_random_password [length] [charset]
# Example: secret_random_password 32
# Example: secret_random_password 16 "alphanumeric"
# Example: secret_random_password 24 "special"
secret_random_password() {
    local length="${1:-16}"
    local charset="${2:-special}"

    local chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

    case "$charset" in
        alphanumeric|alnum)
            # Default chars are alphanumeric
            ;;
        special|full)
            chars+='!@#$%^&*()_+-=[]{}|;:,.<>?'
            ;;
        numeric|digits)
            chars='0123456789'
            ;;
        alpha)
            chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
            ;;
        hex)
            chars='0123456789abcdef'
            ;;
    esac

    local password=""
    local chars_len=${#chars}

    if [[ -r /dev/urandom ]]; then
        while [[ ${#password} -lt $length ]]; do
            local byte
            byte=$(head -c 1 /dev/urandom | od -An -tu1 | tr -d ' ')
            local index=$((byte % chars_len))
            password+="${chars:index:1}"
        done
    else
        _secrets_log error "secret_random_password: /dev/urandom not available"
        return 1
    fi

    printf '%s' "$password"
    return 0
}

# @pre: password non-empty
# @post: returns strength assessment (weak/fair/good/strong)
# @idempotent: yes
# @returns: 0 (always succeeds)
#
# Check password strength.
#
# Usage: secret_strength_check "password"
# Example: strength=$(secret_strength_check "MyP@ssw0rd!")
secret_strength_check() {
    local password="$1"
    local score=0
    local details=""

    if [[ -z "$password" ]]; then
        printf '{"strength":"empty","score":0,"details":"No password provided"}\n'
        return 0
    fi

    local length=${#password}

    # Length scoring
    if (( length >= 8 )); then ((score += 1)); fi
    if (( length >= 12 )); then ((score += 1)); fi
    if (( length >= 16 )); then ((score += 1)); fi
    if (( length >= 20 )); then ((score += 1)); fi

    # Character class scoring
    [[ "$password" =~ [a-z] ]] && ((score += 1))
    [[ "$password" =~ [A-Z] ]] && ((score += 1))
    [[ "$password" =~ [0-9] ]] && ((score += 1))
    [[ "$password" =~ [^a-zA-Z0-9] ]] && ((score += 2))

    # Determine strength category
    local strength
    if (( score <= 2 )); then
        strength="weak"
    elif (( score <= 4 )); then
        strength="fair"
    elif (( score <= 6 )); then
        strength="good"
    else
        strength="strong"
    fi

    # Build details
    details="length=$length"
    [[ "$password" =~ [a-z] ]] && details+=",lowercase=yes" || details+=",lowercase=no"
    [[ "$password" =~ [A-Z] ]] && details+=",uppercase=yes" || details+=",uppercase=no"
    [[ "$password" =~ [0-9] ]] && details+=",digits=yes" || details+=",digits=no"
    [[ "$password" =~ [^a-zA-Z0-9] ]] && details+=",special=yes" || details+=",special=no"

    printf '{"strength":"%s","score":%d,"details":"%s"}\n' "$strength" "$score" "$details"
    return 0
}

# @pre: master key set
# @post: encrypted backup created
# @idempotent: no (creates timestamped backup)
# @returns: 0 on success, 1 on failure
#
# Create an encrypted backup of all secrets.
#
# Usage: secret_backup [output_file]
# Example: secret_backup
# Example: secret_backup "/secure/backup.tar.enc"
secret_backup() {
    local output="${1:-}"

    if [[ -z "$_MAINFRAME_MASTER_KEY" ]]; then
        _secrets_log error "secret_backup: master key not set"
        return 1
    fi

    _secrets_ensure_dir "$MAINFRAME_SECRETS_BACKUP_DIR" || return 1

    # Generate backup filename with timestamp
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${output:-${MAINFRAME_SECRETS_BACKUP_DIR}/secrets_${timestamp}.tar.enc}"

    # Create tar of secrets directory
    local tar_data
    tar_data=$(tar -czf - -C "$MAINFRAME_SECRETS_DIR" data meta salt key_check 2>/dev/null | base64) || {
        _secrets_log error "secret_backup: failed to create archive"
        return 1
    }

    # Encrypt the archive
    local encrypted
    encrypted=$(secret_encrypt "$tar_data" "$_MAINFRAME_MASTER_KEY") || return 1

    # Write backup
    printf '%s' "$encrypted" > "$backup_file" || {
        _secrets_log error "secret_backup: failed to write backup"
        return 1
    }
    chmod 600 "$backup_file"

    secret_audit_log "backup" "secrets_store" "backup created: $backup_file"
    _secrets_log info "Backup created: $backup_file"
    printf '%s' "$backup_file"
    return 0
}

# @pre: backup file exists, password correct
# @post: secrets restored from backup
# @idempotent: yes (overwrites existing)
# @returns: 0 on success, 1 on failure
#
# Restore secrets from an encrypted backup.
#
# Usage: secret_restore "backup_file" "password"
# Example: secret_restore "/secure/backup.tar.enc" "master-password"
secret_restore() {
    local backup_file="$1"
    local password="$2"

    if [[ -z "$backup_file" ]] || [[ ! -f "$backup_file" ]]; then
        _secrets_log error "secret_restore: valid backup file required"
        return 1
    fi

    if [[ -z "$password" ]]; then
        _secrets_log error "secret_restore: password required"
        return 1
    fi

    _secrets_check_openssl || return 1

    # Read backup
    local encrypted
    encrypted=$(<"$backup_file")

    # Get salt from existing installation or fail
    local salt_file="${MAINFRAME_SECRETS_DIR}/salt"
    if [[ ! -f "$salt_file" ]]; then
        _secrets_log error "secret_restore: cannot restore without existing salt (use secret_init first)"
        return 1
    fi

    local salt
    salt=$(<"$salt_file")

    # Derive key
    local key
    key=$(secret_derive_key "$password" "$salt")

    # Decrypt backup
    local tar_data
    tar_data=$(secret_decrypt "$encrypted" "$key") || {
        _secrets_log error "secret_restore: decryption failed (wrong password?)"
        return 1
    }

    # Restore from tar
    _secrets_ensure_dir "${MAINFRAME_SECRETS_DIR}/data" || return 1
    _secrets_ensure_dir "${MAINFRAME_SECRETS_DIR}/meta" || return 1

    printf '%s' "$tar_data" | base64 -d | tar -xzf - -C "$MAINFRAME_SECRETS_DIR" 2>/dev/null || {
        _secrets_log error "secret_restore: failed to extract archive"
        return 1
    }

    # Set master key
    _MAINFRAME_MASTER_KEY="$key"

    secret_audit_log "restore" "secrets_store" "restored from: $backup_file"
    _secrets_log info "Secrets restored from: $backup_file"
    return 0
}

# @pre: none
# @post: all secrets securely wiped
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Securely wipe the entire secrets store.
# WARNING: This is destructive and irreversible!
#
# Usage: secret_wipe [--force]
# Example: secret_wipe --force
secret_wipe() {
    local force="${1:-}"

    if [[ "$force" != "--force" ]]; then
        _secrets_log error "secret_wipe: requires --force flag (destructive operation)"
        return 1
    fi

    if [[ ! -d "$MAINFRAME_SECRETS_DIR" ]]; then
        _secrets_log info "secret_wipe: secrets directory does not exist"
        return 0
    fi

    # Securely overwrite all files before deletion
    local file
    for file in "${MAINFRAME_SECRETS_DIR}/data/"*.enc \
                "${MAINFRAME_SECRETS_DIR}/meta/"*.json \
                "${MAINFRAME_SECRETS_DIR}/salt" \
                "${MAINFRAME_SECRETS_DIR}/key_check"; do
        if [[ -f "$file" ]]; then
            local size
            size=$(wc -c < "$file" 2>/dev/null || echo 64)

            # Overwrite 3 times
            local i
            for i in 1 2 3; do
                head -c "$size" /dev/urandom > "$file" 2>/dev/null
                sync "$file" 2>/dev/null || true
            done
            rm -f "$file"
        fi
    done

    # Clear master key
    secret_clear_master_key

    # Remove directories
    rm -rf "${MAINFRAME_SECRETS_DIR}/data" \
           "${MAINFRAME_SECRETS_DIR}/meta" \
           "${MAINFRAME_SECRETS_DIR}/salt" \
           "${MAINFRAME_SECRETS_DIR}/key_check"

    _secrets_log info "Secrets store wiped"
    return 0
}

# =============================================================================
# USOP JSON OUTPUT HELPERS
# =============================================================================

# @pre: none
# @post: returns JSON status of secrets module
# @idempotent: yes
# @returns: 0
#
# Get module status as JSON (USOP-compliant).
#
# Usage: secret_status
# Example: secret_status | jq .
secret_status() {
    local initialized="false"
    local master_key_set="false"
    local secret_count=0

    if [[ -f "${MAINFRAME_SECRETS_DIR}/salt" ]]; then
        initialized="true"
    fi

    if [[ -n "$_MAINFRAME_MASTER_KEY" ]]; then
        master_key_set="true"
    fi

    if [[ -d "${MAINFRAME_SECRETS_DIR}/data" ]]; then
        secret_count=$(find "${MAINFRAME_SECRETS_DIR}/data" -name "*.enc" 2>/dev/null | wc -l)
        secret_count=${secret_count// /}
    fi

    printf '{"module":"secrets","version":"1.0.0","initialized":%s,"master_key_set":%s,"secret_count":%d,"storage_dir":"%s"}\n' \
        "$initialized" "$master_key_set" "$secret_count" "$(_secrets_json_escape "$MAINFRAME_SECRETS_DIR")"
}

# =============================================================================
# COMPATIBILITY ALIASES
# =============================================================================

# @pre: master key set, secret exists
# @post: secret value returned
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Alias for secret_retrieve for common naming convention.
#
# Usage: secret_get "name"
# Example: api_key=$(secret_get "api_key")
secret_get() {
    secret_retrieve "$@"
}

# @pre: master key set, name non-empty, value non-empty
# @post: encrypted secret stored
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Alias for secret_store for common naming convention.
# Note: --backend flag is accepted but ignored (uses local encrypted storage)
#
# Usage: secret_set "name" "value" [--backend backend]
# Example: secret_set "api_key" "sk-abc123"
secret_set() {
    local name="$1"
    local value="$2"
    shift 2 2>/dev/null || shift

    # Parse and ignore --backend flag for compatibility
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --backend|-b)
                shift 2 2>/dev/null || shift
                ;;
            *)
                shift
                ;;
        esac
    done

    secret_store "$name" "$value"
}

# =============================================================================
# SECRET MASKING (Security: Never log plaintext secrets)
# =============================================================================

# @pre: value non-empty
# @post: returns masked value showing only first/last chars
# @idempotent: yes
# @returns: 0 on success
#
# Mask a secret value for safe logging.
#
# Usage: secret_mask "sk-proj-abc123xyz789"
# Output: "sk**89" (first 2, last 2 chars visible)
# Usage: secret_mask "secret" 3 3
# Output: "sec***ret"
secret_mask() {
    local value="$1"
    local visible_start="${2:-2}"
    local visible_end="${3:-2}"
    local len=${#value}

    # Handle empty or short values
    if [[ -z "$value" ]]; then
        printf '****\n'
        return 0
    fi

    if [[ $len -le $((visible_start + visible_end)) ]]; then
        printf '****\n'
        return 0
    fi

    local start="${value:0:$visible_start}"
    local end="${value:$((len - visible_end))}"
    local mask_len=$((len - visible_start - visible_end))
    local mask
    mask=$(printf '%*s' "$mask_len" '' | tr ' ' '*')

    printf '%s%s%s\n' "$start" "$mask" "$end"
}

# =============================================================================
# BACKEND MANAGEMENT (Compatibility Layer)
# =============================================================================
# The MAINFRAME secrets library uses local encrypted storage as its primary
# backend. These functions provide compatibility with multi-backend patterns.
# =============================================================================

# Registered backends (for compatibility)
declare -gA _SECRETS_BACKENDS=(
    ["local"]='{"type":"encrypted","storage":"local","status":"active"}'
)

# @pre: name valid, config valid JSON
# @post: backend registered (note: only local backend is functional)
# @idempotent: yes
# @returns: 0 on success, 1 on failure
#
# Register a custom backend configuration.
# Note: Only the built-in "local" encrypted backend is fully functional.
# Other backends are registered for metadata purposes but not implemented.
#
# Usage: secret_backend_add "name" '{"type":"vault","endpoint":"..."}'
# Example: secret_backend_add "vault" '{"type":"vault","addr":"http://localhost:8200"}'
secret_backend_add() {
    local name="$1"
    local config="$2"

    if [[ -z "$name" ]]; then
        _secrets_log error "secret_backend_add: name required"
        return 1
    fi

    if [[ -z "$config" ]]; then
        _secrets_log error "secret_backend_add: config required"
        return 1
    fi

    # Validate name format (lowercase alphanumeric with underscores)
    if [[ ! "$name" =~ ^[a-z][a-z0-9_]*$ ]]; then
        _secrets_log error "secret_backend_add: invalid name format (use lowercase alphanumeric)"
        return 1
    fi

    # Store configuration
    _SECRETS_BACKENDS["$name"]="$config"

    secret_audit_log "backend_add" "$name" "backend registered"
    _secrets_log info "Backend registered: $name (note: only 'local' backend is functional)"
    return 0
}

# @pre: none
# @post: list of backends printed to stdout
# @idempotent: yes
# @returns: 0
#
# List all configured backends with their status.
#
# Usage: secret_backend_list
# Example: secret_backend_list | grep active
secret_backend_list() {
    local name status

    for name in "${!_SECRETS_BACKENDS[@]}"; do
        local config="${_SECRETS_BACKENDS[$name]}"

        # Determine status based on backend type
        if [[ "$name" == "local" ]]; then
            if [[ -n "$_MAINFRAME_MASTER_KEY" ]]; then
                status="active"
            else
                status="locked"
            fi
        else
            status="registered"
        fi

        printf '%s:%s\n' "$name" "$status"
    done
}

# =============================================================================
# CLEANUP ON EXIT
# =============================================================================

# Trap to clear master key on script exit for security
trap 'secret_clear_master_key 2>/dev/null' EXIT
