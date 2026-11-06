#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/release-common.sh"

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  echo 'Usage: SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=... scripts/release.sh VERSION BUILD_NUMBER'
  exit 0
fi
[[ $# -le 2 ]] || release_fail 'Expected VERSION and BUILD_NUMBER.'
release_parameters "${1:-}" "${2:-}"
[[ -n "${NOTARY_PROFILE:-}" ]] || release_fail 'Set NOTARY_PROFILE to a notarytool Keychain profile.'
release_require_identity
release_prepare notarized
cd "$RELEASE_REPO_ROOT"

# Keep the unnotarized submission and diagnostics out of the final dist listing.
DIST_DIR="$WORK_DIR/submission" RELEASE_BUILD_ROOT="$RELEASE_BUILD_ROOT" \
  scripts/build-release.sh --signed "$VERSION" "$BUILD_NUMBER"
signed_name="$RELEASE_BASE-signed-unnotarized"
submission_zip="$WORK_DIR/submission/$signed_name.zip"
result_path="$WORK_DIR/notary-result.json"
submission_failed=0
xcrun notarytool submit "$submission_zip" --keychain-profile "$NOTARY_PROFILE" \
  --wait --output-format json > "$result_path" || submission_failed=1
# A successful CLI exit is insufficient: the service must explicitly accept it.
if ! submission_id="$(python3 scripts/distribution.py notary-result "$result_path")"; then
  release_fail "Notarization was not accepted; inspect $result_path (use notarytool log with its submission ID)."
fi
[[ "$submission_failed" == 0 ]] || release_fail "notarytool failed; inspect $result_path"

ditto "$WORK_DIR/submission/$signed_name" "$PACKAGE_DIR"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"
python3 scripts/distribution.py verify "$APP_PATH" --version "$VERSION" \
  --build-number "$BUILD_NUMBER" --signing-mode developer-id \
  --notary-result "$result_path" > "$PACKAGE_DIR/build-info.json"
release_archive
echo "Notarization: Accepted ($submission_id); ticket stapled and validated"
