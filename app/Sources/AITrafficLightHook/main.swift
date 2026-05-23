import Darwin
import Foundation
import TrafficLightCore

let args = CommandLine.arguments.dropFirst()
var state = "idle"
var source = "cursor"

if let first = args.first {
    if first == "set" {
        state = args.dropFirst().first ?? "idle"
        source = args.dropFirst().dropFirst().first ?? "cursor"
    } else {
        state = first
        source = args.dropFirst().first ?? "cursor"
    }
}

if source == "claude" || source == "codex" {
    if let stdin = readAvailableStdin(), stdin.contains("\"cursor_version\"") {
        exit(0)
    }
}

do {
    try StateWriter.write(state: state, source: source)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}

private func readAvailableStdin(limit: Int = 1_048_576, waitMs: Int = 100) -> String? {
    let fd = STDIN_FILENO
    var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    guard poll(&pfd, 1, Int32(waitMs)) > 0, (pfd.revents & Int16(POLLIN)) != 0 else {
        return nil
    }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 65_536)

    while data.count < limit {
        let count = read(fd, &buffer, buffer.count)
        if count > 0 {
            data.append(buffer, count: count)
            continue
        }
        break
    }

    guard !data.isEmpty else { return nil }
    return String(data: data, encoding: .utf8)
}
