//
// This source file was adapted from the My Heart Counts iOS application.
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
private import HealthKitOnFHIR
private import SpeziFoundation
import SpeziHealthKit
import SpeziHealthKitBulkExport

@available(iOS 18, *)
struct HKSampleToFHIRProcessor: BatchProcessor {
    let outputDirectory: URL

    func process<Sample>(_ samples: consuming [Sample], of sampleType: SampleType<Sample>) throws -> URL? {
        guard !samples.isEmpty else {
            return nil
        }
        return try storeSamples(samples, of: sampleType)
    }

    private func storeSamples<Sample>(_ samples: consuming [Sample], of sampleType: SampleType<Sample>) throws -> URL {
        let resources = try samples.mapIntoResourceProxies()
        _ = consume samples
        let encoded = try JSONEncoder().encode(resources)
        _ = consume resources
        let compressed = try encoded.compressed(using: Zlib.self)
        _ = consume encoded
        let compressedUrl = outputDirectory.appendingPathComponent("\(sampleType.id)_\(UUID().uuidString).json.zlib")
        try compressed.write(to: compressedUrl)
        _ = consume compressed
        return compressedUrl
    }
}
