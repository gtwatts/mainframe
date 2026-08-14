# Installed-candidate AWM handoff conformance

Status: candidate mechanism evidence only. No agent, provider, Pi, or Ollama
session is started, and no agent benefit is measured.

This is installed-candidate AWM handoff mechanism-conformance evidence only; it does not measure MAINFRAME benefit, agent quality, developer productivity, or real provider inference.

This protocol answers one bounded question: can the exact authenticated files
from a release archive, after extraction into an owner-private staging layout,
carry one deterministic investigation fact through the staged project-scoped
AWM CLI and four fresh login shells into the same bounded neutral continuation
that a native handoff supplies?

Its only claim scope is:

```text
installed-candidate-awm-handoff-mechanism-conformance-only
```

## What runs

The explicit `run` action:

1. verifies the separately supplied archive and checksum bytes;
2. safely extracts the archive into a new owner-private staging home, validates
   the authenticated release files, and creates a closed local staging receipt
   and shell profile without executing the public installer;
3. runs the checked-in deterministic fake transport once to produce one shared
   investigation continuation;
4. constructs the control as a native bounded continuation;
5. invokes the installed `mainframe` CLI in exactly four distinct fresh login
   shells, in the ordered operations `ensure`, `checkpoint`, `discovery`, and
   `handoff`, and requires every operation to report the same actual Bash 4.4+
   runtime selected through the isolated profile's `MAINFRAME_BASH` binding;
   before execution it rejects Rosetta, rejects group- or other-writable
   executable files, and requires both bound executable images to contain the
   advertised native Mach-O or ELF architecture, then requires their exact
   bindings to remain unchanged after the shell sequence;
6. projects the exported AWM handoff into the same neutral-continuation
   contract and requires the control and treatment envelopes to be byte equal;
7. runs the same deterministic implementation transport once per arm and the
   same hidden deterministic grader once per arm; and
8. emits private reproduction input plus a path-free public certificate only
   if both arms score 100/100, all four grader cases pass in both arms, the
   score delta is zero, and the final workspace trees are identical.

The public candidate status for this boundary is
`authenticated-release-files-private-staging`; it deliberately does not claim
that the public installer or host activation path ran.

The nine measured top-level process-group leaders started directly by the
certifier are four login shells, three deterministic fake-transport processes,
and two grader processes. Descendant utilities within those process groups are
not counted, and extraction and local installation bookkeeping are outside that
measured count. No host integration is activated.

The `verify` action is offline and read-only. It starts no subprocess, rewrites
no artifact, recomputes every bound file and tree identity, reconstructs the
public projection from the archive, checksum, and private record, and requires
an exact canonical match.

## Run and verify

Use outputs outside the repository. Both output paths must be absent, and the
private directory and record must remain owner-private.

```bash
project_root=$(pwd -P)
version=$(tr -d '[:space:]' < "$project_root/VERSION")
archive="$project_root/dist/mainframe-$version.tar.gz"
checksum="$archive.sha256"
private_root=$(mktemp -d "${TMPDIR:-/tmp}/mainframe-installed-awm.XXXXXX")
private_root=$(cd -P -- "$private_root" && pwd -P)
chmod 700 "$private_root"

python3 -I -S -B "$project_root/scripts/dev/certify-installed-awm-handoff.py" run \
  --archive "$archive" \
  --checksum "$checksum" \
  --shell bash \
  --private-output "$private_root/private.json" \
  --output "$private_root/public.json"

python3 -I -S -B "$project_root/scripts/dev/certify-installed-awm-handoff.py" verify \
  --archive "$archive" \
  --checksum "$checksum" \
  --shell bash \
  --private-evidence "$private_root/private.json" \
  --evidence "$private_root/public.json"
```

Select `zsh` instead of `bash` to certify that login-shell route. The selected
shell name, executable digest, version, profile discovery, four-shell count,
and distinct process identities are bound into the evidence. The private
record binds the selected-shell and runtime-Bash executable bytes admitted
before the four operations and revalidated after them, together with the
versions observed from the operations; the public projection retains those
SHA-256 digests and versions without exposing paths. In a Bash cell the
selected login shell and runtime Bash identities must match. In a zsh cell they
remain distinct roles and both are independently bound. Native admission is
derived from those digest-bound executable images plus an in-process Darwin
translation check; a Rosetta process cannot produce a native Darwin
certificate. Portable pathname launch does not establish execution-time byte
identity against a concurrent writer under the same local account, which is
outside this certificate's claim boundary.

The closed contracts are:

- `evals/agent-impact/installed-awm-handoff-private.schema.json`; and
- `evals/agent-impact/installed-awm-handoff-evidence.schema.json`.

The private record contains absolute paths, raw continuation and handoff bytes,
AWM state identities, process output, and per-arm task artifacts. Do not upload,
publish, or commit it. The public evidence contains digests and fixed
mechanism/parity assertions only; it contains no paths, prompts, continuation
text, handoff text, process output, credentials, opaque randomized arm IDs, or
hidden assignment records. Its reviewed mechanism labels (`control` and
`treatment`) are intentionally public and are not randomized assignments.

## Cross-platform acceptance

Complete candidate conformance requires one public certificate for each of six
native cells:

| Platform tuple | Shells |
|---|---|
| `Darwin-arm64-none` | Bash and zsh |
| `Darwin-x86_64-none` | Bash and zsh |
| `Linux-x86_64-glibc` | Bash and zsh |

All six certificates must bind the same release-archive SHA-256. Every cell
must independently establish:

- non-translated native execution and selected-shell/runtime-Bash executable
  images that contain the advertised platform architecture;
- authenticated release files in owner-private staging and a verified local
  staging receipt;
- four ordered, distinct fresh login-shell processes that discover the
  installed candidate through its profile;
- one exact Bash 4.4+ runtime executable and version, observed identically in
  all four installed CLI operations (and equal to the selected shell identity
  in a Bash cell);
- real installed MAINFRAME and project-scoped AWM execution;
- exactly one occurrence of the deterministic source fact in each arm;
- byte-equal neutral envelopes within the fixed 4096-byte ceiling;
- equal initial workspaces, unchanged investigation workspaces, unchanged
  installed payload bytes, and byte-equal final workspace trees;
- 100/100 in both arms, four of four grader cases in both arms, and a zero-delta
  tie; and
- no poison-path sentinel invocation.

The certificate records zero only for operations issued or sessions started by
the certifier: live-agent sessions, provider sessions and requests, Pi sessions,
Ollama sessions, and network API calls. It does not inspect the machine process table,
observe unrelated processes, or install an operating-system network sandbox.

## Evidence boundary

A passing certificate shows that the exact installed candidate's AWM handoff
path preserves one known bounded fact across fresh shell processes and presents
the deterministic implementation with the same neutral continuation as the
control. The deliberate 100/100 tie is a parity vector. A treatment win would
be a protocol failure, not evidence of impact.

The certificate does not establish real-provider inference, agent quality,
developer productivity, comparative agent performance, host runtime trust,
network containment, isolation from another process already running under the
same local account, generalization, adoption, or MAINFRAME benefit. A same-user
peer can race portable filesystem operations and is outside this trusted local
certifier boundary. Those claims require a separately approved real-agent
evaluation or an observed user case study. This mechanism certificate is not
eligible evidence under the current live-study preregistration and does not authorize a provider run.
