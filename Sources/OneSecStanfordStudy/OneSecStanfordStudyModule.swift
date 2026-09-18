//
// This source file is part of the One Sec Stanford Study open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

public import Grove
import GroveFoundation
private import GroveHealthKit
import GroveHealthKitBulkExport
import OSLog
public import SwiftUI
import UIKit

/// The Stanford study integration for the one sec app.
///
/// Available through the SwiftUI environment after initialization.
///
/// ## Topics
///
/// ### Instance Properties
/// - ``state``
/// - ``surveyUrl``
///
/// ### Instance Methods
/// - ``makeOneSecStanfordStudySheet()``
/// - ``triggerHealthExport(forceSessionReset:)``
@available(iOS 18, *)
@Observable
@MainActor
public final class OneSecStanfordStudyModule: Module, EnvironmentAccessible {
    public enum State: Int, Hashable, Codable, Sendable {
        /// The study is not available for this user.
        /// This may occur if the user has been deemed ineligible (e.g., underage)
        /// based on information from a previous survey attempt or other eligibility criteria.
        case unavailable
        /// The study is available but has not yet been initiated.
        case available
        /// The study was started by the participant, but they indicated being underage.
        /// The study is currently on hold until a parent or guardian provides consent.
        case awaitingParentalConsent
        /// The study is currently active.
        case active
        /// The survey flow has completed.
        case completed
    }

    /// The URL of the survey the user should fill out to enroll in the study.
    ///
    /// The host app constructs this URL from the survey and the participant's token obtained from REDCap.
    public var surveyUrl: URL?

    /// The current survey state.
    public private(set) var state: State = .unavailable


    private static var appDelegate: OneSecStanfordStudyAppDelegate? // swiftlint:disable:this weak_delegate

    static func integrate(_ view: some View) -> some View {
        guard let appDelegate else {
            preconditionFailure("Call initializeOneSecStanfordStudy before applying .oneSecStanfordStudy()")
        }
        return view.grove(appDelegate)
    }

    @ObservationIgnored @Application(\.logger) var logger
    @ObservationIgnored @Dependency(HealthKit.self) private var healthKit
    @ObservationIgnored @Dependency(BulkHealthExporter.self) private var bulkExporter

    nonisolated private let healthExportConfig: HealthExportConfiguration
    nonisolated(unsafe) private let fileManager = FileManager.default
    private let prefsStore: LocalPreferencesStore
    @ObservationIgnored private let exportStartCoordinator = HealthExportStartCoordinator()
    /// Identity rejects stale completion callbacks from previous attempts.
    @ObservationIgnored private var activeExportAttempt: HealthExportAttempt?


    /// Creates the module with its export configuration and preference store.
    nonisolated init(healthExportConfig: HealthExportConfiguration, preferences: LocalPreferencesStore = .standard) {
        self.healthExportConfig = healthExportConfig
        self.prefsStore = preferences
    }

    static func initialize(
        application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?, // swiftlint:disable:this discouraged_optional_collection
        healthExportConfig: HealthExportConfiguration
    ) {
        let appDelegate = OneSecStanfordStudyAppDelegate(healthExportConfig: healthExportConfig)
        _ = appDelegate.application(application, willFinishLaunchingWithOptions: launchOptions)
        self.appDelegate = appDelegate
    }

    public func configure() {
        updateState(prefsStore[.oneSecStanfordStudyState])
        Task {
            do {
                if prefsStore[.didInitiateBulkExport] {
                    // we've initiated the Health Export at some point in the past.
                    // we now check if it has completed, and, if not, tell it to continue.
                    try await triggerHealthExport()
                }
            } catch {
                logger.error("\(error)")
            }
        }
    }

    func updateState(_ newState: State) {
        if newState != state {
            prefsStore[.oneSecStanfordStudyState] = newState
        }
        state = newState
    }

    /// Presents the enrollment survey using `surveyUrl`.
    public func makeOneSecStanfordStudySheet() -> AnyView {
        AnyView(StudySurveySheet())
    }

    // MARK: HealthKit Data Collection

    /// Starts or resumes the export, retrying failed batches. Set `forceSessionReset` only for an intentional restart.
    /// Files and the final processing result are delivered through the configured callbacks.
    public func triggerHealthExport(forceSessionReset: Bool = false) async throws {
        let task = exportStartCoordinator.start(forceSessionReset: forceSessionReset) { forceSessionReset in
            try await self.startHealthExport(forceSessionReset: forceSessionReset)
        }
        try await task.value
    }

