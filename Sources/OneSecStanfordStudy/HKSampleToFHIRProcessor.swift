//
// This source file was adapted from the My Heart Counts iOS application.
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
private import GroveFoundation
import GroveHealthKit
import GroveHealthKitBulkExport
import GroveHealthKitFHIR


/// Writes each batch as one zlib-compressed Grove exchange Bundle and counts the samples Grove cannot convert.
@available(iOS 18, *)
struct HKSampleToFHIRProcessor: BatchProcessor {
    enum ProcessingError: Error {
        /// The batch holds a second version of a source record, which one Bundle cannot state.
        case recordDeferred
    }

    let outputDirectory: URL
    let exporter: HealthKitFHIRExporter
    let skippedSamples: SkippedSamplesReport

    func process<Sample>(_ samples: consuming [Sample], of sampleType: SampleType<Sample>) async throws -> URL? {
        // One file holds the whole batch, so the Bundle has no size cap.
        var packer = ExchangeBundlePacker(kind: .active, maximumRecords: .max, maximumBytes: .max)
        var refusals: [String: Int] = [:]
        try await exporter.export(samples) { export in
            switch export.outcome {
            case .record(let record):
                guard try packer.insert(record) != .deferred else {
                    throw ProcessingError.recordDeferred
                }
            case .refused(let error):
                // A refusal is deterministic: failing the batch would only repeat it on every retry.
                refusals[error.diagnostic.code, default: 0] += 1
            }
        }
        if !refusals.isEmpty {
            try skippedSamples.add(refusals, sampleType: sampleType.id)
        }
        guard packer.recordCount > 0 else {
            return nil
        }
        let bundle = try packer.bundle(packedAt: .now)
        let compressed = try bundle.json.compressed(using: Zlib.self)
        let compressedUrl = outputDirectory.appendingPathComponent("\(sampleType.id)_\(UUID().uuidString).json.zlib")
        try (consume compressed).write(to: compressedUrl, options: .atomic)
        return compressedUrl
    }
}
