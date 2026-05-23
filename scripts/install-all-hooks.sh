#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

"${ROOT}/install-hooks.sh"
"${ROOT}/install-claude-hooks.sh"
"${ROOT}/install-codex-hooks.sh"

echo
echo "All hooks installed for Cursor, Claude Code, and Codex."
