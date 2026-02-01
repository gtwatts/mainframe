# WATSON COUNCIL - Expert Review Evaluation Framework

**Version:** 1.0
**Date:** 2026-01-31
**Project:** MAINFRAME Expert Review
**Status:** ACTIVE

---

## Executive Overview

This document establishes the formal evaluation framework for the MAINFRAME Expert Review Council. The Council's role is to adjudicate competing improvement proposals from domain expert teams, ensuring that only **provably better** changes are accepted into the codebase.

### MAINFRAME Context

MAINFRAME is the AI-Native Bash Runtime with:
- **4,230+ functions** across **120 libraries**
- **6,626+ tests** (BATS framework)
- **Zero external dependencies** (pure bash 4.0+)
- **Core mission:** Make AI agent bash execution safe, accurate, and efficient

The stakes are high: MAINFRAME is used by AI agents to control computer systems. A regression here could lead to security vulnerabilities, agent failures, or data loss.

---

## Section 1: Evidence Standards

Evidence is ranked by strength. Higher-ranked evidence supersedes lower-ranked claims.

### 1.1 Evidence Hierarchy (Ranked by Strength)

| Rank | Evidence Type | Description | Required For |
|------|---------------|-------------|--------------|
| **S** | **Reproducible Benchmarks** | Automated timing/memory tests with statistical significance (p<0.05, n>=30) | Performance claims |
| **A** | **Test Results (Before/After)** | BATS tests demonstrating behavior change with passing/failing states | Correctness claims |
| **B** | **Static Analysis Metrics** | ShellCheck, complexity scores, cyclomatic complexity, line counts | Quality claims |
| **C** | **Security Analysis** | Threat model, attack vector analysis, vulnerability scan results | Security claims |
| **D** | **Expert Consensus** | Agreement among 3+ domain experts with documented rationale | Design decisions |
| **E** | **User Studies/Feedback** | Documented evidence of real-world usage patterns | Usability claims |
| **F** | **Theoretical Analysis** | Big-O complexity, proof of correctness, formal verification | Algorithmic claims |

### 1.2 Evidence Requirements by Claim Type

| Claim Type | Minimum Evidence | Preferred Evidence |
|------------|------------------|-------------------|
| "This is faster" | Rank S benchmark (30+ runs, p<0.05) | S + F (benchmark + complexity analysis) |
| "This is safer" | Rank C security analysis | C + A (security analysis + tests) |
| "This is more correct" | Rank A before/after tests | A + F (tests + proof) |
| "This is cleaner" | Rank B static analysis | B + D (metrics + expert consensus) |
| "This is more usable" | Rank E user feedback | E + D (feedback + expert consensus) |

### 1.3 Benchmark Standards

All performance benchmarks MUST:

```bash
# Minimum benchmark requirements
ITERATIONS=30          # Minimum iterations
WARMUP_RUNS=5          # Discard first N runs
CONFIDENCE_LEVEL=0.95  # 95% confidence interval
MAX_STDDEV_PERCENT=20  # Max acceptable standard deviation

# Example benchmark structure
benchmark_function() {
    local func="$1"
    local -a times=()

    # Warmup
    for ((i=0; i<WARMUP_RUNS; i++)); do
        "$func" >/dev/null 2>&1
    done

    # Timed runs
    for ((i=0; i<ITERATIONS; i++)); do
        local start=$(date +%s%N)
        "$func" >/dev/null 2>&1
        local end=$(date +%s%N)
        times+=( $((end - start)) )
    done

    # Calculate statistics
    calculate_mean_and_stddev "${times[@]}"
}
```

### 1.4 Evidence Documentation Template

All proposals MUST include:

```markdown
## Evidence Package

### Claim
[What improvement is being claimed]

### Evidence Type
[Rank from hierarchy: S/A/B/C/D/E/F]

### Methodology
[How was the evidence gathered]

### Data
[Raw results, test output, benchmark numbers]

### Reproducibility
[How can another reviewer reproduce this evidence]

### Limitations
[What does this evidence NOT prove]
```

---

## Section 2: Scoring Rubric

Each proposal is evaluated on four dimensions with weighted scores.

### 2.1 Scoring Dimensions

