#!/usr/bin/env python3
"""Merge per-tool agent states into ai-traffic-light/state.json."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path.home() / "Library/Application Support/ai-traffic-light"
STATE_FILE = STATE_DIR / "state.json"

VALID_STATES = {"idle", "thinking", "running"}
VALID_SOURCES = {"cursor", "claude", "codex"}
PRIORITY = {"running": 3, "thinking": 2, "idle": 1}


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_document() -> dict:
    if not STATE_FILE.exists():
        return {"sources": {}}

    data = json.loads(STATE_FILE.read_text())
    sources = data.get("sources")
    if isinstance(sources, dict):
        return {"sources": sources}

    legacy_state = data.get("state", "idle")
    legacy_source = data.get("source", "cursor")
    legacy_updated = data.get("updated_at", utc_now())
    if legacy_source in VALID_SOURCES:
        return {
            "sources": {
                legacy_source: {
                    "state": legacy_state,
                    "updated_at": legacy_updated,
                }
            }
        }
    return {"sources": {}}


def pick_effective(sources: dict) -> tuple[str, str]:
    best_state = "idle"
    best_source = "none"
    best_rank = 0
    best_time = ""

    for source, entry in sources.items():
        if source not in VALID_SOURCES or not isinstance(entry, dict):
            continue
        state = entry.get("state", "idle")
        if state not in VALID_STATES:
            state = "idle"
        rank = PRIORITY[state]
        updated = entry.get("updated_at", "")
        if rank > best_rank or (rank == best_rank and updated > best_time):
            best_state = state
            best_source = source
            best_rank = rank
            best_time = updated

    return best_state, best_source


def write_state(state: str, source: str) -> None:
    if state not in VALID_STATES:
        state = "idle"
    if source not in VALID_SOURCES:
        print(f"Invalid source: {source}", file=sys.stderr)
        sys.exit(1)

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    doc = load_document()
    sources = doc.setdefault("sources", {})
    sources[source] = {"state": state, "updated_at": utc_now()}

    effective_state, effective_source = pick_effective(sources)
    payload = {
        "state": effective_state,
        "source": effective_source,
        "updated_at": utc_now(),
        "sources": sources,
    }
    STATE_FILE.write_text(json.dumps(payload, indent=2) + "\n")


def main() -> None:
    if len(sys.argv) < 3:
        print("Usage: state-write.py <state> <source>", file=sys.stderr)
        sys.exit(1)
    write_state(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()
