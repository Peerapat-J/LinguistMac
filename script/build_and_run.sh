#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LinguistMac"
BUNDLE_ID="com.peerapatj.LinguistMac"
SCHEME="LinguistMac"
CONFIGURATION="${CONFIGURATION:-Debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
PROJECT_PATH="$ROOT_DIR/LinguistMac.xcodeproj"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode}"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"

cd "$ROOT_DIR"

is_app_running() {
  /usr/bin/osascript <<APPLESCRIPT 2>/dev/null | /usr/bin/grep -q "true"
application id "$BUNDLE_ID" is running
APPLESCRIPT
}

quit_existing_app() {
  if is_app_running; then
    /usr/bin/osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application id "$BUNDLE_ID" to quit
APPLESCRIPT

    for _ in {1..20}; do
      is_app_running || return
      sleep 0.1
    done
  fi

  pkill -f "$APP_BINARY" >/dev/null 2>&1 || true
}

build_app_bundle() {
  xcodebuild \
    -quiet \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
    build

  rm -rf "$APP_BUNDLE"
  mkdir -p "$DIST_DIR"
  ditto "$BUILT_APP" "$APP_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    quit_existing_app
    build_app_bundle
    open_app
    ;;
  --package|package)
    build_app_bundle
    ;;
  --debug|debug)
    quit_existing_app
    build_app_bundle
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    quit_existing_app
    build_app_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    quit_existing_app
    build_app_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    quit_existing_app
    build_app_bundle
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--package|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