| Dimension | Weight | Description |
|-----------|--------|-------------|
| **Impact** | 35% | How significantly does this improve MAINFRAME? |
| **Confidence** | 30% | How certain are we that this is actually better? |
| **Risk** | 25% | How likely is a regression or unintended consequence? |
| **Cost** | 10% | How much effort to implement? |

### 2.2 Impact Score (1-10)

| Score | Criteria | Example |
|-------|----------|---------|
| 10 | Transformational: New capability, 10x improvement | AWM v2 infinite memory |
| 9 | Major: Critical security fix, 5x improvement | Eval site hardening |
| 8 | Significant: Core function improvement, 2-5x gain | json_object optimization |
| 7 | Notable: Measurable improvement to key workflow | New validation function |
| 6 | Moderate: Useful improvement, measurable gain | Performance tuning |
| 5 | Incremental: Small improvement, documented benefit | Code cleanup with tests |
| 4 | Minor: Marginal improvement, limited scope | Comment improvements |
| 3 | Trivial: Cosmetic changes, style fixes | Whitespace normalization |
| 2 | Negligible: No measurable user benefit | Internal refactoring only |
| 1 | None: No improvement demonstrated | Proposed without evidence |

### 2.3 Confidence Score (1-10)

| Score | Criteria | Evidence Required |
|-------|----------|-------------------|
| 10 | Proven: Multiple Rank S/A evidence sources | Benchmarks + Tests + Expert consensus |
| 9 | Strong: Rank S or A evidence with replication | Benchmark reproduced by reviewer |
| 8 | Good: Rank A/B evidence, well-documented | Passing tests, static analysis |
| 7 | Solid: Rank B/C evidence, reasonable coverage | Metrics and security review |
| 6 | Moderate: Rank C/D evidence, some gaps | Expert consensus, partial tests |
| 5 | Fair: Rank D/E evidence, acknowledged limitations | Expert opinion, user feedback |
| 4 | Limited: Rank E/F evidence only | User study or theoretical only |
| 3 | Weak: Claims exceed evidence | Some support but gaps |
| 2 | Minimal: Little supporting evidence | Single data point |
| 1 | None: No evidence provided | Claims without support |

### 2.4 Risk Score (1-10) - INVERTED (1=high risk, 10=low risk)

| Score | Risk Level | Indicators |
|-------|------------|------------|
| 10 | Minimal | Additive only, no existing code changed, full test coverage |
| 9 | Very Low | New function, isolated scope, no API changes |
| 8 | Low | Modifies non-critical code, has rollback plan |
| 7 | Moderate-Low | Touches multiple files, all tests passing |
| 6 | Moderate | API signature changes, requires migration |
| 5 | Moderate-High | Core function changes, performance-sensitive |
| 4 | High | Security-relevant code, audit required |
| 3 | Very High | Breaking changes, affects downstream users |
| 2 | Critical | Modifies AWM/agent safety, extensive testing needed |
| 1 | Extreme | Removes/replaces core functionality, potential data loss |

### 2.5 Implementation Cost

| Cost | Effort | Timeline | Example |
|------|--------|----------|---------|
| **XS** | < 1 hour | Same day | Bug fix, typo, config change |
| **S** | 1-4 hours | 1-2 days | New utility function, test addition |
| **M** | 4-16 hours | 1 week | New library, feature enhancement |
| **L** | 16-40 hours | 2-3 weeks | Major feature, refactoring |
| **XL** | 40+ hours | 1+ months | Architecture change, new subsystem |

### 2.6 Final Score Calculation

```
Final Score = (Impact * 0.35) + (Confidence * 0.30) + (Risk * 0.25) + (Cost_normalized * 0.10)

Cost_normalized:
  XS = 10
  S  = 8
  M  = 6
  L  = 4
  XL = 2

Passing threshold: >= 6.0
High priority: >= 7.5
Fast-track: >= 8.5 AND Risk >= 8
```

---

## Section 3: Veto Criteria

The following conditions automatically disqualify a proposal:

### 3.1 Automatic Veto (Non-Negotiable)

