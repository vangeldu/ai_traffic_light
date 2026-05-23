#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${HOME}/.local/share/ai-traffic-light/bin"
HOOK_CLI="${BIN_DIR}/ai-traffic-light-hook"
cmd="${1:-set}"

if [[ "$cmd" == "set" ]]; then
  state="${2:-idle}"
  source="${3:-cursor}"
else
  state="$cmd"
  source="${2:-cursor}"
fi

if [[ -x "$HOOK_CLI" ]]; then
  exec "$HOOK_CLI" set "$state" "$source"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${SCRIPT_DIR}/state-write.py" ]]; then
  exec python3 "${SCRIPT_DIR}/state-write.py" "$state" "$source"
fi

echo "Hook CLI not found. Build the app or run ./scripts/install-all-hooks.sh first." >&2
exit 1
