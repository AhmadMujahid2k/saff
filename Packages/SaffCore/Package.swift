// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SaffCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "SaffCore", targets: ["SaffCore"])],
    dependencies: [
        .package(url: "https://github.com/batoulapps/adhan-swift", exact: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SaffCore",
            dependencies: [.product(name: "Adhan", package: "adhan-swift")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Command-line sanity check: `swift run saffcheck`
        .executableTarget(
            name: "saffcheck",
            dependencies: ["SaffCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
