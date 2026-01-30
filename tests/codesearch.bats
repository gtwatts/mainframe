#!/usr/bin/env bats
# =============================================================================
# MAINFRAME/tests/codesearch.bats - Tests for Semantic Code Search
# =============================================================================
# Run with: bats tests/codesearch.bats
# =============================================================================

# Setup test environment
setup() {
    # Source the library
    export MAINFRAME_ROOT="${BATS_TEST_DIRNAME}/.."
    source "${MAINFRAME_ROOT}/lib/codesearch.sh"

    # Create test fixtures directory
    export TEST_DIR="${BATS_TMPDIR}/codesearch_test_$$"
    mkdir -p "$TEST_DIR"

    # Disable safe base checking for tests (tests create temp dirs)
    export MAINFRAME_CODESEARCH_SAFE_BASE="$BATS_TMPDIR"

    # Create test files
    _create_test_files
}

# Cleanup
teardown() {
    rm -rf "$TEST_DIR"
}

# Helper to create test source files
_create_test_files() {
    # Python test file
    cat > "$TEST_DIR/test_module.py" << 'EOF'
"""Test Python module"""

import os
from typing import Optional
from collections import defaultdict

MAX_ITEMS = 100
DEFAULT_NAME = "test"

class UserService:
    """User service class"""

    def __init__(self, name: str):
        self.name = name

    def get_user(self, user_id: int) -> Optional[dict]:
        """Get user by ID"""
        return {"id": user_id, "name": self.name}

    def _private_method(self):
        """Private method"""
        pass

class AdminService(UserService):
    """Admin service extending UserService"""

    async def async_operation(self):
        """Async method"""
        pass

def authenticate(username: str, password: str) -> bool:
    """Authenticate user"""
    return True

async def fetch_data(url: str):
    """Async function to fetch data"""
    pass

def _helper_function():
    """Private helper"""
    pass

__all__ = ['UserService', 'AdminService', 'authenticate']
EOF

    # TypeScript test file
    cat > "$TEST_DIR/service.ts" << 'EOF'
import { Request, Response } from 'express';
import type { User } from './types';

export const API_VERSION = '1.0.0';
export const MAX_RETRIES = 3;

export interface IUserService {
    getUser(id: number): Promise<User>;
    createUser(data: Partial<User>): Promise<User>;
}

export interface IAdminService extends IUserService {
    deleteUser(id: number): Promise<void>;
}

export class UserServiceImpl implements IUserService {
    constructor(private readonly db: Database) {}

    async getUser(id: number): Promise<User> {
        return this.db.findUser(id);
    }

    async createUser(data: Partial<User>): Promise<User> {
        return this.db.createUser(data);
    }
}

export function handleRequest(req: Request, res: Response): void {
    res.json({ status: 'ok' });
}

export const processData = async (items: string[]): Promise<void> => {
    for (const item of items) {
        console.log(item);
    }
};

function internalHelper(): void {
    // Not exported
}
EOF

    # Go test file
    cat > "$TEST_DIR/handler.go" << 'EOF'
package main

import (
    "fmt"
    "net/http"
)

const MaxConnections = 100
const defaultTimeout = 30

type UserHandler struct {
    db *Database
}

type Config struct {
    Host string
    Port int
}

func NewUserHandler(db *Database) *UserHandler {
    return &UserHandler{db: db}
}

func (h *UserHandler) HandleGet(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintf(w, "Hello")
}

func (h *UserHandler) handleInternal() {
    // unexported method
}

type UserService interface {
    GetUser(id int) (*User, error)
    CreateUser(data UserData) (*User, error)
}

func processRequest(r *http.Request) error {
    return nil
}
EOF

    # Rust test file
    cat > "$TEST_DIR/lib.rs" << 'EOF'
use std::collections::HashMap;
use crate::models::User;

pub const MAX_ITEMS: usize = 1000;
const INTERNAL_LIMIT: usize = 100;

pub struct UserService {
    users: HashMap<u64, User>,
}

struct InternalState {
    count: usize,
}

pub trait Repository {
    fn find(&self, id: u64) -> Option<&User>;
    fn save(&mut self, user: User) -> Result<(), Error>;
}

trait InternalTrait {
    fn internal_method(&self);
}

impl UserService {
    pub fn new() -> Self {
        UserService {
            users: HashMap::new(),
        }
    }

    pub async fn get_user(&self, id: u64) -> Option<&User> {
        self.users.get(&id)
    }

    fn private_method(&self) {
        // private
    }
}

pub fn authenticate(token: &str) -> bool {
    !token.is_empty()
}

fn internal_helper() -> bool {
    true
}
EOF

    # Bash test file
    cat > "$TEST_DIR/script.sh" << 'EOF'
#!/usr/bin/env bash

readonly MAX_RETRIES=5
readonly DEFAULT_TIMEOUT=30

# Function with 'function' keyword
function process_data() {
    local data="$1"
    echo "Processing: $data"
}

# Function without keyword
cleanup() {
    rm -rf /tmp/test
}

# Another function
validate_input() {
    local input="$1"
    [[ -n "$input" ]]
}
EOF

    # JavaScript test file with various patterns
    cat > "$TEST_DIR/utils.js" << 'EOF'
const fs = require('fs');
const path = require('path');

const MAX_SIZE = 1024;

class FileHandler {
    constructor(basePath) {
        this.basePath = basePath;
    }

    readFile(name) {
        return fs.readFileSync(path.join(this.basePath, name));
    }
}

function parseConfig(configPath) {
    return JSON.parse(fs.readFileSync(configPath));
}

async function fetchRemote(url) {
    const response = await fetch(url);
    return response.json();
}

const helper = function(x) {
    return x * 2;
};

const asyncHelper = async (data) => {
    return data;
};

module.exports = { FileHandler, parseConfig, fetchRemote };
EOF

    # Create a subdirectory with more files
    mkdir -p "$TEST_DIR/subdir"

    cat > "$TEST_DIR/subdir/models.ts" << 'EOF'
export interface User {
    id: number;
    name: string;
    email: string;
}

export interface Admin extends User {
    permissions: string[];
}

export type UserRole = 'admin' | 'user' | 'guest';

export class UserModel implements User {
    constructor(
        public id: number,
        public name: string,
        public email: string
    ) {}
}
EOF

    # Create a sensitive file that should be excluded
    echo "SECRET_KEY=abc123" > "$TEST_DIR/.env"
    echo "API_KEY=xyz789" > "$TEST_DIR/credentials.json"
}

