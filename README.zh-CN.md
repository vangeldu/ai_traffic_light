# AI Traffic Light

[English](README.md)

macOS 菜单栏 + 悬浮窗 AI 状态红绿灯，实时显示 **Cursor**、**Claude Code**、**OpenAI Codex** 的 Agent 活动。

- 🟢 **空闲** — 无 Agent 在工作
- 🟡 **思考中** — 已提交 prompt / 推理中
- 🔴 **运行中** — 工具调用中

## 快速开始（给最终用户）

```bash
# 1. 编译或下载 App 后打开
open dist/AITrafficLight.app

# 2. 首次集成后，完全退出并重新打开 Cursor / Claude Code / Codex

# 3. 正常使用，悬浮灯会跟随 Agent 状态变化
```

**不需要**手动运行任何 install 脚本。App 首次启动时会自动：

1. 安装 hook 程序到 `~/.local/share/ai-traffic-light/bin/`
2. 写入 Cursor、Claude Code、Codex 的 hook 配置
3. 开启 Codex hooks（`[features].hooks = true`）并**自动信任** hook

菜单栏 → **重新安装 IDE 集成**，可在 App 更新后手动刷新 hook 配置。

## 开发者

```bash
# 编译 .app
./scripts/build.sh

# 本地运行（使用仓库里的 ui/widget.html）
./scripts/run.sh

# 可选：不打开 App，仅安装 hooks（调试）
./scripts/install-all-hooks.sh
```

环境要求：macOS 13+、Xcode Command Line Tools（Swift）。Python 3 用于内置辅助脚本（Codex 信任、开发安装）；macOS 自带。

## 工作原理

```text
Cursor / Claude Code / Codex Hooks
    -->  ~/.local/share/ai-traffic-light/bin/ai-traffic-light-hook
    -->  ~/Library/Application Support/ai-traffic-light/state.json
                                              |
macOS 悬浮 App (Swift + WKWebView)  <-- 监听状态文件 --+
         |
    ui/widget.html
```

### 多源合并

每个 IDE 单独写入状态（`cursor` / `claude` / `codex`），再按优先级合并成最终灯态：

`running` > `thinking` > `idle`

同级时取最近更新的来源。

若某个来源长时间没有新事件（例如缺少 `stop` hook），会自动超时恢复：**running 60 秒**、**thinking 90 秒**。

### Cursor 与 Claude Code 共存

Cursor 还会加载 `~/.claude/settings.json` 里的 hook。hook CLI 会检测 Cursor 调用（stdin 中含 `cursor_version`），在 Cursor 环境下**跳过**对 `claude` / `codex` 源的写入，避免重复计数。

Cursor 一轮对话结束时，`afterAgentResponse` / `stop` / `sessionEnd` 会执行 `set idle all`，一次性清空所有来源。

### Hook 映射

| 工具 | 事件 | 状态 |
|------|------|------|
| Cursor | `beforeSubmitPrompt` | thinking |
| Cursor | `preToolUse` | running |
| Cursor | `postToolUse` | thinking |
| Cursor | `afterAgentResponse` / `stop` / `sessionEnd` | idle（全部来源） |
| Claude Code | `UserPromptSubmit` | thinking |
| Claude Code | `PreToolUse` | running |
| Claude Code | `PostToolUse` | thinking |
| Claude Code | `PostToolUseFailure` / `Stop` / `SessionEnd` | idle |
| Codex | `UserPromptSubmit` | thinking |
| Codex | `PreToolUse` | running |
| Codex | `PostToolUse` | thinking |
| Codex | `Stop` | idle |

写入的配置文件：

| 工具 | 路径 |
|------|------|
| Cursor | `~/.cursor/hooks.json` |
| Claude Code | `~/.claude/settings.json` |
| Codex | `~/.codex/hooks.json`、`~/.codex/config.toml` |

## 目录结构

```text
ai_traffic_light/
├── ui/widget.html                  # 悬浮 UI
├── preview/                        # 浏览器预览
├── hooks/                          # Hook 模板与辅助脚本（打包进 App）
│   ├── *-hooks.fragment.json
│   ├── merge-hooks-config.py
│   └── trust-codex-hooks.py
├── scripts/
│   ├── build.sh
│   ├── run.sh
│   └── install-all-hooks.sh        # 仅开发用
└── app/
    ├── Sources/AITrafficLight/         # 悬浮 App + 自动安装
    ├── Sources/AITrafficLightHook/     # 随 App 分发的 hook CLI
    └── Sources/TrafficLightCore/       # 状态写入共享库
```

## 手动测试

```bash
HOOK=~/.local/share/ai-traffic-light/bin/ai-traffic-light-hook

$HOOK set running claude
$HOOK set thinking codex
$HOOK set idle all          # 重置全部来源
```

## 注意事项

- **首次安装或重新安装集成后，请重启对应 IDE**。
- **Codex**：hook 会自动启用并信任；若灯无反应，请完全退出 Codex（Cmd+Q）后重开。
- Claude Code / Codex 的 hook 会**追加**到现有配置，不会覆盖你的其他 hook。
- Cursor 由本 App 管理的 hook 会在重装时**更新**；已移除的事件（如旧的 `afterAgentThought`）会被自动清理。

## 后续计划

- 登录项自动启动
- 代码签名与分发

## 许可证

MIT（如需正式开源，可补充 LICENSE 文件）
