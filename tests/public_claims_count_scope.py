"""Exercise the production gate-count checker with tiny private documents."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
CHECKER = (ROOT / "scripts/verify-public-claims.sh").read_text(encoding="utf-8")
GATE_CHECKER = CHECKER.split("verify_generated_gate_claims() {", 1)[1].split(
    "<<'PY'\n", 1
)[1].split("\nPY\n", 1)[0]


class GateCountScopeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="mainframe-claim-scope-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "security").mkdir()
        (self.root / "scripts").mkdir()
        (self.root / "VERSION").write_text("10.3.1\n", encoding="utf-8")
        (self.root / "security/gate-rules.json").write_text(
            json.dumps({"rules": [{}, {}]}), encoding="utf-8"
        )
        (self.root / "scripts/export-gate-rules.py").write_text(
            "CORPUS = [('a', 'low'), ('b', 'high')]\n", encoding="utf-8"
        )

    def check_document(self, relative, content, *, extra=False):
        document = self.root / relative
        document.parent.mkdir(parents=True, exist_ok=True)
        document.write_text(content, encoding="utf-8")
        return subprocess.run(
            [sys.executable, "-I", "-S", "-B", "-", str(self.root),
             str(int(extra)), str(document)],
            input=GATE_CHECKER, text=True, capture_output=True, check=False,
        )

    def test_exact_archive_keeps_historical_counts(self):
        result = self.check_document(
            "docs/legacy/README-10.2.md",
            "> **Historical v10.2.0 reference.** Not current evidence.\n"
            "43 canonical lexical gate rules; 183 Bash/JavaScript parity cases.\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_archive_requires_prominent_explicit_warning(self):
        for prefix in ("", "\n" * 8):
            with self.subTest(prefix=repr(prefix)):
                header = "> **Historical v10.2.0 reference.**\n" if prefix else ""
                result = self.check_document(
                    "docs/legacy/README-10.2.md",
                    prefix + header + "43 canonical lexical gate rules.\n",
                )
                self.assertEqual(result.returncode, 1)
                self.assertIn("lacks its explicit warning", result.stderr)

    def test_unregistered_document_cannot_self_exempt(self):
        result = self.check_document(
            "docs/current.md",
            "> **Historical v10.2.0 verification record.**\n"
            "43 canonical lexical gate rules.\n",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("gate-rule count claims are stale", result.stderr)

    def test_extra_archive_is_explicitly_current(self):
        result = self.check_document(
            "docs/legacy/README-10.2.md",
            "> **Historical v10.2.0 reference.**\n43 source rules.\n", extra=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("gate-rule count claims are stale", result.stderr)

    def test_only_older_changelog_sections_are_historical(self):
        result = self.check_document(
            "CHANGELOG.md", "# Changelog\n## 10.3.1 - Current\n2 source rules.\n"
            "## 10.2.0 - Old candidate\n43 source rules; 183 corpus cases.\n",
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_current_changelog_section_is_checked(self):
        result = self.check_document(
            "CHANGELOG.md", "# Changelog\n## 10.3.1 - Current\n43 source rules.\n",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("CHANGELOG.md:3: found 43", result.stderr)

    def test_future_changelog_section_is_checked(self):
        result = self.check_document(
            "CHANGELOG.md", "## 10.4.0 - Planned\n43 source rules.\n",
        )
        self.assertEqual(result.returncode, 1)

    def test_unversioned_section_cannot_inherit_historical_exemption(self):
        result = self.check_document(
            "CHANGELOG.md", "## 10.2.0 - Old\n43 source rules.\n"
            "## Current notes\n43 source rules.\n",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("CHANGELOG.md:4: found 43", result.stderr)
        self.assertNotIn("CHANGELOG.md:2: found 43", result.stderr)

    def test_extra_changelog_has_no_historical_exemption(self):
        result = self.check_document(
            "CHANGELOG.md", "## 10.2.0 - Old\n43 source rules.\n", extra=True,
        )
        self.assertEqual(result.returncode, 1)


if __name__ == "__main__":
    unittest.main()
