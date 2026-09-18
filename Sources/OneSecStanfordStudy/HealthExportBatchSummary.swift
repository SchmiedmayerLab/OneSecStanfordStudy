//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

/// Session-wide batch counts, including work completed by earlier attempts.
public struct HealthExportBatchSummary: Codable, Sendable, Equatable {
    /// All batches in the session.
    public let totalBatches: Int
    /// Successful batches, including empty queries that produced no file.
    public let completedBatches: Int
    /// Attempted batches that failed.
    public let failedBatches: Int
    /// Batches still awaiting processing, excluding failed batches.
    public let pendingBatches: Int

    /// Whether every batch succeeded. Empty sample queries count as successful.
    public var allBatchesSucceeded: Bool {
        totalBatches > 0 && completedBatches == totalBatches && failedBatches == 0 && pendingBatches == 0
    }

    public init(totalBatches: Int, completedBatches: Int, failedBatches: Int, pendingBatches: Int) {
        self.totalBatches = totalBatches
        self.completedBatches = completedBatches
        self.failedBatches = failedBatches
        self.pendingBatches = pendingBatches
    }
}
