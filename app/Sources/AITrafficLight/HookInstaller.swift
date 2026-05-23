import AppKit
import Foundation
import TrafficLightCore

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
            errors.append("Failed to install hook CLI: \(error.localizedDescription)")
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
        ensureCodexHooksEnabled(
            configURL: home.appendingPathComponent(".codex/config.toml"),
            errors: &errors
        )
        trustCodexHooks(errors: &errors)

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
        alert.messageText = "IDE integration ready"
        alert.informativeText = """
        Cursor, Claude Code, and Codex hooks are configured. Codex hooks were auto-trusted when possible.

        If the Codex lamp still does not react, fully quit and reopen Codex.app.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func installBundledCLI() throws {
        guard let bundled = bundledHookCLI() else {
            throw NSError(domain: "HookInstaller", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Bundled hook CLI not found"
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
            errors.append("Missing Cursor hook configuration")
            return
        }

        var config = readJSONObject(at: configURL) ?? ["version": 1, "hooks": [:]]
        var hooks = config["hooks"] as? [String: Any] ?? [:]

        for event in Array(hooks.keys) {
            guard fragment[event] == nil else { continue }
            guard let entries = hooks[event] as? [Any], !entries.isEmpty else { continue }
            let onlyOurs = entries.allSatisfy { entry in
                guard let data = try? JSONSerialization.data(withJSONObject: entry),
                      let text = String(data: data, encoding: .utf8) else {
                    return false
                }
                return text.contains(marker)
            }
            if onlyOurs {
                hooks.removeValue(forKey: event)
            }
        }

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
            errors.append("Missing \(source) hook configuration")
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

    private static func ensureCodexHooksEnabled(configURL: URL, errors: inout [String]) {
        var text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        var changed = false

        let deprecatedPatterns = [
            "codex_hooks = true",
            "codex_hooks=true",
            "codex_hooks = false",
            "codex_hooks=false"
        ]
        for pattern in deprecatedPatterns {
            if text.contains(pattern) {
                text = text.replacingOccurrences(of: pattern, with: "")
                changed = true
            }
        }

        if !containsHooksFeatureEnabled(in: text) {
            if let featuresRange = text.range(of: "[features]") {
                let insertPoint = text.index(featuresRange.upperBound, offsetBy: 0)
                let prefix = text[..<insertPoint]
                let suffix = text[insertPoint...]
                if suffix.hasPrefix("\n") {
                    text = String(prefix) + "\nhooks = true" + String(suffix)
                } else {
                    text = String(prefix) + "\nhooks = true\n" + String(suffix)
                }
            } else {
                if !text.isEmpty && !text.hasSuffix("\n") {
                    text += "\n"
                }
                text += "\n[features]\nhooks = true\n"
            }
            changed = true
        }

        guard changed else { return }

        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            errors.append("Failed to write Codex config.toml: \(error.localizedDescription)")
        }
    }

    private static func containsHooksFeatureEnabled(in text: String) -> Bool {
        text.contains("hooks = true") || text.contains("hooks=true")
    }

    private static func trustCodexHooks(errors: inout [String]) {
        guard let script = bundledTrustScript() else {
            errors.append("Missing Codex hook trust script")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path]

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            errors.append("Failed to run Codex hook trust script: \(error.localizedDescription)")
            return
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            errors.append(message?.isEmpty == false ? message! : "Codex hook trust failed")
            return
        }
    }

    private static func bundledTrustScript() -> URL? {
        if let url = Bundle.main.url(
            forResource: "trust-codex-hooks",
            withExtension: "py",
            subdirectory: "hooks"
        ) {
            return url
        }
        return Bundle.main.url(forResource: "trust-codex-hooks", withExtension: "py")
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
            errors.append("Failed to write \(label) configuration: \(error.localizedDescription)")
        }
    }
}
