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

This package combines the original interface and implementation packages into one package that depends on the Grove monorepo.

The old two-package setup worked around a deployment-target mismatch by dynamically loading the iOS 18 implementation from a separate framework while exposing an iOS 15 interface package.
The new single-repo version no longer needs that workaround: apps can depend on this single package and link the implementation directly.


## Installation

Add this package to your app and select the `OneSecStanfordStudy` product. The package can be added to app targets that support iOS 15 or newer. The study integration is active on iOS 18 and newer; on older iOS versions, initialization and the root view modifier are no-ops.

This package currently depends on Grove's export-fix branch:

```swift
.package(
    url: "https://github.com/SchmiedmayerLab/Grove.git",
    branch: "feature/healthkit-export-integrity",
    traits: []
)
```

That branch enables lowered deployment targets for iOS 15 compatibility.
Consume this study package through its branch while it uses a branch dependency.

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
                timeRange: timeRange,
                didStartLocalExport: { attemptID, files in
                    // Consume files in an app-owned task and persist upload jobs with attemptID.
                },
                didFinishLocalExport: { result in
                    switch result.outcome {
                    case .succeeded(let summary):
                        // Record successful local processing for result.attemptID.
                        break
                    case .incomplete(let summary):
                        // Record batch counts and retain retry state.
                        break
                    case .failedToPersist(let summary, let error):
                        // Retain files and retry state; the checkpoint was not confirmed.
                        break
                    case .cancelled(let reason):
                        // Close this attempt; retain files already queued for upload.
                        break
                    case .failedToStart(let error):
                        // Record the startup error; this attempt has no file stream.
                        break
                    }
                }
            )
        )
        return true
    }
}
```

### Export callbacks

The package queries HealthKit, converts samples and writes local batch files.
The calling app owns durable upload jobs, retries and server reconciliation.

| Callback | Payload and timing | Caller responsibility |
|---|---|---|
| `didStartLocalExport(attemptID, files)` | Called when an attempt opens its stream. URLs arrive as nonempty batches succeed; the stream may be empty. | Start one app-owned consumer task. Persist each file and its upload job with the attempt ID. |
| `didFinishLocalExport(result)` | One terminal outcome for that attempt, with the same `attemptID`. Startup failure can occur without a start callback. | Record the outcome and batch counts; keep upload status separate. |

`result.outcome` is one of:

| Outcome | Meaning |
|---|---|
| `.succeeded(summary)` | Every configured batch succeeded, including empty queries, and the final checkpoint was stored. This does not establish that every sample type contained data. |
| `.incomplete(summary)` | Processing stopped with failed, pending or unaccounted-for batches. Launch restoration remains enabled for retry. |
| `.failedToPersist(summary, error)` | The final checkpoint write failed. Batch counts can be complete while restoration state is not confirmed. Retry remains enabled; retain emitted files. |
| `.cancelled(reason)` | Reset, session termination or startup-task cancellation ended the attempt. Previously emitted files remain the caller's responsibility. |
| `.failedToStart(error)` | Validation, authorization, session preparation or starting failed before a stream was opened. The error is also thrown to the initiating caller. |

`HealthExportBatchSummary` counts all batches in the session, including earlier attempts: `totalBatches`, successful `completedBatches`, `failedBatches` and remaining `pendingBatches` (excluding failures).
A successful empty query emits no file; batch counts are not file or sample counts.
On resume, only newly processed files are emitted, so reconcile uploads against the persisted manifest across attempts.

Both callbacks run synchronously on `MainActor`; keep them short and delegate file/network work to an app-owned coordinator.
The result can arrive before the consumer drains the stream or finishes uploads.
If the host records `didEndSequence`, emit it after every yielded file has a durable upload job.
If it records `didFinishUploading`, emit it after reconciling server receipts with the file manifest.
Complete delivery requires successful local processing, a drained stream and acknowledgment of all expected files.
Survey completion is separate.

Each retry or reset creates a new attempt ID; it is not a participant ID or a persistent export-session ID.
The host must retain the association with the participant and export manifest across launches.
Duplicate starts of a running session and already-completed sessions do not create new callbacks or replay files.
Callbacks are in-process notifications: app termination can prevent a terminal callback, and results are not replayed after relaunch.
A reset reports cancellation of the old attempt before preparing the replacement; its stream may still be draining.

### Sample types

`HealthExportConfiguration.defaultSampleTypes` contains eight types.

| Protocol measure | HealthKit type |
|---|---|
| Time in bed and awake/REM/core/deep sleep | `HKCategoryType(.sleepAnalysis)` |
| Steps | `HKQuantityType(.stepCount)` |
| Walking/running distance | `HKQuantityType(.distanceWalkingRunning)` |
| Flights climbed | `HKQuantityType(.flightsClimbed)` |
| Active energy | `HKQuantityType(.activeEnergyBurned)` |
| Workouts | `HKObjectType.workoutType()` |
| State of mind | `HKObjectType.stateOfMindType()` |
| Time in daylight | `HKQuantityType(.timeInDaylight)` |


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