| # | Condition | Reason |
|---|-----------|--------|
| V1 | **Introduces `eval` without security review** | Command injection risk |
| V2 | **Removes existing tests without replacement** | Regression risk |
| V3 | **Breaks backward compatibility without migration path** | Downstream breakage |
| V4 | **Adds external runtime dependency** | Violates zero-dependency principle |
| V5 | **Fails ShellCheck with critical errors** | Basic quality gate |
| V6 | **No evidence provided for claims** | Cannot be evaluated |
| V7 | **Conflicts with active security audit** | Timing risk |
| V8 | **Modifies AWM data format without migration** | Data loss risk |

### 3.2 Conditional Veto (Require Remediation)

| # | Condition | Remediation Required |
|---|-----------|---------------------|
| C1 | Evidence quality < Rank D | Provide stronger evidence |
| C2 | Confidence score < 4 | Additional testing/review |
| C3 | Risk score < 4 | Security review and mitigation plan |
| C4 | No test coverage for new code | Add BATS tests |
| C5 | Modifies public API | Document migration path |
| C6 | Touches security-critical code | security-reviewer sign-off |

### 3.3 Veto Override Process

A veto MAY be overridden with:
1. **Unanimous Council vote** (all reviewers agree)
2. **Project Owner approval** (Gordon explicit approval)
3. **Documented risk acceptance** (written acknowledgment of risks)
4. **Time-bounded exception** (must be remediated within 30 days)

---

## Section 4: Integration Coherence

Changes must work together. The Council evaluates proposals holistically.

### 4.1 Coherence Dimensions

| Dimension | Evaluation Criteria |
|-----------|---------------------|
| **API Consistency** | Does the proposal match existing function naming, argument patterns, return conventions? |
| **Architectural Fit** | Does it align with MAINFRAME's layered design (core/data/agent/ui)? |
| **Performance Budget** | Does it impact startup time, memory footprint, or hot paths? |
| **Security Posture** | Does it maintain or improve the security model? |
| **Test Strategy** | Does it follow established testing patterns? |
| **Documentation** | Is CHEATSHEET.md updated? Are examples provided? |

### 4.2 Conflict Resolution

When proposals conflict:

1. **Identify conflict type:**
   - Resource conflict (same code area)
   - Design conflict (incompatible approaches)
   - Priority conflict (competing for review time)

2. **Resolution precedence:**
   - Security fixes > All other changes
   - Bug fixes > New features
   - Higher Final Score wins
   - Earlier submission wins (if scores equal)

3. **Merge strategies:**
   - Sequential: Merge one, rebase other
   - Composite: Extract best elements of each
   - Defer: Hold proposal for next cycle

### 4.3 Cross-Library Impact Assessment

For proposals affecting multiple libraries:

```markdown
## Cross-Library Impact

### Libraries Modified
- lib/json.sh (primary)
- lib/output.sh (secondary)
- lib/csv.sh (affected)

### Dependency Graph
json.sh -> output.sh -> csv.sh

### Regression Testing
- [ ] json.bats (direct)
- [ ] output.bats (dependent)
- [ ] csv.bats (transitive)

### Integration Points
- USOP envelope format
- Error code compatibility
- AWM serialization
```

---

## Section 5: Review Process Timeline

### 5.1 Standard Review Cycle (14 Days)

| Phase | Duration | Activities |
|-------|----------|------------|
| **Submission** | Day 0 | Proposal submitted with evidence package |
| **Triage** | Days 1-2 | Council assigns reviewers, checks completeness |
| **Expert Review** | Days 3-7 | Domain experts evaluate claims |
| **Evidence Verification** | Days 8-10 | Reproducibility check |
| **Scoring** | Days 11-12 | Independent scoring by reviewers |
| **Council Decision** | Day 13 | Consensus meeting, final vote |
| **Notification** | Day 14 | Results communicated |

### 5.2 Fast-Track Process (4 Days)

For proposals scoring >= 8.5 with Risk >= 8:

| Phase | Duration |
|-------|----------|
| Submission + Triage | Day 0-1 |
| Expert Review + Scoring | Days 2-3 |
| Council Decision | Day 4 |

### 5.3 Emergency Process (12 Hours)

For critical security fixes:

| Phase | Duration |
|-------|----------|
| Submission | Hour 0 |
| Security Review | Hours 1-4 |
| Council Decision | Hours 4-6 |
| Deployment | Hours 6-12 |

---

## Section 6: Reviewer Responsibilities

