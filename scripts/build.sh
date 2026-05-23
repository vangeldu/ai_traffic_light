#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${ROOT}/app"
DIST_DIR="${ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/AITrafficLight.app"
RESOURCE_DIR="${APP_DIR}/Sources/AITrafficLight/Resources"
HOOKS_RESOURCE_DIR="${RESOURCE_DIR}/hooks"
ICONSET="${ROOT}/assets/AppIcon.iconset"
ICNS="${ROOT}/assets/AppIcon.icns"

mkdir -p "$RESOURCE_DIR" "$HOOKS_RESOURCE_DIR"
cp "${ROOT}/ui/widget.html" "${RESOURCE_DIR}/widget.html"
cp "${ROOT}/hooks/"*.fragment.json "$HOOKS_RESOURCE_DIR/"

cd "$APP_DIR"
swift build -c release --product AITrafficLight --product AITrafficLightHook

BIN="${APP_DIR}/.build/release/AITrafficLight"
HOOK_BIN="${APP_DIR}/.build/release/AITrafficLightHook"

echo "Generating A5 app icon..."
mkdir -p "${ROOT}/assets"
swift "${ROOT}/scripts/generate-app-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "Packaging .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/hooks"

cp "$BIN" "$APP_BUNDLE/Contents/MacOS/AITrafficLight"
cp "$HOOK_BIN" "$APP_BUNDLE/Contents/Resources/hooks/ai-traffic-light-hook"
cp "$HOOKS_RESOURCE_DIR/"*.fragment.json "$APP_BUNDLE/Contents/Resources/hooks/"
cp "$ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleExecutable</key>
  <string>AITrafficLight</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.ai-traffic-light.app</string>
  <key>CFBundleName</key>
  <string>AI Traffic Light</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

echo
echo "Built binary: $BIN"
echo "Built hook:   $HOOK_BIN"
echo "Built app:    $APP_BUNDLE"
echo "App icon:     $ICNS (A5 · HIG-compliant)"
