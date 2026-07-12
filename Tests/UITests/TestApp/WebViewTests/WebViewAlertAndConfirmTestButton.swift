//
// This source file is part of the OneSecStanfordStudy open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import OneSecStanfordStudy
import SwiftUI

@available(iOS 18, *)
struct WebViewAlertAndConfirmTestButton: View {
    @Environment(OneSecStanfordStudyModule.self) private var oneSecStanfordStudy

    @State private var isSheetPresented = false

    var body: some View {
        Button("Test Alert/Confirm") {
            oneSecStanfordStudy.surveyUrl = Bundle.main.url(forResource: "alert-confirm-test", withExtension: "html")
            isSheetPresented = true
        }
        .sheet(isPresented: $isSheetPresented) {
            oneSecStanfordStudy.makeOneSecStanfordStudySheet()
        }
    }
}
