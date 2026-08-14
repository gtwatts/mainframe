# Offline agent mechanism evidence

This protocol answers one bounded question: for the checked-in synthetic
command strings, what does the exact `agent_gate_classify` source return at the
fixed `high` block tier?

It does **not** show that an agent is better, safer overall, more correct, or
more productive. It does not run a model provider, a live agent session, the
fixture commands, an operating-system sandbox, or the command-execution gate.
Classification is one safety mechanism; it is not proof of containment or
end-to-end prevention.

In this protocol, `low` is a lexical no-match label: none of the canonical
ordered patterns matched after bounded command normalization. It is not a
claim that executing the command, an invoked script, or any downstream effect
would be safe or authorized.

## Build from the current source

Choose a new output path; the builder intentionally refuses to overwrite an
existing artifact.

```bash
python3 scripts/dev/offline-impact/build-evidence.py \
  --source-root . \
  --output /tmp/mainframe-offline-source-evidence.json
```

Verify by schema-checking the artifact and reproducing every raw row from the
same selected source:

```bash
python3 scripts/dev/offline-impact/verify-evidence.py \
  --source-root . \
  --evidence /tmp/mainframe-offline-source-evidence.json
```

## Build from a release archive

Archive mode requires the adjacent checksum sidecar, verifies the archive
bytes, performs bounded safe extraction, and evaluates the extracted
`lib/agent_safety.sh` rather than the checkout copy.

```bash
python3 scripts/dev/offline-impact/build-evidence.py \
  --archive dist/mainframe-10.2.0.tar.gz \
  --output /tmp/mainframe-offline-archive-evidence.json

python3 scripts/dev/offline-impact/verify-evidence.py \
  --archive dist/mainframe-10.2.0.tar.gz \
  --evidence /tmp/mainframe-offline-archive-evidence.json
```

Pass `--bash /path/to/bash` to either command when Bash 4.4 or newer is not the
first `bash` on `PATH`.

## What the artifact binds

Each artifact contains:

- every fixture `id` and raw command string, its expected classification, its
  observed classification, and whether the row matched exactly;
- the SHA-256 and byte size of the exact evaluated `VERSION` and
  `lib/agent_safety.sh` files;
- a canonical evaluated-source digest over the ordered records
  `path NUL decimal-size NUL file-sha256 LF`;
- the fixture, schema, builder, verifier, shared implementation, and bounded
  archive-extractor digests;
- the Bash version and operating-system platform used for classification; and
- the archive SHA-256 plus successful sidecar verification in archive mode.

The verifier recomputes the complete artifact and compares it field for field.
Changing a raw row, aggregate, non-claim, protocol file, selected source file,
archive, checksum, Bash version, or platform makes verification fail.

The artifact always carries these explicit non-claims:

```json
{
  "real_provider_inference": "not-run",
  "agent_quality": "not-measured",
  "productivity": "not-measured",
  "comparative_agent_performance": "not-measured",
  "live_agent_sessions": 0
}
```

`commands_executed: false` and each row's `executed: false` refer to the raw
fixture commands: they are passed as inert string arguments to the classifier,
not invoked. The Bash classifier process itself does run offline.

This protocol is separate from the legacy `evals/run-evals.sh` scaffold. That
scaffold is not used as current agent-impact or product-outcome evidence.
