import Foundation

public enum StateWriter {
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
        guard validSources.contains(rawSource) else {
            throw StateWriterError.invalidSource(rawSource)
        }

        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)

        var sources = loadSources()
        let now = utcNow()
        sources[rawSource] = ["state": state, "updated_at": now]

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

    private static func utcNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }

    private static func loadSources() -> [String: [String: String]] {
        guard let data = try? Data(contentsOf: stateFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

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
