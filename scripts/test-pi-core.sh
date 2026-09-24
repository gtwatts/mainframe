#!/usr/bin/env bash
# Focused source checks. Actual installed Pi evidence is generated separately
# by scripts/dev/verify-pi-runtime.mjs using that runtime's native SDK.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd -- "$ROOT"
umask 077
PYTHON="${MAINFRAME_TEST_PYTHON:-python3}"

bash -n bin/mainframe lib/setup.sh lib/pi.sh lib/agent_safety.sh lib/durable_awm.sh
node --check security/gate-normalizer.mjs
node --test tests/pi_local_verification.test.mjs tests/pi_process_cancellation.test.mjs
"$PYTHON" scripts/export-gate-rules.py --check
"$PYTHON" scripts/export-gate-rules.py --verify
"$PYTHON" scripts/check-function-exports.py --check
"$PYTHON" scripts/generate-runtime-closure.py --check
"$PYTHON" -m unittest discover -s tests/control_plane -p 'test_*.py'
bash tests/run_bats_suite.sh --scope safety --formatter tap
bash tests/run_bats_suite.sh --scope pi --formatter tap
./tests/bats/bin/bats tests/doctor.bats tests/uninstall-cli.bats tests/setup.bats
printf 'Pi source checks passed. Verify the installed Pi SDK before claiming local runtime support.\n'
