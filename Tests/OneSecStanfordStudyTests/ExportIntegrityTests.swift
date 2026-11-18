//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import GroveHealthKitFHIR
import HealthKit
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
    func rejectsSampleTypesNotSupportedByExporter() throws {
        let documentType = try #require(HKObjectType.documentType(forIdentifier: .CDA))
        let config = HealthExportConfiguration(
            destination: URL(fileURLWithPath: "/tmp/export"),
            sampleTypes: [HKQuantityType(.stepCount), documentType],
            timeRange: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1),
            didStartLocalExport: { _, _ in }, didFinishLocalExport: { _ in }
        )
        #expect(documentType.sampleType == nil)
        #expect(throws: HealthExportConfiguration.ValidationError.self) { try config.validate() }
    }

    @Test @available(iOS 18, *)
    func compressedBundlePreservesDSTInstantsAndSampleID() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = try #require(ISO8601DateFormatter().date(from: "2025-10-26T00:55:00Z"))
        let end = try #require(ISO8601DateFormatter().date(from: "2025-10-26T01:05:00Z"))
        let sample = HKQuantitySample(
            type: HKQuantityType(.stepCount), quantity: HKQuantity(unit: .count(), doubleValue: 12),
            start: start, end: end, metadata: [HKMetadataKeyTimeZone: "Europe/Berlin"]
        )
        let skippedSamples = SkippedSamplesReport(directory: directory)
        let processor = HKSampleToFHIRProcessor(
            outputDirectory: directory,
            exporter: try Self.exporter(participantID: "participant-1"),
            skippedSamples: skippedSamples
        )
        let file = try #require(try await processor.process([sample], of: SampleType.stepCount))
        #expect(file.lastPathComponent.hasPrefix("HKQuantityTypeIdentifierStepCount_"))
        #expect(file.lastPathComponent.hasSuffix(".json.zlib"))
        let data = try Data(contentsOf: file).decompressed(using: Zlib.self)
        let graph = try ExchangeGraph(validating: data, kind: .active)
        let resources = graph.bundle.entry?.compactMap { $0.resource?.get() } ?? []
        let observations = resources.compactMap { $0 as? Observation }
        let observation = try #require(observations.first)
        #expect(observations.count == 1)
        #expect(observation.subject?.identifier?.value?.value?.string == "participant-1")
        #expect(observation.identifier?.contains { $0.value?.value?.string == sample.uuid.uuidString.lowercased() } == true)
        guard case .period(let period) = observation.effective else {
            Issue.record("Expected a period")
            return
        }
        #expect(try #require(period.start?.value).asNSDate() == start)
        #expect(try #require(period.end?.value).asNSDate() == end)
        #expect(try await processor.process([HKQuantitySample](), of: SampleType.stepCount) == nil)
        #expect(skippedSamples.existingFile == nil)
    }

    @Test @available(iOS 18, *)
    func skippedSamplesAccumulateInOneReport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = SkippedSamplesReport(directory: directory)
        try report.add(["code-b": 2, "code-a": 1], sampleType: "HKQuantityTypeIdentifierStepCount")
        // A later launch continues the same file.
        try SkippedSamplesReport(directory: directory).add(["code-b": 3], sampleType: "HKQuantityTypeIdentifierStepCount")
        let file = try #require(report.existingFile)
        #expect(file.lastPathComponent == "skipped-samples.json")
        let entries = try JSONDecoder().decode([SkippedSamplesReport.Entry].self, from: Data(contentsOf: file))
        #expect(entries == [
            .init(sampleType: "HKQuantityTypeIdentifierStepCount", diagnosticCode: "code-a", count: 1),
            .init(sampleType: "HKQuantityTypeIdentifierStepCount", diagnosticCode: "code-b", count: 5)
        ])
        report.remove()
        #expect(report.existingFile == nil)
    }

    @Test @available(iOS 18, *)
    func recordIdentityFollowsIdentityAndParticipant() async throws {
        let sample = HKQuantitySample(
            type: HKQuantityType(.stepCount), quantity: HKQuantity(unit: .count(), doubleValue: 12),
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60)
        )
        let identity = HealthExportIdentity()
        func sourceRecord(_ identity: HealthExportIdentity, participantID: String) async throws -> BusinessIdentifier {
            var records: [ExchangeRecord] = []
            try await Self.exporter(identity, participantID: participantID).export([sample]) { export in
                if let record = export.record {
                    records.append(record)
                }
            }
            return try #require(records.first).sourceRecord
        }
        let first = try await sourceRecord(identity, participantID: "participant-1")
        // Another device that received the identity through iCloud Keychain decodes the same value.
        let synchronized = try JSONDecoder().decode(HealthExportIdentity.self, from: JSONEncoder().encode(identity))
        #expect(try await sourceRecord(synchronized, participantID: "participant-1") == first)
        #expect(try await sourceRecord(identity, participantID: "participant-2") != first)
        #expect(try await sourceRecord(HealthExportIdentity(), participantID: "participant-1") != first)
    }

    @available(iOS 18, *)
    private static func exporter(
        _ identity: HealthExportIdentity = HealthExportIdentity(),
        participantID: String
    ) throws -> HealthKitFHIRExporter {
        try identity.exporter(
            participantID: participantID,
            application: ApplicationDevice(name: "Tests", bundleIdentifier: "edu.stanford.OneSecStanfordStudy.tests", version: "1")
        )
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
        "https://ONE-SEC.APP/survey-callback/success",
        "https://one-sec.app:443/survey-callback/success",
        "https://one-sec.app:444/survey-callback/success",
        "https://user@one-sec.app/survey-callback/success",
        "https://one-sec.app/survey-callback/success/",
        "https://one-sec.app/survey-callback/success?token=example#complete"
    ])
    func acceptsCallbackURLVariants(_ address: String) throws {
        #expect(StudySurveyCallback(url: try #require(URL(string: address))) == .success)
    }

    @Test(arguments: [
        "https://one-sec.app/help", "https://one-sec.app/survey-callback/success-extra",
        "https://one-sec.app/other/survey-callback/success", "http://one-sec.app/survey-callback/success",
        "https://one-sec.app.example.org/survey-callback/success", "https://one-sec.app@other.example/survey-callback/success",
        "https://one-sec.app/survey-callback/unknown"
    ])
    func rejectsOtherNavigation(_ address: String) throws {
        #expect(StudySurveyCallback(url: try #require(URL(string: address))) == nil)
    }
}
