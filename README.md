<!--

This source file is part of the One Sec Stanford Study open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# OneSecStanfordStudy

[![Build and Test](https://github.com/SchmiedmayerLab/OneSecStanfordStudy/actions/workflows/ci.yml/badge.svg)](https://github.com/SchmiedmayerLab/OneSecStanfordStudy/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/SchmiedmayerLab/OneSecStanfordStudy/branch/main/graph/badge.svg)](https://codecov.io/gh/SchmiedmayerLab/OneSecStanfordStudy)
[![REUSE status](https://api.reuse.software/badge/github.com/SchmiedmayerLab/OneSecStanfordStudy)](https://api.reuse.software/info/github.com/SchmiedmayerLab/OneSecStanfordStudy)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)

Stanford study integration module for the one sec app's Digital Interventions Outcome study.

## Overview

The package adds the study to the one sec app: it presents the enrollment survey in a web view, tracks the participant's study state, and exports the participant's HealthKit data to local files that the app uploads.

It supports iOS 15 and newer. The study runs on iOS 18 and newer; on earlier versions initialization and the view modifier do nothing.

## Installation

Add the package with a branch dependency:

```swift
.package(url: "https://github.com/SchmiedmayerLab/OneSecStanfordStudy.git", branch: "main")
```

Add the `OneSecStanfordStudy` product to your app target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "OneSecStanfordStudy", package: "OneSecStanfordStudy")
    ]
)
```


## Usage

Initialize the study in your app delegate:

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
                    // Consume files in a Task and save an upload job for each URL.
                },
                didFinishLocalExport: { result in
                    // Record result.attemptID and result.outcome.
                }
            )
        )
        return true
    }
}
```

Apply the view modifier at the root of your SwiftUI hierarchy:

```swift
WindowGroup {
    ContentView()
        .oneSecStanfordStudy()
}
```

On iOS 18 and newer, access the module through the environment and call its methods on `MainActor`:

```swift
@Environment(OneSecStanfordStudyModule.self) private var oneSec
```

| Member | Use |
|---|---|
| `surveyUrl` | The enrollment survey, built from the participant's REDCap token. Set it before presenting the survey. |
| `participantID` | The study's identifier of the participant, such as the REDCap record ID. Set it with `surveyUrl`. |
| `makeOneSecStanfordStudySheet()` | Presents the survey. The export starts when the survey reaches its HealthKit step. |
| `state` | The participant's study state. |
| `updateState(.available)` | Resets enrollment, for example in TestFlight. Export progress and files are kept. |
| `triggerHealthExport(forceSessionReset:)` | Starts, resumes or restarts the export. |

### Export callbacks

The package writes HealthKit data to files in `destination`. Your app uploads them and tracks backend receipts.

- `didStartLocalExport(attemptID, files)` provides the file stream. Consume it in an app-owned task and save an upload job for each URL.
- `didFinishLocalExport(result)` reports the local outcome. It can arrive before file consumption or uploads finish, and without a start callback if startup fails.

Both callbacks run on `MainActor`. Each started attempt gets a new ID; associate it with the participant and the upload jobs.

| Outcome | Meaning |
|---|---|
| `.succeeded(summary)` | All batches succeeded and progress was saved. |
| `.incomplete(summary)` | Processing paused or batches remain unfinished. |
| `.failedToPersist(summary, error)` | Saving progress failed. Check `error.category` before retrying. |
| `.cancelled(reason)` | The attempt was reset, terminated or cancelled. |
| `.failedToStart(error)` | Startup failed. The error is also thrown to the caller. |

Batch counts cover the whole session, including earlier attempts. An empty query counts as successful and produces no file, also when HealthKit read access is denied.
Survey completion, local export success and confirmed uploads are separate events.

Keep files and upload jobs across attempts: a resumed stream yields only newly processed files.
Callbacks are not saved or replayed after app termination, and starting a running or completed session produces no new callbacks.

### Exported files

Each batch is one file named `<HealthKit type identifier>_<UUID>.json.zlib`. It holds a zlib-compressed FHIR R4 Bundle in the [Grove exchange format](https://grovealliance.org/fhir/healthkit/).

| Content | Representation |
|---|---|
| Participant | The subject of each sample's resource, identified by `participantID` under `https://schmiedmayerlab.stanford.edu/fhir/onesec/identifiers/participant`. |
| HealthKit UUID | An identifier on each sample's resource, in lowercase. Its system ends in `/healthkit-native-record` and is specific to the participant's HealthKit store. |
| Grove identifiers | Derived from a random key that the package creates on first use and stores in the iCloud-synchronized keychain. |
| Omitted facts | The name of the source that wrote a sample, a source bundle identifier of the form `com.apple.health.<UUID>`, and the recording device's name, serial number, UDI and local identifier. |

The key survives a reinstall. With iCloud Keychain enabled, the participant's devices share it once it has synchronized, and a sample then gets the same source-record identifier on each of them.

Samples that Grove cannot convert are skipped, and a batch without convertible samples produces no file.
The package counts skipped samples by sample type and Grove diagnostic code in `skipped-samples.json` in `destination`. The file holds no sample values.
If it exists, the file stream yields it after the batch files of each attempt. Its counts cover the whole session, and a repeated batch is counted again.

### Export recovery

An unfinished export, including one that failed to start, retries on the next launch. To retry sooner, resolve the error and call `triggerHealthExport()`. The package does not retry on its own while the app runs.

A retry keeps completed batches and the original participant ID, sample types and date range.
After a failed progress save, restarting the app can repeat batches. Deduplicate samples by participant ID and HealthKit UUID.

`triggerHealthExport(forceSessionReset: true)` starts over and adopts the current `participantID` and export configuration. It reports cancellation for an active attempt, whose file stream may still be draining.

An export started without `participantID` fails with `OneSecStanfordStudyModule.HealthExportError.missingParticipantID`.
An export that a package version without `participantID` left unfinished starts over on the first `triggerHealthExport()` after `participantID` is set.

### Sample types

The default study sample types are listed below. Pass `sampleTypes` to override them; types Grove cannot represent fail startup.

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


## Testing

Unit tests are in `Tests/OneSecStanfordStudyTests`.
Run UI tests with the `TestApp` scheme in `Tests/UITests/UITests.xcodeproj`; they cover app launch and web view alerts and confirmations.

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
