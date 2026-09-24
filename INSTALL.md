# Install MAINFRAME for Pi

MAINFRAME 10.3 is a Pi-focused source build. Use a reviewed checkout or a locally
assembled, verified runtime. A public 10.3 release and Homebrew formula are not
claimed by this guide.

## Requirements

Bash 4.4+, jq, Python 3.10+, an installed Pi runtime and its supported Node.js,
and Git for source installation. On macOS, install a newer Bash and use its
absolute path; the system Bash is too old.

## Install a reviewed checkout

Pin the source revision you reviewed. From its root:

```bash
/bin/bash --noprofile --norc -p ./install.sh --dir "$PWD" --bin "$HOME/.local/bin"
```

Inspect installer help for custom runtime or binary directories. Preserve the
previous runtime until the new build and Pi package are verified. The installer
can link the CLI and update managed shell-profile entries.

```bash
mainframe version
mainframe doctor
mainframe shell status --shell all
mainframe setup --project . --proof
```

These checks establish local mechanisms, not live Pi protection.

## Configure Pi

```bash
mainframe setup --project .
mainframe setup --project . --dry-run
mainframe setup --project . --yes
```

Setup manages Pi's user package, preserves unrelated settings, and reports
recovery backups. Resolve any project override or duplicate legacy extension
before trusting activation.

Inside Pi:

```text
/reload
/mainframe doctor
```

Existing Pi processes keep their old extension until reloaded or restarted.

## Verify the actual runtime

A version number alone cannot certify a local fork or bundled distribution.
The native verifier loads the installed Pi SDK and exercises the integration.
Use its help for the exact arguments:

```bash
node scripts/dev/verify-pi-runtime.mjs --help
```

Local evidence binds to the inspected runtime and Mainframe files. Re-run it
after either changes. It is separate from upstream and public-release evidence.

## Inspect and recover

```bash
mainframe status
mainframe pi status --json
mainframe pi remove --dry-run
mainframe pi restore --backup-id BACKUP_ID --dry-run
mainframe uninstall --dry-run
```

Use the exact backup ID from the package manager. To return to a preserved source
runtime, preview its Pi install command, apply it, and reload Pi. Keep the CLI,
shell profiles, and Pi package source pointing at the same intended build.

Older distribution and multi-agent procedures are retained in the
[historical guide](docs/legacy/INSTALL-10.2.md).
