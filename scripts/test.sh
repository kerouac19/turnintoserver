#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TEST_ROOT=$(mktemp -d /tmp/turnintoserver-tests.XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos13 \
  -module-cache-path "$TEST_ROOT/modules" \
  turnintoserver/AppIdentity.swift \
  turnintoserver/Models.swift \
  turnintoserver/ShellRunner.swift \
  turnintoserver/AutomationManagers.swift \
  turnintoserver/Display/DisplaySafetyPolicy.swift \
  turnintoserver/CleaningMode/CleaningUnlockCounter.swift \
  turnintoserver/CleaningMode/CleaningMouseReleaseGate.swift \
  turnintoserver/CleaningMode/CleaningHealthMonitor.swift \
  turnintoserver/PowerGuard/PowerLeaseEngine.swift \
  turnintoserver/PowerGuard/LeaseContactMonitor.swift \
  Tests/IntegrationTests.swift -o "$TEST_ROOT/integration-tests"
"$TEST_ROOT/integration-tests"
