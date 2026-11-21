//
// This source file is part of the One Sec Stanford Study open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Synchronization


/// Counts the samples the export skipped, by sample type and Grove diagnostic code, in one JSON file next to the exported files.
///
/// The file holds no sample values. It accumulates across batches and app launches until the session is reset.
@available(iOS 18, *)
final class SkippedSamplesReport: Sendable {
    struct Entry: Codable, Hashable, Sendable {
        let sampleType: String
        let diagnosticCode: String
        var count: Int
    }

    let file: URL
    private let lock = Mutex(())

    /// The report file, once a sample was skipped.
    var existingFile: URL? {
        FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    init(directory: URL) {
        self.file = directory.appendingPathComponent("skipped-samples.json")
    }

    /// Adds the skipped samples of one batch, as counts by diagnostic code.
    func add(_ counts: [String: Int], sampleType: String) throws {
        try lock.withLock { _ in
            var entries = (try? JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))) ?? []
            for (code, count) in counts {
                if let index = entries.firstIndex(where: { $0.sampleType == sampleType && $0.diagnosticCode == code }) {
                    entries[index].count += count
                } else {
                    entries.append(Entry(sampleType: sampleType, diagnosticCode: code, count: count))
                }
            }
            entries.sort { ($0.sampleType, $0.diagnosticCode) < ($1.sampleType, $1.diagnosticCode) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: file, options: .atomic)
        }
    }

    func remove() {
        lock.withLock { _ in
            try? FileManager.default.removeItem(at: file)
        }
    }
}
