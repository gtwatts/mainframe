from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CHECKER = PROJECT_ROOT / "scripts/check-control-plane-claim.py"
SCHEMA = PROJECT_ROOT / "config/control-plane-claim-receipt.schema.json"
PYTHON = Path("/usr/bin/python3")

PROMOTIONS = {
    "source-candidate": [
        "release-integrity",
        "semantic-authority",
        "runtime-closure",
    ],
    "control-plane-preview": [
        "release-integrity",
        "semantic-authority",
        "runtime-closure",
        "durable-authority-kernel",
        "reviewed-broker-routing",
        "coding-agent-contract",
        "project-memory-contract",
    ],
    "host-preview": [
        "release-integrity",
        "semantic-authority",
        "runtime-closure",
        "durable-authority-kernel",
        "reviewed-broker-routing",
        "coding-agent-contract",
        "project-memory-contract",
        "adapter-contract",
        "host-conformance",
    ],
    "stable-release": [
        "release-integrity",
        "semantic-authority",
        "runtime-closure",
        "durable-authority-kernel",
        "reviewed-broker-routing",
        "coding-agent-contract",
        "project-memory-contract",
        "adapter-contract",
        "host-conformance",
        "immutable-distribution",
    ],
    "category-claim": [
        "release-integrity",
        "semantic-authority",
        "runtime-closure",
        "durable-authority-kernel",
        "reviewed-broker-routing",
        "coding-agent-contract",
        "project-memory-contract",
        "adapter-contract",
        "host-conformance",
        "immutable-distribution",
        "independent-outcomes",
    ],
}

EVIDENCE_PATHS = {
    "release-integrity": [
        "scripts/dev/release.sh",
        "scripts/dev/release-payload.sh",
        "scripts/generate-sbom.sh",
        "scripts/build-release-archive.sh",
        "tests/release-archive.bats",
        "config/release-attestation-exclusions.txt",
        "SHA256SUMS",
    ],
    "semantic-authority": [
        "config/semantic-trust-policy.json",
        "scripts/generate-manifest.py",
        "tests/owner-parity.bats",
    ],
    "runtime-closure": [
        "config/runtime-closure.json",
        "scripts/generate-runtime-closure.py",
        "tests/runtime_closure.bats",
    ],
    "durable-authority-kernel": [
        "control_plane/mainframe_control_plane/kernel.py",
        "control_plane/mainframe_control_plane/executor.py",
        "control_plane/mainframe_control_plane/worker.py",
        "tests/control_plane/test_kernel.py",
        "tests/control_plane/test_policy_lifecycle.py",
        "tests/control_plane/test_stable_core.py",
        "tests/control_plane/test_supervised_executor.py",
    ],
    "reviewed-broker-routing": [
        "config/stable-core.json",
        "tests/control_plane/public_cli.bats",
    ],
    "coding-agent-contract": [
        "control_plane/mainframe_control_plane/coding.py",
        "control_plane/mainframe_control_plane/cli.py",
        "control_plane/mainframe_control_plane/kernel.py",
        "tests/control_plane/test_coding_agent.py",
        "tests/control_plane/test_coding_public.py",
    ],
    "project-memory-contract": [
        "bin/mainframe",
        "lib/durable_awm.sh",
        "control_plane/mainframe_control_plane/memory.py",
        "control_plane/mainframe_control_plane/memory_executor.py",
        "control_plane/mainframe_control_plane/memory_transient.py",
        "control_plane/mainframe_control_plane/cli.py",
        "control_plane/mainframe_control_plane/kernel.py",
        "tests/control_plane/test_project_memory.py",
        "tests/control_plane/test_project_memory_reads.py",
        "tests/control_plane/test_project_memory_integration.py",
        "tests/durable_project_memory_route.bats",
    ],
    "adapter-contract": [
        "config/host-capabilities.json",
        "scripts/generate-host-adapters.sh",
        "tests/host_capabilities.bats",
    ],
    "host-conformance": [
        "config/host-capabilities.json",
        "tests/native_host_certification.bats",
        "tests/pi_cell_evidence.bats",
    ],
    "immutable-distribution": [
        "scripts/build-release-archive.sh",
        "scripts/dev/release-candidate.sh",
        "tests/release-archive.bats",
    ],
    "independent-outcomes": [
        "docs/AGENT_IMPACT_EVALUATION.md",
        "docs/CLAIMS_AND_BENCHMARKS.md",
    ],
}

