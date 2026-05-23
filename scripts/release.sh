#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/AITrafficLight.app"

VERSION="${1:-${APP_VERSION:-1.0.0}}"
STAGING_DIR="${DIST_DIR}/release-staging"
DMG_PATH="${DIST_DIR}/AITrafficLight-${VERSION}-macOS-universal.dmg"
ZIP_PATH="${DIST_DIR}/AITrafficLight-${VERSION}-macOS-universal.zip"
CHECKSUMS_PATH="${DIST_DIR}/SHA256SUMS"

export APP_VERSION="$VERSION"
export APP_BUILD="${APP_BUILD:-1}"

echo "==> Building universal .app (${VERSION})"
UNIVERSAL=1 "${ROOT}/scripts/build.sh" --universal

echo "==> Creating DMG"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_BUNDLE" "$STAGING_DIR/AITrafficLight.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "AI Traffic Light" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "==> Creating ZIP"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Writing checksums"
(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")"
) > "$CHECKSUMS_PATH"

rm -rf "$STAGING_DIR"

echo
echo "Release artifacts:"
echo "  DMG:  $DMG_PATH"
echo "  ZIP:  $ZIP_PATH"
echo "  SUMS: $CHECKSUMS_PATH"
echo
file "$APP_BUNDLE/Contents/MacOS/AITrafficLight"
echo
echo "Upload to GitHub Releases:"
echo "  gh release create v${VERSION} \\"
echo "    \"${DMG_PATH}\" \\"
echo "    \"${ZIP_PATH}\" \\"
echo "    \"${CHECKSUMS_PATH}\" \\"
echo "    --title \"AI Traffic Light ${VERSION}\" \\"
echo "    --notes \"macOS 13+. Universal (Apple Silicon + Intel). First open: right-click → Open, or System Settings → Privacy & Security → Open Anyway.\""
