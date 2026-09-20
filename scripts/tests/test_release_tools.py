"""Release safety regressions using a disposable repo and fake Flutter, never signing."""

import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
PROJECT_REF = "imtbyrvsonzvtddswbtb"
PUBLIC_KEY = "sb_publishable_" + "releaseFixturePublicKey" * 2


class ReleaseToolsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="workloop-release-test-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        (self.repo / "scripts").mkdir()
        (self.repo / "bin").mkdir()
        for name in ("qa_signed_builds.sh", "qa_release_candidate.sh", "release_config.py"):
            shutil.copy2(SCRIPTS / name, self.repo / "scripts" / name)
        (self.repo / "scripts/dev_env.sh").write_text(":\n")
        (self.repo / "pubspec.yaml").write_text("name: workloop\nversion: 1.0.0+10\n")
        (self.repo / ".gitignore").write_text("/build/\n.env\n")
        flutter = self.repo / "bin/flutter"
        flutter.write_text('''#!/usr/bin/env python3
import json, os, plistlib, sys, zipfile
from pathlib import Path
args = sys.argv[1:]
if args == ['--version']:
    print('Flutter test fixture'); sys.exit(0)
assert args[:1] == ['build'], args
out = Path('build'); out.mkdir(exist_ok=True)
with open(out / 'fake-calls.jsonl', 'a') as f:
    f.write(json.dumps(args) + '\\n')
defines_path = next(a.split('=', 1)[1] for a in args if a.startswith('--dart-define-from-file='))
defines = json.loads(Path(defines_path).read_text())
(out / 'fake-capability.json').write_text(json.dumps({'payments': defines['PAYMENT_COLLECTION_ENABLED'], 'tap_to_pay': defines['TAP_TO_PAY_ENABLED'], 'crash_reporting': defines['WORKLOOP_CRASH_REPORTING_ENABLED'], 'subscriptions': defines['WORKLOOP_SUBSCRIPTIONS_ENABLED'], 'url': defines['SUPABASE_URL']}))
assert not any('ci-public-anon-key' in a or 'example.supabase.co' in a for a in args)
if args[1] == 'ipa':
    options_path = next(a.split('=', 1)[1] for a in args if a.startswith('--export-options-plist='))
    options = plistlib.loads(Path(options_path).read_bytes())
    assert options['destination'] == 'export'
    assert options['manageAppVersionAndBuildNumber'] is False
    path = out / 'ios/ipa/Workloop.ipa'; path.parent.mkdir(parents=True)
    name = next(a.split('=', 1)[1] for a in args if a.startswith('--build-name='))
    number = next(a.split('=', 1)[1] for a in args if a.startswith('--build-number='))
    if os.environ.get('FAKE_WRONG_VERSION'): number = '999'
    with zipfile.ZipFile(path, 'w') as archive:
        info = {'CFBundleIdentifier': 'com.ismaeel.workloop', 'CFBundleShortVersionString': name, 'CFBundleVersion': number, 'NSLocationWhenInUseUsageDescription': 'Foreground weather', 'NSLocationAlwaysAndWhenInUseUsageDescription': 'Foreground weather only. No background tracking.'}
        if os.environ.get('FAKE_MISSING_LOCATION_PURPOSE'): del info['NSLocationAlwaysAndWhenInUseUsageDescription']
        if os.environ.get('FAKE_BACKGROUND_LOCATION'): info['UIBackgroundModes'] = ['location']
        archive.writestr('Payload/Runner.app/Info.plist', plistlib.dumps(info))
else:
    path = out / 'app/outputs/bundle/release/app-release.aab'; path.parent.mkdir(parents=True)
    path.write_bytes(b'fixture-aab')
''')
        flutter.chmod(0o755)
        uname = self.repo / "bin/uname"
        uname.write_text("#!/bin/sh\necho Darwin\n")
        uname.chmod(0o755)
        self.env = {**os.environ, "PATH": f"{self.repo / 'bin'}:{os.environ['PATH']}"}
        for key in list(self.env):
            if key.startswith("RELEASE_"):
                del self.env[key]
        self.env.update({
            "RELEASE_DEFINES_FILE": str(self.repo / ".env"),
            "RELEASE_PAYMENT_COLLECTION_ENABLED": "true",
            "RELEASE_PLATFORMS": "ios",
        })
        for args in (["init", "-q"], ["add", "."], ["-c", "user.name=Release Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture"]):
            subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True)
        self.write_config()

    def write_config(self, **overrides):
        config = {"SUPABASE_URL": f"https://{PROJECT_REF}.supabase.co", "SUPABASE_PUBLISHABLE_KEY": PUBLIC_KEY}
        config.update(overrides)
        (self.repo / ".env").write_text(json.dumps(config))

    def run_release(self):
        return subprocess.run(["bash", "scripts/qa_signed_builds.sh"], cwd=self.repo, env=self.env, capture_output=True, text=True)

    def assert_blocked(self):
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.repo / "build/fake-calls.jsonl").exists())
        self.assertNotIn(PUBLIC_KEY, result.stdout + result.stderr)
        return result

    def test_missing_release_file_fails_before_build(self):
        (self.repo / ".env").unlink()
        self.assert_blocked()

    def test_placeholder_backend_fails_before_build(self):
        self.write_config(SUPABASE_URL="https://example.supabase.co")
        self.assert_blocked()

    def test_privileged_key_and_unknown_secrets_are_rejected_without_echo(self):
        encoded = base64.urlsafe_b64encode(json.dumps({"role": "service_role", "ref": PROJECT_REF}).encode()).decode().rstrip("=")
        key = f"header.{encoded}.signature"
        self.write_config(SUPABASE_PUBLISHABLE_KEY=key)
        result = self.assert_blocked()
        self.assertNotIn(key, result.stdout + result.stderr)
        self.write_config(STRIPE_SECRET_KEY="never-print-this")
        result = self.assert_blocked()
        self.assertNotIn("never-print-this", result.stdout + result.stderr)

    def test_payment_choice_required_and_cannot_conflict(self):
        del self.env["RELEASE_PAYMENT_COLLECTION_ENABLED"]
        self.assert_blocked()
        self.env["RELEASE_PAYMENT_COLLECTION_ENABLED"] = "true"
        self.write_config(PAYMENT_COLLECTION_ENABLED=False)
        self.assert_blocked()

    def test_store_config_rejects_sandbox_apns(self):
        self.write_config(APNS_ENVIRONMENT="sandbox")
        self.assert_blocked()

    def test_tap_to_pay_cannot_be_enabled_for_this_candidate(self):
        self.write_config(TAP_TO_PAY_ENABLED=True)
        self.assert_blocked()

    def test_crash_reporting_explicit_false_is_preserved_for_rollback(self):
        self.write_config(WORKLOOP_CRASH_REPORTING_ENABLED=False)
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(json.loads((self.repo / 'build/fake-capability.json').read_text())['crash_reporting'])
        provenance = (self.repo / 'build/release/release-provenance.txt').read_text()
        self.assertIn('crash_reporting_enabled=false', provenance)

    def test_crash_reporting_invalid_values_fail_before_build(self):
        for value in [1, None, [], 'yes', 'true;echo private']:
            with self.subTest(value=value):
                self.write_config(WORKLOOP_CRASH_REPORTING_ENABLED=value)
                self.assert_blocked()

    def test_subscriptions_enabled_for_release(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(json.loads((self.repo / 'build/fake-capability.json').read_text())['subscriptions'])
        self.assertIn('subscriptions_enabled=true', (self.repo / 'build/release/release-provenance.txt').read_text())

    def test_subscription_rollback_flag_is_preserved(self):
        self.write_config(WORKLOOP_SUBSCRIPTIONS_ENABLED=False)
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(json.loads((self.repo / 'build/fake-capability.json').read_text())['subscriptions'])

    def test_invalid_subscription_flags_fail_before_build(self):
        for value in [1, None, [], 'yes', 'true;echo private']:
            with self.subTest(value=value):
                self.write_config(WORKLOOP_SUBSCRIPTIONS_ENABLED=value)
                self.assert_blocked()

    def test_test_crash_and_debug_flags_cannot_enter_store_configuration(self):
        for key in ['WORKLOOP_CRASH_REPORTING_TEST_MODE', 'WORKLOOP_CRASH_DIAGNOSTICS', 'FORCE_TEST_CRASH', 'DEBUG']:
            with self.subTest(key=key):
                self.write_config(**{key: True})
                self.assert_blocked()

    def test_old_archive_preserved_even_when_no_ipa_exists(self):
        old = self.repo / "build/ios/archive/Runner.xcarchive"
        old.mkdir(parents=True)
        (old / "sentinel").write_text("build9")
        self.assert_blocked()
        self.assertEqual((old / "sentinel").read_text(), "build9")

    def test_dirty_source_cannot_be_signed(self):
        (self.repo / "unreviewed.dart").write_text("unreviewed")
        self.assert_blocked()

    def test_ios_only_records_actual_identity_without_keys(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in (self.repo / "build/fake-calls.jsonl").read_text().splitlines()]
        self.assertEqual([args[1] for args in calls], ["ipa"])
        self.assertIn("--build-number=10", calls[0])
        self.assertIn("--build-name=1.0.0", calls[0])
        self.assertTrue(json.loads((self.repo / "build/fake-capability.json").read_text())["payments"])
        self.assertFalse(json.loads((self.repo / "build/fake-capability.json").read_text())["tap_to_pay"])
        self.assertTrue(json.loads((self.repo / "build/fake-capability.json").read_text())["crash_reporting"])
        provenance = (self.repo / "build/release/release-provenance.txt").read_text()
        self.assertIn("pubspec_version=1.0.0+10", provenance)
        self.assertIn("payment_collection_enabled=true", provenance)
        self.assertIn("apns_environment=production", provenance)
        self.assertIn("tap_to_pay_enabled=false", provenance)
        self.assertIn("crash_reporting_enabled=true", provenance)
        self.assertIn("artifact_sha256=", provenance)
        self.assertNotIn(PUBLIC_KEY, provenance + result.stdout + result.stderr)
        defines_path = next(arg.split("=", 1)[1] for arg in calls[0] if arg.startswith("--dart-define-from-file="))
        self.assertFalse(Path(defines_path).exists(), "private snapshot must be removed")

    def test_android_only_does_not_touch_ios_archive(self):
        self.env["RELEASE_PLATFORMS"] = "android"
        old = self.repo / "build/ios/archive/Runner.xcarchive"
        old.mkdir(parents=True)
        self.env["RELEASE_PAYMENT_COLLECTION_ENABLED"] = "false"
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in (self.repo / "build/fake-calls.jsonl").read_text().splitlines()]
        self.assertEqual([args[1] for args in calls], ["appbundle"])
        self.assertFalse(json.loads((self.repo / "build/fake-capability.json").read_text())["payments"])
        self.assertTrue(old.exists())

    def test_rewritten_ipa_version_cannot_receive_artifact_provenance(self):
        self.env["FAKE_WRONG_VERSION"] = "true"
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        provenance = (self.repo / "build/release/release-provenance.txt").read_text()
        self.assertNotIn("artifact_sha256=", provenance)

    def test_missing_location_purpose_cannot_receive_artifact_provenance(self):
        self.env["FAKE_MISSING_LOCATION_PURPOSE"] = "true"
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing a required location purpose string", result.stderr)
        self.assertNotIn("artifact_sha256=", (self.repo / "build/release/release-provenance.txt").read_text())

    def test_background_location_cannot_enter_release(self):
        self.env["FAKE_BACKGROUND_LOCATION"] = "true"
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not support background location", result.stderr)


if __name__ == "__main__":
    unittest.main()
