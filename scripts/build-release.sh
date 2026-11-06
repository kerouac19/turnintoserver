#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/release-common.sh"

usage() {
  echo 'Usage: scripts/build-release.sh --ad-hoc|--signed VERSION BUILD_NUMBER'
  echo 'VERSION / BUILD_NUMBER may alternatively be supplied as environment variables.'
}
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --ad-hoc) signing_mode=adhoc; artifact_mode=adhoc ;;
  --signed) signing_mode=developer-id; artifact_mode=signed-unnotarized ;;
  *) usage >&2; exit 2 ;;
esac
shift
[[ $# -le 2 ]] || { usage >&2; exit 2; }
release_parameters "${1:-}" "${2:-}"
if [[ "$signing_mode" == developer-id ]]; then release_require_identity; fi
release_prepare "$artifact_mode"
cd "$RELEASE_REPO_ROOT"

extra_flags=()
if [[ "${COMPILER_SUBPROCESS_SANDBOX:-YES}" == NO ]]; then
  extra_flags+=('OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -disable-sandbox')
fi
# The final bundle (including notices) is signed below, after all writes.
if ! xcodebuild -project turnintoserver.xcodeproj -scheme turnintoserver \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$WORK_DIR/DerivedData" -disableAutomaticPackageResolution \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  "MARKETING_VERSION=$VERSION" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
  ${extra_flags[@]+"${extra_flags[@]}"} build > "$WORK_DIR/xcodebuild.log" 2>&1; then
  tail -n 60 "$WORK_DIR/xcodebuild.log" >&2
  release_fail "Release build failed; see $WORK_DIR/xcodebuild.log"
fi
ditto "$WORK_DIR/DerivedData/Build/Products/Release/turnintoserver.app" "$APP_PATH"
release_copy_notices "$APP_PATH"
signing_flags=(--force --options runtime --entitlements "$RELEASE_REPO_ROOT/turnintoserver/turnintoserver.entitlements")
if [[ "$signing_mode" == developer-id ]]; then
  codesign "${signing_flags[@]}" --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
else
  codesign "${signing_flags[@]}" --sign - "$APP_PATH"
fi
python3 scripts/distribution.py verify "$APP_PATH" --version "$VERSION" \
  --build-number "$BUILD_NUMBER" --signing-mode "$signing_mode" > "$PACKAGE_DIR/build-info.json"
release_archive
echo "Signing: $signing_mode; notarization: not submitted"
