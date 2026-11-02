//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

import Foundation

/// Supported survey callback URLs.
enum StudySurveyCallback: String {
    // Keep callback URL values explicit so renaming a case cannot change the URL.
    // swiftlint:disable redundant_string_enum_value
    case success = "success"
    case noteligible = "noteligible"
    case waitingforconsent = "waitingforconsent"
    // swiftlint:enable redundant_string_enum_value

    init?(url: URL) {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "one-sec.app" else {
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
