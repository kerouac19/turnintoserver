#!/bin/bash
# Shared by build-release.sh and release.sh; compatible with macOS Bash 3.2.
RELEASE_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

release_fail() { echo "Error: $*" >&2; exit 1; }

release_parameters() {
  VERSION="${1:-${VERSION:-}}"
  BUILD_NUMBER="${2:-${BUILD_NUMBER:-}}"
  python3 "$RELEASE_REPO_ROOT/scripts/distribution.py" validate-version "$VERSION" "$BUILD_NUMBER"
  RELEASE_BUILD_ROOT="${RELEASE_BUILD_ROOT:-$RELEASE_REPO_ROOT/build-release}"
  DIST_DIR="${DIST_DIR:-$RELEASE_REPO_ROOT/dist}"
  # Resolve paths before changing directory for checksums or invoking child scripts.
  RELEASE_BUILD_ROOT="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$RELEASE_BUILD_ROOT")"
  DIST_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$DIST_DIR")"
  RELEASE_BASE="turnintoserver-dev-$VERSION-b$BUILD_NUMBER-arm64"
}

release_require_identity() {
  case "${SIGN_IDENTITY:-}" in
    'Developer ID Application: '*) ;;
    *) release_fail 'Set SIGN_IDENTITY to the full Developer ID Application certificate name.' ;;
  esac
  if ! security find-identity -v -p codesigning | grep -F -- "\"$SIGN_IDENTITY\"" > /dev/null; then
    release_fail "No valid signing identity found: $SIGN_IDENTITY"
  fi
}

release_prepare() {
  RELEASE_NAME="$RELEASE_BASE-$1"
  mkdir -p "$DIST_DIR" "$RELEASE_BUILD_ROOT"
  for target in "$DIST_DIR/$RELEASE_NAME" "$DIST_DIR/$RELEASE_NAME.zip" "$DIST_DIR/$RELEASE_NAME.zip.sha256"; do
    [[ ! -e "$target" && ! -L "$target" ]] || release_fail "Output already exists; use a new build number or DIST_DIR: $target"
  done
  # This also reserves the artifact name against another simultaneous build.
  mkdir "$DIST_DIR/$RELEASE_NAME"
  PACKAGE_DIR="$DIST_DIR/$RELEASE_NAME"
  WORK_DIR="$(mktemp -d "$RELEASE_BUILD_ROOT/$RELEASE_NAME.XXXXXX")"
  APP_PATH="$PACKAGE_DIR/turnintoserver.app"
  echo "Build workspace: $WORK_DIR"
}

release_copy_notices() {
  local app="$1"
  mkdir -p "$app/Contents/Resources/ThirdParty"
  ditto "$RELEASE_REPO_ROOT/Licenses" "$app/Contents/Resources/ThirdParty/Licenses"
  cp "$RELEASE_REPO_ROOT/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/ThirdParty/"
  ditto "$RELEASE_REPO_ROOT/Licenses" "$PACKAGE_DIR/Licenses"
  cp "$RELEASE_REPO_ROOT/THIRD_PARTY_NOTICES.md" "$RELEASE_REPO_ROOT/INSTALL.md" "$PACKAGE_DIR/"
}

release_archive() {
  local temporary_dir
  temporary_dir="$(mktemp -d "$DIST_DIR/.package.XXXXXX")"
  ditto -c -k --keepParent "$PACKAGE_DIR" "$temporary_dir/$RELEASE_NAME.zip"
  (
    cd "$temporary_dir"
    shasum -a 256 "$RELEASE_NAME.zip" > "$RELEASE_NAME.zip.sha256"
  )
  # Never replace a previously published artifact, even when a name races us.
  mv -n "$temporary_dir/$RELEASE_NAME.zip" "$DIST_DIR/"
  [[ ! -e "$temporary_dir/$RELEASE_NAME.zip" ]] || release_fail 'ZIP output already exists.'
  mv -n "$temporary_dir/$RELEASE_NAME.zip.sha256" "$DIST_DIR/"
  [[ ! -e "$temporary_dir/$RELEASE_NAME.zip.sha256" ]] || release_fail 'Checksum output already exists.'
  rmdir "$temporary_dir"
  echo "App: $APP_PATH"
  echo "ZIP: $DIST_DIR/$RELEASE_NAME.zip"
  echo "SHA256: $DIST_DIR/$RELEASE_NAME.zip.sha256"
}