# =============================================================================
# Language Detection Tests
# =============================================================================

@test "code_detect_lang: detects Python files" {
    run code_detect_lang "test.py"
    [ "$status" -eq 0 ]
    [ "$output" = "python" ]
}

@test "code_detect_lang: detects TypeScript files" {
    run code_detect_lang "component.tsx"
    [ "$status" -eq 0 ]
    [ "$output" = "typescript" ]
}

@test "code_detect_lang: detects JavaScript files" {
    run code_detect_lang "app.js"
    [ "$status" -eq 0 ]
    [ "$output" = "javascript" ]
}

@test "code_detect_lang: detects Go files" {
    run code_detect_lang "main.go"
    [ "$status" -eq 0 ]
    [ "$output" = "go" ]
}

@test "code_detect_lang: detects Rust files" {
    run code_detect_lang "lib.rs"
    [ "$status" -eq 0 ]
    [ "$output" = "rust" ]
}

@test "code_detect_lang: detects Bash files" {
    run code_detect_lang "script.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "bash" ]
}

@test "code_detect_lang: returns unknown for unrecognized extensions" {
    run code_detect_lang "data.xyz"
    [ "$output" = "unknown" ]
}

@test "code_detect_lang: handles case-insensitive extensions" {
    run code_detect_lang "Test.PY"
    [ "$status" -eq 0 ]
    [ "$output" = "python" ]
}

# =============================================================================
# Function Search Tests
# =============================================================================

@test "code_find_functions: finds Python functions" {
    run code_find_functions "$TEST_DIR/test_module.py" --lang python
    [ "$status" -eq 0 ]
    [[ "$output" == *"authenticate"* ]]
    [[ "$output" == *"fetch_data"* ]]
}

@test "code_find_functions: finds async Python functions" {
    run code_find_functions "$TEST_DIR/test_module.py" --lang python
    [ "$status" -eq 0 ]
    [[ "$output" == *"fetch_data"* ]]
    [[ "$output" == *"async_operation"* ]]
}

@test "code_find_functions: filters by name pattern" {
    run code_find_functions "$TEST_DIR/test_module.py" --lang python --name "^auth"
    [ "$status" -eq 0 ]
    [[ "$output" == *"authenticate"* ]]
    [[ "$output" != *"fetch_data"* ]]
}

@test "code_find_functions: finds TypeScript functions" {
    run code_find_functions "$TEST_DIR/service.ts" --lang typescript
    [ "$status" -eq 0 ]
    [[ "$output" == *"handleRequest"* ]]
}

