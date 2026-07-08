//
// This source file is part of the OneSecStanfordStudy open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import OneSecStanfordStudy
import Foundation
import HealthKit
import Testing

@Suite
struct OneSecStanfordStudyTests {
    @Test
    func healthExportConfigurationStoresValues() {
        let destination = URL(filePath: "/tmp/one-sec-export")
        let sampleTypes: Set<HKObjectType> = []
        let timeRange = Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1)

        let configuration = HealthExportConfiguration(
            destination: destination,
            sampleTypes: sampleTypes,
            timeRange: timeRange,
            didStartExport: { _ in },
            didEndExport: {}
        )

        #expect(configuration.destination == destination)
        #expect(configuration.sampleTypes == sampleTypes)
        #expect(configuration.timeRange == timeRange)
    }

    @Test
    func anyAsyncSequenceWrapsNonThrowingSequences() async throws {
        let stream = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
            continuation.finish()
        }
        let sequence = AnyAsyncSequence<Int, Never>(unsafelyAssumingDoesntThrow: stream)

        var values: [Int] = []
        for try await value in sequence {
            values.append(value)
        }

        #expect(values == [1, 2, 3])
    }
}
