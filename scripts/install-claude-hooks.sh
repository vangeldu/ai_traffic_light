#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=install-common.sh
source "${ROOT}/scripts/install-common.sh"

CLAUDE_DIR="${HOME}/.claude"
SETTINGS_JSON="${CLAUDE_DIR}/settings.json"
FRAGMENT="${ROOT}/hooks/claude-hooks.fragment.json"

HOOK_CMD="$(install_hook_bin)"
TMP_FRAGMENT="$(prepare_fragment "$FRAGMENT" "$HOOK_CMD")"
trap 'rm -f "$TMP_FRAGMENT"' EXIT

merge_hooks_config claude "$SETTINGS_JSON" "$TMP_FRAGMENT"

echo "Installed hook binary to ${HOOK_CMD}"
echo "Updated Claude Code hooks at ${SETTINGS_JSON}"
echo "Restart Claude Code if hooks do not load immediately."
