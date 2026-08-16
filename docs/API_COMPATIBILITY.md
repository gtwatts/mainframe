# MAINFRAME Public API Compatibility

This document defines how MAINFRAME names, owns, aliases, deprecates, and
removes public Bash functions. Its purpose is to keep a function's behavior
stable regardless of which supported loader path a caller uses.

The compatibility contract applies to functions reached through
`lib/common.sh`, the `mainframe` CLI, and the maintained language bindings.
Directly sourcing an individual library is covered only when that library's
documentation identifies it as a supported entry point.

## Canonical ownership

Every public function name must have exactly one canonical defining library.
Two libraries must not define the same public name and rely on source order to
choose the implementation.

For an existing collision, the implementation reached through the documented
default `source lib/common.sh` path is the compatibility baseline unless tests
and published documentation establish a different contract. Alternate
implementations receive distinct, module-prefixed names.

The following supported loading modes must resolve an available public name to
the same canonical behavior:

- the default `source lib/common.sh` path;
- `MAINFRAME_LIBS` and `MAINFRAME_PROFILE` selective loading;
- lazy loading; and
- `mainframe_load` or `mainframe_load_all` after common has been sourced.

A loading mode may intentionally expose a smaller surface, but it must not
silently change the meaning or signature of a function it does expose.

## Naming and prefixes

Public function names use lowercase words separated by underscores.
Library-specific functions use a module prefix, such as `json_object`,
`collection_join`, or `awm_checkpoint`.

Short, unprefixed names are reserved for established core primitives. Adding a
new unprefixed name requires checking the complete public registry and all
loader modes for collisions.

Do not introduce a new `namespace::function` canonical API until registry,
quick-reference, lazy-loading, completion, CLI, and binding support for that
form is consistent. Use the underscore form for new cross-surface APIs.

## Resolving call-shape collisions

When two historical functions share a name but accept different arguments:

1. Keep one canonical owner for the historical name.
2. Give each alternate behavior an explicit module-prefixed name.
3. Preserve both call shapes under the historical name only when they are
   unambiguous and can be dispatched deterministically.

A dispatcher must not guess between overlapping signatures. It must preserve
quoting, stdout, stderr, and exit status, and it must have regression coverage
for every supported call shape. When reliable dispatch is impossible, retain
the documented default behavior and provide a named migration path to the
alternate function.

## Compatibility aliases and warnings

A deprecated name remains an explicit wrapper around its canonical
replacement. The wrapper forwards arguments with `"$@"` and preserves the
replacement's output and exit status.

New and migrated wrappers use `MAINFRAME_COMPAT_WARNINGS` as the common warning
control:

- unset or `1`: emit one warning per deprecated symbol per shell;
- `0`: suppress compatibility warnings.

Warnings go to stderr and name both the deprecated symbol and its replacement.
Calling the canonical function never emits a compatibility warning. Older
module-specific controls may remain during migration, but new controls must not
fragment the warning policy further.

Example wrapper:

```bash
# @since: 10.2.0
# @deprecated: Use collection_join
# @alias-for: collection_join
# @remove: 12.0.0
old_collection_join() {
    mainframe_deprecated \
        "old_collection_join" \
        "collection_join" \
        "12.0.0"
    collection_join "$@"
}
```

The deprecation helper must validate symbol names before using dynamic Bash
features. Compatibility code does not receive an exception from MAINFRAME's
normal input-validation and ShellCheck requirements.

## Deprecation and removal floor

A deprecated public function may be removed only after both conditions are
met:

1. The deprecation has shipped in at least two documented releases after the
   release that introduced the warning and migration guidance.
2. Removal occurs no earlier than the next major release.

The removal version is a floor, not a promise to remove the function. If the
migration is still risky or poorly documented, retain the alias longer.

Every deprecation must appear in the changelog and migration documentation with
the old name, canonical replacement, behavior differences, deprecation
version, and earliest removal version.

## Source annotations

Public functions should use structured source annotations so generated and
runtime discovery can describe the same API:

```bash
# @description: Join a named collection with a separator
# @since: 10.2.0
collection_join() {
    # ...
}
```

Deprecated aliases additionally use:

```bash
# @deprecated: Use collection_join
# @alias-for: collection_join
# @remove: 12.0.0
```

`@deprecated` explains the migration in user-facing language. `@alias-for`
contains the exact canonical symbol. `@remove` records the earliest eligible
major version and remains subject to the two-release floor.

Registry generators, CLI help, search, completion, and quick-reference tooling
should consume the same metadata. A parser that cannot represent an annotation
must not silently invent conflicting ownership.

## Export arrays and child-shell export

The standardized module export array is named
`MAINFRAME_<MODULE>_EXPORTS`. It declares the source-level public API for that
module and is used for documentation and validation.

Membership in this array does not automatically mean a function should be
exported into child Bash processes. `export -f` changes the process environment
and is required only when subprocess availability is an intentional, tested
part of the API. Modules that require child-shell propagation should declare
that surface separately rather than using source-level visibility and
subprocess export as synonyms.

Legacy export-array names may remain while modules are migrated, but new
modules and newly standardized modules use the `MAINFRAME_<MODULE>_EXPORTS`
form. Export arrays must contain canonical functions and retained public
aliases; they must not list a second implementation under a colliding name.

## Collision ratchet

The public API collision count may only decrease.

- A change must not introduce a new public function-name collision.
- An existing collision may remain temporarily only when recorded in the
  repository's collision baseline with its competing owners and intended
  canonical owner.
- A resolved collision is removed from that baseline and must never be added
  back without an explicitly reviewed breaking-change decision.
- CI should fail when the current collision set exceeds or differs from the
  approved baseline, when a canonical owner changes across loader modes, or
  when registry metadata reports more than one canonical owner.

Aliases do not count as permission to define the same function name in two
libraries. An alias has its own old name, one definition, and one canonical
replacement.

## Required migration evidence

A public-name change is complete only when it includes:

- behavior tests for the canonical function;
- alias parity tests for stdout and exit status;
- warning tests covering once-per-shell behavior and
  `MAINFRAME_COMPAT_WARNINGS=0`;
- loader-matrix coverage showing stable canonical ownership;
- registry and CLI help/search coverage; and
- user-facing migration and changelog entries.
