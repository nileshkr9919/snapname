// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Snapname",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Snapname",
            path: "Sources/Snapname"
        ),
        .testTarget(
            name: "SnapnameTests",
            dependencies: ["Snapname"],
            path: "Tests/SnapnameTests"
        ),
    ]
)
