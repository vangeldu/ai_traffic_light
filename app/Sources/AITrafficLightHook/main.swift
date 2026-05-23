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

do {
    try StateWriter.write(state: state, source: source)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
