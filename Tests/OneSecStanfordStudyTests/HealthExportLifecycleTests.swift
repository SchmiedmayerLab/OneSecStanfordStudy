//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveHealthKit
@testable import GroveHealthKitBulkExport
import Observation
@testable import OneSecStanfordStudy
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct HealthExportLifecycleTests {
    @Test @available(iOS 18, *)
    func streamAndResultShareAttemptID() async throws {
        let recorder = CallbackRecorder()
        let attempt = HealthExportAttempt(configuration: recorder.configuration)
        let (files, continuation) = AsyncStream.makeStream(of: URL.self)
        let file = URL(fileURLWithPath: "/tmp/synthetic-export.json")
        attempt.start(files: AnyAsyncSequence(files))
        attempt.start(files: AnyAsyncSequence(files))
        continuation.yield(file)
        continuation.finish()
        attempt.finish(.succeeded(Self.success))
        attempt.finish(.cancelled(.sessionReset))
        #expect(recorder.startedIDs == [attempt.id])
        #expect(recorder.results.map(\.attemptID) == [attempt.id])
        // A processing result does not mean the caller has consumed the file stream.
        let stream = try #require(recorder.files)
        var received: [URL] = []
        for try await url in stream { received.append(url) }
        #expect(received == [file])
    }

    @Test(arguments: [BulkExportSessionState.completed, .paused, .terminated])
    @available(iOS 18, *)
    func reportsTerminalSessionState(_ terminalState: BulkExportSessionState) async throws {
        let recorder = CallbackRecorder()
        let session = StubExportSession()
        let attempt = HealthExportAttempt(configuration: recorder.configuration)
        attempt.start(files: AnyAsyncSequence(AsyncStream<URL> { $0.finish() }))
        attempt.trackCompletion(of: session) { _ in }
        switch terminalState {
        case .completed: session.completedBatches = [Self.batch]
        case .paused: session.failedBatches = [Self.batch]
        case .terminated, .running: break
        }
        session.state = terminalState
        var results = recorder.resultStream.makeAsyncIterator()
        let result = try #require(await results.next())
        #expect(result.attemptID == attempt.id)
        switch (terminalState, result.outcome) {
        case (.completed, .succeeded(let summary)): #expect(summary == Self.success)
        case (.paused, .incomplete(let summary)):
            #expect(summary.failedBatches == 1)
            #expect(!summary.allBatchesSucceeded)
        case (.terminated, .cancelled(.sessionTerminated)): break
        default: Issue.record("Unexpected terminal outcome")
        }
        attempt.trackCompletion(of: session) { _ in Issue.record("Duplicate completion") }
        #expect(recorder.results.count == 1)
    }

    @Test @available(iOS 18, *)
    func checkpointFailureOverridesSuccessfulBatchCounts() async throws {
        let recorder = CallbackRecorder()
        let session = StubExportSession()
        let attempt = HealthExportAttempt(configuration: recorder.configuration)
        attempt.trackCompletion(of: session) { _ in }
        session.completedBatches = [Self.batch]
        session.persistenceError = CocoaError(.fileWriteOutOfSpace)
        session.state = .paused
        var results = recorder.resultStream.makeAsyncIterator()
        let result = try #require(await results.next())
        guard case .failedToPersist(let summary, let error) = result.outcome else {
            Issue.record("A checkpoint failure must not report success")
            return
        }
        #expect(summary == Self.success)
        #expect((error as? CocoaError)?.code == .fileWriteOutOfSpace)
    }

    @Test @available(iOS 18, *)
    func resetSuppressesQueuedCompletionAndRetryGetsNewID() async throws {
        let recorder = CallbackRecorder()
        let session = StubExportSession()
        let oldAttempt = HealthExportAttempt(configuration: recorder.configuration)
        oldAttempt.start(files: AnyAsyncSequence(AsyncStream<URL> { $0.finish() }))
        oldAttempt.trackCompletion(of: session) { _ in Issue.record("Stale completion") }
        session.state = .paused // Queues a completion task on MainActor.
        oldAttempt.finish(.cancelled(.sessionReset))
        session.state = .running
        let retry = HealthExportAttempt(configuration: recorder.configuration)
        retry.start(files: AnyAsyncSequence(AsyncStream<URL> { $0.finish() }))
        retry.trackCompletion(of: session) { _ in }
        session.completedBatches = [Self.batch]
        session.state = .completed
        var results = recorder.resultStream.makeAsyncIterator()
        let cancelled = try #require(await results.next())
        let completed = try #require(await results.next())
        #expect(cancelled.attemptID == oldAttempt.id)
        #expect(completed.attemptID == retry.id)
        #expect(oldAttempt.id != retry.id)
        guard case .cancelled(.sessionReset) = cancelled.outcome,
              case .succeeded = completed.outcome else {
            Issue.record("Expected reset cancellation followed by retry success")
            return
        }
        #expect(recorder.results.count == 2)
    }

    @Test @available(iOS 18, *)
    func startupFailureReportsErrorWithoutOpeningStream() async throws {
        let recorder = CallbackRecorder()
        let config = HealthExportConfiguration(
            destination: try #require(URL(string: "https://example.invalid/export")),
            timeRange: Self.timeRange,
            didStartLocalExport: recorder.configuration.didStartLocalExport,
            didFinishLocalExport: recorder.configuration.didFinishLocalExport
        )
        let module = OneSecStanfordStudy(healthExportConfig: config)
        await #expect(throws: HealthExportConfiguration.ValidationError.self) {
            try await module.triggerHealthExport(forceSessionReset: false)
        }
        #expect(recorder.startedIDs.isEmpty)
        #expect(recorder.results.count == 1)
        let result = try #require(recorder.results.first)
        guard case .failedToStart(let error) = result.outcome else {
            Issue.record("Expected a startup failure")
            return
        }
        #expect(error is HealthExportConfiguration.ValidationError)
    }

    private static let timeRange = Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1)
    private static let success = HealthExportBatchSummary(totalBatches: 1, completedBatches: 1, failedBatches: 0, pendingBatches: 0)
    @available(iOS 18, *)
    private static var batch: ExportBatch { ExportBatch(sampleType: SampleType.stepCount, timeRange: timeRange) }
}

