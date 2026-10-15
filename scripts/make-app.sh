#!/bin/bash
# Builds dist/CVMatrix.app (release build, icon, ad-hoc signature). Drag it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/CVMatrix.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/CVMatrix"

rm -rf "$APP" dist/icon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist/icon.iconset
cp "$BIN" "$APP/Contents/MacOS/CVMatrix"

# icon: draw one 1024 px PNG, then scale it to every size an .icns needs
swift scripts/make-icon.swift dist/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s dist/icon-1024.png --out "dist/icon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) dist/icon-1024.png --out "dist/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns dist/icon.iconset -o "$APP/Contents/Resources/CVMatrix.icns"
rm -rf dist/icon.iconset dist/icon-1024.png

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>CVMatrix</string>
  <key>CFBundleIdentifier</key><string>com.boocup.cvmatrix</string>
  <key>CFBundleName</key><string>CV Matrix</string>
  <key>CFBundleDisplayName</key><string>CV Matrix</string>
  <key>CFBundleIconFile</key><string>CVMatrix</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>The ES-8 is one audio device with inputs and outputs. CV Matrix only sends control voltages and never records.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"
echo "Built $APP"
