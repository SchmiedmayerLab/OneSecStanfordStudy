// swift-tools-version:6.2

//
// This source file is part of the OneSecStanfordStudy open-source project
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
        .package(url: "https://github.com/SchmiedmayerLab/Spezi.git", revision: "513178d3f0356a2c0ce5c11c8882e6b59dd3f971", traits: [])
    ],
    targets: [
        .target(
            name: "OneSecStanfordStudy",
            dependencies: [
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "SpeziFoundation", package: "Spezi"),
                .product(name: "SpeziHealthKit", package: "Spezi"),
                .product(name: "SpeziHealthKitBulkExport", package: "Spezi"),
                .product(name: "HealthKitOnFHIR", package: "Spezi"),
                .product(name: "SpeziLocalStorage", package: "Spezi")
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