PROOFS = {
    "release-integrity": ("inventory-suite", "mainframe.release-integrity.inventory.v1", ["/bin/bash", "--noprofile", "--norc", "-p", "scripts/generate-sbom.sh", "--check"]),
    "semantic-authority": ("source-suite", "mainframe.semantic-authority.source.v1", ["python3", "-I", "-S", "-B", "scripts/check-owner-parity.py"]),
    "runtime-closure": ("source-suite", "mainframe.runtime-closure.source.v1", ["python3", "-I", "-S", "-B", "scripts/generate-runtime-closure.py", "--check"]),
    "durable-authority-kernel": ("kernel-foundation", "mainframe.durable-kernel.foundation.v1", ["python3", "-I", "-S", "-B", "tests/control_plane/test_kernel.py"]),
    "coding-agent-contract": ("public-safe-read-search", "mainframe.coding-agent.public-safe-reads.v1", ["python3", "-I", "-S", "-B", "tests/control_plane/test_coding_public.py"]),
    "project-memory-contract": ("twelve-operation-route", "mainframe.project-memory.twelve-operation-route.v1", ["bats", "tests/durable_project_memory_route.bats"]),
    "adapter-contract": ("instruction-contract", "mainframe.adapter-contract.instructions.v1", ["/bin/bash", "--noprofile", "--norc", "-p", "scripts/generate-host-adapters.sh", "--check"]),
}
RELEASE_ARCHIVE_PROOF = (
    "archive-reproducibility",
    "mainframe.release-integrity.archive.v1",
    ["/bin/bash", "--noprofile", "--norc", "-p", "scripts/build-release-archive.sh", "--verify"],
)
ADDITIONAL_PROOFS = {
    "release-integrity": [RELEASE_ARCHIVE_PROOF],
    "coding-agent-contract": [
        (
            "approval-required-fail-closed",
            "mainframe.coding-agent.approval-required.v1",
            ["python3", "-I", "-S", "-B", "tests/control_plane/test_coding_public.py"],
        ),
    ],
    "project-memory-contract": [
        (
            "privacy-recovery-no-fallback",
            "mainframe.project-memory.privacy-recovery.v1",
            ["bats", "tests/durable_project_memory_route.bats"],
        ),
    ],
    "adapter-contract": [
        (
            "kernel-routed-adapters",
            "mainframe.adapter-contract.kernel-route.v1",
            ["bats", "tests/adapter_kernel_route.bats"],
        ),
        (
            "durable-correlation",
            "mainframe.adapter-contract.correlation.v1",
            ["bats", "tests/adapter_kernel_route.bats"],
        ),
    ],
}


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def attestation_exclusions(root: Path) -> tuple[str, ...]:
    return tuple(
        line
        for raw_line in (
            root / "config/release-attestation-exclusions.txt"
        ).read_text(encoding="utf-8").splitlines()
        if (line := raw_line.strip()) and not line.startswith("#")
    )


def is_attestation_metadata(root: Path, relative: str) -> bool:
    return any(
        relative.startswith(excluded) if excluded.endswith("/")
        else relative == excluded
        for excluded in attestation_exclusions(root)
    )


