#!/usr/bin/env python3
"""Validate the final distribution bundle without launching it or its services."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import uuid

REPO_ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "com.local.macutils.turnintoserver.dev"
AGENT_NAME = BUNDLE_ID + ".power-guard"
NOTICE_FILES = ("THIRD_PARTY_NOTICES.md", "Licenses/Unplug-MIT.txt", "Licenses/Vorssaint-GPL-3.0.txt")


class DistributionError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise DistributionError(message)


def validate_versions(version, build):
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) is not None,
            "VERSION must contain three decimal components, for example 0.1.0.")
    require(re.fullmatch(r"[1-9][0-9]{0,3}", build) is not None,
            "BUILD_NUMBER must be a positive integer from 1 to 9999.")


def accepted_submission(path):
    result = json.loads(Path(path).read_text())
    require(isinstance(result, dict), "Invalid notarization response: expected an object.")
    require(result.get("status") == "Accepted",
            "Notarization not accepted: status=%s, id=%s" % (result.get("status"), result.get("id")))
    submission_id = result.get("id")
    try:
        uuid.UUID(submission_id)
    except (ValueError, TypeError, AttributeError):
        raise DistributionError("Accepted notarization response has no valid submission ID.")
    return submission_id


def checked_output(command):
    process = subprocess.run(command, capture_output=True, check=False)
    if process.returncode:
        raise DistributionError("%s failed: %s" % (command[0], process.stderr.decode(errors="replace")[-3000:]))
    return process.stdout, process.stderr


def load_plist(path):
    with Path(path).open("rb") as handle:
        value = plistlib.load(handle)
    require(isinstance(value, dict), "Expected plist dictionary: %s" % path)
    return value


def verify_structure(app, version, build):
    validate_versions(version, build)
    info = load_plist(app / "Contents/Info.plist")
    expected = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleExecutable": "turnintoserver",
        "CFBundleDisplayName": "turnintoserver Dev",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "LSMinimumSystemVersion": "13.0",
        "LSUIElement": True,
    }
    for key, value in expected.items():
        require(info.get(key) == value, "Unexpected %s: %r (expected %r)" % (key, info.get(key), value))
    executable = app / "Contents/MacOS/turnintoserver"
    require(executable.is_file() and os.access(executable, os.X_OK), "Main executable is missing or not executable.")
    agents_dir = app / "Contents/Library/LaunchAgents"
    agent_path = agents_dir / (AGENT_NAME + ".plist")
    require(sorted(p.name for p in agents_dir.glob("*.plist")) == [agent_path.name], "Unexpected LaunchAgent files.")
    agent = load_plist(agent_path)
    expected_agent = {
        "Label": AGENT_NAME,
        "BundleProgram": "Contents/MacOS/turnintoserver",
        "ProgramArguments": ["turnintoserver", "--power-guard"],
        "AssociatedBundleIdentifiers": [BUNDLE_ID],
        "RunAtLoad": True,
        "KeepAlive": True,
        "LimitLoadToSessionType": "Aqua",
    }
    for key, value in expected_agent.items():
        require(agent.get(key) == value, "Unexpected LaunchAgent %s: %r" % (key, agent.get(key)))
    require("Program" not in agent, "LaunchAgent must use bundle-relative BundleProgram.")
    for name in NOTICE_FILES:
        source = REPO_ROOT / name
        embedded = app / "Contents/Resources/ThirdParty" / name
        require(embedded.is_file() and embedded.read_bytes() == source.read_bytes(), "Missing or changed embedded notice: " + name)
    return executable


def verify_signature(app, mode):
    checked_output(["codesign", "--verify", "--deep", "--strict", str(app)])
    _, details_bytes = checked_output(["codesign", "--display", "--verbose=4", str(app)])
    details = details_bytes.decode(errors="replace")
    require(re.search(r"flags=.*\([^\n]*runtime", details) is not None, "Hardened runtime is not enabled.")
    if mode == "adhoc":
        require("Signature=adhoc" in details, "Expected an ad-hoc signature.")
    else:
        require("Authority=Developer ID Application:" in details, "Expected a Developer ID Application signature.")
        require(re.search(r"^Timestamp=.+", details, re.MULTILINE) is not None, "Secure timestamp is missing.")
        require(re.search(r"^TeamIdentifier=(?!not set).+", details, re.MULTILINE) is not None, "Signing team is missing.")
    try:
        entitlements_bytes, _ = checked_output(["codesign", "--display", "--entitlements", "-", "--xml", str(app)])
    except DistributionError:
        # Older codesign versions lack --xml and use the legacy stdout path.
        entitlements_bytes, _ = checked_output(["codesign", "--display", "--entitlements", ":-", str(app)])
    entitlements = plistlib.loads(entitlements_bytes)
    require(isinstance(entitlements, dict), "Expected an entitlements dictionary.")
    require(entitlements.get("com.apple.security.automation.apple-events") is True, "Apple Events entitlement is missing.")
    require(entitlements.get("com.apple.security.get-task-allow") is not True, "Debug entitlement get-task-allow is enabled.")
    require(entitlements.get("com.apple.security.app-sandbox") is not True, "Unexpected App Sandbox entitlement.")


def verify(app, version, build, mode, notary_result=None):
    executable = verify_structure(app, version, build)
    architectures, _ = checked_output(["lipo", "-archs", str(executable)])
    require(architectures.decode().split() == ["arm64"], "Expected an arm64-only executable.")
    build_info, _ = checked_output(["xcrun", "vtool", "-show-build", str(executable)])
    require(re.search(r"\bminos\s+13\.0(?:\s|$)", build_info.decode()) is not None,
            "Mach-O minimum system version is not macOS 13.0.")
    verify_signature(app, mode)
    commit, _ = checked_output(["git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"])
    dirty, _ = checked_output(["git", "-C", str(REPO_ROOT), "status", "--porcelain"])
    manifest = {
        "application": app.name,
        "bundle_identifier": BUNDLE_ID,
        "version": version,
        "build_number": build,
        "architecture": "arm64",
        "minimum_system_version": "13.0",
        "signing_mode": mode,
        "notarization": "not-submitted",
        "source_commit": commit.decode().strip(),
        "source_has_uncommitted_changes": bool(dirty.strip()),
        "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "verified_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    if notary_result:
        require(mode == "developer-id", "An ad-hoc package cannot be marked notarized.")
        manifest["notarization"] = "Accepted"
        manifest["notarization_id"] = accepted_submission(notary_result)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    version_parser = commands.add_parser("validate-version")
    version_parser.add_argument("version")
    version_parser.add_argument("build_number")
    notary_parser = commands.add_parser("notary-result")
    notary_parser.add_argument("path", type=Path)
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("app", type=Path)
    verify_parser.add_argument("--version", required=True)
    verify_parser.add_argument("--build-number", required=True)
    verify_parser.add_argument("--signing-mode", choices=("adhoc", "developer-id"), required=True)
    verify_parser.add_argument("--notary-result", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "validate-version":
            validate_versions(args.version, args.build_number)
        elif args.command == "notary-result":
            print(accepted_submission(args.path))
        else:
            print(json.dumps(verify(args.app, args.version, args.build_number, args.signing_mode, args.notary_result), indent=2))
    except (DistributionError, OSError, ValueError, plistlib.InvalidFileException) as error:
        print("Error: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
