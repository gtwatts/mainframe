#!/usr/bin/env bats
# =============================================================================
# MAINFRAME: TypeScript Analysis Library Tests
# =============================================================================
# Tests for lib/typescript.sh - TypeMiner, TypeDiff, ImportCost
# =============================================================================

load 'test_helper'

setup() {
    source_lib "typescript"
    TEST_DIR=$(create_test_dir "typescript")

    # Create directories
    mkdir -p "$TEST_DIR/src/services" "$TEST_DIR/src/utils"
    mkdir -p "$TEST_DIR/api/v1" "$TEST_DIR/api/v2"
    mkdir -p "$TEST_DIR/node_modules/express/lib"
    mkdir -p "$TEST_DIR/node_modules/lodash"
    mkdir -p "$TEST_DIR/node_modules/@types/node"

    # Create tsconfig.json
    printf '{\n  "compilerOptions": {\n    "rootDir": "./src",\n    "outDir": "./dist",\n    "strict": true\n  }\n}\n' > "$TEST_DIR/tsconfig.json"

    # Create src/index.ts
    printf "import { UserService } from './services/user';\n" > "$TEST_DIR/src/index.ts"
    printf "import { Logger } from './utils/logger';\n" >> "$TEST_DIR/src/index.ts"
    printf "import type { Config } from './types';\n" >> "$TEST_DIR/src/index.ts"
    printf "import express from 'express';\n" >> "$TEST_DIR/src/index.ts"
    printf "import lodash from 'lodash';\n\n" >> "$TEST_DIR/src/index.ts"
    printf "export function main(): void {\n    const logger = new Logger();\n    const service = new UserService(logger);\n}\n\n" >> "$TEST_DIR/src/index.ts"
    printf 'export const VERSION = "1.0.0";\n' >> "$TEST_DIR/src/index.ts"

    # Create src/services/user.ts
    printf "import { Logger } from '../utils/logger';\n" > "$TEST_DIR/src/services/user.ts"
    printf "import { DatabaseClient } from '../db/client';\n" >> "$TEST_DIR/src/services/user.ts"
    printf "import type { User } from '../types';\n\n" >> "$TEST_DIR/src/services/user.ts"
    printf "export class UserService {\n    constructor(private logger: Logger) {}\n\n" >> "$TEST_DIR/src/services/user.ts"
    printf "    async getUser(id: string): Promise<User> {\n        return { id, name: 'test' };\n    }\n}\n\n" >> "$TEST_DIR/src/services/user.ts"
    printf "export function createUserService(logger: Logger): UserService {\n    return new UserService(logger);\n}\n" >> "$TEST_DIR/src/services/user.ts"

    # Create src/utils/logger.ts
    printf "export class Logger {\n    info(msg: string): void {\n        console.log(msg);\n    }\n" > "$TEST_DIR/src/utils/logger.ts"
    printf "    error(msg: string): void {\n        console.error(msg);\n    }\n}\n\n" >> "$TEST_DIR/src/utils/logger.ts"
    printf "export type LogLevel = 'info' | 'warn' | 'error';\n" >> "$TEST_DIR/src/utils/logger.ts"

    # Create src/types.ts
    printf "export interface User {\n    id: string;\n    name: string;\n    email?: string;\n}\n\n" > "$TEST_DIR/src/types.ts"
    printf "export type Config = {\n    port: number;\n    host: string;\n};\n\n" >> "$TEST_DIR/src/types.ts"
    printf "export interface DatabaseConfig {\n    url: string;\n    pool: number;\n}\n" >> "$TEST_DIR/src/types.ts"

    # Create api/v1/index.d.ts
    printf "export declare function getUser(id: string): Promise<User>;\n" > "$TEST_DIR/api/v1/index.d.ts"
    printf "export declare function createUser(name: string, email: string): Promise<User>;\n" >> "$TEST_DIR/api/v1/index.d.ts"
    printf "export declare function deleteUser(id: string): Promise<void>;\n" >> "$TEST_DIR/api/v1/index.d.ts"
    printf "export declare const VERSION: string;\n" >> "$TEST_DIR/api/v1/index.d.ts"
    printf "export interface User {\n    id: string;\n    name: string;\n}\n" >> "$TEST_DIR/api/v1/index.d.ts"
    printf "export type UserId = string;\n" >> "$TEST_DIR/api/v1/index.d.ts"

    # Create api/v2/index.d.ts
    printf "export declare function getUser(id: string, options?: GetOptions): Promise<User>;\n" > "$TEST_DIR/api/v2/index.d.ts"
    printf "export declare function createUser(data: CreateUserData): Promise<User>;\n" >> "$TEST_DIR/api/v2/index.d.ts"
    printf "export declare const VERSION: string;\n" >> "$TEST_DIR/api/v2/index.d.ts"
    printf "export declare function updateUser(id: string, data: Partial<User>): Promise<User>;\n" >> "$TEST_DIR/api/v2/index.d.ts"
    printf "export interface User {\n    id: string;\n    name: string;\n    email?: string;\n}\n" >> "$TEST_DIR/api/v2/index.d.ts"
    printf "export type UserId = string;\n" >> "$TEST_DIR/api/v2/index.d.ts"
    printf "export type GetOptions = { includeDeleted?: boolean };\n" >> "$TEST_DIR/api/v2/index.d.ts"

    # Create fake node_modules JS files for ImportCost tests
    printf 'module.exports = function() { return "express"; }\n' > "$TEST_DIR/node_modules/express/index.js"
    printf 'var app = {};\n%.0s' {1..100} > "$TEST_DIR/node_modules/express/lib/app.js"
    printf 'module.exports = {};\n%.0s' {1..50} > "$TEST_DIR/node_modules/lodash/index.js"
}

