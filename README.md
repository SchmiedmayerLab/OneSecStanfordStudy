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

Supports iOS 15 and newer. Study features require iOS 18; initialization and the view modifier do nothing on earlier versions.

## Installation

Use a branch dependency for this package. Its Grove dependency is pinned to a commit that uses the iOS 15 configuration with optional traits disabled:

```swift
.package(
    url: "https://github.com/SchmiedmayerLab/Grove.git",
    revision: "d34149c068e4e5f00ff5c577818690998327fe9e",
    traits: []
)
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

On iOS 18 and newer, access the module through the environment:

```swift
@Environment(OneSecStanfordStudyModule.self) private var oneSec
```

Set `surveyUrl` and `participantID`, then use `makeOneSecStanfordStudySheet()` to present the survey.
`participantID` is the study's identifier of the participant, such as the REDCap record ID. An export started without it fails with `OneSecStanfordStudyModule.HealthExportError.missingParticipantID`.
Use `updateState(.available)` to reset enrollment in TestFlight. Export progress and files are kept.
Call module methods on `MainActor`.

### Exports

The package writes HealthKit data to local files. Your app uploads them and tracks backend receipts.

Each file holds one batch as a zlib-compressed FHIR R4 Bundle in the [Grove exchange format](https://grovealliance.org/fhir/healthkit/).
The subject of each sample's resource is the participant, identified by `participantID` under `https://schmiedmayerlab.stanford.edu/fhir/onesec/identifiers/participant`.
The resource of each sample carries its lowercase HealthKit UUID as an identifier whose system ends in `/healthkit-native-record`. The system is specific to the participant's HealthKit store.
The export leaves out the name of the source that wrote a sample, which can be a name a person gave a device, and the name, serial number, UDI and local identifier of the recording device.

Grove's opaque identifiers are derived from a random key that the package creates on first use and stores in the iCloud-synchronized keychain.
The key survives a reinstall. With iCloud Keychain enabled, the participant's devices share it once it has synchronized, and a sample then gets the same source-record identifier on each of them.

Samples that Grove cannot convert are skipped. A batch without convertible samples produces no file.
The package counts skipped samples by sample type and Grove diagnostic code in `skipped-samples.json` in the export directory. The file holds no sample values.
If it exists, the file stream yields it last, after the batch files of each attempt. The counts cover the whole session, and a batch that is repeated is counted again.

- `didStartLocalExport(attemptID, files)` provides the file stream. Consume it in an app-owned task and save upload jobs as files arrive.
- `didFinishLocalExport(result)` reports the local outcome. It can arrive before file consumption or uploads finish, or without a start callback if startup fails.

Both callbacks run on `MainActor`. Each started attempt gets a new ID; associate it with the participant and upload jobs.

| Outcome | Meaning |
|---|---|
| `.succeeded(summary)` | All batches succeeded and progress was saved. |
| `.incomplete(summary)` | Processing paused or batches remain unfinished. |
| `.failedToPersist(summary, error)` | Saving progress failed. Check `error.category` before retrying. |
| `.cancelled(reason)` | The attempt was reset, terminated or cancelled. |
| `.failedToStart(error)` | Startup failed. The error is also thrown to the caller. |

Batch counts cover the whole session, including earlier attempts. Empty queries count as successful and produce no file, including when HealthKit read access is denied.
Survey completion, local export success and confirmed uploads are separate. Report outcomes and upload status to your backend as needed.

Keep files and upload jobs across attempts: resumed streams only yield newly processed files.
Callbacks are not saved or replayed after app termination, and starting an already-running or completed session produces no new callbacks.

### Recovering an export

Unfinished exports retry on the next launch, including failed starts. To retry sooner, resolve the error and call `triggerHealthExport()`.
There is no automatic retry loop. Storage errors may require freeing space, waiting for availability or correcting permissions; invalid configuration needs fixing.

A normal retry keeps completed batches and the original participant ID, sample types and date range.
After a failed progress save, restarting the app may repeat batches. Deduplicate samples by participant ID and HealthKit UUID.

Use `triggerHealthExport(forceSessionReset: true)` to start over or change the participant ID or export configuration.
An export that a package version without `participantID` left unfinished starts over on the next `triggerHealthExport()` after `participantID` is set.
Reset reports cancellation for an active attempt; its file stream may still be draining.

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
