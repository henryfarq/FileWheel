#!/bin/zsh
# Builds build/FileWheel.app (a normal Mac app you can double-click).
set -e
cd "$(dirname "$0")/.."

# Signing: a fixed identity lets macOS remember the app between builds.
# Machine-specific settings (identity, keychain password) live in scripts/local.env, which is not committed.
[[ -f scripts/local.env ]] && source scripts/local.env
if [[ -n "$SIGN_KEYCHAIN" && -n "$SIGN_KEYCHAIN_PASSWORD" ]]; then
  security unlock-keychain -p "$SIGN_KEYCHAIN_PASSWORD" "$SIGN_KEYCHAIN"
fi

swift build -c release
APP=build/FileWheel.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FileWheel "$APP/Contents/MacOS/FileWheel"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # remake with: swift scripts/make-icon.swift Assets/AppIcon-source.png Assets/AppIcon.icns
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>FileWheel</string>
<key>CFBundleIdentifier</key><string>com.henry.filewheel</string>
<key>CFBundleExecutable</key><string>FileWheel</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSDesktopFolderUsageDescription</key><string>FileWheel saves converted copies of your files to the Desktop.</string>
</dict></plist>
PLIST
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"   # "-" = unsigned-style signature when no identity is set
echo "Built $APP"
