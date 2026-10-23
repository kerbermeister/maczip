// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacZip",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacZip", targets: ["MacZip"])],
    targets: [
        .target(name: "ArchiveCore"),
        .executableTarget(name: "MacZip", dependencies: ["ArchiveCore"]),
        .testTarget(name: "ArchiveCoreTests", dependencies: ["ArchiveCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MacZipTests", dependencies: ["MacZip", "ArchiveCore"])
    ]
)
