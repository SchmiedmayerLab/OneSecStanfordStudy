//
// This source file is part of the OneSecStanfordStudy open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import HealthKit
import OneSecStanfordStudy
import SwiftUI

final class TestAppDelegate: NSObject, UIApplicationDelegate {
    private var sampleTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKCategoryType(.sleepAnalysis)
        ]
        if #available(iOS 18.0, *) {
            types.insert(.stateOfMindType())
        }
        return types
    }

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? // swiftlint:disable:this discouraged_optional_collection
    ) -> Bool {
        let calendar = Calendar.current
        initializeOneSecStanfordStudy(
            application,
            launchOptions: launchOptions,
            healthExportConfig: .init(
                destination: FileManager.default.temporaryDirectory,
                sampleTypes: sampleTypes,
                timeRange: calendar.date(byAdding: .year, value: -1, to: .now)!..<Date.now, // swiftlint:disable:this force_unwrapping
                didStartExport: Self.handleHealthExportDidStart,
                didEndExport: Self.handleHealthExportDidEnd
            )
        )
        return true
    }

    @MainActor
    private static func handleHealthExportDidStart(_ urls: AnyAsyncSequence<URL, Never>) {
        Task {
            do {
                for try await url in urls {
                    print("Did create export batch \(url)")
                }
            } catch {
                fatalError("Should not throw an error during testing here ...")
            }
        }
    }

    @MainActor
    private static func handleHealthExportDidEnd() {
        print("Health Export complete")
    }
}
