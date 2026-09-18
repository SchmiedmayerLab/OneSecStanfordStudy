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

This package links the Grove-based study implementation directly into the host app.
It supports iOS 15 and newer; study features run on iOS 18 and newer.

## Installation

Add the `OneSecStanfordStudy` product to your app.
On iOS 15–17, initialization and the root view modifier are no-ops.

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
                        // Record success for result.attemptID.
                        break
                    case .incomplete(let summary):
                        // Record batch counts and retain retry state.
                        break
                    case .failedToPersist(let summary, let error):
                        // Keep files and address error.category before retrying.
                        break
                    case .cancelled(let reason):
                        // Keep files already queued for upload.
                        break
                    case .failedToStart(let error):
                        // Record the error; no file stream was opened.
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

The package queries HealthKit, converts samples and writes batch files.
The host app handles uploads, upload retries and server receipts.

| Callback | Contract |
|---|---|
| `didStartLocalExport(attemptID, files)` | Opens the attempt's stream. Consume it in an app-owned task and persist an upload job for each file. The stream may be empty. |
| `didFinishLocalExport(result)` | Reports one final outcome with the same attempt ID. It can arrive before the stream is drained or uploads finish. Startup failure has no preceding start callback. |

Both callbacks run synchronously on `MainActor`; keep file and network work in the consumer task.

| Outcome | Meaning |
|---|---|
| `.succeeded(summary)` | All batches succeeded and the final checkpoint was stored. Empty queries count as successful. |
| `.incomplete(summary)` | The session paused or batch counts are incomplete. Retry remains enabled. |
| `.failedToPersist(summary, error)` | The checkpoint write failed, even if all batches succeeded. `CheckpointWriteFailure` provides a recovery category, domain, code and message. |
| `.cancelled(reason)` | Reset, termination or startup-task cancellation ended the attempt. Keep files already queued for upload. |
| `.failedToStart(error)` | Startup failed before opening a stream. The error is also thrown to the caller. |

`HealthExportBatchSummary` counts the whole session, including earlier attempts: `totalBatches`, `completedBatches`, `failedBatches` and `pendingBatches` (excluding failures).
Empty queries emit no file; batch counts do not measure files, samples or upload delivery.

Record `didEndSequence` after every yielded file has a durable upload job, and `didFinishUploading` after all expected files have server receipts.
Survey completion is independent of export and upload completion.
On resume, the stream emits only newly processed files; reconcile uploads across attempts using the host's saved file manifest.

Each started retry or reset gets a new attempt ID. Associate it with the participant and export manifest.
Starting an already-running or completed session does not produce new callbacks or replay files.
Callbacks are not persisted: app termination may prevent the final callback, and results are not replayed after launch.
A successful reset reports cancellation before preparing its replacement; the old stream may still be draining.

### Recovering an export

For `.failedToPersist`, retain emitted files and upload jobs, then address `error.category`:

| Category | Action before retrying |
|---|---|
| `.insufficientSpace` | Free device storage. |
| `.temporarilyUnavailable` | Wait for storage to become available. |
| `.accessDenied` | Check permissions and protected-data availability; the error alone does not identify the cause. |
| `.invalidDestination` | Correct the storage location or configuration. |
| `.unknown` | Inspect the error domain, code and message. |

Resume with `triggerHealthExport()`, as the export screen and launch restoration do.
Call this public method on the environment-injected `OneSecStanfordStudyModule`, on `MainActor` on iOS 18 or newer.
Retry after a user action or storage availability change, not repeatedly from the failure callback.

Session progress is checkpointed for restoration across launches.
After a checkpoint failure, the live session retains unsaved progress; retrying it preserves completed batches and may emit no new files.
If the app terminates first, restoration may repeat batches whose completion was not saved.
Generated files and upload jobs are separate from that checkpoint and must be retained by the host.
Deduplicate HealthKit samples by participant ID and sample UUID.
Use `forceSessionReset: true` only for an intentional restart.

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

On iOS 18 and newer, access study state, the survey sheet and export retries through `OneSecStanfordStudyModule`:

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
