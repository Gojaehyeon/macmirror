// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macmirror",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "CVirtualDisplay",
            path: "Sources/CVirtualDisplay",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation")
            ]
        ),
        .executableTarget(
            name: "macmirror",
            dependencies: ["CVirtualDisplay"],
            path: "Sources/macmirror",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Network"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
