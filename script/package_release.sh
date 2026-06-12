#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-unsigned}"
APP_NAME="LinguistMac"
BUNDLE_ID="com.peerapatj.LinguistMac"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ENTITLEMENTS="$ROOT_DIR/Configuration/LinguistMac/LinguistMac.entitlements"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$MODE.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$MODE.dmg"
PACKAGE_DERIVED_DATA_PATH="${PACKAGE_DERIVED_DATA_PATH:-/private/tmp/linguistmac-release-xcode}"

cd "$ROOT_DIR"
mkdir -p "$RELEASE_DIR"

case "$MODE" in
  unsigned)
    CONFIGURATION=Release \
      CODE_SIGNING_ALLOWED=NO \
      DERIVED_DATA_PATH="$PACKAGE_DERIVED_DATA_PATH" \
      ./script/build_and_run.sh --package
    ;;
  signed)
    CONFIGURATION=Release \
      CODE_SIGNING_ALLOWED=NO \
      DERIVED_DATA_PATH="$PACKAGE_DERIVED_DATA_PATH" \
      ./script/build_and_run.sh --package
    : "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the Developer ID Application certificate name.}"
    /usr/bin/codesign \
      --force \
      --options runtime \
      --timestamp \
      --entitlements "$ENTITLEMENTS" \
      --sign "$DEVELOPER_ID_APPLICATION" \
      "$APP_BUNDLE"

    ;;
  *)
    echo "usage: $0 [unsigned|signed]" >&2
    exit 2
    ;;
esac

/usr/bin/codesign --verify --strict --verbose=2 "$APP_BUNDLE" || {
  if [[ "$MODE" == "signed" ]]; then
    exit 1
  fi
  echo "Unsigned artifact is expected to skip strict code-sign verification." >&2
}

package_artifacts() {
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  /usr/bin/hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$APP_BUNDLE" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
}

package_artifacts

if [[ "$MODE" == "signed" ]]; then
  if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    /usr/bin/xcrun notarytool submit "$ZIP_PATH" \
      --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
      --wait
    /usr/bin/xcrun stapler staple "$APP_BUNDLE"
    /usr/bin/xcrun stapler validate "$APP_BUNDLE"
    package_artifacts
  fi

  /usr/bin/spctl --assess --type execute --verbose "$APP_BUNDLE"
fi

echo "Created:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
