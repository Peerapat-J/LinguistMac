#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LinguistMac"
BUNDLE_ID="com.peerapatj.LinguistMac"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

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
  swift build --product "$APP_NAME"
  local build_binary
  build_binary="$(swift build --show-bin-path)/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
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
