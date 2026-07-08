//
// This source file is part of the OneSecStanfordStudy open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import OneSecStanfordStudy
import SwiftUI

@available(iOS 17, *)
struct StudyButton: View {
    @Environment(OneSecStanfordStudyModule.self) private var oneSecStanfordStudy
    @State private var isShowingSheet = false

    var body: some View {
        Button("Initiate Flow") {
            oneSecStanfordStudy.surveyUrl = try? URL("https://redcap.stanford.edu/surveys/?s=R73YCP9CTL9MDYAW", strategy: .url)
            isShowingSheet = true
        }
        .sheet(isPresented: $isShowingSheet) {
            oneSecStanfordStudy.makeOneSecStanfordStudySheet()
        }
    }
}
