import AppKit
import Foundation

struct HookInstallResult {
    let errors: [String]
    var succeeded: Bool { errors.isEmpty }
}

enum HookInstaller {
    private static let marker = "ai-traffic-light"
    private static let installedVersionKey = "hooksInstalledVersion"
    private static let codexNoticeKey = "codexHooksNoticeShown"

    private static var binDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/ai-traffic-light/bin", isDirectory: true)
    }

    private static var installedHookCLI: URL {
        binDirectory.appendingPathComponent("ai-traffic-light-hook")
    }

    static func installOnLaunch() {
        DispatchQueue.global(qos: .utility).async {
            let result = install()
            DispatchQueue.main.async {
                handlePostInstall(result)
            }
        }
    }

    @discardableResult
    static func install() -> HookInstallResult {
        var errors: [String] = []

        do {
            try installBundledCLI()
        } catch {
            errors.append("安装 hook 程序失败：\(error.localizedDescription)")
            return HookInstallResult(errors: errors)
        }

        let hookCommand = installedHookCLI.path
        let home = FileManager.default.homeDirectoryForCurrentUser

        mergeCursor(
            configURL: home.appendingPathComponent(".cursor/hooks.json"),
            hookCommand: hookCommand,
            errors: &errors
        )
        mergeNestedHooks(
            configURL: home.appendingPathComponent(".claude/settings.json"),
            hookCommand: hookCommand,
            source: "claude",
            resourceName: "claude-hooks.fragment",
            errors: &errors
        )
        mergeNestedHooks(
            configURL: home.appendingPathComponent(".codex/hooks.json"),
            hookCommand: hookCommand,
            source: "codex",
            resourceName: "codex-hooks.fragment",
            errors: &errors
        )

        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            UserDefaults.standard.set(version, forKey: installedVersionKey)
        }

        return HookInstallResult(errors: errors)
    }

    private static func handlePostInstall(_ result: HookInstallResult) {
        guard result.succeeded else { return }
        guard !UserDefaults.standard.bool(forKey: codexNoticeKey) else { return }

        UserDefaults.standard.set(true, forKey: codexNoticeKey)
        let alert = NSAlert()
        alert.messageText = "IDE 集成已就绪"
        alert.informativeText = """
        已自动配置 Cursor、Claude Code 和 Codex 的 hooks。

        若使用 Codex，首次请在 Codex 中运行 /hooks 并信任新 hook。
        修改 hook 后，重启对应 IDE 即可生效。
        """
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private static func installBundledCLI() throws {
        guard let bundled = bundledHookCLI() else {
            throw NSError(domain: "HookInstaller", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "未找到内置 hook 程序"
            ])
        }

        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: installedHookCLI.path) {
            try FileManager.default.removeItem(at: installedHookCLI)
        }
        try FileManager.default.copyItem(at: bundled, to: installedHookCLI)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedHookCLI.path)
    }

    private static func bundledHookCLI() -> URL? {
        if let url = Bundle.main.url(forResource: "ai-traffic-light-hook", withExtension: nil, subdirectory: "hooks") {
            return url
        }
        return Bundle.main.url(forResource: "ai-traffic-light-hook", withExtension: nil)
    }

    private static func loadFragment(named name: String, hookCommand: String) -> [String: Any]? {
        let url =
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "hooks")
            ?? Bundle.main.url(forResource: name, withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let rawFragment = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let fragment = replaceHookCommand(in: rawFragment, hookCommand: hookCommand) as? [String: Any] else {
            return nil
        }
        return fragment
    }

    private static func replaceHookCommand(in value: Any, hookCommand: String) -> Any {
        if var dict = value as? [String: Any] {
            for (key, nested) in dict {
                if key == "command", let command = nested as? String {
                    dict[key] = command.replacingOccurrences(of: "__HOOK_CMD__", with: hookCommand)
                } else {
                    dict[key] = replaceHookCommand(in: nested, hookCommand: hookCommand)
                }
            }
            return dict
        }

        if let array = value as? [Any] {
            return array.map { replaceHookCommand(in: $0, hookCommand: hookCommand) }
        }

        return value
    }

    private static func mergeCursor(configURL: URL, hookCommand: String, errors: inout [String]) {
        guard let fragment = loadFragment(named: "cursor-hooks.fragment", hookCommand: hookCommand) else {
            errors.append("缺少 Cursor hook 配置")
            return
        }

        var config = readJSONObject(at: configURL) ?? ["version": 1, "hooks": [:]]
        var hooks = config["hooks"] as? [String: Any] ?? [:]

        for (event, entries) in fragment {
            hooks[event] = entries
        }

        config["hooks"] = hooks
        writeJSONObject(config, to: configURL, errors: &errors, label: "Cursor")
    }

    private static func mergeNestedHooks(
        configURL: URL,
        hookCommand: String,
        source: String,
        resourceName: String,
        errors: inout [String]
    ) {
        guard let fragment = loadFragment(named: resourceName, hookCommand: hookCommand) else {
            errors.append("缺少 \(source) hook 配置")
            return
        }

        var config = readJSONObject(at: configURL) ?? [:]
        var hooks = config["hooks"] as? [String: Any] ?? [:]

        for (event, incomingAny) in fragment {
            let incoming = incomingAny as? [Any] ?? []
            let existing = hooks[event] as? [Any] ?? []
            hooks[event] = mergeEventList(existing: existing, incoming: incoming)
        }

        config["hooks"] = hooks
        writeJSONObject(config, to: configURL, errors: &errors, label: source)
    }

    private static func mergeEventList(existing: [Any], incoming: [Any]) -> [Any] {
        let kept = existing.filter { entry in
            guard let data = try? JSONSerialization.data(withJSONObject: entry),
                  let text = String(data: data, encoding: .utf8) else {
                return true
            }
            return !text.contains(marker)
        }
        return kept + incoming
    }

    private static func readJSONObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func writeJSONObject(
        _ object: [String: Any],
        to url: URL,
        errors: inout [String],
        label: String
    ) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            errors.append("写入 \(label) 配置失败：\(error.localizedDescription)")
        }
    }
}
