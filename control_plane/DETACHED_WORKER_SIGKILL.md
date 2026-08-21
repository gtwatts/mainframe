# Detached worker SIGKILL guardian

Status: **GREEN for the fixed stable-core broker route**.

The executor creates an anonymous liveness pipe immediately before it starts
the fixed Bash broker. The read end is inherited only as fixed descriptor 198;
the descriptor number is absent from argv, environment, canonical input, and
the durable ledger. The worker retains the non-inheritable write end until the
executor has terminated and reaped the broker group. Worker `SIGKILL` closes
that write end in the kernel and therefore produces EOF.

The hidden Bash broker validates descriptor 198, starts a background guardian
in the broker process group, and closes the main shell's copy before dispatch.
The guardian ignores `HUP` and `TERM`, closes unrelated standard descriptors,
and blocks on the liveness pipe. EOF causes a fixed TERM, grace, and KILL of its
own process group. It deliberately survives normal broker-leader exit until the
Python executor performs its existing group cleanup, so the group ID remains
anchored and cannot be reused during the leader-exit cleanup window.

No liveness path, PID, process-group ID, executable, signal, timeout, or file
descriptor is caller-selectable. No named file or ambient environment value is
used. The fixed descriptor is installed only across `Popen` under a process
lock, and any pre-existing descriptor 198 is restored with its prior
inheritability.

`test_worker_sigkill_liveness_guardian_eliminates_adapter_group` kills the
detached worker after both guardian and adapter are live, then proves the
adapter PGID no longer exists. Normal completion, cancellation, timeout, and
leader-exit descendant tests continue to exercise the same group cleanup.
