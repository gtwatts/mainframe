# MAINFRAME AI-Native Runtime Expansion - Master Plan

> Generated: 2026-01-28 by Watson Council + GLM Build Teams
> **Status: COMPLETED** - All 3 phases implemented

## Executive Summary

This document captures the comprehensive expansion plan for transforming MAINFRAME from a function library into a complete AI-native runtime with LSP support.

### Build Results

| Phase | Component | File | Lines | Status |
|-------|-----------|------|-------|--------|
| 1 | USOP v3.0 | lib/output.sh (extended) | +200 | ✅ Complete |
| 1 | Runtime Introspection | lib/introspect.sh | 336 | ✅ Complete |
| 1 | State Persistence | lib/state.sh | 456 | ✅ Complete |
| 2 | Event/Hook System | lib/events.sh | 346 | ✅ Complete |
| 2 | Testing/Mocking | lib/testing.sh | 505 | ✅ Complete |
| 2 | MCP Server | mcp/*.py | 292 | ✅ Complete |
| 3 | Execution Sandboxing | lib/sandbox.sh | 410 | ✅ Complete |
| 3 | Task Graphs | lib/taskgraph.sh | 356 | ✅ Complete |
| 3 | Bash LSP | lsp/*.ts | 147 | ✅ Scaffold |

**Total: ~2,848 lines of new code**

## Current State (v5.0)

| Component | Status | Location |
|-----------|--------|----------|
| **2,000+ Functions** | Production | lib/*.sh (77 libraries) |
| **USOP v2** | Production | lib/output.sh (1,676 lines) |
| **Task State** | Production | lib/taskstate.sh (1,386 lines) |
| **Agent Safety** | Production | lib/agent_safety.sh (991 lines) |
| **Agent Comm** | Production | lib/agent.sh (1,613 lines) |
| **Workflow/DAG** | Production | lib/workflow.sh |
| **Meta/Introspection** | Production | lib/meta.sh (595 lines) |
| **FUNCTIONS.json** | Production | 1,546 functions documented |

## Gap Analysis (POST-BUILD)

| Proposed | Implementation | Status |
|----------|----------------|--------|
| USOP Enhancement | lib/output.sh - usop_result, usop_progress, usop_error_* | ✅ FILLED |
| Runtime Introspection | lib/introspect.sh - mainframe_describe, mainframe_search | ✅ FILLED |
| State Persistence | lib/state.sh - state_set, state_get, state_checkpoint | ✅ FILLED |
| MCP Server | mcp/server.py - Python MCP SDK server | ✅ FILLED |
| Execution Sandboxing | lib/sandbox.sh - sandbox_enable, sandbox_exec | ✅ FILLED |
| Task Graphs | lib/taskgraph.sh - task_define, task_run_graph | ✅ FILLED |
| Testing/Mocking | lib/testing.sh - mock_function, assert_* | ✅ FILLED |
| Event/Hook System | lib/events.sh - hook_on, event_emit | ✅ FILLED |
| Bash LSP | lsp/src/index.ts - TypeScript LSP scaffold | ✅ SCAFFOLD |

## Build Phases

### Phase 1: Foundation (Weeks 1-2)
1. **USOP Enhancement** - Extend output.sh with usop::* namespace
2. **Runtime Introspection** - Add mainframe::describe/capabilities/search
3. **State Persistence** - Thin wrapper over taskstate.sh

### Phase 2: Extensibility (Weeks 3-4)
4. **Event/Hook System** - New lib/events.sh
5. **Testing/Mocking** - New lib/testing.sh
6. **MCP Server** - Python server in mcp/

### Phase 3: Advanced (Weeks 5-8)
7. **Execution Sandboxing** - Extend agent_safety.sh
8. **Task Graphs** - Namespace workflow.sh
9. **Bash LSP** - TypeScript extension

## Dependency Graph

```
                                  +--------------+
                                  |   Bash LSP   |
                                  |   (Phase 3)  |
                                  +------+-------+
                                         |
                                         | uses
                                         v
+------------------+             +----------------+
|  MCP Server      |<------------|  FUNCTIONS.json|
|  (Phase 2)       |             |  (existing)    |
+--------+---------+             +----------------+
         |
         | exposes
         v
+--------+---------+             +----------------+
| Runtime          |------------>| meta.sh        |
| Introspection    |   extends   | (existing)     |
+--------+---------+             +----------------+
         ^
         |
         | depends on
         |
+--------+---------+             +----------------+
| USOP Enhancement |------------>| output.sh      |
| (Phase 1)        |   extends   | (existing)     |
+------------------+             +----------------+
```

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| MCP Server language choice | HIGH | TypeScript/Python recommended |
| Bash LSP maintenance | HIGH | Extend existing bash-lsp |
| Sandbox security | HIGH | Use namespaces/cgroups |
| USOP backward compat | MEDIUM | Version envelope format |

## Estimated Effort

| Phase | Duration | Components |
|-------|----------|------------|
| Phase 1 | 2-3 weeks | USOP, Introspection, State |
| Phase 2 | 3-4 weeks | Events, Testing, MCP |
| Phase 3 | 4-6 weeks | Sandbox, Task Graphs, LSP |
| **Total** | **9-13 weeks** | Full runtime |

## Design Documents

Detailed designs available for:
- [USOP Enhancement](./USOP_V3_DESIGN.md)
- [Runtime Introspection](./INTROSPECTION_DESIGN.md)
- [State Persistence](./STATE_PERSISTENCE_DESIGN.md)
- [MCP Server](./MCP_SERVER_DESIGN.md)
- [Bash LSP](./BASH_LSP_DESIGN.md)

## Next Steps

1. Review and approve designs
2. Begin Phase 1 implementation
3. Set up CI/CD for new components
4. Update ROADMAP.md with milestones
