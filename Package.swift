// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pasteur",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Pasteur", targets: ["Pasteur"])
    ],
    targets: [
        .executableTarget(
            name: "Pasteur",
            path: "macos/Pasteur",
            resources: [
                .copy("Resources/web-dist"),
                .copy("Resources/pasteur_icon.png")
            ]
        )
    ]
)