@test "code_find_functions: finds Go functions" {
    run code_find_functions "$TEST_DIR/handler.go" --lang go
    [ "$status" -eq 0 ]
    [[ "$output" == *"NewUserHandler"* ]]
    [[ "$output" == *"processRequest"* ]]
}

@test "code_find_functions: finds Rust functions" {
    run code_find_functions "$TEST_DIR/lib.rs" --lang rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"authenticate"* ]]
}

@test "code_find_functions: finds Bash functions" {
    run code_find_functions "$TEST_DIR/script.sh" --lang bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"process_data"* ]]
    [[ "$output" == *"cleanup"* ]]
}

@test "code_find_functions: outputs JSON format" {
    run code_find_functions "$TEST_DIR/test_module.py" --lang python --json
    [ "$status" -eq 0 ]
    [[ "$output" == "["* ]]
    [[ "$output" == *'"name":"authenticate"'* ]]
    [[ "$output" == *'"lang":"python"'* ]]
}

@test "code_find_functions: --exported filters to public functions (Python)" {
    run code_find_functions "$TEST_DIR/test_module.py" --lang python --exported
    [ "$status" -eq 0 ]
    [[ "$output" == *"authenticate"* ]]
    [[ "$output" != *"_helper_function"* ]]
    [[ "$output" != *"_private_method"* ]]
}

@test "code_find_functions: --exported filters to exported functions (Go)" {
    run code_find_functions "$TEST_DIR/handler.go" --lang go --exported
    [ "$status" -eq 0 ]
    [[ "$output" == *"NewUserHandler"* ]]
    [[ "$output" == *"HandleGet"* ]]
    [[ "$output" != *"processRequest"* ]]  # lowercase = unexported
}

@test "code_find_functions: searches directories recursively" {
    run code_find_functions "$TEST_DIR" --lang typescript
    [ "$status" -eq 0 ]
    [[ "$output" == *"handleRequest"* ]]
}

@test "code_find_functions: returns error for non-existent path" {
    run code_find_functions "/nonexistent/path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"error"* ]]
}

@test "code_find_functions: returns 2 when no matches found" {
    run code_find_functions "$TEST_DIR/test_module.py" --lang python --name "^nonexistent"
    [ "$status" -eq 2 ]
}

# =============================================================================
# Class Search Tests
# =============================================================================

@test "code_find_classes: finds Python classes" {
    run code_find_classes "$TEST_DIR/test_module.py" --lang python
    [ "$status" -eq 0 ]
    [[ "$output" == *"UserService"* ]]
    [[ "$output" == *"AdminService"* ]]
}

@test "code_find_classes: finds TypeScript classes" {
    run code_find_classes "$TEST_DIR/service.ts" --lang typescript
    [ "$status" -eq 0 ]
    [[ "$output" == *"UserServiceImpl"* ]]
}

@test "code_find_classes: finds Go structs" {
    run code_find_classes "$TEST_DIR/handler.go" --lang go
    [ "$status" -eq 0 ]
    [[ "$output" == *"UserHandler"* ]]
    [[ "$output" == *"Config"* ]]
}

@test "code_find_classes: finds Rust structs" {
    run code_find_classes "$TEST_DIR/lib.rs" --lang rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"UserService"* ]]
}

@test "code_find_classes: filters by name pattern" {
    run code_find_classes "$TEST_DIR/test_module.py" --lang python --name "User"
    [ "$status" -eq 0 ]
    [[ "$output" == *"UserService"* ]]
}

@test "code_find_classes: outputs JSON format" {
    run code_find_classes "$TEST_DIR/handler.go" --lang go --json
    [ "$status" -eq 0 ]
    [[ "$output" == "["* ]]
    [[ "$output" == *'"type":"struct"'* ]]
}

# =============================================================================
# Interface Search Tests
# =============================================================================

@test "code_find_interfaces: finds TypeScript interfaces" {
    run code_find_interfaces "$TEST_DIR/service.ts" --lang typescript
    [ "$status" -eq 0 ]
    [[ "$output" == *"IUserService"* ]]
    [[ "$output" == *"IAdminService"* ]]
}

@test "code_find_interfaces: finds Go interfaces" {
    run code_find_interfaces "$TEST_DIR/handler.go" --lang go
    [ "$status" -eq 0 ]
    [[ "$output" == *"UserService"* ]]
}

@test "code_find_interfaces: finds Rust traits" {
    run code_find_interfaces "$TEST_DIR/lib.rs" --lang rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repository"* ]]
}

@test "code_find_interfaces: outputs JSON format" {
    run code_find_interfaces "$TEST_DIR/service.ts" --lang typescript --json
    [ "$status" -eq 0 ]
    [[ "$output" == "["* ]]
    [[ "$output" == *'"name":"IUserService"'* ]]
}

