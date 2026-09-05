## Problem and resulting behavior

<!-- What user problem does this solve? Describe the before/after behavior. -->

## Scope and ownership

<!-- Link the issue or work package; list the affected routes/files and dependencies. -->

## Validation

<!-- List commands actually run, results, exact commit, and relevant OS/architecture,
calling shell, Bash runtime, and agent versions. Explain failed, skipped, or
unavailable checks. Documentation changes need links and claims checked. -->

## Agent and user impact

<!-- For behavior changes: show valid work permitted, invalid input/unsupported
routes rejected, and error/recovery behavior. Note false blocks or overhead.
Distinguish source tests, installed CLI, live host invocation, hook enforcement,
and release evidence. Mark sections not applicable rather than inventing proof. -->

## Compatibility and recovery

<!-- Any API, state, dependency, configuration, or support-cell change?
How can a user recover or revert? Do not put secrets or private audit data here. -->

## Review checklist

- [ ] The change has one bounded purpose and follows CONTRIBUTING.md
- [ ] Claims match the evidence above; untested cells and limitations are explicit
- [ ] Relevant tests/docs are updated, or not-applicable sections are explained
- [ ] New public exports follow MAINFRAME_<MODULE>_EXPORTS and API compatibility rules (if applicable)
- [ ] No permissive fallback or implied approval was added (if applicable)
- [ ] I understand the submitted diff and can reproduce its checks, including AI-assisted work

<!-- A PR does not authorize merge, release, deployment, or external outreach.
Report vulnerabilities through SECURITY.md, not this public template. -->
