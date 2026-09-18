//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

import Foundation

/// Supported survey callback URLs.
enum StudySurveyCallback: String {
    case success, noteligible, waitingforconsent

    init?(url: URL) {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "one-sec.app",
              url.port == nil || url.port == 443,
              url.user == nil, url.password == nil else {
            return nil
        }
        let prefix = "/survey-callback/"
        guard url.path.hasPrefix(prefix),
              let callback = Self(rawValue: String(url.path.dropFirst(prefix.count))) else {
            return nil
        }
        self = callback
    }
}
