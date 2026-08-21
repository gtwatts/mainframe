from __future__ import annotations

import errno
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "control_plane"))

from mainframe_control_plane import (  # noqa: E402
    ControlPlaneKernel,
    DurabilityUnavailable,
)
from mainframe_control_plane import cli, durability, executor  # noqa: E402


class DirectoryDurabilityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name).resolve()

    def test_new_private_state_and_runtime_directories_are_fsynced(self) -> None:
        state = self.root / "state" / "mainframe"
        real_state_fsync = durability.fsync_directory
        state_synced = []

        def capture_state(path: Path) -> None:
            state_synced.append(Path(path))
            real_state_fsync(path)

        with mock.patch.object(
            durability, "fsync_directory", side_effect=capture_state
        ):
            cli._validate_owner_private_directory(state, create=True)
        self.assertIn(state, state_synced)
        self.assertIn(state.parent, state_synced)
        self.assertTrue(state.is_dir())
        self.assertEqual(state.stat().st_mode & 0o777, 0o700)

        runtime = state / ".mainframe-control-plane-runtime"
        runtime_synced = []

        def capture_runtime(path: Path) -> None:
            runtime_synced.append(Path(path))
            real_state_fsync(path)

        with mock.patch.object(
            durability, "fsync_directory", side_effect=capture_runtime
        ):
            executor._validate_private_directory(runtime, create=True)
        self.assertEqual(runtime_synced, [runtime, runtime.parent])
        self.assertTrue(runtime.is_dir())
        self.assertEqual(runtime.stat().st_mode & 0o777, 0o700)

    def test_first_ledger_file_fsyncs_its_parent_directory(self) -> None:
        ledger = self.root / "ledger.jsonl"
        observed = []
        real_fsync = durability.fsync_directory

        def capture(path: Path) -> None:
            observed.append(Path(path))
            real_fsync(path)

        with mock.patch(
            "mainframe_control_plane.kernel.fsync_directory", side_effect=capture
        ):
            kernel = ControlPlaneKernel(ledger)
            kernel.create_run(
                run_id="run-durable",
                actor="agent:test",
                workspace=str(self.root),
                policy="policy:test",
            )
        self.assertEqual(observed, [self.root])
        self.assertTrue(ledger.is_file())
        self.assertGreater(ledger.stat().st_size, 0)

    def test_unsupported_directory_fsync_fails_closed(self) -> None:
        with mock.patch.object(durability.os, "O_DIRECTORY", None):
            with self.assertRaisesRegex(
                DurabilityUnavailable,
                "directory fsync is unsupported on this platform",
            ):
                durability.fsync_directory(self.root)

        with mock.patch.object(
            durability.os,
            "fsync",
            side_effect=OSError(errno.ENOTSUP, "unsupported"),
        ):
            with self.assertRaises(DurabilityUnavailable):
                durability.fsync_directory(self.root)


if __name__ == "__main__":
    unittest.main()
