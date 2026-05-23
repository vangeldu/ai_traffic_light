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

ensure_codex_hooks_feature() {
  local config_toml="${HOME}/.codex/config.toml"
  python3 - "$config_toml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text() if path.exists() else ""

for deprecated in ("codex_hooks = true", "codex_hooks=true", "codex_hooks = false", "codex_hooks=false"):
    text = text.replace(deprecated, "")

if "hooks = true" not in text and "hooks=true" not in text:
    if "[features]" in text:
        text = text.replace("[features]", "[features]\nhooks = true", 1)
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        text += "\n[features]\nhooks = true\n"

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(text)
print(f"Updated {path}")
PY
}

trust_codex_hooks() {
  python3 "${ROOT}/hooks/trust-codex-hooks.py"
}
