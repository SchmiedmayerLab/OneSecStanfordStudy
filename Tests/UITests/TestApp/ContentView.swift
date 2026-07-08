//
// This source file is part of the OneSecStanfordStudy open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@_spi(APISupport) import OneSecStanfordStudy
import SwiftUI

@available(iOS 17, *)
struct ContentView: View {
    @Environment(OneSecStanfordStudyModule.self) private var oneSecStanfordStudy

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("OneSecStanfordStudy active")
                        .accessibilityIdentifier("integration-status-active")
                    StudyButton()
                    Button("Trigger Health Export") {
                        Task {
                            do {
                                try await oneSecStanfordStudy.triggerHealthExport(forceSessionReset: true)
                            } catch {
                                fatalError("Health export failed: \(error)")
                            }
                        }
                    }
                }
                Section {
                    WebViewAlertAndConfirmTestButton()
                }
            }
        }
    }
}