@MainActor
private final class CallbackRecorder {
    var startedIDs: [UUID] = []
    var files: AnyAsyncSequence<URL, Never>?
    var results: [HealthExportResult] = []
    let resultStream: AsyncStream<HealthExportResult>
    private let continuation: AsyncStream<HealthExportResult>.Continuation

    init() {
        (resultStream, continuation) = AsyncStream.makeStream(of: HealthExportResult.self)
    }

    var configuration: HealthExportConfiguration {
        HealthExportConfiguration(
            destination: URL(fileURLWithPath: "/tmp/export"),
            timeRange: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1),
            didStartLocalExport: { id, files in
                self.startedIDs.append(id)
                self.files = files
            },
            didFinishLocalExport: { result in
                self.results.append(result)
                self.continuation.yield(result)
            }
        )
    }
}

@available(iOS 18, *)
@Observable @MainActor
private final class StubExportSession: BulkExportSession {
    typealias Processor = HKSampleToFHIRProcessor
    let sessionId = BulkExportSessionIdentifier("test")
    var state: BulkExportSessionState = .running
    var persistenceError: (any Error)?
    var pendingBatches: [ExportBatch] = []
    var completedBatches: [ExportBatch] = []
    var failedBatches: [ExportBatch] = []
    var numTotalBatches: Int { 1 }
    var progress: BulkExportSessionProgress? { nil }

    func start(retryFailedBatches: Bool, concurrencyLevel: BulkExportConcurrencyLevel) throws(StartSessionError) -> AsyncStream<URL?> {
        state = .running
        return AsyncStream { $0.finish() }
    }

    func pause() async { state = .paused }
    func _terminate() async { state = .terminated } // swiftlint:disable:this identifier_name
}
