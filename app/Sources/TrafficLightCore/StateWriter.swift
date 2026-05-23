import Foundation

public enum StateWriter {
    public static let runningStaleInterval: TimeInterval = 60
    public static let thinkingStaleInterval: TimeInterval = 90

    private static let validStates: Set<String> = ["idle", "thinking", "running"]
    private static let validSources: Set<String> = ["cursor", "claude", "codex"]
    private static let priority: [String: Int] = ["running": 3, "thinking": 2, "idle": 1]

    private static var stateDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ai-traffic-light", isDirectory: true)
    }

    private static var stateFile: URL {
        stateDirectory.appendingPathComponent("state.json")
    }

    public static func write(state rawState: String, source rawSource: String) throws {
        let state = validStates.contains(rawState) ? rawState : "idle"

        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)

        var sources = loadSources()
        let now = utcNow()

        if rawSource == "all" {
            for source in validSources.sorted() {
                sources[source] = ["state": state, "updated_at": now]
            }
        } else {
            guard validSources.contains(rawSource) else {
                throw StateWriterError.invalidSource(rawSource)
            }
            sources[rawSource] = ["state": state, "updated_at": now]
        }

        try persist(sources: sources, now: now)
    }

    @discardableResult
    public static func resetAllSourcesToIdle() throws -> String {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let now = utcNow()
        var sources: [String: [String: String]] = [:]
        for source in validSources.sorted() {
            sources[source] = ["state": "idle", "updated_at": now]
        }
        try persist(sources: sources, now: now)
        return "idle"
    }

    @discardableResult
    public static func reconcile(persistChanges: Bool = true) -> String {
        guard let data = try? Data(contentsOf: stateFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "idle"
        }

        var sources = sourcesFromJSON(json)
        let now = Date()
        let nowString = utcNow(from: now)
        var changed = false

        for source in validSources {
            guard var entry = sources[source] else { continue }
            let state = validStates.contains(entry["state"] ?? "") ? entry["state"]! : "idle"
            guard state != "idle" else { continue }

            let staleAfter = state == "running" ? runningStaleInterval : thinkingStaleInterval
            guard isStale(updatedAt: entry["updated_at"], now: now, staleAfter: staleAfter) else { continue }

            entry["state"] = "idle"
            entry["updated_at"] = nowString
            sources[source] = entry
            changed = true
        }

        let (effectiveState, _) = pickEffective(from: sources)

        if changed && persistChanges {
            try? persist(sources: sources, now: nowString)
        }

        return effectiveState
    }

    private static func persist(sources: [String: [String: String]], now: String) throws {
        let (effectiveState, effectiveSource) = pickEffective(from: sources)
        let payload: [String: Any] = [
            "state": effectiveState,
            "source": effectiveSource,
            "updated_at": now,
            "sources": sources
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateFile, options: .atomic)
    }

    private static func utcNow(from date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func loadSources() -> [String: [String: String]] {
        guard let data = try? Data(contentsOf: stateFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return sourcesFromJSON(json)
    }

    private static func sourcesFromJSON(_ json: [String: Any]) -> [String: [String: String]] {
        if let sources = json["sources"] as? [String: [String: String]] {
            return sources
        }

        let legacyState = json["state"] as? String ?? "idle"
        let legacySource = json["source"] as? String ?? "cursor"
        let legacyUpdated = json["updated_at"] as? String ?? utcNow()
        guard validSources.contains(legacySource) else { return [:] }

        return [
            legacySource: [
                "state": legacyState,
                "updated_at": legacyUpdated
            ]
        ]
    }

    private static func isStale(updatedAt: String?, now: Date, staleAfter: TimeInterval) -> Bool {
        guard let updatedAt, let updated = parseUTC(updatedAt) else { return false }
        return now.timeIntervalSince(updated) > staleAfter
    }

    private static func parseUTC(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: value)
    }

    private static func pickEffective(from sources: [String: [String: String]]) -> (String, String) {
        var bestState = "idle"
        var bestSource = "none"
        var bestRank = 0
        var bestTime = ""

        for (source, entry) in sources {
            guard validSources.contains(source) else { continue }
            let state = validStates.contains(entry["state"] ?? "") ? entry["state"]! : "idle"
            let rank = priority[state] ?? 0
            let updated = entry["updated_at"] ?? ""
            if rank > bestRank || (rank == bestRank && updated > bestTime) {
                bestState = state
                bestSource = source
                bestRank = rank
                bestTime = updated
            }
        }

        return (bestState, bestSource)
    }
}

public enum StateWriterError: Error, CustomStringConvertible {
    case invalidSource(String)

    public var description: String {
        switch self {
        case .invalidSource(let source):
            return "Invalid source: \(source)"
        }
    }
}
