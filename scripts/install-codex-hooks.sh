#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=install-common.sh
source "${ROOT}/scripts/install-common.sh"

CODEX_DIR="${HOME}/.codex"
HOOKS_JSON="${CODEX_DIR}/hooks.json"
FRAGMENT="${ROOT}/hooks/codex-hooks.fragment.json"

HOOK_CMD="$(install_hook_bin)"
TMP_FRAGMENT="$(prepare_fragment "$FRAGMENT" "$HOOK_CMD")"
trap 'rm -f "$TMP_FRAGMENT"' EXIT

merge_hooks_config codex "$HOOKS_JSON" "$TMP_FRAGMENT"
ensure_codex_hooks_feature
trust_codex_hooks

echo "Installed hook binary to ${HOOK_CMD}"
echo "Updated Codex hooks at ${HOOKS_JSON}"
echo "Restart Codex.app so trusted hooks take effect."