### 6.1 Council Composition

| Role | Responsibility | Required Expertise |
|------|----------------|-------------------|
| **Council Chair** | Facilitates decisions, resolves ties | MAINFRAME architecture |
| **Security Reviewer** | Evaluates security implications | Security audit experience |
| **Performance Reviewer** | Validates benchmarks | Bash optimization |
| **Quality Reviewer** | Checks testing, docs | Testing methodology |
| **Integration Reviewer** | Assesses cross-library impact | Full codebase knowledge |

### 6.2 Conflict of Interest

Reviewers MUST recuse themselves if:
- They authored the proposal
- They have a competing proposal in the same area
- They have a personal relationship with the author

### 6.3 Review Checklist

Each reviewer completes:

```markdown
## Reviewer Checklist: [Proposal ID]

### Completeness
- [ ] Evidence package provided
- [ ] Claim clearly stated
- [ ] Reproducibility instructions included

### Evidence Verification
- [ ] Benchmarks reproduced (if applicable)
- [ ] Tests executed locally
- [ ] Static analysis verified

### Scoring
- Impact: [1-10] - Rationale: ___
- Confidence: [1-10] - Rationale: ___
- Risk: [1-10] - Rationale: ___
- Cost: [XS/S/M/L/XL] - Rationale: ___

### Veto Check
- [ ] No automatic veto conditions
- [ ] No unresolved conditional vetoes

### Recommendation
[ ] APPROVE / [ ] REVISE / [ ] REJECT

### Comments
___
```

---

## Section 7: Decision Recording

All Council decisions are recorded in Architecture Decision Records (ADRs).

### 7.1 ADR Template

```markdown
# ADR-XXX: [Decision Title]

## Status
[PROPOSED | ACCEPTED | REJECTED | SUPERSEDED]

## Date
YYYY-MM-DD

## Context
[Why this decision was needed]

## Proposal
[What was proposed]

## Evidence Summary
| Type | Score | Key Finding |
|------|-------|-------------|
| ... | ... | ... |

## Scoring
| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Impact | X/10 | ... |
| Confidence | X/10 | ... |
| Risk | X/10 | ... |
| Cost | XS-XL | ... |
| **Final** | X.X | |

## Decision
[ACCEPT / REJECT / DEFER]

## Rationale
[Why this decision was made]

## Consequences
### Positive
- ...

### Negative
- ...

### Risks
- ...

## Implementation Notes
[If accepted, how to implement]

## Review Team
| Reviewer | Vote | Comments |
|----------|------|----------|
| ... | ... | ... |
```

---

## Section 8: Appeals Process

### 8.1 Grounds for Appeal

Appeals are permitted when:
1. **New evidence** not available during initial review
2. **Procedural error** in the review process
3. **Changed context** (new requirements, priorities)
4. **Clarification** of misunderstood proposal

### 8.2 Appeal Procedure

1. Submit written appeal within 7 days of decision
2. Include new evidence or rationale
3. Different reviewer assigned (not original)
4. Appeal decision is final

---

## Appendix A: MAINFRAME-Specific Guidelines

### A.1 Function Naming Evaluation

Functions MUST follow established patterns:

| Pattern | Example | Evaluation |
|---------|---------|------------|
| `verb_noun` | `trim_string`, `parse_json` | Preferred |
| `module_action` | `json_object`, `awm_checkpoint` | Preferred for modules |
| `is_*`, `has_*` | `is_empty`, `has_key` | Boolean functions |
| `ensure_*` | `ensure_dir`, `ensure_file` | Idempotent operations |
| `_private_*` | `_json_escape` | Internal functions |

### A.2 Performance Baseline

New functions are compared against established baselines:

| Category | Baseline | Acceptable Overhead |
|----------|----------|---------------------|
| String operations | 1ms per 1K chars | < 2x baseline |
| Array operations | 1ms per 100 elements | < 2x baseline |
| JSON generation | 5ms per 100 fields | < 2x baseline |
| File operations | 10ms per file | < 1.5x baseline |
| Network operations | 100ms + RTT | < 1.2x overhead |

### A.3 Security-Critical Areas

Proposals involving these areas require security-reviewer sign-off:

