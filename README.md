# AI Traffic Light

[中文文档](README.zh-CN.md)

A macOS floating traffic-light widget that shows AI agent activity across **Cursor**, **Claude Code**, and **Codex**.

- 🟢 **Idle** — agent is not running
- 🟡 **Thinking** — prompt submitted / reasoning
- 🔴 **Running** — tool call in progress

## Quick start (end users)

```bash
# 1. Build or download the app, then open it
open dist/AITrafficLight.app

# 2. Use Cursor, Claude Code, or Codex as usual
```

No install scripts are required. On first launch, the app automatically:

1. Installs the hook CLI to `~/.local/share/ai-traffic-light/bin/`
2. Registers hooks for Cursor, Claude Code, and Codex
3. Shows a one-time note about trusting Codex hooks (see below)

Use the menu bar item **Reinstall IDE Integration** if hooks need to be refreshed.

## For developers

```bash
# Build the .app bundle
./scripts/build.sh

# Run locally (uses repo ui/widget.html)
./scripts/run.sh

# Optional: install hooks without launching the app
./scripts/install-all-hooks.sh
```

Requirements: macOS 13+, Xcode Command Line Tools (Swift), Python 3 (dev scripts only).

## How it works

```text
Cursor / Claude Code / Codex hooks
    -->  ~/.local/share/ai-traffic-light/bin/ai-traffic-light-hook
    -->  ~/Library/Application Support/ai-traffic-light/state.json
                                              |
Floating macOS app (Swift + WKWebView)  <---- watches state file
         |
    ui/widget.html
```

### Multi-source merge

Each IDE writes its own state. The effective lamp state is merged with priority:

`running` > `thinking` > `idle`

When priorities tie, the most recently updated source wins.

### Hook mapping

| Tool | Event | State |
|------|-------|-------|
| Cursor | `beforeSubmitPrompt` / `afterAgentThought` | thinking |
| Cursor | `preToolUse` | running |
| Cursor | `postToolUse` | thinking |
| Cursor | `stop` / `sessionEnd` | idle |
| Claude Code | `UserPromptSubmit` | thinking |
| Claude Code | `PreToolUse` | running |
| Claude Code | `PostToolUse` | thinking |
| Claude Code | `Stop` / `SessionEnd` | idle |
| Codex | `UserPromptSubmit` | thinking |
| Codex | `PreToolUse` | running |
| Codex | `PostToolUse` | thinking |
| Codex | `Stop` | idle |

## Project layout

```text
ai_traffic_light/
├── ui/widget.html              # Floating widget UI
├── preview/                    # Browser previews
├── hooks/                      # Hook templates (bundled into the app)
├── scripts/
│   ├── build.sh
│   ├── run.sh
│   └── install-all-hooks.sh    # Dev-only hook installer
└── app/
    ├── Sources/AITrafficLight/     # App + auto-installer
    ├── Sources/AITrafficLightHook/ # Hook CLI shipped with the app
    └── Sources/TrafficLightCore/   # Shared state writer
```

## Manual testing

```bash
~/.local/share/ai-traffic-light/bin/ai-traffic-light-hook set running claude
~/.local/share/ai-traffic-light/bin/ai-traffic-light-hook set idle cursor
```

## Notes

- **Codex**: run `/hooks` in the Codex CLI once and trust the new hooks (OpenAI security requirement).
- Restart the IDE after hook changes or app updates.
- Claude Code and Codex hooks are **appended** to your existing hook config.
- Cursor hook entries for the same events are **replaced** by this app.

## Roadmap

- Login item / launch at startup
- Code signing and distribution

## License

MIT (add a LICENSE file if you plan to open-source formally)
