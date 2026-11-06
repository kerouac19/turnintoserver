#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_ROOT="${BUILD_ROOT:-$PWD/build-dev}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
extra_flags=()
if [[ "${COMPILER_SUBPROCESS_SANDBOX:-YES}" == NO ]]; then
  extra_flags+=('OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -disable-sandbox')
fi
if [[ "${1:-}" == --signed && -z "${SIGN_IDENTITY:-}" ]]; then
  echo 'Set SIGN_IDENTITY to a stable code-signing identity for Accessibility / background-item testing.' >&2
  exit 2
fi
xcodebuild -project turnintoserver.xcodeproj -scheme turnintoserver -configuration Debug \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD_ROOT" \
  -disableAutomaticPackageResolution ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  "CODE_SIGN_IDENTITY=${SIGN_IDENTITY:--}" CODE_SIGN_STYLE=Manual \
  ${extra_flags[@]+"${extra_flags[@]}"} build
echo "App: $BUILD_ROOT/Build/Products/Debug/turnintoserver.app"