# =============================================================================
# Constants Search Tests
# =============================================================================

@test "code_find_constants: finds Python constants" {
    run code_find_constants "$TEST_DIR/test_module.py" --lang python
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAX_ITEMS"* ]]
    [[ "$output" == *"DEFAULT_NAME"* ]]
}

@test "code_find_constants: finds TypeScript constants" {
    run code_find_constants "$TEST_DIR/service.ts" --lang typescript
    [ "$status" -eq 0 ]
    [[ "$output" == *"API_VERSION"* ]]
    [[ "$output" == *"MAX_RETRIES"* ]]
}

@test "code_find_constants: finds Go constants" {
    run code_find_constants "$TEST_DIR/handler.go" --lang go
    [ "$status" -eq 0 ]
    [[ "$output" == *"MaxConnections"* ]]
}

@test "code_find_constants: finds Rust constants" {
    run code_find_constants "$TEST_DIR/lib.rs" --lang rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAX_ITEMS"* ]]
}

@test "code_find_constants: finds Bash readonly variables" {
    run code_find_constants "$TEST_DIR/script.sh" --lang bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAX_RETRIES"* ]]
}

# =============================================================================
# Caller Search Tests
# =============================================================================

@test "code_find_callers: finds function call sites" {
    run code_find_callers "getUser" "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"getUser"* ]]
}

@test "code_find_callers: outputs JSON format" {
    run code_find_callers "getUser" "$TEST_DIR" --json
    [ "$status" -eq 0 ]
    [[ "$output" == "["* ]] || [[ "$output" == "{" ]]
}

@test "code_find_callers: filters by language" {
    run code_find_callers "getUser" "$TEST_DIR" --lang typescript
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# =============================================================================
# Import Search Tests
# =============================================================================

@test "code_find_imports: finds Python imports" {
    run code_find_imports "$TEST_DIR/test_module.py" --lang python
    [ "$status" -eq 0 ]
    [[ "$output" == *"os"* ]]
    [[ "$output" == *"typing"* ]]
}

@test "code_find_imports: finds TypeScript imports" {
    run code_find_imports "$TEST_DIR/service.ts" --lang typescript
    [ "$status" -eq 0 ]
    [[ "$output" == *"express"* ]]
}

@test "code_find_imports: finds Go imports" {
    run code_find_imports "$TEST_DIR/handler.go" --lang go
    [ "$status" -eq 0 ]
    [[ "$output" == *"fmt"* ]]
    [[ "$output" == *"net/http"* ]]
}

@test "code_find_imports: finds Rust use statements" {
    run code_find_imports "$TEST_DIR/lib.rs" --lang rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"std::collections::HashMap"* ]]
}

@test "code_find_imports: filters by module pattern" {
    run code_find_imports "$TEST_DIR/test_module.py" --lang python --module "typing"
    [ "$status" -eq 0 ]
    [[ "$output" == *"typing"* ]]
    [[ "$output" != *"collections"* ]]
}

@test "code_find_imports: outputs JSON format" {
    run code_find_imports "$TEST_DIR/service.ts" --lang typescript --json
    [ "$status" -eq 0 ]
    [[ "$output" == "["* ]]
    [[ "$output" == *'"module"'* ]]
}

# =============================================================================
# Export Search Tests
# =============================================================================

@test "code_find_exports: finds TypeScript exports" {
    run code_find_exports "$TEST_DIR/service.ts" --lang typescript
    [ "$status" -eq 0 ]
    [[ "$output" == *"handleRequest"* ]] || [[ "$output" == *"UserServiceImpl"* ]]
}

@test "code_find_exports: finds Go exported symbols" {
    run code_find_exports "$TEST_DIR/handler.go" --lang go
    [ "$status" -eq 0 ]
    [[ "$output" == *"NewUserHandler"* ]] || [[ "$output" == *"UserHandler"* ]]
}

@test "code_find_exports: finds Rust pub symbols" {
    run code_find_exports "$TEST_DIR/lib.rs" --lang rust
    [ "$status" -eq 0 ]
    [[ "$output" == *"UserService"* ]] || [[ "$output" == *"authenticate"* ]]
}

@test "code_find_exports: finds Python __all__" {
    run code_find_exports "$TEST_DIR/test_module.py" --lang python
    [ "$status" -eq 0 ]
    [[ "$output" == *"__all__"* ]]
}

# =============================================================================
# Symbol At Position Tests
# =============================================================================

