#!/bin/zsh
# Builds the app, then packs it into build/FileWheel-<version>.dmg with a shortcut to Applications.
set -e
cd "$(dirname "$0")/.."
./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/FileWheel.app/Contents/Info.plist)
STAGE=$(mktemp -d)
cp -R build/FileWheel.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="build/FileWheel-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "FileWheel" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Made $DMG"
