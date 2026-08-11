<!--

This source file is part of the One Sec Stanford Study open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# OneSecStanfordStudy

[![Build and Test](https://github.com/SchmiedmayerLab/OneSecStanfordStudy/actions/workflows/ci.yml/badge.svg)](https://github.com/SchmiedmayerLab/OneSecStanfordStudy/actions/workflows/ci.yml)
[![REUSE status](https://api.reuse.software/badge/github.com/SchmiedmayerLab/OneSecStanfordStudy)](https://api.reuse.software/info/github.com/SchmiedmayerLab/OneSecStanfordStudy)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)

Stanford study integration module for the one sec app's Digital Interventions Outcome study.


## Overview

This package combines the original interface and implementation packages into one package that depends on the Spezi monorepo.

The old two-package setup worked around a deployment-target mismatch by dynamically loading the iOS 18 implementation from a separate framework while exposing an iOS 15 interface package.
The new single-repo version no longer needs that workaround: apps can depend on this single package and link the implementation directly.


## Installation

Add this package to your app and select the `OneSecStanfordStudy` product. The package can be added to app targets that support iOS 15 or newer. The study integration is active on iOS 18 and newer; on older iOS versions, initialization and the root view modifier are no-ops.

This setup temporarily depends on the Spezi monorepo feature branch that adds the monorepo-backed deployment target support:

```swift
.package(url: "https://github.com/SchmiedmayerLab/Spezi.git", branch: "oldiOSVersion", traits: [])
```

After the Spezi changes are merged and tagged, replace the branch dependency with the tagged `0.x` release range:

```swift
.package(url: "https://github.com/SchmiedmayerLab/Spezi.git", "0.1.0"..<"0.2.0", traits: [])
```

Then add the product dependency to the target that needs it:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "OneSecStanfordStudy", package: "OneSecStanfordStudy")
    ]
)
```


## Usage

Call `initializeOneSecStanfordStudy(_:launchOptions:healthExportConfig:)` from your app delegate's `application(_:willFinishLaunchingWithOptions:)` method:

```swift
import OneSecStanfordStudy
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        initializeOneSecStanfordStudy(
            application,
            launchOptions: launchOptions,
            healthExportConfig: HealthExportConfiguration(
                destination: healthExportDirectory,
                sampleTypes: sampleTypes,
                timeRange: timeRange,
                didStartExport: { files in
                    // Upload or process the generated files.
                },
                didEndExport: {
                    // Handle completion.
                }
            )
        )
        return true
    }
}
```

Apply `.oneSecStanfordStudy()` to the root of your SwiftUI hierarchy:

```swift
WindowGroup {
    ContentView()
        .oneSecStanfordStudy()
}
```

The runtime is configured directly and `OneSecStanfordStudyModule` is available through SwiftUI environment injection:

```swift
@Environment(OneSecStanfordStudyModule.self) private var oneSec
```


## Testing

The package includes unit tests in `Tests/OneSecStanfordStudyTests` and a consolidated iOS UI test app in `Tests/UITests`.

Run the UI test app with the `TestApp` scheme in `Tests/UITests/UITests.xcodeproj`. The test app has an iOS 15 deployment target. On iOS 15 and iOS 16, the wrapper launch test validates that initialization and `.oneSecStanfordStudy()` are no-ops. On iOS 18 and newer, the same app validates the active integration and the web view alert/confirm hooks.

## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guidelines](https://github.com/SchmiedmayerLab/.github/blob/main/CONTRIBUTING.md) and the [contributor covenant code of conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first. You can find a list of contributors in the [CONTRIBUTORS.md](CONTRIBUTORS.md) file.

## License

This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for more information.

## Citation

If you use this software, please cite it using the metadata in [CITATION.cff](CITATION.cff), which GitHub surfaces through the [*Cite this repository*](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-citation-files) button.

## Our Research

For more information, visit the [Schmiedmayer Lab GitHub organization](https://github.com/SchmiedmayerLab).

![Schmiedmayer Lab](https://raw.githubusercontent.com/SchmiedmayerLab/.github/main/assets/footer-light.png#gh-light-mode-only)
![Schmiedmayer Lab](https://raw.githubusercontent.com/SchmiedmayerLab/.github/main/assets/footer-dark.png#gh-dark-mode-only)
