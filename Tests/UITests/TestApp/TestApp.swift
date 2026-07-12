//
// This source file is part of the OneSecStanfordStudy open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import OneSecStanfordStudy
import SwiftUI

@main
struct UITestsApp: App {
    @UIApplicationDelegateAdaptor private var delegate: TestAppDelegate

    var body: some Scene {
        WindowGroup {
            rootContent
                .oneSecStanfordStudy()
        }
    }

    @ViewBuilder private var rootContent: some View {
        if #available(iOS 18, *) {
            ContentView()
        } else {
            VStack(spacing: 12) {
                Text("OneSecStanfordStudy inactive")
                    .font(.headline)
                    .accessibilityIdentifier("integration-status-inactive")
                Text("The iOS 15 compatibility wrapper loaded successfully.")
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}
