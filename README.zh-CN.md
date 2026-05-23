# AI Traffic Light

[English](README.md)

macOS 悬浮 AI 状态红绿灯，支持 **Cursor**、**Claude Code**、**Codex**。

- 🟢 **空闲** — Agent 未运行
- 🟡 **思考中** — 提交 prompt / 推理阶段
- 🔴 **运行中** — 工具调用中

## 快速开始（给最终用户）

```bash
# 1. 编译或下载 App 后打开
open dist/AITrafficLight.app

# 2. 正常使用 Cursor / Claude Code / Codex
```

**不需要**手动运行任何 install 脚本。App 首次启动时会自动：

1. 安装 hook 程序到 `~/.local/share/ai-traffic-light/bin/`
2. 写入 Cursor、Claude Code、Codex 的 hook 配置
3. 弹出一次说明（Codex 需在 CLI 里运行 `/hooks` 并信任新 hook）

菜单栏 → **重新安装 IDE 集成**，可手动修复 hook 配置。

## 开发者

```bash
# 编译 .app
./scripts/build.sh

# 本地运行（使用仓库里的 ui/widget.html）
./scripts/run.sh

# 可选：不打开 App，仅安装 hooks（调试）
./scripts/install-all-hooks.sh
```

环境要求：macOS 13+、Xcode Command Line Tools（Swift）；Python 3 仅开发脚本需要。

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

每个 IDE 单独写入状态，再按优先级合并成最终灯态：

`running` > `thinking` > `idle`

同级时取最近更新的来源。

### Hook 映射

| 工具 | 事件 | 状态 |
|------|------|------|
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

## 目录结构

```text
ai_traffic_light/
├── ui/widget.html              # 悬浮 UI
├── preview/                    # 浏览器预览
├── hooks/                      # Hook 模板（打包进 App）
├── scripts/
│   ├── build.sh
│   ├── run.sh
│   └── install-all-hooks.sh    # 仅开发用
└── app/
    ├── Sources/AITrafficLight/     # 悬浮 App + 自动安装
    ├── Sources/AITrafficLightHook/ # 随 App 分发的 hook CLI
    └── Sources/TrafficLightCore/   # 状态写入共享库
```

## 手动测试

```bash
~/.local/share/ai-traffic-light/bin/ai-traffic-light-hook set running claude
~/.local/share/ai-traffic-light/bin/ai-traffic-light-hook set idle cursor
```

## 注意事项

- **Codex**：首次需在 Codex 中运行 `/hooks` 并信任 hook（OpenAI 安全机制）
- 修改 hook 或更新 App 后，重启对应 IDE
- Claude / Codex 的 hook 会**追加**到现有配置，不覆盖你的其他 hook
- Cursor 的同名字段会被本 App **更新**

## 后续计划

- 登录项自动启动
- 代码签名与分发

## 许可证

MIT（如需正式开源，可补充 LICENSE 文件）
