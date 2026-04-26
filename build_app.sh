#!/bin/bash
set -e

echo "→ Building Claudy (release)…"
swift build -c release

APP="Claudy.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp .build/release/Claudy "$CONTENTS/MacOS/Claudy"

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>        <string>Claudy</string>
    <key>CFBundleIdentifier</key>        <string>com.claudy.app</string>
    <key>CFBundleName</key>              <string>Claudy</string>
    <key>CFBundleDisplayName</key>       <string>Claudy</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

echo "✅ Claudy.app built."
echo ""
echo "  Launch:   open Claudy.app"
echo "  Or move to /Applications and double-click."
