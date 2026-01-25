#!/usr/bin/env bats
# =============================================================================
# Redirect: Symbols tests are in tests/unit/symbols.bats
# This file exists for backwards compatibility with direct test runs.
# =============================================================================

load 'test_helper'

setup() {
    source_lib "symbols"
    FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures/symbols"
}

@test "symbols library loads successfully" {
    [ -n "$_MAINFRAME_SYMBOLS_LOADED" ]
}
