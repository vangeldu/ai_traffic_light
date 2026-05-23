#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${ROOT}/dist/AITrafficLight.app"
BIN="${ROOT}/app/.build/release/AITrafficLight"

if [[ ! -d "$APP_BUNDLE" ]]; then
  "${ROOT}/scripts/build.sh"
fi

export AI_TRAFFIC_LIGHT_UI="${ROOT}/ui/widget.html"
exec "$APP_BUNDLE/Contents/MacOS/AITrafficLight"
