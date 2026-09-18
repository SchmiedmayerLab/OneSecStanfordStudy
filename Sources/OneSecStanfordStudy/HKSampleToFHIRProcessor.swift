//
// This source file was adapted from the My Heart Counts iOS application.
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

private import FHIRModelsExtensions
import Foundation
private import GroveHealthKitFHIR
private import ModelsR4
private import GroveFoundation
import GroveHealthKit
import GroveHealthKitBulkExport


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
        var resources = try samples.mapIntoResourceProxies()
        for index in resources.indices {
            // Preserve absolute instants through the repeated DST hour.
            if var observation = resources[index].get(if: ModelsR4::Observation.self) {
                try observation.setEffective(startDate: samples[index].startDate, endDate: samples[index].endDate, timeZone: .gmt)
                resources[index] = ResourceProxy(with: observation)
            }
            if var resource = resources[index].get() as? any ModelsR4::DomainResource {
                resource.stripDeviceNameMetadata()
                resources[index] = ResourceProxy(with: resource)
            }
        }
        let encoded = try JSONEncoder().encode(consume resources)
        let compressed = try (consume encoded).compressed(using: Zlib.self)
        let compressedUrl = outputDirectory.appendingPathComponent("\(sampleType.id)_\(UUID().uuidString).json.zlib")
        try (consume compressed).write(to: compressedUrl, options: .atomic)
        return compressedUrl
    }
}


@available(iOS 18, *)
extension ModelsR4::DomainResource {
    /// Removes the `HKSourceRevision.source.name` metadata field from the resource, if it exists.
    mutating func stripDeviceNameMetadata() {
        guard var extensions = self.extension else { return }
        let revisionURLs = FHIRExtensionURL.sourceRevision.allURLs
        let sourceURLs = FHIRExtensionURL.sourceRevision.appending(component: "source").allURLs
        let nameURLs = FHIRExtensionURL.sourceRevision.appending(components: ["source", "name"]).allURLs
        for revisionIndex in extensions.indices where extensions[revisionIndex].url.value.map({ revisionURLs.contains($0.url) }) == true {
            guard var sources = extensions[revisionIndex].extension else { continue }
            for sourceIndex in sources.indices where sources[sourceIndex].url.value.map({ sourceURLs.contains($0.url) }) == true {
                sources[sourceIndex].extension?.removeAll { field in
                    field.url.value.map { nameURLs.contains($0.url) } ?? false
                }
            }
            extensions[revisionIndex].extension = sources
        }
        self.extension = extensions
    }
}
