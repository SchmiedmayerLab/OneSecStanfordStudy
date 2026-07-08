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
        .package(url: "https://github.com/SchmiedmayerLab/Spezi.git", branch: "oldiOSVersion", traits: [])
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
