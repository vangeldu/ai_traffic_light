# AI Traffic Light

[English](README.md)

macOS 菜单栏 + 悬浮窗 AI 状态红绿灯，实时显示 **Cursor**、**Claude Code**、**OpenAI Codex** 的 Agent 活动。

- 🟢 **空闲** — 无 Agent 在工作
- 🟡 **思考中** — 已提交 prompt / 推理中
- 🔴 **运行中** — 工具调用中

![macOS 悬浮 AI 红绿灯](assets/screenshot.png)

## 快速开始（给最终用户）

### 从 GitHub Releases 安装（推荐）

1. 在 [Releases](https://github.com/vangeldu/ai_traffic_light/releases) 下载 **`AITrafficLight-x.y.z-macOS-universal.dmg`**
2. 打开 DMG，把 **AI Traffic Light** 拖进 **Applications**
3. **首次打开**（未签名版本，任选一种）：
   - **右键** App → **打开** → 再点 **打开**，或
   - 先双击一次（可能被拦截），再打开 **系统设置 → 隐私与安全性**，向下找到 **仍要打开** / **Open Anyway** 并点击
4. 完全退出并重新打开 **Cursor / Claude Code / Codex** 一次
5. 正常使用，悬浮灯会跟随 Agent 状态

Release 包是 **Universal 二进制**（Apple Silicon + Intel），需要 **macOS 13+**。

每个 Release 也会附带 `.zip`，不想用 DMG 可以直接解压。

### 从源码编译

```bash
# 本地开发（仅当前机器架构）
./scripts/build.sh
open dist/AITrafficLight.app

# 打 GitHub Release 包（Universal + DMG + ZIP）
./scripts/release.sh 1.0.0
```

**不需要**手动运行任何 install 脚本。App 首次启动时会自动：

1. 安装 hook 程序到 `~/.local/share/ai-traffic-light/bin/`
2. 写入 Cursor、Claude Code、Codex 的 hook 配置
3. 开启 Codex hooks（`[features].hooks = true`）并**自动信任** hook

菜单栏 → **重新安装 IDE 集成**，可在 App 更新后手动刷新 hook 配置。

## 开发者

```bash
# 编译 .app（本机架构，开发迭代快）
./scripts/build.sh

# 编译 .app（Apple Silicon + Intel）
./scripts/build.sh --universal

# 打 Release：Universal .app + DMG + ZIP + 校验和
./scripts/release.sh 1.0.0

# 本地运行
./scripts/run.sh

# 可选：不打开 App，仅安装 hooks
./scripts/install-all-hooks.sh

# 发布 GitHub Release（先推送 tag v1.0.0）
git tag v1.0.0
git push origin v1.0.0
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
- **首次打开（未签名）**：macOS 可能拦截首次启动。可 **右键 → 打开**，或在双击被拦后进入 **系统设置 → 隐私与安全性**，点 **仍要打开**。正式签名公证后可免此步骤（见后续计划）。
- **Codex**：hook 会自动启用并信任；若灯无反应，请完全退出 Codex（Cmd+Q）后重开。
- Claude Code / Codex 的 hook 会**追加**到现有配置，不会覆盖你的其他 hook。
- Cursor 由本 App 管理的 hook 会在重装时**更新**；已移除的事件（如旧的 `afterAgentThought`）会被自动清理。

## 后续计划

- 登录项自动启动
- Apple Developer ID 签名与公证

## 许可证

MIT（如需正式开源，可补充 LICENSE 文件）
