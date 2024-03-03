// swift-tools-version: 5.9

import Foundation
import PackageDescription

var globalSwiftSettings: [PackageDescription.SwiftSetting] = []

if ProcessInfo.processInfo.environment["LOCAL_BUILD"] != nil {
    globalSwiftSettings.append(.enableExperimentalFeature("StrictConcurrency"))
}

let package = Package(
    name: "automerge-repo",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(
            name: "AutomergeRepo",
            targets: ["AutomergeRepo"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/automerge/automerge-swift", .upToNextMajor(from: "0.5.7")),
        .package(url: "https://github.com/outfoxx/PotentCodables", .upToNextMajor(from: "3.1.0")),
        .package(url: "https://github.com/keefertaylor/Base58Swift", .upToNextMajor(from: "2.1.14")),
    ],
    targets: [
        .target(
            name: "AutomergeRepo",
            dependencies: [.product(name: "Automerge", package: "automerge-swift"),
                           .product(name: "PotentCodables", package: "PotentCodables"),
                           .product(name: "Base58Swift", package: "Base58Swift")
                          ]
        ),
        .testTarget(
            name: "AutomergeRepoTests",
            dependencies: ["AutomergeRepo"]
        ),
    ]
)