| Library | Reason |
|---------|--------|
| `lib/agent_safety.sh` | Agent execution controls |
| `lib/awm*.sh` | Agent Working Memory (persistent state) |
| `lib/validation.sh` | Input validation and sanitization |
| `lib/capability.sh` | Capability-based security model |
| `lib/secrets.sh` | Secret management |
| `lib/sandbox.sh` | Execution sandboxing |
| Any use of `eval`, `source`, or dynamic execution | Command injection risk |

### A.4 Test Coverage Requirements

| Code Type | Minimum Coverage | Test Types Required |
|-----------|------------------|---------------------|
| New functions | 80% | Unit tests (BATS) |
| Bug fixes | 100% of fix | Regression test |
| Security code | 90% | Unit + Security tests |
| Performance code | 70% | Unit + Benchmark |
| AWM/Agent code | 85% | Unit + Integration |

### A.5 Documentation Requirements

| Change Type | Documentation Required |
|-------------|------------------------|
| New public function | CHEATSHEET.md entry with signature, example, output |
| API change | Migration guide, deprecation notice |
| New library | README section, usage examples |
| Security change | SECURITY.md update, threat model |
| Breaking change | CHANGELOG.md, version bump |

---

## Appendix B: Quick Reference Card

### Evidence Quick Lookup
```
S = Benchmarks (timing/memory, n>=30, p<0.05)
A = Tests (BATS before/after)
B = Static Analysis (ShellCheck, complexity)
C = Security Analysis (threat model)
D = Expert Consensus (3+ experts)
E = User Studies
F = Theoretical Analysis
```

### Scoring Formula
```
Final = Impact(35%) + Confidence(30%) + Risk(25%) + Cost(10%)

Passing: >= 6.0
Priority: >= 7.5
Fast-track: >= 8.5 AND Risk >= 8
```

### Veto Quick Check
```
AUTOMATIC VETO (V1-V8):
[ ] V1: Uses eval without security review
[ ] V2: Removes tests without replacement
[ ] V3: Breaks backward compatibility
[ ] V4: Adds external dependency
[ ] V5: Fails ShellCheck critical
[ ] V6: No evidence provided
[ ] V7: Conflicts with security audit
[ ] V8: AWM format change without migration

CONDITIONAL VETO (C1-C6):
[ ] C1: Evidence quality < Rank D
[ ] C2: Confidence score < 4
[ ] C3: Risk score < 4
[ ] C4: No test coverage for new code
[ ] C5: Modifies public API without migration
[ ] C6: Security-critical code without sign-off
```

### Timeline Quick Reference
```
Standard Review:  14 days (full cycle)
Fast-Track:        4 days (score >= 8.5, risk >= 8)
Emergency:        12 hours (critical security)
```

### Cost Normalization
```
XS (<1hr)    = 10 points
S  (1-4hr)   =  8 points
M  (4-16hr)  =  6 points
L  (16-40hr) =  4 points
XL (40+hr)   =  2 points
```

---

## Appendix C: Proposal Submission Template

```markdown
# Proposal: [Title]

## Metadata
- **Author:** [Name]
- **Date:** YYYY-MM-DD
- **Category:** [Performance | Security | Feature | Bug Fix | Refactor]
- **Libraries Affected:** [list]

## Summary
[One paragraph describing the change]

## Motivation
[Why is this change needed?]

## Proposed Change
[Detailed description of what will change]

## Evidence Package

### Claim
[What improvement is being claimed]

### Evidence Type
[Rank: S/A/B/C/D/E/F]

### Methodology
[How evidence was gathered]

### Data
[Raw results]

### Reproducibility
[Steps to reproduce]

## Risk Assessment
- [ ] Modifies existing code: Yes/No
- [ ] Changes public API: Yes/No
- [ ] Affects security-critical code: Yes/No
- [ ] Has rollback plan: Yes/No

## Test Plan
[What tests will be added/modified]

## Documentation Updates
[What docs will be updated]

## Checklist
- [ ] Evidence package complete
- [ ] Tests written
- [ ] ShellCheck passes
- [ ] Documentation updated
- [ ] No automatic veto conditions
```

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-31 | WATSON Council | Initial framework |

---

*WATSON COUNCIL - MAINFRAME Expert Review Framework v1.0*
*"Mainframe can make a computer do anything short of tap dance."*
