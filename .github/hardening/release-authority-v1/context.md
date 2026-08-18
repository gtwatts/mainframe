# Release Authority Hardening Context

This is local design context for the 2026-08-12 Mainframe release-authority
review. It is derived analysis, not release evidence and not proof that the
recommended design has been implemented.

## Source identity

- Local source root: `/Users/gordonwatts/Documents/Projects/mainframe`
- Git HEAD: `2724995e22a51758c55e960fcba891f9c60e5a3d`
- Source drift: `present`
- Reason: the release workflow is modified and both focused contract tests are
  untracked in the working tree.
- Evidence collection SHA-256:
  `1a52a5b428a0ddf3bd28625259cf531d32e0b8f0a701cf9cf50650ce47f0578a`

The collection digest is SHA-256 over the sorted `shasum -a 256` records for
the three local files below.

| Evidence | Local input | SHA-256 | Purpose |
| --- | --- | --- | --- |
| `E001` | `.github/workflows/test.yml` | `c71d9d7ae57999a9492bcb65e2c45238f0a5a234a7bd9f4fc644691f033c08be` | Current build, signing, and publishing authority graph |
| `E002` | `tests/release_evidence_workflow.bats` | `b240b9a250077aa2d79084a3c00c12ff81cb40482b504bd045819be04bd1c553` | Current release workflow contract and immutable-release checks |
| `E003` | `tests/mcp_package.bats` | `4624094bd0a4e0612a6b52cc2953c9253cf777405e4e8c3ed694e9d00a2a058a` | MCP artifact, pipx, and workflow trust-split acceptance |

## External platform evidence

These official GitHub documents were read on 2026-08-12. They are cited as
platform semantics, not as proof that Mainframe's proposed workflows have run.

| Evidence | Document | Relevant fact |
| --- | --- | --- |
| `E004` | [Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run) | A `workflow_run` consumer can receive secrets and write tokens even when its producer is unprivileged; its workflow file must exist on the default branch; untrusted artifacts and caches require defensive handling; chaining is limited to three levels. |
| `E005` | [OIDC with reusable workflows](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-with-reusable-workflows) and [artifact attestations with reusable workflows](https://docs.github.com/en/enterprise-cloud@latest/actions/how-tos/secure-your-work/use-artifact-attestations/increase-security-rating) | OIDC exposes the called workflow as `job_workflow_ref`, and attestation verification can restrict the exact signer workflow. |
| `E006` | [Actions artifact REST API](https://docs.github.com/en/rest/actions/artifacts) and [release REST API](https://docs.github.com/en/rest/releases/releases) | Workflow artifacts and release assets expose IDs, run/source metadata, sizes, and SHA-256 digests that a trusted consumer can bind before use. |
| `E007` | [Default workflow variables](https://docs.github.com/en/actions/reference/workflows-and-actions/variables#default-environment-variables), [workflow-run attempts REST API](https://docs.github.com/en/rest/actions/workflow-runs#get-a-workflow-run-attempt), and [upload-artifact](https://github.com/actions/upload-artifact) | A run ID survives reruns while its attempt increments; artifact metadata does not record an attempt, so exact-attempt lineage needs an attempt-qualified name plus a signed receipt rather than an artifact-name or run-ID inference. |
| `E008` | [Deployment environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments), [reviewing deployments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/review-deployments), and [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases) | Environment approval gates the publisher job, while draft-byte verification must finish before publication because asset immutability starts only after publication. A `workflow_run` publisher uses the default-branch ref, so upstream tag identity requires an independent REST and receipt check. |
| `E009` | [Repository immutable-release status](https://docs.github.com/en/enterprise-cloud@latest/rest/repos/repos#check-if-immutable-releases-are-enabled-for-a-repository) and [workflow permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions) | Immutable-release policy introspection requires Administration read, which the minimal repository-scoped publisher token does not expose. Keep that check in a separately scoped policy credential or treat it as a protected external prerequisite. |

## Current observed boundary

- `mcp-package-build` and `mcp-package-test` have read-only repository
  permissions, and the MCP candidate moves by one immutable upload artifact ID.
- `mcp-package-attestation` has OIDC and attestation write authority.
- `release-build` also has OIDC and attestation write authority while checking
  out and executing repository-controlled scripts.
- `release-publish` has `contents: write`, checks out the release commit, reads
  a protected-environment policy secret, and executes repository validators.
- The current mechanical artifact chain is strong: exact MCP candidate
  inventory, ordered digest manifest, runtime equality and binding, singleton
  attestations, exact 16 release assets, pre-publication draft verification,
  and rerun-safe immutable verification are locally contract-tested.

## Evidence limitations

- No tagged hosted run has exercised the current uncommitted workflow.
- No GitHub attestation or immutable 10.2.0 release was created in this review.
- The review does not model a malicious GitHub-hosted runner or GitHub service
  compromise.
- The repository's large unrelated dirty worktree is outside this design
  collection; only the three hashed inputs above are bound here.
