//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

import Foundation
import Grove
import GroveFoundation
import GroveHealthKit
import GroveHealthKitBulkExport
@testable import GroveLocalStorage
import GroveTesting
import HealthKit
@testable import OneSecStanfordStudy
import Testing

@Suite @MainActor struct HealthExportStartupTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true]) @available(iOS 18, *)
    func directoryFailureReportsErrorAndRespectsReset(forceReset: Bool) async throws {
        let namespace = StorageNamespace.custom("HealthExportStartupTests.\(UUID().uuidString)")
        let storage = LocalStorage(namespace: namespace)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: namespace.containerURL())
        }
        let blocker = directory.appendingPathComponent("file")
        try Data("existing file".utf8).write(to: blocker)
        let suiteName = "HealthExportStartupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var starts = 0
        var results: [HealthExportResult] = []
        let config = HealthExportConfiguration(
            destination: blocker.appendingPathComponent("export"),
            sampleTypes: [HKQuantityType(.stepCount)],
            timeRange: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1),
            didStartLocalExport: { _, _ in starts += 1 },
            didFinishLocalExport: { results.append($0) }
        )
        let module = OneSecStanfordStudy(healthExportConfig: config, preferences: LocalPreferencesStore(defaults: defaults))
        withDependencyResolution(standard: ExportTestStandard()) {
            storage
            HealthKit()
            BulkHealthExporter()
            module
        }
        let checkpoint = LocalStorageKey<Data>("HealthKit.bulkExport.edu.stanford.OneSecStanfordStudy", setting: .unencrypted())
        let existingCheckpoint = Data("existing checkpoint".utf8)
        try storage.store(existingCheckpoint, for: checkpoint)

        var thrownError: NSError?
        do {
            try await module.triggerHealthExport(forceSessionReset: forceReset)
            Issue.record("Export must fail when its output directory cannot be created")
        } catch {
            thrownError = error as NSError
        }
        #expect(starts == 0)
        #expect(results.count == 1)
        guard case .failedToStart(let reportedError) = try #require(results.first).outcome else {
            Issue.record("Expected a startup failure")
            return
        }
        let error = try #require(thrownError)
        #expect((reportedError as NSError).domain == error.domain)
        #expect((reportedError as NSError).code == error.code)
        #expect(try Data(contentsOf: blocker) == Data("existing file".utf8))
        #expect(try storage.load(checkpoint) == (forceReset ? nil : existingCheckpoint))
    }
}

@available(iOS 18, *)
private actor ExportTestStandard: Standard, HealthKitConstraint {
    func handleNewSamples<Sample>(_ addedSamples: some Collection<Sample>, ofType sampleType: SampleType<Sample>) async {}
    func handleDeletedObjects<Sample>(_ deletedObjects: some Collection<HKDeletedObject>, ofType sampleType: SampleType<Sample>) async {}
}
