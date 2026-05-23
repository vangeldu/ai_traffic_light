#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=install-common.sh
source "${ROOT}/scripts/install-common.sh"

CURSOR_DIR="${HOME}/.cursor"
HOOKS_JSON="${CURSOR_DIR}/hooks.json"
FRAGMENT="${ROOT}/hooks/cursor-hooks.fragment.json"

HOOK_CMD="$(install_hook_bin)"
TMP_FRAGMENT="$(prepare_fragment "$FRAGMENT" "$HOOK_CMD")"
trap 'rm -f "$TMP_FRAGMENT"' EXIT

merge_hooks_config cursor "$HOOKS_JSON" "$TMP_FRAGMENT"

echo "Installed hook binary to ${HOOK_CMD}"
echo "Updated Cursor hooks at ${HOOKS_JSON}"
echo "Restart Cursor if hooks do not load immediately."