teardown() {
    cleanup_test_dir "$TEST_DIR"
}

# =============================================================================
# PROJECT DETECTION TESTS
# =============================================================================

@test "ts_is_project detects tsconfig.json" {
    run ts_is_project "$TEST_DIR"
    [ "$status" -eq 0 ]
}

@test "ts_is_project returns 1 for non-TS directory" {
    local non_ts
    non_ts=$(create_test_dir "non_ts")
    run ts_is_project "$non_ts"
    [ "$status" -ne 0 ]
    cleanup_test_dir "$non_ts"
}

@test "ts_source_dir reads rootDir from tsconfig" {
    run ts_source_dir "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"src"* ]]
}

# =============================================================================
# TYPEMINER - IMPORT ANALYSIS TESTS
# =============================================================================

@test "ts_file_imports extracts imports from TS file" {
    run ts_file_imports "$TEST_DIR/src/index.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"./services/user"* ]]
    [[ "$output" == *"./utils/logger"* ]]
    [[ "$output" == *"express"* ]]
    [[ "$output" == *"lodash"* ]]
}

@test "ts_file_imports extracts type imports" {
    run ts_file_imports "$TEST_DIR/src/index.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"./types"* ]]
}

@test "ts_file_imports returns error for non-existent file" {
    run ts_file_imports "/nonexistent/file.ts"
    [ "$status" -ne 0 ]
}

@test "ts_import_frequency counts module usage" {
    run ts_import_frequency "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"logger"* ]]
}

@test "ts_import_frequency respects threshold" {
    run ts_import_frequency "$TEST_DIR" 999
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ts_import_graph shows dependency edges" {
    run ts_import_graph "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *" -> "* ]]
    [[ "$output" == *"index.ts"* ]]
}

@test "ts_import_graph fails for non-TS project" {
    local non_ts
    non_ts=$(create_test_dir "non_ts_graph")
    run ts_import_graph "$non_ts"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not a TypeScript project"* ]]
    cleanup_test_dir "$non_ts"
}

@test "ts_type_only_imports runs without error" {
    run ts_type_only_imports "$TEST_DIR"
    [ "$status" -eq 0 ]
}

# =============================================================================
# TYPEDIFF - API BREAKING CHANGE TESTS
# =============================================================================

@test "ts_api_extract finds exported declarations" {
    run ts_api_extract "$TEST_DIR/api/v1/index.d.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function getUser"* ]]
    [[ "$output" == *"function createUser"* ]]
    [[ "$output" == *"function deleteUser"* ]]
    [[ "$output" == *"const VERSION"* ]]
    [[ "$output" == *"interface User"* ]]
}

@test "ts_api_names extracts identifiers" {
    run ts_api_names "$TEST_DIR/api/v1/index.d.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"getUser"* ]]
    [[ "$output" == *"createUser"* ]]
    [[ "$output" == *"VERSION"* ]]
    [[ "$output" == *"User"* ]]
    [[ "$output" == *"UserId"* ]]
}

