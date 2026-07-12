//
// This source file is part of the OneSecStanfordStudy open source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI
public import UIKit

/// Initializes the Stanford study integration for the current app.
///
/// This function should be called as part of the parent app's
/// `-[UIApplicationDelegate application:willFinishLaunchingWithOptions:]` method.
/// Once this function has returned, the ``SwiftUICore/View/oneSecStanfordStudy()`` view modifier is
/// available and should be called on the root level of the app's view hierarchy.
///
/// - Note: If the device is running below iOS 18, this function has no effect.
@MainActor
public func initializeOneSecStanfordStudy(
    _ application: UIApplication,
    launchOptions: [UIApplication.LaunchOptionsKey: Any]?, // swiftlint:disable:this discouraged_optional_collection
    healthExportConfig: HealthExportConfiguration
) {
    guard #available(iOS 18, *) else {
        return
    }
    OneSecStanfordStudy.initialize(application: application, launchOptions: launchOptions, healthExportConfig: healthExportConfig)
}

extension View {
    /// Injects the study runtime into the SwiftUI view hierarchy.
    ///
    /// - Note: This modifier should be called on the root view of the application.
    ///     If the device is running below iOS 18, this modifier has no effect.
    @ViewBuilder
    public func oneSecStanfordStudy() -> some View {
        if #available(iOS 18, *) {
            OneSecStanfordStudy.studyIntegrationViewModifier.applying(to: self)
        } else {
            self
        }
    }
}

extension ViewModifier {
    fileprivate func applying(to view: some View) -> some View {
        view.modifier(self)
    }
}
