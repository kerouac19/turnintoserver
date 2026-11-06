"""Distribution boundaries and failure paths; never launch the app or change system settings."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("distribution", ROOT / "scripts/distribution.py")
distribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribution)
SUBMISSION_ID = "12345678-1234-1234-1234-123456789abc"


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="turnintoserver-distribution-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def make_app(self):
        app = self.root / "turnintoserver.app"
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        info = distribution.load_plist(ROOT / "turnintoserver/Info.plist")
        info.update(CFBundleExecutable="turnintoserver", CFBundleIdentifier=distribution.BUNDLE_ID,
                    CFBundleShortVersionString="0.1.0", CFBundleVersion="1", LSMinimumSystemVersion="13.0")
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        executable = contents / "MacOS/turnintoserver"
        executable.write_bytes(b"fixture only; never executed")
        executable.chmod(0o755)
        agents = contents / "Library/LaunchAgents"
        agents.mkdir(parents=True)
        shutil.copy(ROOT / "turnintoserver/PowerGuard" / (distribution.AGENT_NAME + ".plist"), agents)
        for name in distribution.NOTICE_FILES:
            destination = contents / "Resources/ThirdParty" / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / name, destination)
        return app

    def test_rejects_invalid_version_and_shell_input(self):
        for version, build in (("1.0", "1"), ("1.0.0;touch bad", "1"), ("1.0.0", "0"),
                               ("1.0.0", "10000"), ("1.0.0", "$(whoami)")):
            with self.subTest(version=version, build=build), self.assertRaises(distribution.DistributionError):
                distribution.validate_versions(version, build)

    def test_notarization_requires_accepted_and_valid_id(self):
        result_path = self.root / "result.json"
        for response in ({"status": "Invalid", "id": SUBMISSION_ID}, {"status": "In Progress", "id": SUBMISSION_ID},
                         {"status": "Accepted"}, {"status": "Accepted", "id": "not-an-id"}, []):
            result_path.write_text(json.dumps(response))
            with self.subTest(response=response), self.assertRaises(distribution.DistributionError):
                distribution.accepted_submission(result_path)
        result_path.write_text(json.dumps({"status": "Accepted", "id": SUBMISSION_ID}))
        self.assertEqual(distribution.accepted_submission(result_path), SUBMISSION_ID)

    def test_valid_bundle_structure(self):
        app = self.make_app()
        self.assertEqual(distribution.verify_structure(app, "0.1.0", "1"), app / "Contents/MacOS/turnintoserver")

    def test_wrong_version_is_not_hidden_by_zip_filename(self):
        app = self.make_app()
        with self.assertRaisesRegex(distribution.DistributionError, "CFBundleShortVersionString"):
            distribution.verify_structure(app, "0.2.0", "1")

    def test_mismatched_agent_identity_is_rejected(self):
        app = self.make_app()
        path = app / "Contents/Library/LaunchAgents" / (distribution.AGENT_NAME + ".plist")
        agent = distribution.load_plist(path)
        agent["AssociatedBundleIdentifiers"] = ["com.qianyushi.turnintoserver"]
        path.write_bytes(plistlib.dumps(agent))
        with self.assertRaisesRegex(distribution.DistributionError, "AssociatedBundleIdentifiers"):
            distribution.verify_structure(app, "0.1.0", "1")

    def test_missing_embedded_license_is_rejected(self):
        app = self.make_app()
        (app / "Contents/Resources/ThirdParty/Licenses/Unplug-MIT.txt").unlink()
        with self.assertRaisesRegex(distribution.DistributionError, "notice"):
            distribution.verify_structure(app, "0.1.0", "1")

    def test_signed_mode_without_certificate_never_builds(self):
        environment = dict(os.environ, SIGN_IDENTITY="", DIST_DIR=str(self.root / "dist"))
        result = subprocess.run(["bash", str(ROOT / "scripts/build-release.sh"), "--signed", "0.1.0", "1"],
                                env=environment, capture_output=True, text=True, timeout=15)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SIGN_IDENTITY", result.stderr)
        self.assertFalse((self.root / "dist").exists())

    def test_existing_output_is_preserved(self):
        destination = self.root / "dist/turnintoserver-dev-0.1.0-b1-arm64-adhoc"
        destination.mkdir(parents=True)
        marker = destination / "preserve.txt"
        marker.write_text("existing build")
        environment = dict(os.environ, DIST_DIR=str(destination.parent), RELEASE_BUILD_ROOT=str(self.root / "work"))
        result = subprocess.run(["bash", str(ROOT / "scripts/build-release.sh"), "--ad-hoc", "0.1.0", "1"],
                                env=environment, capture_output=True, text=True, timeout=15)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Output already exists", result.stderr)
        self.assertEqual(marker.read_text(), "existing build")

    def run_notary_driver(self, status, exit_code=0):
        """Use the real release driver/parser with fake upload/signing tools; no credentials or network."""
        scripts = self.root / "repo/scripts"
        scripts.mkdir(parents=True)
        for name in ("release.sh", "release-common.sh", "distribution.py"):
            shutil.copy(ROOT / "scripts" / name, scripts)
        builder = scripts / "build-release.sh"
        builder.write_text('''#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/release-common.sh"
release_parameters "$2" "$3"
name="$RELEASE_BASE-signed-unnotarized"
mkdir -p "$DIST_DIR/$name/turnintoserver.app"
touch "$DIST_DIR/$name.zip"
''')
        builder.chmod(0o755)
        binaries = self.root / "bin"
        binaries.mkdir()
        security = binaries / "security"
        security.write_text('#!/bin/sh\necho \' 1) fixture "Developer ID Application: Fixture (TEAMID)"\'\n')
        security.chmod(0o755)
        xcrun = binaries / "xcrun"
        xcrun.write_text('''#!%s
import json, os, sys
from pathlib import Path
with open(os.environ["TEST_TOOL_LOG"], "a") as log:
    log.write(" ".join(sys.argv[1:3]) + "\\n")
if sys.argv[1:3] == ["notarytool", "submit"]:
    print(json.dumps({"status": os.environ["TEST_NOTARY_STATUS"], "id": "%s"}))
    sys.exit(int(os.environ["TEST_NOTARY_EXIT"]))
sys.exit(10)  # Simulate a failed stapler; no real signature or service is invoked.
''' % (sys.executable, SUBMISSION_ID))
        xcrun.chmod(0o755)
        environment = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ["PATH"],
                           SIGN_IDENTITY="Developer ID Application: Fixture (TEAMID)", NOTARY_PROFILE="fixture",
                           DIST_DIR=str(self.root / "dist"), RELEASE_BUILD_ROOT=str(self.root / "work"),
                           TEST_TOOL_LOG=str(self.root / "tool.log"), TEST_NOTARY_STATUS=status,
                           TEST_NOTARY_EXIT=str(exit_code))
        result = subprocess.run(["bash", str(scripts / "release.sh"), "0.1.0", "1"],
                                env=environment, capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list((self.root / "dist").glob("*.zip")), [])
        return (self.root / "tool.log").read_text()

    def test_rejected_notarization_never_staples_or_publishes(self):
        self.assertEqual(self.run_notary_driver("Invalid"), "notarytool submit\n")

    def test_failed_notary_command_never_publishes_even_if_json_says_accepted(self):
        self.assertEqual(self.run_notary_driver("Accepted", exit_code=1), "notarytool submit\n")

    def test_failed_stapler_never_publishes(self):
        self.assertEqual(self.run_notary_driver("Accepted"), "notarytool submit\nstapler staple\n")


if __name__ == "__main__":
    unittest.main()
