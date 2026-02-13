// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "macOSWindows",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "CenterWindow",
            targets: ["macOSWindows"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "macOSWindows"
        ),
        .testTarget(
            name: "macOSWindowsTests",
            dependencies: [
                "macOSWindows",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
