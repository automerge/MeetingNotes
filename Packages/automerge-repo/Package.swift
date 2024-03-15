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
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AutomergeRepo",
            dependencies: [
                .product(name: "Automerge", package: "automerge-swift"),
                .product(name: "PotentCodables", package: "PotentCodables"),
                .product(name: "Base58Swift", package: "Base58Swift"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            // borrowing a set of Swift6 enabling features to double-check against
            // future proofing concurrency, safety, and exportable feature-creep.
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),

                // .unsafeFlags(["-require-explicit-sendable"]),

                .enableExperimentalFeature("AccessLevelOnImport"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "AutomergeRepoTests",
            dependencies: ["AutomergeRepo"]
        ),
    ]
)
