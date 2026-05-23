// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AITrafficLight",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "TrafficLightCore"
        ),
        .executableTarget(
            name: "AITrafficLightHook",
            dependencies: ["TrafficLightCore"]
        ),
        .executableTarget(
            name: "AITrafficLight",
            dependencies: ["TrafficLightCore"],
            resources: [.process("Resources")]
        )
    ]
)
