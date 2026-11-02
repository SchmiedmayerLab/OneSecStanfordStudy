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
    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true]) @available(iOS 18, *)
    func directoryFailureReportsErrorAndRespectsReset(forceReset: Bool, destinationIsFile: Bool) async throws {
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
            destination: destinationIsFile ? blocker : blocker.appendingPathComponent("export"),
            sampleTypes: [HKQuantityType(.stepCount)],
            timeRange: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1),
            didStartLocalExport: { _, _ in starts += 1 },
            didFinishLocalExport: { results.append($0) }
        )
        let module = OneSecStanfordStudyModule(healthExportConfig: config, preferences: LocalPreferencesStore(defaults: defaults))
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
        expectStartupFailure(try #require(results.first), matching: try #require(thrownError))
        #expect(try Data(contentsOf: blocker) == Data("existing file".utf8))
        #expect(try storage.load(checkpoint) == (forceReset ? nil : existingCheckpoint))
        let restorationKey = LocalPreferenceKey<Bool>(
            .init("didInitiateBulkExport", in: .custom("edu.stanford.SpeziOneSec")), default: false
        )
        #expect(LocalPreferencesStore(defaults: defaults)[restorationKey])
    }

    private func expectStartupFailure(_ result: HealthExportResult, matching error: NSError) {
        guard case .failedToStart(let reportedError) = result.outcome else {
            Issue.record("Expected a startup failure")
            return
        }
        #expect((reportedError as NSError).domain == error.domain)
        #expect((reportedError as NSError).code == error.code)
    }

    @Test(.timeLimit(.minutes(1))) @available(iOS 18, *)
    func launchRetriesFailedStartup() async throws {
        let suiteName = "HealthExportStartupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (results, continuation) = AsyncStream.makeStream(of: HealthExportResult.self)
        defer { continuation.finish() }
        let config = HealthExportConfiguration(
            destination: try #require(URL(string: "https://example.invalid/export")),
            timeRange: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1),
            didStartLocalExport: { _, _ in Issue.record("Invalid configuration must not open a stream") },
            didFinishLocalExport: { continuation.yield($0) }
        )
        let module = OneSecStanfordStudyModule(healthExportConfig: config, preferences: LocalPreferencesStore(defaults: defaults))
        await #expect(throws: HealthExportConfiguration.ValidationError.self) {
            try await module.triggerHealthExport()
        }
        var iterator = results.makeAsyncIterator()
        let first = try #require(await iterator.next())
        let restored = OneSecStanfordStudyModule(
            healthExportConfig: config,
            preferences: LocalPreferencesStore(defaults: try #require(UserDefaults(suiteName: suiteName)))
        )
        withDependencyResolution(standard: ExportTestStandard()) {
            HealthKit()
            BulkHealthExporter()
            restored
        }
        let retried = try #require(await iterator.next())
        #expect(retried.attemptID != first.attemptID)
        guard case .failedToStart = retried.outcome else {
            Issue.record("Launch must retry the pending request even if configuration still needs correction")
            return
        }
    }
}

@available(iOS 18, *)
private actor ExportTestStandard: Standard, HealthKitConstraint {
    func handleNewSamples<Sample>(_ addedSamples: some Collection<Sample>, ofType sampleType: SampleType<Sample>) async {}
    func handleDeletedObjects<Sample>(_ deletedObjects: some Collection<HKDeletedObject>, ofType sampleType: SampleType<Sample>) async {}
}
