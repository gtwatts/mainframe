# Security Hardening Review: Mainframe Release Authority

## Evidence Basis

This review is bound to the three-file source collection recorded in
[context.md](context.md). I inspected the current build, attestation, and
publication paths and the focused contract tests. The artifact mechanics are
substantially stronger than the public release boundary: the wheel, source
distribution, runtime-pair manifest, runtime archive, Pi receipts, and native
evidence now have exact byte and provenance checks. The remaining structural
question is which workflow is allowed to turn those verified bytes into a
signature and an immutable public release.

The current files are uncommitted and no hosted tagged run has exercised them,
so this is a design recommendation rather than release evidence.

## Constraints

We assume a balanced change profile. We must preserve the exact 16 candidate
assets and add one durable, versioned release-authorization receipt, retain
rerun-safe verification of an existing immutable release, protected human
approval, tag-object and peeled-commit identity, and the current four-subject
native evidence predicate. We must not execute candidate bytes,
tag-controlled scripts, or downloaded repository code in a job that holds
signing or publication authority. Changes under `.github/**` and `tests/**`
must remain outside the runtime archive so the installed candidate digest does
not move solely for this control-plane migration.

## Opportunity Portfolio

| Opportunity | Evidence | Options | Recommendation | Proposal |
| --- | --- | --- | --- | --- |
| Separate release authority from candidate code | Privileged tag-workflow publisher and indistinguishable signer authority (`E001`); strong artifact mechanics (`E002`, `E003`); GitHub default-branch, run-attempt, approval, and identity controls (`E004`-`E009`) | 1. Local guards; 2. Default-branch signer and publisher; 3. External controller | Option 2 under the current single-repository constraints | [Split release authority](proposals/split-release-authority.md) |

## Recommendation Summary

I recommend Option 2: keep all build, test, and semantic certification in an
unprivileged candidate workflow, then cross an exact packet and canonical
signing request into two default-branch `workflow_run` workflows. The first
creates a durable authorization receipt and supplies a certificate-distinct
signer identity; the second is checkout-free, protected by the release
environment, and owns the only `contents: write` permission. It independently
validates the receipt, exact packet, attestations, tag identity, and draft
bytes before publication. The resulting public inventory is the 16 tested
candidate assets plus that authorization receipt.

This is the smallest option that removes both observed authority overlaps
without introducing a second repository or service. Option 1 preserves the
problem even if we add more checks. Option 3 becomes preferable if independent
organizational ownership or a separate release service is required.

## Next Decisions

- Select Option 2 before implementation work begins, or choose Option 3 if
  repository-level separation is a requirement.
- Confirm that the signer will issue one release-authorization statement over
  the exact 16 candidate assets plus the authorization receipt, while retaining
  specialized statements only where their narrower semantics remain truthful.
- Confirm that the protected `mainframe-release` environment will govern only
  the checkout-free publisher job.
- Confirm that immutable-release policy checking remains a separately scoped
  policy prerequisite instead of broadening the publisher's `GITHUB_TOKEN`.
- Keep public claims narrow until a tagged hosted run exercises the new signer
  and publisher and the resulting release is independently verified.
