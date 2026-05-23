#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${HOME}/.local/share/ai-traffic-light/bin"
APP_DIR="${ROOT}/app"
HOOK_BIN="${APP_DIR}/.build/release/AITrafficLightHook"

install_hook_bin() {
  if [[ ! -x "$HOOK_BIN" ]]; then
    echo "Building hook CLI..." >&2
    (cd "$APP_DIR" && swift build -c release --product AITrafficLightHook)
  fi

  mkdir -p "$BIN_DIR"
  install -m 755 "$HOOK_BIN" "${BIN_DIR}/ai-traffic-light-hook"
  echo "${BIN_DIR}/ai-traffic-light-hook"
}

prepare_fragment() {
  local fragment_path="$1"
  local hook_cmd="$2"
  local tmp
  tmp="$(mktemp)"
  sed "s|__HOOK_CMD__|${hook_cmd}|g" "$fragment_path" > "$tmp"
  echo "$tmp"
}

merge_hooks_config() {
  local mode="$1"
  local config_path="$2"
  local fragment_path="$3"
  python3 "${ROOT}/hooks/merge-hooks-config.py" "$mode" "$config_path" "$fragment_path"
}
