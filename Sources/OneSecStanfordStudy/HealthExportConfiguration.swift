//
// This source file is part of the One Sec Stanford Study open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import HealthKit

public struct HealthExportConfiguration: Sendable {
    /// Called once an attempt opens its file stream; URLs arrive as nonempty batches succeed.
    /// Consume the stream in an app-owned task. This callback does not wait for any files or uploads.
    public typealias DidStartLocalExport = @Sendable @MainActor (_ attemptID: UUID, _ files: AnyAsyncSequence<URL, Never>) -> Void

    /// Called once per attempt with its terminal local-processing outcome, including checkpoint failures.
    /// It does not wait for the file consumer or uploads. Startup failure has no preceding start callback.
    public typealias DidFinishLocalExport = @Sendable @MainActor (_ result: HealthExportResult) -> Void

    /// Directory to which the Health export files should be written.
    public let destination: URL
    /// The sample types that should be included in the export.
    public let sampleTypes: Set<HKObjectType>
    /// The time range for which health samples should be exported.
    public let timeRange: Range<Date>
    public let didStartLocalExport: DidStartLocalExport
    public let didFinishLocalExport: DidFinishLocalExport

    /// Create a configuration with handlers for file delivery and local processing outcomes.
    public init(
        destination: URL,
        sampleTypes: Set<HKObjectType> = HealthExportConfiguration.defaultSampleTypes,
        timeRange: Range<Date>,
        didStartLocalExport: @escaping DidStartLocalExport,
        didFinishLocalExport: @escaping DidFinishLocalExport
    ) {
        self.destination = destination
        self.sampleTypes = sampleTypes
        self.timeRange = timeRange
        self.didStartLocalExport = didStartLocalExport
        self.didFinishLocalExport = didFinishLocalExport
    }
}


extension HealthExportConfiguration {
    /// Validates the destination, sample types, and time range.
    func validate() throws {
        guard destination.isFileURL else { throw ValidationError.invalidDestination }
        guard !timeRange.isEmpty else { throw ValidationError.emptyTimeRange }
        guard !sampleTypes.isEmpty else { throw ValidationError.emptySampleTypes }
        guard sampleTypes.allSatisfy({ $0 is HKSampleType }) else { throw ValidationError.unsupportedObjectType }
    }

    enum ValidationError: Error {
        case invalidDestination, emptyTimeRange, emptySampleTypes, unsupportedObjectType
    }
}
