#!/usr/bin/env python3
"""Trust ai-traffic-light hooks in Codex via the app-server hooks/list API."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

MARKER = "ai-traffic-light"
DEFAULT_CODEX_PATHS = (
    "/Applications/Codex.app/Contents/Resources/codex",
    "/Applications/Codex.app/Contents/MacOS/Codex",
)


def find_codex_binary() -> str | None:
    for candidate in DEFAULT_CODEX_PATHS:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate

    for name in ("codex",):
        found = subprocess.run(["/usr/bin/which", name], capture_output=True, text=True)
        if found.returncode == 0:
            path = found.stdout.strip()
            if path:
                return path
    return None


def default_cwd() -> str:
    return str(Path.home())


class AppServerClient:
    def __init__(self, codex_binary: str) -> None:
        self._proc = subprocess.Popen(
            [codex_binary, "app-server"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self._messages: list[dict] = []
        self._lock = threading.Lock()
        self._next_id = 1
        self._reader = threading.Thread(target=self._read_stdout, daemon=True)
        self._reader.start()

    def close(self) -> None:
        if self._proc.stdin:
            self._proc.stdin.close()
        self._proc.terminate()
        try:
            self._proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self._proc.kill()

    def _read_stdout(self) -> None:
        assert self._proc.stdout is not None
        for line in self._proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            with self._lock:
                self._messages.append(message)

    def request(self, method: str, params: dict | None = None, timeout: float = 8.0) -> dict:
        assert self._proc.stdin is not None
        request_id = self._next_id
        self._next_id += 1
        payload = {"jsonrpc": "2.0", "id": request_id, "method": method}
        if params is not None:
            payload["params"] = params
        self._proc.stdin.write(json.dumps(payload) + "\n")
        self._proc.stdin.flush()

        deadline = time.time() + timeout
        while time.time() < deadline:
            with self._lock:
                for message in self._messages:
                    if message.get("id") == request_id:
                        if "error" in message:
                            raise RuntimeError(message["error"].get("message", "app-server error"))
                        return message.get("result", {})
            time.sleep(0.05)
        raise TimeoutError(f"Timed out waiting for {method}")


def list_hooks(client: AppServerClient, cwd: str) -> list[dict]:
    result = client.request("hooks/list", {"cwds": [cwd]})
    data = result.get("data") or []
    if not data:
        return []
    return data[0].get("hooks") or []


def trust_hooks(client: AppServerClient, hooks: list[dict]) -> int:
    edits = []
    for hook in hooks:
        command = hook.get("command") or ""
        if MARKER not in command:
            continue
        if hook.get("trustStatus") == "trusted":
            continue
        key = hook["key"]
        edits.append(
            {
                "keyPath": f'hooks.state."{key}"',
                "mergeStrategy": "upsert",
                "value": {"trusted_hash": hook["currentHash"]},
            }
        )

    if not edits:
        return 0

    client.request("config/batchWrite", {"edits": edits})
    return len(edits)


def main() -> int:
    codex_binary = find_codex_binary()
    if codex_binary is None:
        print("Codex CLI not found; skipped hook trust", file=sys.stderr)
        return 0

    cwd = sys.argv[1] if len(sys.argv) > 1 else default_cwd()
    client = AppServerClient(codex_binary)
    try:
        client.request(
            "initialize",
            {
                "clientInfo": {"name": "ai-traffic-light", "version": "1.0"},
                "capabilities": {},
            },
        )
        hooks = list_hooks(client, cwd)
        trusted_count = trust_hooks(client, hooks)
        if trusted_count:
            print(f"Trusted {trusted_count} Codex hook(s)")
        else:
            print("Codex hooks already trusted or not installed")
        return 0
    except Exception as exc:  # noqa: BLE001 - surface install errors to caller
        print(f"Failed to trust Codex hooks: {exc}", file=sys.stderr)
        return 1
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
