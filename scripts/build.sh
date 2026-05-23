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

UNIVERSAL="${UNIVERSAL:-0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --universal)
      UNIVERSAL=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--universal]" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$RESOURCE_DIR" "$HOOKS_RESOURCE_DIR"
cp "${ROOT}/ui/widget.html" "${RESOURCE_DIR}/widget.html"
cp "${ROOT}/hooks/"*.fragment.json "$HOOKS_RESOURCE_DIR/"
cp "${ROOT}/hooks/trust-codex-hooks.py" "$HOOKS_RESOURCE_DIR/"

cd "$APP_DIR"

BUILD_FLAGS=(-c release)
ARCH_FLAGS=()
if [[ "$UNIVERSAL" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  BIN_DIR="${APP_DIR}/.build/apple/Products/Release"
  echo "Building universal binary (Apple Silicon + Intel)..."
else
  BIN_DIR="${APP_DIR}/.build/release"
  echo "Building for host architecture ($(uname -m))..."
fi

swift build "${BUILD_FLAGS[@]}" "${ARCH_FLAGS[@]}" --product AITrafficLight --product AITrafficLightHook

BIN="${BIN_DIR}/AITrafficLight"
HOOK_BIN="${BIN_DIR}/AITrafficLightHook"
RESOURCE_BUNDLE="${BIN_DIR}/AITrafficLight_AITrafficLight.bundle"

echo "Generating A5 app icon..."
mkdir -p "${ROOT}/assets"
swift "${ROOT}/scripts/generate-app-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "Packaging .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/hooks"

cp "$BIN" "$APP_BUNDLE/Contents/MacOS/AITrafficLight"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing SPM resource bundle: $RESOURCE_BUNDLE" >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
BUNDLE_WIDGET="$APP_BUNDLE/Contents/Resources/AITrafficLight_AITrafficLight.bundle/Contents/Resources/widget.html"
cp "${ROOT}/ui/widget.html" "$BUNDLE_WIDGET"
cp "$HOOK_BIN" "$APP_BUNDLE/Contents/Resources/hooks/ai-traffic-light-hook"
cp "$HOOKS_RESOURCE_DIR/"*.fragment.json "$APP_BUNDLE/Contents/Resources/hooks/"
cp "$HOOKS_RESOURCE_DIR/trust-codex-hooks.py" "$APP_BUNDLE/Contents/Resources/hooks/"
cp "$ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

APP_VERSION="${APP_VERSION:-1.0.0}"
APP_BUILD="${APP_BUILD:-1}"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
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
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

echo
echo "Built binary: $BIN"
file "$BIN"
echo "Built hook:   $HOOK_BIN"
file "$HOOK_BIN"
echo "Built app:    $APP_BUNDLE"
echo "App icon:     $ICNS (A5 · HIG-compliant)"
