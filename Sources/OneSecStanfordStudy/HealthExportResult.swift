//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveHealthKitBulkExport

/// The terminal result of one local export attempt; it does not describe upload status.
public struct HealthExportResult: Sendable {
    public enum Outcome: Sendable {
        /// Every configured batch succeeded and the final checkpoint was stored.
        case succeeded(HealthExportBatchSummary)
        /// The session paused, or its batch counts do not establish completion.
        case incomplete(HealthExportBatchSummary)
        /// The final checkpoint could not be stored; retain files and retry state.
        case failedToPersist(HealthExportBatchSummary, CheckpointWriteFailure)
        /// The attempt was cancelled; files already emitted may still need uploading.
        case cancelled(CancellationReason)
        /// No file stream was opened. The error is also thrown to the initiating caller.
        case failedToStart(any Error)
    }

    public enum CancellationReason: Sendable {
        case sessionReset
        case sessionTerminated
        case taskCancelled
    }

    /// Matches the ID passed to `didStartLocalExport`; each retry receives a new ID.
    public let attemptID: UUID
    public let outcome: Outcome

    public init(attemptID: UUID, outcome: Outcome) {
        self.attemptID = attemptID
        self.outcome = outcome
    }
}
