// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SplitDNSManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SplitDNSManager", targets: ["SplitDNSManager"])
    ],
    targets: [
        // UI-free logic: validation, resolver file handling, privileged execution and the view model.
        .target(name: "SplitDNSCore"),
        // The SwiftUI application shell.
        .executableTarget(
            name: "SplitDNSManager",
            dependencies: ["SplitDNSCore"]
        ),
        .testTarget(
            name: "SplitDNSCoreTests",
            dependencies: ["SplitDNSCore"]
        ),
    ]
)
