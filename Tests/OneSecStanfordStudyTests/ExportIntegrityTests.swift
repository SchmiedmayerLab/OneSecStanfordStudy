//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import Foundation
import HealthKit
import GroveHealthKitFHIR
import ModelsR4
import GroveFoundation
import GroveHealthKit
@testable import OneSecStanfordStudy
import Testing

@Suite struct ExportIntegrityTests {
    @Test @available(iOS 18, *)
    func defaultTypesMatchDocumentedSet() throws {
        let config = HealthExportConfiguration(
            destination: URL(fileURLWithPath: "/tmp/export"),
            timeRange: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1),
            didStartLocalExport: { _, _ in }, didFinishLocalExport: { _ in }
        )
        let expected: Set<String> = [
            "HKCategoryTypeIdentifierSleepAnalysis",
            "HKQuantityTypeIdentifierStepCount",
            "HKQuantityTypeIdentifierDistanceWalkingRunning",
            "HKQuantityTypeIdentifierFlightsClimbed",
            "HKQuantityTypeIdentifierActiveEnergyBurned",
            "HKWorkoutTypeIdentifier",
            "HKDataTypeStateOfMind",
            "HKQuantityTypeIdentifierTimeInDaylight"
        ]
        #expect(Set(config.sampleTypes.map(\.identifier)) == expected)
        try config.validate()
    }

    @Test func explicitTypesOverrideDefault() throws {
        let config = HealthExportConfiguration(
            destination: URL(fileURLWithPath: "/tmp/export"),
            sampleTypes: [HKQuantityType(.stepCount)],
            timeRange: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1),
            didStartLocalExport: { _, _ in }, didFinishLocalExport: { _ in }
        )
        #expect(config.sampleTypes == [HKQuantityType(.stepCount)])
        try config.validate()
    }

    @Test func rejectsUnexportableConfiguration() throws {
        let config = HealthExportConfiguration(
            destination: URL(fileURLWithPath: "/tmp/export"),
            sampleTypes: [HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!],
            timeRange: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1),
            didStartLocalExport: { _, _ in }, didFinishLocalExport: { _ in }
        )
        #expect(throws: HealthExportConfiguration.ValidationError.self) { try config.validate() }
    }

    @Test @available(iOS 18, *)
    func compressedExportPreservesDSTInstantsAndSampleID() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = try #require(ISO8601DateFormatter().date(from: "2025-10-26T00:55:00Z"))
        let end = try #require(ISO8601DateFormatter().date(from: "2025-10-26T01:05:00Z"))
        let sample = HKQuantitySample(
            type: HKQuantityType(.stepCount), quantity: HKQuantity(unit: .count(), doubleValue: 12),
            start: start, end: end, metadata: [HKMetadataKeyTimeZone: "Europe/Berlin"]
        )
        let processor = HKSampleToFHIRProcessor(outputDirectory: directory)
        let file = try #require(try processor.process([sample], of: SampleType.stepCount))
        let data = try Data(contentsOf: file).decompressed(using: Zlib.self)
        let observations = try JSONDecoder().decode([Observation].self, from: data)
        let observation = try #require(observations.first)
        #expect(observations.count == 1)
        let revision = try #require(observation.extensions(for: FHIRExtensionURL.sourceRevision.r4).first)
        let sourceURL = FHIRExtensionURL.sourceRevision.appending(component: "source")
        let source = try #require(revision.extensions(for: sourceURL).first)
        #expect(source.extensions(for: sourceURL.appending(component: "name")).isEmpty)
        #expect(!source.extensions(for: sourceURL.appending(component: "bundleIdentifier")).isEmpty)
        #expect(observation.id?.value?.string == sample.uuid.uuidString)
        guard case .period(let period) = observation.effective else {
            Issue.record("Expected a period")
            return
        }
        #expect(try #require(period.start?.value).asNSDate() == start)
        #expect(try #require(period.end?.value).asNSDate() == end)
        #expect(try processor.process([HKQuantitySample](), of: SampleType.stepCount) == nil)
    }

    @Test(arguments: [
        HealthExportBatchSummary(totalBatches: 4, completedBatches: 3, failedBatches: 1, pendingBatches: 0),
        HealthExportBatchSummary(totalBatches: 4, completedBatches: 3, failedBatches: 0, pendingBatches: 1),
        HealthExportBatchSummary(totalBatches: 4, completedBatches: 3, failedBatches: 0, pendingBatches: 0),
        HealthExportBatchSummary(totalBatches: 0, completedBatches: 0, failedBatches: 0, pendingBatches: 0)
    ])
    func incompleteExportIsNotSuccess(_ outcome: HealthExportBatchSummary) {
        #expect(!outcome.allBatchesSucceeded)
    }

    @Test func completeExportAndRoundTrip() throws {
        let outcome = HealthExportBatchSummary(totalBatches: 4, completedBatches: 4, failedBatches: 0, pendingBatches: 0)
        #expect(outcome.allBatchesSucceeded)
        #expect(try JSONDecoder().decode(HealthExportBatchSummary.self, from: JSONEncoder().encode(outcome)) == outcome)
    }

    @Test(arguments: ["success", "noteligible", "waitingforconsent"])
    func acceptsExactCallback(_ name: String) throws {
        let url = try #require(URL(string: "https://one-sec.app/survey-callback/\(name)?token=example"))
        #expect(StudySurveyCallback(url: url)?.rawValue == name)
    }

    @Test(arguments: [
        "https://one-sec.app/help", "https://one-sec.app/survey-callback/success-extra",
        "https://one-sec.app/other/survey-callback/success", "http://one-sec.app/survey-callback/success",
        "https://one-sec.app.example.org/survey-callback/success", "https://one-sec.app:444/survey-callback/success",
        "https://user@one-sec.app/survey-callback/success", "https://one-sec.app/survey-callback/unknown"
    ])
    func rejectsOtherNavigation(_ address: String) throws {
        #expect(StudySurveyCallback(url: try #require(URL(string: address))) == nil)
    }
}
