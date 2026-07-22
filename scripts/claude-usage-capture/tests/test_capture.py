from __future__ import annotations

import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_DIRECTORY = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
FIXTURE_ROOT = REPOSITORY_ROOT / "app/PromptJuiceTests/Fixtures/Claude"
sys.path.insert(0, str(SCRIPT_DIRECTORY))

import capture_claude_usage
import sanitize_capture


class SanitizerTests(unittest.TestCase):
    def test_redacts_sensitive_shapes_and_preserves_parser_structure(self):
        raw = (
            b'\x1b[32m{"loggedIn":true,"authMethod":"oauth",'
            b'"apiProvider":"firstParty","subscriptionType":"max",'
            b'"email":"person@example.com","organizationId":"org_123456789",'
            b'"sessionToken":"sk-ant-1234567890abcdef",'
            b'"requestId":"123e4567-e89b-12d3-a456-426614174000",'
            b'"configPath":"/Users/example/.claude/settings.json"}\x1b[0m\n'
            b'Usage as of Nov 3, 2026 at 1:30 AM EST\n'
        )

        sanitized, report = sanitize_capture.sanitize_bytes(raw, usernames=("example",))

        self.assertIn(b'\x1b[32m', sanitized)
        self.assertIn(b'"loggedIn":true', sanitized)
        self.assertIn(b'"authMethod":"oauth"', sanitized)
        self.assertIn(b'"apiProvider":"firstParty"', sanitized)
        self.assertIn(b'"subscriptionType":"max"', sanitized)
        self.assertIn(b'Usage as of Nov 3, 2026 at 1:30 AM EST', sanitized)
        self.assertNotIn(b'person@example.com', sanitized)
        self.assertNotIn(b'org_123456789', sanitized)
        self.assertNotIn(b'sk-ant-1234567890abcdef', sanitized)
        self.assertNotIn(b'123e4567-e89b-12d3-a456-426614174000', sanitized)
        self.assertNotIn(b'/Users/example', sanitized)
        self.assertGreaterEqual(sum(report.replacements.values()), 5)

    def test_preserves_usage_command_and_twenty_four_hour_timestamp(self):
        raw = b"/usage\r\nAs of 2026-11-03 01:30:00 -0500\nSession 42% used\n"
        sanitized, _ = sanitize_capture.sanitize_bytes(raw, usernames=("sample-user",))
        self.assertEqual(sanitized, raw)

    def test_redacts_free_text_labels_and_bearer_credentials(self):
        raw = (
            b"Welcome back Example Person!\n"
            b"Account: Personal Workspace\n"
            b"Organization: Example Incorporated\n"
            b"Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456\n"
            b'16% of your usage came from MCP server "Private Tool"\n'
            b"MCP servers % of usage\nPrivate Tool 16%\nAnother Tool 12%\n"
        )
        sanitized, _ = sanitize_capture.sanitize_bytes(raw, usernames=("sample-user",))
        self.assertIn(b"Welcome back [REDACTED_USERNAME]!", sanitized)
        self.assertIn(b"Account: [REDACTED_FIELD]", sanitized)
        self.assertIn(b"Organization: [REDACTED_FIELD]", sanitized)
        self.assertNotIn(b"abcdefghijklmnopqrstuvwxyz123456", sanitized)
        self.assertNotIn(b"Private Tool", sanitized)
        self.assertNotIn(b"Another Tool", sanitized)

    def test_rejects_oversized_capture(self):
        with self.assertRaises(sanitize_capture.SanitizationError):
            sanitize_capture.sanitize_bytes(b"x" * (sanitize_capture.MAX_CAPTURE_BYTES + 1))

    def test_rejects_unexpected_sensitive_json_container(self):
        raw = b'{"loggedIn":true,"credentials":{"futureShape":"opaque"}}\n'
        with self.assertRaisesRegex(
            sanitize_capture.SanitizationError, "unexpected sensitive structure"
        ):
            sanitize_capture.sanitize_bytes(raw, usernames=("sample-user",))

    def test_sanitize_file_rejects_symlink_and_writes_mode_0600(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.write_text("2.1.211 (Claude Code)\n", encoding="utf-8")
            symlink = root / "source-link"
            symlink.symlink_to(source)
            with self.assertRaises(sanitize_capture.SanitizationError):
                sanitize_capture.sanitize_file(symlink, root / "rejected")

            output = root / "safe"
            sanitize_capture.sanitize_file(source, output)
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)


