//
// This source file is part of the One Sec Stanford Study open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

@_spi(APISupport) import Grove
private import GroveFoundation
private import GroveHealthKit
private import GroveHealthKitBulkExport
import OSLog
import SwiftUI
import UIKit

/// The OneSecStanfordStudy module.
@available(iOS 18, *)
@Observable
@MainActor
@objc(OneSecStanfordStudy)
final class OneSecStanfordStudy: OneSecStanfordStudyModule, Module, EnvironmentAccessible {
    private static var appDelegate: OneSecStanfordStudyAppDelegate? // swiftlint:disable:this weak_delegate

    override static var studyIntegrationViewModifier: any ViewModifier {
        struct OneSecStanfordStudyInjectionModifier: ViewModifier {
            let runtime: Grove
            func body(content: Content) -> some View {
                if let oneSecStanfordStudy = runtime.modules.lazy.compactMap({ $0 as? OneSecStanfordStudy }).first {
                    // SwiftUI's Environment mechanism seems to be using the static type of the parameter passed to `.environment()`,
                    // we need to inject the module a second time (the first time being the automatic runtime injection,
                    // as a result of the module's conformance to EnvironmentAccessible), and we need to explicitly specify the
                    // static type as that of our base class.
                    content.environment(oneSecStanfordStudy as OneSecStanfordStudyModule)
                } else {
                    content
                }
            }
        }
        guard let runtime = GroveAppDelegate.grove else {
            preconditionFailure("\(#function) accessed before 'initialize' was called!")
        }
        return GroveViewModifier(runtime).concat(OneSecStanfordStudyInjectionModifier(runtime: runtime))
    }

    @ObservationIgnored @Application(\.logger) var logger
    @ObservationIgnored @Dependency(HealthKit.self) private var healthKit
    @ObservationIgnored @Dependency(BulkHealthExporter.self) private var bulkExporter

    nonisolated private let healthExportConfig: HealthExportConfiguration
    nonisolated(unsafe) private let fileManager = FileManager.default
    private let prefsStore = LocalPreferencesStore.standard
    @ObservationIgnored private var exportStartTask: Task<Void, any Error>?
    /// Identity also rejects stale completion callbacks; `exportStartTask` coalesces concurrent starts.
    @ObservationIgnored private var activeExportAttempt: HealthExportAttempt?


    /// Creates a new instance of the `OneSecStanfordStudy` module
    nonisolated init(healthExportConfig: HealthExportConfiguration) {
        self.healthExportConfig = healthExportConfig
    }

    override static func initialize(
        application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?, // swiftlint:disable:this discouraged_optional_collection
        healthExportConfig: HealthExportConfiguration
    ) {
        let appDelegate = OneSecStanfordStudyAppDelegate(healthExportConfig: healthExportConfig)
        _ = appDelegate.application(application, willFinishLaunchingWithOptions: launchOptions)
        self.appDelegate = appDelegate
    }

    func configure() {
        updateState(prefsStore[.oneSecStanfordStudyState])
        Task {
            do {
                if prefsStore[.didInitiateBulkExport] {
                    // we've initiated the Health Export at some point in the past.
                    // we now check if it has completed, and, if not, tell it to continue.
                    try await triggerHealthExport(forceSessionReset: false)
                }
            } catch {
                logger.error("\(error)")
            }
        }
    }

    override func updateState(_ newState: OneSecStanfordStudyModule.State) {
        if newState != state {
            prefsStore[.oneSecStanfordStudyState] = newState
        }
        super.updateState(newState)
    }

    override func makeOneSecStanfordStudySheet() -> AnyView {
        AnyView(StudySurveySheet())
    }

    // MARK: HealthKit Data Collection

    override func triggerHealthExport(forceSessionReset: Bool) async throws {
        if let exportStartTask {
            // Coalesce page navigation and launch restoration across suspension points.
            try await exportStartTask.value
            return
        }
        let task = Task { @MainActor in
            try await self.startHealthExport(forceSessionReset: forceSessionReset)
        }
        exportStartTask = task
        defer { exportStartTask = nil }
        try await task.value
    }

    private func startHealthExport(forceSessionReset: Bool) async throws {
        let attempt = HealthExportAttempt(configuration: healthExportConfig)
        do {
            try Task.checkCancellation()
            try healthExportConfig.validate()
            if forceSessionReset {
                let previousAttempt = activeExportAttempt
                activeExportAttempt = nil
                previousAttempt?.finish(.cancelled(.sessionReset))
                try await bulkExporter.deleteSessionRestorationInfo(for: .oneSecStanfordStudy)
            }
            if !fileManager.itemExists(at: healthExportConfig.destination) {
                try fileManager.createDirectory(at: healthExportConfig.destination, withIntermediateDirectories: true)
            }
            try await healthKit.askForAuthorization(for: .init(read: healthExportConfig.sampleTypes))
            try Task.checkCancellation()
            let session = try await healthExportSession()
            try Task.checkCancellation()
            guard session.state != .running else { return }
            if session.state == .completed && session.failedBatches.isEmpty && session.pendingBatches.isEmpty {
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
            OneSecStanfordStudy(healthExportConfig: healthExportConfig)
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
    fileprivate static let oneSecStanfordStudyState = LocalPreferenceKey<OneSecStanfordStudy.State>(
        .init("state", in: .oneSecStudy),
        default: .available
    )
    fileprivate static let didInitiateBulkExport = LocalPreferenceKey<Bool>(
        .init("didInitiateBulkExport", in: .oneSecStudy),
        default: false
    )
}
