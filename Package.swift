// swift-tools-version:6.3
//
// This source file is part of the One Sec Stanford Study open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault")
]

let package = Package(
    name: "OneSecStanfordStudy",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "OneSecStanfordStudy", targets: ["OneSecStanfordStudy"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/SchmiedmayerLab/Grove.git",
            branch: "feature/healthkit-export-integrity",
            traits: []
        )
    ],
    targets: [
        .target(
            name: "OneSecStanfordStudy",
            dependencies: [
                .product(name: "Grove", package: "Grove"),
                .product(name: "GroveFoundation", package: "Grove"),
                .product(name: "GroveHealthKit", package: "Grove"),
                .product(name: "GroveHealthKitBulkExport", package: "Grove"),
                .product(name: "GroveHealthKitFHIR", package: "Grove"),
                .product(name: "FHIRModelsExtensions", package: "Grove")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "OneSecStanfordStudyTests",
            dependencies: [
                .target(name: "OneSecStanfordStudy")
            ],
            swiftSettings: swiftSettings
        )
    ],
    swiftLanguageModes: [.v6]
)