class CaptureHarnessTests(unittest.TestCase):
    def make_fake_cli(self, parent: Path) -> Path:
        fake = parent / "claude-fixture"
        fake.write_text(
            """#!/usr/bin/env python3
import sys
import time

if sys.argv[1:] == ["--version"]:
    print("2.1.211 (Claude Code)")
elif sys.argv[1:] == ["auth", "status"]:
    print('{"loggedIn":true,"authMethod":"oauth","apiProvider":"firstParty","subscriptionType":"max","email":"fixture@example.test"}')
else:
    print("ARGS=" + " ".join(sys.argv[1:]), flush=True)
    print("Claude Code ready", flush=True)
    received = sys.stdin.buffer.readline()
    print("RECEIVED=" + received.decode("utf-8", errors="replace").strip(), flush=True)
    print("Usage\\nSession 42% used\\nResets 3:14 PM", flush=True)
    time.sleep(2)
""",
            encoding="utf-8",
        )
        fake.chmod(0o700)
        return fake

    def test_fake_cli_capture_is_private_sanitized_and_sends_only_usage(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            parent.chmod(0o700)
            fake = self.make_fake_cli(parent)

            result = capture_claude_usage.run_capture(
                fake.resolve(), scratch_parent=parent, startup_delay=0.05, capture_duration=0.2
            )

            scratch = Path(result["scratchDirectory"])
            raw = Path(result["rawDirectory"])
            sanitized = Path(result["sanitizedDirectory"])
            self.assertEqual(stat.S_IMODE(scratch.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(raw.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(sanitized.stat().st_mode), 0o700)
            for name in capture_claude_usage.RAW_NAMES:
                self.assertEqual(stat.S_IMODE((raw / name).stat().st_mode), 0o600)

            usage_raw = (raw / "usage.raw").read_bytes()
            self.assertEqual(usage_raw.count(b"RECEIVED=/usage"), 1)
            self.assertNotIn(b"hi", usage_raw.lower())
            metadata = json.loads((scratch / "capture-metadata.json").read_text(encoding="utf-8"))
            self.assertEqual(metadata["writesToClaudePTY"], ["/usage\\r"])
            auth_sanitized = (sanitized / "auth-status.json").read_text(encoding="utf-8")
            self.assertIn("[REDACTED_FIELD]", auth_sanitized)
            self.assertNotIn("fixture@example.test", auth_sanitized)
            self.assertEqual(list((scratch / "controlled-workdir").iterdir()), [])

    def test_usage_retry_runs_only_usage_with_approved_trust_bypass(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            parent.chmod(0o700)
            fake = self.make_fake_cli(parent)

            result = capture_claude_usage.run_usage_retry(
                fake.resolve(), scratch_parent=parent, startup_delay=0.05, capture_duration=1.0
            )

            scratch = Path(result["scratchDirectory"])
            raw_directory = Path(result["rawDirectory"])
            self.assertEqual({path.name for path in raw_directory.iterdir()}, {"usage.raw"})
            usage_raw = (raw_directory / "usage.raw").read_text(
                encoding="utf-8", errors="replace"
            )
            self.assertIn("--dangerously-skip-permissions", usage_raw)
            self.assertEqual(usage_raw.count("RECEIVED=/usage"), 1)
            metadata = json.loads((scratch / "capture-metadata.json").read_text(encoding="utf-8"))
            self.assertEqual(len(metadata["commands"]), 1)
            self.assertIn("--dangerously-skip-permissions", metadata["commands"][0])
            self.assertEqual(metadata["writesToClaudePTY"], ["/usage\\r"])

    def test_trusted_fixture_exception_uses_approved_cwd_without_bypass_flag(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            parent.chmod(0o700)
            fake = self.make_fake_cli(parent)
            trusted = parent / "trusted-checkout"
            trusted.mkdir(mode=0o700)

            result = capture_claude_usage.run_usage_retry(
                fake.resolve(),
                scratch_parent=parent,
                startup_delay=0.05,
                capture_duration=1.0,
                trusted_working_directory=trusted,
            )

            usage_raw = (Path(result["rawDirectory"]) / "usage.raw").read_text(
                encoding="utf-8", errors="replace"
            )
            self.assertNotIn("--dangerously-skip-permissions", usage_raw)
            self.assertEqual(usage_raw.count("RECEIVED=/usage"), 1)
            self.assertEqual(
                result["workingDirectoryPolicy"], "explicit-trusted-fixture-exception"
            )


class FixtureInventoryTests(unittest.TestCase):
    REQUIRED_COVERAGE = {
        "usage-session-only",
        "usage-session-plus-weekly",
        "usage-model-specific-weekly",
        "usage-zero-percent",
        "usage-ansi-residue",
        "usage-truncated",
        "usage-malformed",
        "cached-bars-F-RL1",
        "cached-bars-F-RL2",
        "cached-bars-F-RL3",
        "cached-bars-F-RL4",
        "timestamp-12-hour",
        "timestamp-24-hour",
        "timestamp-timezone",
        "timestamp-dst-spring",
        "timestamp-dst-fall-first",
        "timestamp-dst-fall-second",
        "timestamp-ansi-residue",
        "timestamp-malformed",
        "auth-subscription",
        "auth-first-party-api-billing",
        "auth-external-bedrock",
        "auth-external-vertex",
        "auth-external-foundry",
        "auth-external-gateway",
        "auth-signed-out-initial",
        "auth-reauth-expired",
        "auth-reauth-revoked",
        "auth-additive-harmless-fields",
        "auth-missing-required-fields",
        "auth-unknown-auth-method",
        "auth-unknown-api-provider",
        "auth-unknown-subscription-type",
        "version-current",
        "version-minimum-2.1.208",
        "version-below-minimum",
        "version-older",
        "version-prefixed",
        "version-malformed",
        "provenance-native",
        "provenance-homebrew-apple-silicon",
        "provenance-homebrew-intel",
        "provenance-npm-global",
        "provenance-custom-symlink",
        "provenance-unknown",
        "cooldown-corrupt-nextAttemptAt",
        "probe-snapshot-and-backoff",
        "auth-subscription-real-shape",
        "usage-flat-real-shape",
        "usage-real-redraws",
        "usage-real-timezone-reset",
        "usage-real-model-specific-weekly",
        "version-real-shape",
    }

    def test_manifest_is_complete_and_declares_zero_third_party_material(self):
        manifest = json.loads((FIXTURE_ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(
            manifest["provenance"], "independently-authored-synthetic-and-sanitized-real"
        )
        self.assertFalse(manifest["thirdPartyMaterialImported"])

        entries = manifest["fixtures"]
        listed = {entry["path"] for entry in entries}
        actual = {
            str(path.relative_to(FIXTURE_ROOT))
            for path in FIXTURE_ROOT.rglob("*")
            if path.is_file()
            and path.name not in {"README.md", "manifest.json", "provenance.json"}
        }
        self.assertEqual(listed, actual)
        coverage = {item for entry in entries for item in entry["covers"]}
        self.assertTrue(self.REQUIRED_COVERAGE.issubset(coverage))

    def test_general_fixtures_have_no_sensitive_shapes(self):
        manifest = json.loads((FIXTURE_ROOT / "manifest.json").read_text(encoding="utf-8"))
        for entry in manifest["fixtures"]:
            if entry["path"].startswith("Provenance/"):
                continue
            path = FIXTURE_ROOT / entry["path"]
            text = path.read_bytes().decode("utf-8", errors="surrogateescape")
            self.assertEqual(
                sanitize_capture.sensitive_findings(text, usernames=("fixture-user",)),
                [],
                entry["path"],
            )

    def test_provenance_paths_are_fictional_and_ansi_cases_contain_real_escape_bytes(self):
        provenance = (FIXTURE_ROOT / "Provenance/outcomes.json").read_text(encoding="utf-8")
        self.assertIn("/Users/fixture/", provenance)
        self.assertNotIn(os.environ.get("USER", "local-user-placeholder"), provenance)
        self.assertIn(b"\x1b[", (FIXTURE_ROOT / "Usage/ansi-residue.ans").read_bytes())
        self.assertIn(b"\x1b[", (FIXTURE_ROOT / "Usage/as-of-ansi-residue.ans").read_bytes())


if __name__ == "__main__":
    unittest.main()
