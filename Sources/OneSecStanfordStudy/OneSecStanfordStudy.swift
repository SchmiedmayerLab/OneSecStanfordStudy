//
// This source file is part of the OneSecStanfordStudy open source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

@_spi(APISupport) import Spezi
private import SpeziHealthKit
private import SpeziHealthKitBulkExport
private import SpeziLocalStorage
import OSLog
import SwiftUI
import UIKit

/// The OneSecStanfordStudy module.
@available(iOS 17, *)
@Observable
@MainActor
@objc(OneSecStanfordStudy)
final class OneSecStanfordStudy: OneSecStanfordStudyModule, Module, EnvironmentAccessible {
    private static var appDelegate: OneSecStanfordStudyAppDelegate? // swiftlint:disable:this weak_delegate

    override static var studyIntegrationViewModifier: any ViewModifier {
        struct OneSecStanfordStudyInjectionModifier: ViewModifier {
            let runtime: Spezi
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
        guard let runtime = SpeziAppDelegate.spezi else {
            preconditionFailure("\(#function) accessed before 'initialize' was called!")
        }
        return SpeziViewModifier(runtime).concat(OneSecStanfordStudyInjectionModifier(runtime: runtime))
    }

    @ObservationIgnored @Application(\.logger) var logger
    @ObservationIgnored @Dependency(HealthKit.self) private var healthKit
    @ObservationIgnored @Dependency(BulkHealthExporter.self) private var bulkExporter
    @ObservationIgnored @Dependency(LocalStorage.self) private var localStorage

    nonisolated private let healthExportConfig: HealthExportConfiguration
    nonisolated(unsafe) private let fileManager = FileManager.default

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
        updateState((try? localStorage.load(.oneSecStanfordStudyState)) ?? .available)
        Task {
            do {
                if try localStorage.load(.didInitiateBulkExport) == true {
                    // we've initiated the Health Export at some point in the past.
                    // we now check if it has completed, and, if not, tell it to continue.
                    let session = try await healthExportSession()
                    if session.state != .completed {
                        try await triggerHealthExport(forceSessionReset: false)
                    }
                }
            } catch {
                logger.error("\(error)")
            }
        }
    }

    override func updateState(_ newState: OneSecStanfordStudyModule.State) {
        if newState != state {
            try? localStorage.store(newState, for: .oneSecStanfordStudyState)
        }
        super.updateState(newState)
    }

    override func makeOneSecStanfordStudySheet() -> AnyView {
        AnyView(StudySurveySheet())
    }

    // MARK: HealthKit Data Collection

    override func triggerHealthExport(forceSessionReset: Bool) async throws {
        if forceSessionReset {
            try await bulkExporter.deleteSessionRestorationInfo(for: .oneSecStanfordStudy)
        }
        if !fileManager.itemExists(at: healthExportConfig.destination) {
            try fileManager.createDirectory(at: healthExportConfig.destination, withIntermediateDirectories: true)
        }
        try await healthKit.askForAuthorization(for: .init(read: healthExportConfig.sampleTypes))
        let session = try await healthExportSession()
        let stream = try session.start(retryFailedBatches: true)
        if #available(iOS 18, *) {
            healthExportConfig.didStartExport(AnyAsyncSequence(stream.compactMap(\.self)))
        } else {
            healthExportConfig.didStartExport(AnyAsyncSequence(unsafelyAssumingDoesntThrow: stream.compactMap(\.self)))
        }
        _trackCompletion(of: session)
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

    private func _trackCompletion(of session: some BulkExportSession) {
        let isCompleted = withObservationTracking {
            session.state == .completed
        } onChange: {
            Task { @MainActor in
                self._trackCompletion(of: session)
            }
        }
        if isCompleted {
            healthExportConfig.didEndExport()
        }
    }
}

// MARK: App Delegate and Standard

@available(iOS 17, *)
private final class OneSecStanfordStudyAppDelegate: SpeziAppDelegate {
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

@available(iOS 17, *)
private actor OneSecStanfordStudyStandard: Standard, HealthKitConstraint {
    func handleNewSamples<Sample>(_ addedSamples: some Collection<Sample>, ofType sampleType: SampleType<Sample>) async {}
    func handleDeletedObjects<Sample>(_ deletedObjects: some Collection<HKDeletedObject>, ofType sampleType: SampleType<Sample>) async {}
}

// MARK: Utils

@available(iOS 17, *)
extension BulkExportSessionIdentifier {
    fileprivate static let oneSecStanfordStudy = Self("edu.stanford.OneSecStanfordStudy")
}

@available(iOS 17, *)
extension LocalStorageKeys {
    fileprivate static let oneSecStanfordStudyState = LocalStorageKey<OneSecStanfordStudy.State>("edu.stanford.OneSecStanfordStudy.state")
    fileprivate static let didInitiateBulkExport = LocalStorageKey<Bool>("edu.stanford.OneSecStanfordStudy.didInitiateBulkExport")
}
