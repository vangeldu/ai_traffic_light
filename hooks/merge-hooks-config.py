#!/usr/bin/env python3
"""Merge ai-traffic-light hook fragments into tool config files."""

from __future__ import annotations

import json
import sys
from copy import deepcopy
from pathlib import Path

MARKER = "ai-traffic-light"


def strip_our_hooks(entries: list) -> list:
    kept = []
    for entry in entries:
        serialized = json.dumps(entry)
        if MARKER not in serialized:
            kept.append(entry)
    return kept


def merge_event_list(existing: list, incoming: list) -> list:
    merged = strip_our_hooks(existing)
    merged.extend(deepcopy(incoming))
    return merged


def merge_cursor(config_path: Path, fragment_path: Path) -> None:
    fragment = json.loads(fragment_path.read_text())
    if config_path.exists():
        config = json.loads(config_path.read_text())
    else:
        config = {"version": 1, "hooks": {}}

    config.setdefault("version", 1)
    config.setdefault("hooks", {})

    for event in list(config["hooks"].keys()):
        entries = config["hooks"][event]
        if not isinstance(entries, list) or not entries:
            continue
        if event in fragment:
            continue
        if all(MARKER in json.dumps(entry) for entry in entries):
            del config["hooks"][event]

    for event, entries in fragment.items():
        config["hooks"][event] = entries

    config_path.write_text(json.dumps(config, indent=2) + "\n")


def merge_nested_hooks(config_path: Path, fragment_path: Path, hooks_key: str = "hooks") -> None:
    fragment = json.loads(fragment_path.read_text())
    if config_path.exists():
        config = json.loads(config_path.read_text())
    else:
        config = {}

    hooks = config.setdefault(hooks_key, {})
    for event, entries in fragment.items():
        existing = hooks.get(event, [])
        if not isinstance(existing, list):
            existing = []
        hooks[event] = merge_event_list(existing, entries)

    config_path.write_text(json.dumps(config, indent=2) + "\n")


def main() -> None:
    if len(sys.argv) != 4:
        print(
            "Usage: merge-hooks-config.py <cursor|claude|codex> <config-path> <fragment-path>",
            file=sys.stderr,
        )
        sys.exit(1)

    mode, config_path_str, fragment_path_str = sys.argv[1:]
    config_path = Path(config_path_str)
    fragment_path = Path(fragment_path_str)

    config_path.parent.mkdir(parents=True, exist_ok=True)

    if mode == "cursor":
        merge_cursor(config_path, fragment_path)
    elif mode in {"claude", "codex"}:
        merge_nested_hooks(config_path, fragment_path)
    else:
        print(f"Unknown mode: {mode}", file=sys.stderr)
        sys.exit(1)

    print(f"Updated {config_path}")


if __name__ == "__main__":
    main()
