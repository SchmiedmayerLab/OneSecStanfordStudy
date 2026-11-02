//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

import Foundation

/// Coalesces starts, preserving a reset requested while ordinary startup is in flight.
@MainActor
final class HealthExportStartCoordinator {
    private struct Start {
        let id: UUID
        let forceSessionReset: Bool
        let task: Task<Void, any Error>
    }

    private var current: Start?

    func start(
        forceSessionReset: Bool,
        operation: @escaping @MainActor (Bool) async throws -> Void
    ) -> Task<Void, any Error> {
        if let current, !forceSessionReset || current.forceSessionReset {
            return current.task
        }
        let predecessor = current?.task
        let id = UUID()
        let task = Task { @MainActor in
            defer {
                if self.current?.id == id {
                    self.current = nil
                }
            }
            // A failed ordinary start must not discard the queued reset.
            if let predecessor {
                _ = await predecessor.result
            }
            try await operation(forceSessionReset)
        }
        current = Start(id: id, forceSessionReset: forceSessionReset, task: task)
        return task
    }
}
