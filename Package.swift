// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CleanMyClaude",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CleanMyClaude",
            path: "Sources/CleanMyClaude",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
