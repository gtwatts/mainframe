"""File storage parity and deterministic producer/consumer interleaving tests."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

PROJECT_ROOT = Path(__file__).resolve().parents[2]


class FileStorageRegressionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mainframe-storage-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment = {
            "PATH": "/usr/bin:/bin", "MAINFRAME_STORAGE": "file",
            "MAINFRAME_AWM_DIR": str(self.root),
            "QUEUE_READY": str(self.root / "ready"),
            "QUEUE_RESUME": str(self.root / "resume"),
        }

    def command(self, script):
        return ["/bin/bash", "--noprofile", "--norc", "-c",
                'set -e; source "$1/lib/awm_storage.sh"; awm_storage_init; ' + script,
                "bash", str(PROJECT_ROOT)]

    def run_script(self, script):
        result = subprocess.run(self.command(script), env=self.environment,
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_search_accumulates_matches_under_errexit(self):
        result = json.loads(self.run_script(
            "awm_store_index one 'needle first'; awm_store_index two 'needle second'; "
            "awm_store_search needle 10"
        ))
        self.assertEqual(len(result), 2)
        self.assertTrue(all(item["score"] > 0 for item in result))
        self.assertEqual(len(json.loads(self.run_script("awm_store_search needle 1"))), 1)

    def test_negative_ranges_match_inclusive_redis_semantics_and_preserve_bytes(self):
        self.run_script("awm_store_push q zero; awm_store_push q one; awm_store_push q $'two\\n\\n'")
        for start, end, expected in (
            (-1, -1, ["two\n\n"]), (-2, -1, ["one", "two\n\n"]),
            (-99, 0, ["zero"]), (1, 99, ["one", "two\n\n"]),
            (99, 100, []), (0, -99, []), (2, 1, []),
        ):
            with self.subTest(start=start, end=end):
                result = json.loads(self.run_script("awm_store_range q {} {}".format(start, end)))
                self.assertEqual(result, expected)

    def test_push_cannot_be_lost_during_pop_replacement(self):
        self.run_script("awm_store_push q first; awm_store_push q second")
        pop = subprocess.Popen(self.command(
            'tail() { command tail "$@"; : > "$QUEUE_READY"; '
            'while [[ ! -e "$QUEUE_RESUME" ]]; do sleep 0.02; done; }; awm_store_pop q'
        ), env=self.environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        producer = None
        try:
            deadline = time.monotonic() + 5
            while not (self.root / "ready").exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue((self.root / "ready").exists())
            producer = subprocess.Popen(self.command("awm_store_push q third"),
                env=self.environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            with self.assertRaises(subprocess.TimeoutExpired):
                producer.wait(timeout=0.2)
        finally:
            (self.root / "resume").touch()
            popped, errors = pop.communicate(timeout=5)
            if producer is not None:
                producer.communicate(timeout=5)
        self.assertEqual(pop.returncode, 0, errors)
        self.assertEqual(producer.returncode, 0)
        self.assertEqual(popped, "first")
        self.assertEqual(json.loads(self.run_script("awm_store_range q 0 -1")), ["second", "third"])


if __name__ == "__main__":
    unittest.main()
