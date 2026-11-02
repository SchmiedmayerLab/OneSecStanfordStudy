//
// This source file is part of the One Sec Stanford Study open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import HealthKit
import OneSecStanfordStudy
import SwiftUI

final class TestAppDelegate: NSObject, UIApplicationDelegate {
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
                timeRange: calendar.date(byAdding: .year, value: -1, to: .now)!..<Date.now, // swiftlint:disable:this force_unwrapping
                didStartLocalExport: Self.handleLocalExportDidStart,
                didFinishLocalExport: Self.handleLocalExportDidFinish
            )
        )
        return true
    }

    @MainActor
    private static func handleLocalExportDidStart(_ attemptID: UUID, _ urls: AnyAsyncSequence<URL, Never>) {
        Task {
            do {
                for try await url in urls {
                    print("Local export \(attemptID) created batch \(url)")
                }
            } catch {
                fatalError("Should not throw an error during testing here ...")
            }
        }
    }

    @MainActor
    private static func handleLocalExportDidFinish(_ result: HealthExportResult) {
        print("Local export \(result.attemptID): \(result.outcome)")
    }
}
