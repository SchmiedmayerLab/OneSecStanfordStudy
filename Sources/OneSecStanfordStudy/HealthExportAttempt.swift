//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveHealthKitBulkExport
import Observation

/// Delivers at most one start and one terminal result for an in-process attempt.
@MainActor
final class HealthExportAttempt {
    let id = UUID()
    private let configuration: HealthExportConfiguration
    private var didStart = false
    private(set) var didFinish = false
    private var isResetting = false
    private var deferredCompletion: (@MainActor () -> Void)?

    init(configuration: HealthExportConfiguration) {
        self.configuration = configuration
    }

    func start(files: AnyAsyncSequence<URL, Never>) {
        guard !didStart && !didFinish else { return }
        didStart = true
        configuration.didStartLocalExport(id, files)
    }

    @available(iOS 18, *)
    func trackCompletion(
        of session: some BulkExportSession,
        willFinish: @escaping @MainActor (HealthExportResult.Outcome) -> Void
    ) {
        guard !didFinish else { return }
        if isResetting {
            deferredCompletion = { self.trackCompletion(of: session, willFinish: willFinish) }
            return
        }
        let state = session.state
        if state == .running {
            withObservationTracking {
                _ = session.state
            } onChange: {
                Task { @MainActor in
                    self.trackCompletion(of: session, willFinish: willFinish)
                }
            }
            return
        }
        let outcome: HealthExportResult.Outcome
        if state == .terminated {
            outcome = .cancelled(.sessionTerminated)
        } else {
            let summary = HealthExportBatchSummary(
                totalBatches: session.numTotalBatches,
                completedBatches: session.completedBatches.count,
                failedBatches: session.failedBatches.count,
                pendingBatches: session.pendingBatches.count
            )
            if let error = session.persistenceError {
                outcome = .failedToPersist(summary, error)
            } else {
                outcome = summary.allBatchesSucceeded ? .succeeded(summary) : .incomplete(summary)
            }
        }
        willFinish(outcome)
        finish(outcome)
    }

    func resetSession(_ reset: @MainActor () async throws -> Void) async throws {
        isResetting = true
        defer {
            isResetting = false
            let completion = deferredCompletion
            deferredCompletion = nil
            completion?()
        }
        // Deletion may terminate the session before throwing a storage error.
        try await reset()
        finish(.cancelled(.sessionReset))
    }

    func finish(_ outcome: HealthExportResult.Outcome) {
        guard !didFinish else { return }
        didFinish = true
        configuration.didFinishLocalExport(HealthExportResult(attemptID: id, outcome: outcome))
    }
}
