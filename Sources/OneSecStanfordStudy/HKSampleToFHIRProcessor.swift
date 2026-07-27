//
// This source file was adapted from the My Heart Counts iOS application.
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable line_length

import Foundation
private import HealthKitOnFHIR
private import ModelsR4
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
        let resources = try (consume samples).mapIntoResourceProxies()
        for resource in resources {
            resource.get(if: ModelsR4::DomainResource.self)?.stripDeviceNameMetadata()
        }
        let encoded = try JSONEncoder().encode(consume resources)
        let compressed = try (consume encoded).compressed(using: Zlib.self)
        let compressedUrl = outputDirectory.appendingPathComponent("\(sampleType.id)_\(UUID().uuidString).json.zlib")
        try (consume compressed).write(to: compressedUrl)
        return compressedUrl
    }
}


extension ModelsR4::DomainResource {
    nonisolated(unsafe) private static let sourceRevisionUrl = "https://bdh.stanford.edu/fhir/defs/sourceRevision".asFHIRURIPrimitive()!
    nonisolated(unsafe) private static let sourceRevisionSourceUrl = "https://bdh.stanford.edu/fhir/defs/sourceRevision/source".asFHIRURIPrimitive()!
    nonisolated(unsafe) private static let sourceRevisionSourceDeviceNameUrl = "https://bdh.stanford.edu/fhir/defs/sourceRevision/source/name".asFHIRURIPrimitive()!
    
    /// Removes the `HKSourceRevision.source.name` metadata field from the resource, if it exists.
    func stripDeviceNameMetadata() {
        for sourceRevisionExt in self.extensions(for: Self.sourceRevisionUrl) {
            for sourceExt in sourceRevisionExt.extensions(for: Self.sourceRevisionSourceUrl) {
                sourceExt.removeAllExtensions(withUrl: Self.sourceRevisionSourceDeviceNameUrl)
            }
        }
    }
}
