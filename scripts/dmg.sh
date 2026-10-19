#!/bin/sh
# Builds Rail.app and packs it into build/Rail-<version>.dmg with an Applications shortcut.
# Usage: scripts/dmg.sh [signing identity, default "Apple Development"]
# Set NOTARY_PROFILE (a `xcrun notarytool store-credentials` profile) to notarize and staple;
# that only works with a "Developer ID Application" identity.
set -eu
cd "$(dirname "$0")/.."

IDENTITY="${1:-Apple Development}"
APP="build/Rail.app"

scripts/bundle.sh "$IDENTITY"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/Rail-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
diskutil image create from --format ULFO --volumeName "Rail $VERSION" "$STAGE" "$DMG"
codesign --force --sign "$IDENTITY" --identifier com.olchu.Rail.dmg "$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "Built $DMG"
