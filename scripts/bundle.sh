#!/bin/sh
# Builds Rail.app into ./build. Usage: scripts/bundle.sh [signing identity, default "Apple Development"]
# A stable identity matters: with ad-hoc signing macOS drops the Accessibility grant on every rebuild.
set -eu
cd "$(dirname "$0")/.."

IDENTITY="${1:-Apple Development}"
APP="build/Rail.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Rail"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Rail"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