    private func startHealthExport(forceSessionReset: Bool) async throws {
        let attempt = HealthExportAttempt(configuration: healthExportConfig)
        do {
            try Task.checkCancellation()
            try healthExportConfig.validate()
            if forceSessionReset {
                let reset: @MainActor () async throws -> Void = {
                    try await self.bulkExporter.deleteSessionRestorationInfo(for: .oneSecStanfordStudy)
                }
                if let previousAttempt = activeExportAttempt {
                    try await previousAttempt.resetSession(reset)
                    if activeExportAttempt === previousAttempt {
                        activeExportAttempt = nil
                    }
                } else {
                    try await reset()
                }
            }
            if !fileManager.itemExists(at: healthExportConfig.destination) {
                try fileManager.createDirectory(at: healthExportConfig.destination, withIntermediateDirectories: true)
            }
            try await healthKit.askForAuthorization(for: .init(read: healthExportConfig.sampleTypes))
            try Task.checkCancellation()
            let session = try await healthExportSession()
            try Task.checkCancellation()
            guard session.state != .running else { return }
            if clearRestorationFlagIfCompleted(session) {
                return
            }
            // A retry can arrive before the previous attempt's queued completion callback.
            if let previousAttempt = activeExportAttempt {
                trackCompletion(of: session, attempt: previousAttempt)
            }
            let stream = try session.start(retryFailedBatches: true, concurrencyLevel: .limit(4))
            prefsStore[.didInitiateBulkExport] = true
            activeExportAttempt = attempt
            attempt.start(files: AnyAsyncSequence(stream.compactMap(\.self)))
            trackCompletion(of: session, attempt: attempt)
        } catch {
            if error is CancellationError {
                attempt.finish(.cancelled(.taskCancelled))
            } else {
                attempt.finish(.failedToStart(error))
            }
            throw error
        }
    }

    func clearRestorationFlagIfCompleted(_ session: some BulkExportSession) -> Bool {
        guard session.state == .completed,
              session.numTotalBatches > 0, session.completedBatches.count == session.numTotalBatches,
              session.failedBatches.isEmpty, session.pendingBatches.isEmpty else {
            return false
        }
        prefsStore[.didInitiateBulkExport] = false
        return true
    }

    /// Obtains the bulk health export session.
    private func healthExportSession() async throws -> some BulkExportSession<HKSampleToFHIRProcessor> {
        try await bulkExporter.session(
            withId: .oneSecStanfordStudy,
            for: SampleTypesCollection(healthExportConfig.sampleTypes.compactMap { $0.sampleType }),
            startDate: .absolute(healthExportConfig.timeRange.lowerBound),
            endDate: healthExportConfig.timeRange.upperBound,
            batchSize: .automatic,
            using: HKSampleToFHIRProcessor(outputDirectory: healthExportConfig.destination)
        )
    }

    private func trackCompletion(of session: some BulkExportSession, attempt: HealthExportAttempt) {
        attempt.trackCompletion(of: session) { [self] outcome in
            guard activeExportAttempt === attempt else { return }
            activeExportAttempt = nil
            switch outcome {
            case .succeeded:
                prefsStore[.didInitiateBulkExport] = false
            case .incomplete(let summary):
                // Keep launch restoration enabled so failed batches remain retryable.
                logger.error("Health export incomplete: \(summary.failedBatches) failed, \(summary.pendingBatches) pending batches")
            case .failedToPersist(_, let error):
                logger.error("Health export checkpoint failed: \(error)")
            case .cancelled, .failedToStart:
                break
            }
        }
    }

}

// MARK: App Delegate and Standard

@available(iOS 18, *)
private final class OneSecStanfordStudyAppDelegate: GroveAppDelegate {
    private let healthExportConfig: HealthExportConfiguration

    override var configuration: Configuration {
        Configuration(standard: OneSecStanfordStudyStandard()) {
            HealthKit()
            BulkHealthExporter()
            OneSecStanfordStudyModule(healthExportConfig: healthExportConfig)
        }
    }

    init(healthExportConfig: HealthExportConfiguration) {
        self.healthExportConfig = healthExportConfig
    }
}

@available(iOS 18, *)
private actor OneSecStanfordStudyStandard: Standard, HealthKitConstraint {
    func handleNewSamples<Sample>(_ addedSamples: some Collection<Sample>, ofType sampleType: SampleType<Sample>) async {}
    func handleDeletedObjects<Sample>(_ deletedObjects: some Collection<HKDeletedObject>, ofType sampleType: SampleType<Sample>) async {}
}

// MARK: Utils

@available(iOS 18, *)
extension BulkExportSessionIdentifier {
    fileprivate static let oneSecStanfordStudy = Self("edu.stanford.OneSecStanfordStudy")
}

@available(iOS 18, *)
extension LocalPreferenceKeys.Namespace {
    // Preserve the namespace used by existing installations.
    fileprivate static let oneSecStudy: Self = .custom("edu.stanford.SpeziOneSec")
}

@available(iOS 18, *)
extension LocalPreferenceKeys {
    fileprivate static let oneSecStanfordStudyState = LocalPreferenceKey<OneSecStanfordStudyModule.State>(
        .init("state", in: .oneSecStudy),
        default: .available
    )
    fileprivate static let didInitiateBulkExport = LocalPreferenceKey<Bool>(
        .init("didInitiateBulkExport", in: .oneSecStudy),
        default: false
    )
}