def source_tree_sha256(root: Path) -> str:
    paths = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
    ).split(b"\0")
    digest = hashlib.sha256()
    for encoded in sorted(path for path in paths if path):
        relative = encoded.decode("utf-8")
        if is_attestation_metadata(root, relative):
            continue
        path = root / relative
        mode = os.lstat(path).st_mode & 0o777
        digest.update(encoded + b"\0" + f"{mode:04o}".encode("ascii") + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


class ClaimReceiptFixture:
    def __init__(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for relative in sorted({path for paths in EVIDENCE_PATHS.values() for path in paths}):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"fixture evidence: {relative}\n", encoding="utf-8")
        shutil.copyfile(
            PROJECT_ROOT / "config/release-attestation-exclusions.txt",
            self.root / "config/release-attestation-exclusions.txt",
        )
        (self.root / "docs/unrelated.md").write_text("irrelevant\n", encoding="utf-8")
        verifier_files = {
            "scripts/generate-sbom.sh": """#!/bin/bash
set -eu
actual=$(sed -n 's/^[0-9a-f]\\{64\\}  //p' SHA256SUMS | LC_ALL=C sort)
registry=$(grep -v '^#' config/release-attestation-exclusions.txt | sed '/^$/d')
expected_registry=$(printf '%s\\n' SHA256SUMS config/control-plane-claim.json config/control-plane-claim-receipts/)
[[ "$registry" == "$expected_registry" ]]
expected=$(find . -type f ! -path './.git/*' ! -path './config/control-plane-claim.json' ! -path './config/control-plane-claim-receipts/*' ! -name SHA256SUMS -print | sed 's|^./||' | LC_ALL=C sort)
[[ "$actual" == "$expected" ]]
""",
            "scripts/build-release-archive.sh": "#!/bin/bash\nexit 0\n",
            "scripts/check-owner-parity.py": "raise SystemExit(0)\n",
            "scripts/generate-runtime-closure.py": "raise SystemExit(0)\n",
            "tests/control_plane/test_kernel.py": "raise SystemExit(0)\n",
            "tests/control_plane/test_coding_public.py": "raise SystemExit(0)\n",
            "tests/durable_project_memory_route.bats": "#!/usr/bin/env bats\n@test \"fixture project-memory contract\" { true; }\n",
            "tests/adapter_kernel_route.bats": "#!/usr/bin/env bats\n@test \"fixture adapter contract\" { true; }\n",
            "scripts/generate-host-adapters.sh": "#!/bin/bash\nexit 0\n",
        }
        for relative, content in verifier_files.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        (self.root / "VERSION").write_text("10.2.0\n", encoding="utf-8")
        schema_path = self.root / "config/control-plane-claim-receipt.schema.json"
        schema_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SCHEMA, schema_path)
        inventory_paths = sorted(
            path for path in self.root.rglob("*")
            if path.is_file()
            and not is_attestation_metadata(
                self.root, str(path.relative_to(self.root))
            )
        )
        (self.root / "SHA256SUMS").write_text(
            "".join(
                f"{sha256_bytes(path.read_bytes())}  {path.relative_to(self.root)}\n"
                for path in inventory_paths
            ),
            encoding="utf-8",
        )
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(["git", "-C", str(self.root), "config", "user.email", "claim-tests@example.invalid"], check=True)
        subprocess.run(["git", "-C", str(self.root), "config", "user.name", "Claim Tests"], check=True)
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.root), "commit", "-qm", "fixture"], check=True)
        self.revision = subprocess.check_output(
            ["git", "-C", str(self.root), "rev-parse", "HEAD"], text=True
        ).strip()
        self.receipt_dir = self.root / "config/control-plane-claim-receipts"
        self.receipt_dir.mkdir()
        self.contract = {
            "schema_version": 2,
            "contract_version": "2.1.0",
            "receipt_schema": "config/control-plane-claim-receipt.schema.json",
            "target_claim": "category-claim",
            "advertised_claim": "source-candidate",
            "promotions": PROMOTIONS,
            "gates": {},
        }
        for gate_id, paths in EVIDENCE_PATHS.items():
            self.contract["gates"][gate_id] = {
                "summary": f"Fixture summary for {gate_id}.",
                "evidence_paths": paths,
                "receipt_refs": [],
                "remaining": [] if gate_id in (
                    set(PROMOTIONS["source-candidate"])
                    | {"coding-agent-contract", "project-memory-contract", "adapter-contract"}
                ) else ["Fixture proof remains."],
            }
        for gate_id in PROOFS:
            self.add_receipt(gate_id)
        for gate_id, proof_specs in ADDITIONAL_PROOFS.items():
            for proof_kind, _, _ in proof_specs:
                self.add_receipt(
                    gate_id,
                    self.make_receipt(gate_id, proof_kind=proof_kind),
                )
        self.write_contract()

    def cleanup(self) -> None:
        self.temp.cleanup()

    def evidence(self, gate_id: str) -> list[dict[str, str]]:
        return [
            {
                "path": relative,
                "sha256": sha256_bytes((self.root / relative).read_bytes()),
                "role": "inventory" if relative == "SHA256SUMS" else "source-evidence",
            }
            for relative in EVIDENCE_PATHS[gate_id]
        ]

    def make_receipt(
        self,
        gate_id: str,
        *,
        proof_kind: str | None = None,
        subject_kind: str = "source",
        authority_class: str = "local-verifier",
    ) -> dict[str, object]:
        default_proof, command_identity, argv = PROOFS.get(
            gate_id,
            ("published-release-attestation", "mainframe.immutable-distribution.release.v1", ["mainframe", "release", "verify"]),
        )
        selected_proof = proof_kind or default_proof
        for candidate in ADDITIONAL_PROOFS.get(gate_id, []):
            if selected_proof == candidate[0]:
                _, command_identity, argv = candidate
                break
        now = datetime.now(timezone.utc).replace(microsecond=0)
        return {
            "schema_version": 1,
            "receipt_type": "mainframe-control-plane-gate-receipt",
            "receipt_id": f"{gate_id}-{selected_proof}-fixture",
            "gate_id": gate_id,
            "proof_kind": selected_proof,
            "protocol_version": "1.0.0",
            "subject": {
                "kind": subject_kind,
                "source_revision": self.revision if subject_kind == "source" else None,
                "source_tree_sha256": source_tree_sha256(self.root) if subject_kind == "source" else None,
                "inventory_sha256": sha256_bytes((self.root / "SHA256SUMS").read_bytes()) if subject_kind == "payload" else None,
                "payload_sha256": "1" * 64 if subject_kind == "payload" else None,
                "version": "10.2.0",
            },
            "command": {"identity": command_identity, "argv": argv},
            "environment": {
                "os": "darwin" if platform.system() == "Darwin" else "linux",
                "architecture": "arm64" if platform.machine() in {"arm64", "aarch64"} else "x86_64",
                "runner_class": "maintainer-local",
            },
            "issued_at": now.isoformat().replace("+00:00", "Z"),
            "expires_at": (now + timedelta(days=1)).isoformat().replace("+00:00", "Z"),
            "evidence": self.evidence(gate_id),
            "result": "pass",
            "authority": {
                "class": authority_class,
                "signer_id": "scripts/check-control-plane-claim.py",
                "independence": "project",
                "signature": None,
            },
            "limitations": ["Fixture receipt proves only content-bound source execution."],
        }

    def add_receipt(self, gate_id: str, receipt: dict[str, object] | None = None) -> Path:
        value = receipt or self.make_receipt(gate_id)
        primary_proof = PROOFS.get(gate_id, (None, None, None))[0]
        suffix = "" if value["proof_kind"] == primary_proof else f"-{value['proof_kind']}"
        path = self.receipt_dir / f"{gate_id}{suffix}.json"
        path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
        self.contract["gates"][gate_id]["receipt_refs"].append({
            "path": str(path.relative_to(self.root)),
            "sha256": sha256_bytes(path.read_bytes()),
        })
        return path

    def mutate_receipt(self, gate_id: str, mutate, *, refresh_ref: bool = True) -> None:
        path = self.receipt_dir / f"{gate_id}.json"
        receipt = json.loads(path.read_text(encoding="utf-8"))
        mutate(receipt)
        path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
        if refresh_ref:
            self.contract["gates"][gate_id]["receipt_refs"][0]["sha256"] = sha256_bytes(path.read_bytes())
        self.write_contract()

    def refresh_all_bindings(self) -> None:
        inventory = self.root / "SHA256SUMS"
        paths = [line[66:] for line in inventory.read_text(encoding="utf-8").splitlines() if line]
        inventory.write_text(
            "".join(
                f"{sha256_bytes((self.root / relative).read_bytes())}  {relative}\n"
                for relative in paths
            ),
            encoding="utf-8",
        )
        inventory_digest = sha256_bytes(inventory.read_bytes())
        tree_digest = source_tree_sha256(self.root)
        for gate_id in PROOFS:
            for ref in self.contract["gates"][gate_id]["receipt_refs"]:
                path = self.root / ref["path"]
                receipt = json.loads(path.read_text(encoding="utf-8"))
                if receipt["subject"]["kind"] == "payload":
                    receipt["subject"]["inventory_sha256"] = inventory_digest
                receipt["subject"]["source_tree_sha256"] = tree_digest
                for item in receipt["evidence"]:
                    item["sha256"] = sha256_bytes((self.root / item["path"]).read_bytes())
                path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
                ref["sha256"] = sha256_bytes(path.read_bytes())
        self.write_contract()

    def write_contract(self) -> None:
        path = self.root / "config/control-plane-claim.json"
        path.write_text(json.dumps(self.contract, indent=2) + "\n", encoding="utf-8")

    def commit(self, message: str) -> str:
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(
            ["git", "-C", str(self.root), "commit", "-qm", message],
            check=True,
        )
        return subprocess.check_output(
            ["git", "-C", str(self.root), "rev-parse", "HEAD"], text=True
        ).strip()

    def check(self) -> tuple[int, dict[str, object]]:
        result = subprocess.run(
            [str(PYTHON), "-I", "-S", "-B", str(CHECKER), "--root", str(self.root), "--contract", str(self.root / "config/control-plane-claim.json"), "--json"],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return result.returncode, json.loads(result.stdout)


class ClaimReceiptAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = ClaimReceiptFixture()
        self.addCleanup(self.fixture.cleanup)

    def assert_rejected(self, needle: str) -> None:
        status, output = self.fixture.check()
        self.assertNotEqual(status, 0, output)
        self.assertIn(needle, str(output.get("error")))

    def test_valid_receipts_derive_source_candidate_without_authored_states(self) -> None:
        status, output = self.fixture.check()
        self.assertEqual(status, 0, output)
        self.assertEqual(output["highest_eligible_claim"], "source-candidate")
        self.assertEqual(output["gate_states"]["release-integrity"], "green")
        self.assertEqual(output["gate_states"]["durable-authority-kernel"], "amber")
        self.assertEqual(output["gate_states"]["reviewed-broker-routing"], "red")
        self.assertEqual(output["gate_states"]["coding-agent-contract"], "green")
        self.assertEqual(output["gate_states"]["project-memory-contract"], "green")
        self.assertEqual(output["gate_states"]["adapter-contract"], "green")

    def test_inventory_then_receipt_reference_issuance_has_no_digest_cycle(self) -> None:
        verifier = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-p",
             "scripts/generate-sbom.sh", "--check"],
            cwd=self.fixture.root,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.assertEqual(verifier.returncode, 0, verifier.stdout.decode())

        self.fixture.mutate_receipt(
            "semantic-authority",
            lambda receipt: receipt["limitations"].append(
                "Issued after the canonical subject inventory was generated."
            ),
        )
        verifier = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", "-p",
             "scripts/generate-sbom.sh", "--check"],
            cwd=self.fixture.root,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.assertEqual(verifier.returncode, 0, verifier.stdout.decode())
        status, output = self.fixture.check()
        self.assertEqual(status, 0, output)
        self.assertEqual(output["highest_eligible_claim"], "source-candidate")

    def test_source_candidate_does_not_require_preview_only_coding_or_memory(self) -> None:
        for gate_id in ("coding-agent-contract", "project-memory-contract"):
            gate = self.fixture.contract["gates"][gate_id]
            gate["receipt_refs"] = []
            gate["remaining"] = ["Preview-only local proof remains."]
        self.fixture.write_contract()

        status, output = self.fixture.check()
        self.assertEqual(status, 0, output)
        self.assertEqual(output["highest_eligible_claim"], "source-candidate")
        self.assertEqual(output["gate_states"]["coding-agent-contract"], "red")
        self.assertEqual(output["gate_states"]["project-memory-contract"], "red")

    def test_one_coding_receipt_cannot_green_a_two_proof_contract(self) -> None:
        gate = self.fixture.contract["gates"]["coding-agent-contract"]
        gate["receipt_refs"] = gate["receipt_refs"][:1]
        gate["remaining"] = ["Approval-required fail-closed proof remains."]
        self.fixture.write_contract()

        status, output = self.fixture.check()
        self.assertEqual(status, 0, output)
        self.assertEqual(output["highest_eligible_claim"], "source-candidate")
        self.assertEqual(output["gate_states"]["coding-agent-contract"], "amber")

    def test_authored_state_cannot_promote_a_gate(self) -> None:
        self.fixture.contract["gates"]["host-conformance"]["state"] = "green"
        self.fixture.write_contract()
        self.assert_rejected("unknown gate host-conformance keys")

    def test_irrelevant_evidence_file_is_rejected(self) -> None:
        unrelated = self.fixture.root / "docs/unrelated.md"

        def mutate(receipt):
            receipt["evidence"] = [{"path": "docs/unrelated.md", "sha256": sha256_bytes(unrelated.read_bytes()), "role": "source-evidence"}]

        self.fixture.mutate_receipt("semantic-authority", mutate)
        self.assert_rejected("evidence paths do not match the reviewed policy")

    def test_stale_source_revision_is_rejected(self) -> None:
        self.fixture.mutate_receipt("runtime-closure", lambda receipt: receipt["subject"].update(source_revision="0" * 40))
        self.assert_rejected("source revision does not match HEAD or its sole detached-attestation parent")

    def test_parent_revision_is_accepted_for_one_detached_attestation_commit(self) -> None:
        subject_revision = self.fixture.revision
        attestation_revision = self.fixture.commit("detached attestations")
        self.assertNotEqual(attestation_revision, subject_revision)

        status, output = self.fixture.check()
        self.assertEqual(status, 0, output)
        self.assertEqual(output["highest_eligible_claim"], "source-candidate")

    def test_parent_revision_is_rejected_when_commit_changes_subject_bytes(self) -> None:
        (self.fixture.root / "docs/unrelated.md").write_text(
            "subject changed in attestation commit\n", encoding="utf-8"
        )
        self.fixture.refresh_all_bindings()
        self.fixture.commit("mixed source and attestations")

        self.assert_rejected(
            "source revision does not match HEAD or its sole detached-attestation parent"
        )

    def test_grandparent_revision_is_rejected_after_two_attestation_commits(self) -> None:
        self.fixture.commit("first detached attestations")
        self.fixture.mutate_receipt(
            "runtime-closure",
            lambda receipt: receipt["limitations"].append(
                "Second detached attestation generation."
            ),
        )
        self.fixture.commit("second detached attestations")

        self.assert_rejected(
            "source revision does not match HEAD or its sole detached-attestation parent"
        )

    def test_stale_payload_digest_is_rejected(self) -> None:
        receipt = self.fixture.make_receipt("immutable-distribution", subject_kind="payload", authority_class="release-authority")
        receipt["subject"]["inventory_sha256"] = "0" * 64
        receipt["authority"].update(independence="external", signature="fixture-signature-not-trusted")
        self.fixture.add_receipt("immutable-distribution", receipt)
        self.fixture.write_contract()
        self.assert_rejected("inventory digest does not match canonical SHA256SUMS")

    def test_copied_gate_receipt_is_rejected(self) -> None:
        source = self.fixture.receipt_dir / "release-integrity.json"
        destination = self.fixture.receipt_dir / "semantic-authority.json"
        destination.write_bytes(source.read_bytes())
        self.fixture.contract["gates"]["semantic-authority"]["receipt_refs"] = [{
            "path": str(destination.relative_to(self.fixture.root)),
            "sha256": sha256_bytes(destination.read_bytes()),
        }]
        self.fixture.write_contract()
        self.assert_rejected("receipt gate_id does not match semantic-authority")

    def test_receipt_and_evidence_tamper_are_rejected(self) -> None:
        self.fixture.mutate_receipt("release-integrity", lambda receipt: receipt.update(result="fail"), refresh_ref=False)
        self.assert_rejected("receipt digest mismatch")

        self.fixture.cleanup()
        self.fixture = ClaimReceiptFixture()
        self.addCleanup(self.fixture.cleanup)
        path = self.fixture.root / EVIDENCE_PATHS["release-integrity"][0]
        path.write_text("tampered\n", encoding="utf-8")
        self.assert_rejected("canonical SHA256SUMS payload drift")

    def test_expired_receipt_is_rejected(self) -> None:
        self.fixture.mutate_receipt(
            "semantic-authority",
            lambda receipt: receipt.update(
                issued_at="2019-12-31T00:00:00Z",
                expires_at="2020-01-01T00:00:00Z",
            ),
        )
        self.assert_rejected("receipt is expired")

    def test_environment_and_ttl_are_recomputed_not_trusted(self) -> None:
        self.fixture.mutate_receipt(
            "semantic-authority",
            lambda receipt: receipt["environment"].update(os="linux" if platform.system() == "Darwin" else "darwin"),
        )
        self.assert_rejected("environment does not match the local verifier")

        self.fixture.cleanup()
        self.fixture = ClaimReceiptFixture()
        self.addCleanup(self.fixture.cleanup)
        now = datetime.now(timezone.utc).replace(microsecond=0)
        self.fixture.mutate_receipt(
            "semantic-authority",
            lambda receipt: receipt.update(
                issued_at=now.isoformat().replace("+00:00", "Z"),
                expires_at=(now + timedelta(days=8)).isoformat().replace("+00:00", "Z"),
            ),
        )
        self.assert_rejected("TTL exceeds seven days")

    def test_pass_assertion_cannot_override_a_failed_fixed_verifier(self) -> None:
        verifier = self.fixture.root / "scripts/generate-runtime-closure.py"
        verifier.write_text("raise SystemExit(9)\n", encoding="utf-8")
        self.fixture.refresh_all_bindings()
        self.assert_rejected("receipt result does not match fixed verifier execution")

    def test_incomplete_inventory_fails_the_fixed_inventory_verifier(self) -> None:
        inventory = self.fixture.root / "SHA256SUMS"
        lines = inventory.read_text(encoding="utf-8").splitlines()
        inventory.write_text("\n".join(lines[1:]) + "\n", encoding="utf-8")
        for ref in self.fixture.contract["gates"]["release-integrity"]["receipt_refs"]:
            path = self.fixture.root / ref["path"]
            receipt = json.loads(path.read_text(encoding="utf-8"))
            for item in receipt["evidence"]:
                if item["path"] == "SHA256SUMS":
                    item["sha256"] = sha256_bytes(inventory.read_bytes())
            path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
            ref["sha256"] = sha256_bytes(path.read_bytes())
        self.fixture.write_contract()
        self.assert_rejected("receipt result does not match fixed verifier execution")

    def test_unbound_dirty_source_drift_is_rejected(self) -> None:
        path = self.fixture.root / "unbound.txt"
        path.write_text("unbound drift\n", encoding="utf-8")
        self.assert_rejected("source tree digest does not match the current working tree")

    def test_missing_and_self_asserted_authority_are_rejected(self) -> None:
        self.fixture.mutate_receipt("runtime-closure", lambda receipt: receipt.pop("authority"))
        self.assert_rejected("missing receipt keys")

        self.fixture.cleanup()
        self.fixture = ClaimReceiptFixture()
        self.addCleanup(self.fixture.cleanup)
        self.fixture.mutate_receipt("runtime-closure", lambda receipt: receipt["authority"].update({"class": "self-asserted", "signer_id": "self"}))
        self.assert_rejected("self-asserted authority is not admissible")

    def test_local_authority_cannot_satisfy_release_or_independent_gate(self) -> None:
        receipt = self.fixture.make_receipt("immutable-distribution", subject_kind="payload", authority_class="local-verifier")
        self.fixture.add_receipt("immutable-distribution", receipt)
        self.fixture.write_contract()
        self.assert_rejected("authority class local-verifier is not permitted")


class ClaimGatePolicyShapeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = json.loads(
            (PROJECT_ROOT / "config/control-plane-claim.json").read_text(
                encoding="utf-8"
            )
        )
        specification = importlib.util.spec_from_file_location(
            "mainframe_claim_checker", CHECKER
        )
        assert specification is not None and specification.loader is not None
        self.checker = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(self.checker)

    def test_preview_adds_coding_and_memory_without_expanding_source_candidate(self) -> None:
        source = [
            "release-integrity",
            "semantic-authority",
            "runtime-closure",
        ]
        self.assertEqual(self.contract["promotions"]["source-candidate"], source)
        preview = source + [
            "durable-authority-kernel",
            "reviewed-broker-routing",
            "coding-agent-contract",
            "project-memory-contract",
        ]
        self.assertEqual(self.contract["promotions"]["control-plane-preview"], preview)
        for claim in ("host-preview", "stable-release", "category-claim"):
            self.assertEqual(
                self.contract["promotions"][claim][: len(preview)], preview
            )
        self.assertEqual(
            tuple(self.contract["gates"]), tuple(self.checker.GATE_POLICIES)
        )

    def test_new_gates_use_fixed_public_verifiers_and_keep_approval_external(self) -> None:
        policies = self.checker.GATE_POLICIES
        adapter = policies["adapter-contract"]["proofs"]
        self.assertEqual(
            adapter["durable-correlation"]["argv"],
            ("bats", "tests/adapter_kernel_route.bats"),
        )

        coding = policies["coding-agent-contract"]
        self.assertEqual(
            coding["required"],
            ("public-safe-read-search", "approval-required-fail-closed"),
        )
        self.assertEqual(
            {
                tuple(coding["proofs"][proof_kind]["argv"])
                for proof_kind in coding["required"]
            },
            {
                (
                    "python3",
                    "-I",
                    "-S",
                    "-B",
                    "tests/control_plane/test_coding_public.py",
                )
            },
        )

        memory = policies["project-memory-contract"]
        self.assertEqual(
            memory["required"],
            ("twelve-operation-route", "privacy-recovery-no-fallback"),
        )
        self.assertEqual(
            {
                tuple(memory["proofs"][proof_kind]["argv"])
                for proof_kind in memory["required"]
            },
            {("bats", "tests/durable_project_memory_route.bats")},
        )

        authority = policies["durable-authority-kernel"]["proofs"]
        external = authority["coding-approval-authority-integration"]
        self.assertEqual(external["subject_kind"], "payload")
        self.assertTrue(external["external_verifier"])
        self.assertEqual(external["authorities"], ("host-operator",))

    def test_ci_checkouts_include_the_attested_subject_parent(self) -> None:
        workflow = (PROJECT_ROOT / ".github/workflows/test.yml").read_text(
            encoding="utf-8"
        ).splitlines()
        checkout_indexes = [
            index
            for index, line in enumerate(workflow)
            if "uses: actions/checkout@" in line
        ]
        self.assertGreater(len(checkout_indexes), 0)
        for index in checkout_indexes:
            uses_indent = len(workflow[index]) - len(workflow[index].lstrip())
            step_indent = uses_indent - 2
            block: list[str] = []
            for line in workflow[index + 1 :]:
                stripped = line.lstrip()
                indent = len(line) - len(stripped)
                if stripped.startswith("- name:") and indent == step_indent:
                    break
                block.append(line)
            depths = [
                line.split(":", 1)[1].strip()
                for line in block
                if line.strip().startswith("fetch-depth:")
            ]
            self.assertEqual(
                len(depths),
                1,
                f"checkout at workflow line {index + 1} must set one fetch-depth",
            )
            self.assertIn(
                depths[0],
                {"2", "0"},
                f"checkout at workflow line {index + 1} must fetch the parent",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
