//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

@testable import OneSecStanfordStudy
import Testing

@Suite @MainActor struct HealthExportStartCoordinatorTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true]) @available(iOS 16, *)
    func resetWaitsForOrdinaryStartupAndCoalescesLaterRequests(firstStartFails: Bool) async throws {
        let coordinator = HealthExportStartCoordinator()
        let (started, startedContinuation) = AsyncStream.makeStream(of: Bool.self)
        let (ordinaryGate, ordinaryContinuation) = AsyncStream.makeStream(of: Void.self)
        let (resetGate, resetContinuation) = AsyncStream.makeStream(of: Void.self)
        defer {
            startedContinuation.finish()
            ordinaryContinuation.finish()
            resetContinuation.finish()
        }
        var calls: [Bool] = []
        var ordinaryFinished = false
        let operation: @MainActor (Bool) async throws -> Void = { reset in
            if reset { #expect(ordinaryFinished) }
            defer {
                if !reset { ordinaryFinished = true }
            }
            calls.append(reset)
            startedContinuation.yield(reset)
            for await _ in reset ? resetGate : ordinaryGate {}
            if !reset && firstStartFails { throw StartupError.failed }
        }
        let ordinary = coordinator.start(forceSessionReset: false, operation: operation)
        let duplicate = coordinator.start(forceSessionReset: false, operation: operation)
        var events = started.makeAsyncIterator()
        #expect(await events.next() == false)
        let reset = coordinator.start(forceSessionReset: true, operation: operation)
        let duplicateReset = coordinator.start(forceSessionReset: true, operation: operation)
        #expect(calls == [false])
        ordinaryContinuation.finish()
        #expect(await events.next() == true)
        // The predecessor's cleanup must not clear the reset that is now running.
        let laterReset = coordinator.start(forceSessionReset: true, operation: operation)
        let laterOrdinary = coordinator.start(forceSessionReset: false, operation: operation)
        resetContinuation.finish()
        try await reset.value
        try await duplicateReset.value
        try await laterReset.value
        try await laterOrdinary.value
        for task in [ordinary, duplicate] {
            if firstStartFails {
                await #expect(throws: StartupError.self) { try await task.value }
            } else {
                try await task.value
            }
        }
        #expect(calls == [false, true])
    }

    @Test(.timeLimit(.minutes(1))) @available(iOS 16, *)
    func startupFailureAllowsAnotherAttempt() async throws {
        let coordinator = HealthExportStartCoordinator()
        let failed = coordinator.start(forceSessionReset: true) { _ in throw StartupError.failed }
        await #expect(throws: StartupError.self) { try await failed.value }
        var didRetry = false
        let retry = coordinator.start(forceSessionReset: false) { reset in
            #expect(!reset)
            didRetry = true
        }
        try await retry.value
        #expect(didRetry)
    }
}

private enum StartupError: Error {
    case failed
}