@test "ts_api_diff shows additions" {
    run ts_api_diff "$TEST_DIR/api/v1/index.d.ts" "$TEST_DIR/api/v2/index.d.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"+function updateUser"* ]]
}

@test "ts_api_diff shows removals" {
    run ts_api_diff "$TEST_DIR/api/v1/index.d.ts" "$TEST_DIR/api/v2/index.d.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-function deleteUser"* ]]
}

@test "ts_api_diff shows signature changes" {
    run ts_api_diff "$TEST_DIR/api/v1/index.d.ts" "$TEST_DIR/api/v2/index.d.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"createUser"* ]]
}

@test "ts_breaking_changes detects removed exports" {
    run ts_breaking_changes "$TEST_DIR/api/v1/index.d.ts" "$TEST_DIR/api/v2/index.d.ts"
    [ "$status" -ne 0 ]
    [[ "$output" == *"BREAKING"* ]]
    [[ "$output" == *"deleteUser"* ]]
}

@test "ts_breaking_changes detects signature changes" {
    run ts_breaking_changes "$TEST_DIR/api/v1/index.d.ts" "$TEST_DIR/api/v2/index.d.ts"
    [[ "$output" == *"Signature changed"* ]]
}

@test "ts_breaking_changes reports no breaks for identical files" {
    run ts_breaking_changes "$TEST_DIR/api/v1/index.d.ts" "$TEST_DIR/api/v1/index.d.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No breaking changes"* ]]
}

@test "ts_api_summary counts additions and removals" {
    run ts_api_summary "$TEST_DIR/api/v1/index.d.ts" "$TEST_DIR/api/v2/index.d.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"added="* ]]
    [[ "$output" == *"removed="* ]]
    [[ "$output" == *"semver=major"* ]]
}

@test "ts_api_summary suggests major for removals" {
    run ts_api_summary "$TEST_DIR/api/v1/index.d.ts" "$TEST_DIR/api/v2/index.d.ts"
    [[ "$output" == *"major"* ]]
}

@test "ts_api_extract returns error for missing file" {
    run ts_api_extract "/nonexistent.d.ts"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# =============================================================================
# IMPORTCOST - BUNDLE SIZE TESTS
# =============================================================================

@test "ts_import_cost measures package size" {
    run ts_import_cost "express" "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -gt 0 ]
}

@test "ts_import_cost returns 0 for missing package" {
    run ts_import_cost "nonexistent-package" "$TEST_DIR"
    [ "$status" -ne 0 ]
    [ "$output" = "0" ]
}

@test "ts_import_cost_js measures JS-only size" {
    run ts_import_cost_js "express" "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -gt 0 ]
}

@test "ts_import_cost_file analyzes file imports" {
    run ts_import_cost_file "$TEST_DIR/src/index.ts" "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"express"* ]] || [[ "$output" == *"lodash"* ]]
}

@test "ts_dep_count counts transitive deps" {
    mkdir -p "$TEST_DIR/node_modules/express/node_modules/body-parser"
    mkdir -p "$TEST_DIR/node_modules/express/node_modules/cookie"
    run ts_dep_count "express" "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "ts_dep_count returns 0 for package without deps" {
    run ts_dep_count "lodash" "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

@test "ts_file_count counts TS files" {
    run ts_file_count "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]
}

@test "ts_file_count excludes node_modules" {
    printf "export type X = string;\n" > "$TEST_DIR/node_modules/express/types.ts"
    local count
    count=$(ts_file_count "$TEST_DIR")
    [ "$count" -lt 10 ]
}

@test "ts_loc counts lines of code" {
    run ts_loc "$TEST_DIR"
    [ "$status" -eq 0 ]
    [ "$output" -gt 10 ]
}

@test "ts_exports lists exported symbols" {
    run ts_exports "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"export"* ]]
}

@test "ts_summary gives project overview" {
    run ts_summary "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"files="* ]]
    [[ "$output" == *"loc="* ]]
    [[ "$output" == *"unique_imports="* ]]
}

@test "ts_summary fails for non-TS project" {
    local non_ts
    non_ts=$(create_test_dir "non_ts_sum")
    run ts_summary "$non_ts"
    [ "$status" -ne 0 ]
    cleanup_test_dir "$non_ts"
}