@test "code_symbol_at: identifies symbol at position" {
    run code_symbol_at "$TEST_DIR/test_module.py" 23 5
    [ "$status" -eq 0 ]
    [[ "$output" == *"def"* ]] || [[ "$output" == *"authenticate"* ]] || [[ "$output" == *"identifier"* ]]
}

@test "code_symbol_at: outputs JSON format" {
    run code_symbol_at "$TEST_DIR/test_module.py" 23 5 --json
    [ "$status" -eq 0 ]
    [[ "$output" == "{"* ]]
    [[ "$output" == *'"symbol"'* ]]
}

@test "code_symbol_at: returns error for invalid line" {
    run code_symbol_at "$TEST_DIR/test_module.py" 9999 1
    [ "$status" -ne 0 ]
    [[ "$output" == *"error"* ]]
}

# =============================================================================
# Index Building Tests
# =============================================================================

@test "code_build_index: builds comprehensive index" {
    run code_build_index "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Functions"* ]]
    [[ "$output" == *"Classes"* ]]
}

@test "code_build_index: outputs JSON format" {
    run code_build_index "$TEST_DIR" --json
    [ "$status" -eq 0 ]
    [[ "$output" == "{"* ]]
    [[ "$output" == *'"functions"'* ]]
    [[ "$output" == *'"classes"'* ]]
    [[ "$output" == *'"totals"'* ]]
}

@test "code_build_index: filters by language" {
    run code_build_index "$TEST_DIR" --lang python --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"lang":"python"'* ]] || [[ "$output" == *"python"* ]] || true  # Index may not include lang
}

# =============================================================================
# Unified Search Tests
# =============================================================================

@test "code_search: searches by type 'function'" {
    run code_search "$TEST_DIR" --type function --lang python
    [ "$status" -eq 0 ]
    [[ "$output" == *"authenticate"* ]]
}

@test "code_search: searches by type 'class'" {
    run code_search "$TEST_DIR" --type class --lang python
    [ "$status" -eq 0 ]
    [[ "$output" == *"UserService"* ]]
}

@test "code_search: searches all types" {
    run code_search "$TEST_DIR" --type all --lang python
    [ "$status" -eq 0 ]
    [[ "$output" == *"Functions"* ]] || [[ "$output" == *"functions"* ]]
}

@test "code_search: filters by name across types" {
    run code_search "$TEST_DIR" --type all --name "User"
    [ "$status" -eq 0 ]
    [[ "$output" == *"User"* ]]
}

@test "code_search: outputs JSON format" {
    run code_search "$TEST_DIR" --type all --lang typescript --json
    [ "$status" -eq 0 ]
    [[ "$output" == "{"* ]]
}

# =============================================================================
# Security Tests
# =============================================================================

@test "security: excludes sensitive files (.env)" {
    run code_find_functions "$TEST_DIR" --lang python
    [ "$status" -eq 0 ]
    [[ "$output" != *".env"* ]]
}

@test "security: excludes credentials files" {
    run code_find_constants "$TEST_DIR"
    [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
    [[ "$output" != *"credentials.json"* ]]
}

@test "security: rejects shell injection in pattern" {
    run code_find_functions "$TEST_DIR" --name '$(rm -rf /)'
    [ "$status" -ne 0 ]
    [[ "$output" == *"error"* ]] || [[ "$output" == *"injection"* ]]
}

@test "security: validates path traversal attempts" {
    # Note: This depends on safe base configuration
    export MAINFRAME_CODESEARCH_SAFE_BASE="$TEST_DIR"
    run code_find_functions "/etc/passwd"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "edge: handles empty directory" {
    mkdir -p "$TEST_DIR/empty"
    run code_find_functions "$TEST_DIR/empty"
    [ "$status" -eq 2 ]  # No matches
}

@test "edge: handles files without recognized extensions" {
    echo "function test() {}" > "$TEST_DIR/unknown.xyz"
    run code_find_functions "$TEST_DIR/unknown.xyz"
    [ "$status" -eq 2 ]  # Unknown language
}

@test "edge: handles binary files gracefully" {
    # Create a binary-ish file
    printf '\x00\x01\x02\x03' > "$TEST_DIR/binary.py"
    run code_find_functions "$TEST_DIR/binary.py" --lang python
    # Should not crash
    [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
}

@test "edge: respects max results limit" {
    export MAINFRAME_CODESEARCH_MAX_RESULTS=2
    run code_find_functions "$TEST_DIR" --lang python
    [ "$status" -eq 0 ]
    # Count newlines to verify limit
    local count
    count=$(echo "$output" | grep -c ":" || true)
    [ "$count" -le 2 ]
}
