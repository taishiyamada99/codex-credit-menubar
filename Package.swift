// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CodexCreditMenuBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexCreditMenuBar", targets: ["CodexCreditMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "CodexCreditMenuBar",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CodexCreditMenuBarTests",
            dependencies: ["CodexCreditMenuBar"]
        )
    ]
)
