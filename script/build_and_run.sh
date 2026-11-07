#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME=ThreeMFPreview
MODE=${1:-run}
BUILD_DIR=/private/tmp/ThreeMFPreview-build
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
xcodegen generate
xcodebuild -project ThreeMFPreview.xcodeproj -scheme ThreeMFPreview -configuration Debug -derivedDataPath "$BUILD_DIR" build > build.log 2>&1 || { tail -60 build.log; exit 1; }
APP="$BUILD_DIR/Build/Products/Debug/$APP_NAME.app"
case "$MODE" in
  --build) exit 0 ;;
  --debug) lldb "$APP/Contents/MacOS/$APP_NAME" ;;
  run) open -n "$APP" ;;
  --verify) open -n "$APP"; sleep 1; pgrep -x "$APP_NAME" ;;
  --logs|--telemetry) open -n "$APP"; /usr/bin/log stream --info --predicate 'process == "ThreeMFPreview"' ;;
  *) exit 2 ;;
esac
