#!/usr/bin/env bash
# Compile AeroBezel.app (bezels arcade pour aero-center) → ${1:-~/Applications}/AeroBezel.app
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)
app="${1:-$HOME/Applications}/AeroBezel.app"
mkdir -p "$app/Contents/MacOS"
swiftc -O -o "$app/Contents/MacOS/AeroBezel" "$src/main.swift"
cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.jgsquare.aero-bezel</string>
  <key>CFBundleName</key><string>AeroBezel</string>
  <key>CFBundleExecutable</key><string>AeroBezel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app" >/dev/null 2>&1 || true
echo "$app"
