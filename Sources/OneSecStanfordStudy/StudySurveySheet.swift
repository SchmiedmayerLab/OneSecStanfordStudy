//
// This source file is part of the OneSecStanfordStudy open source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Spezi
import SwiftUI

@available(iOS 17, *)
struct StudySurveySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(OneSecStanfordStudy.self) private var oneSecStanfordStudy

    @State private var didCompleteInitialNavigation = false
    @State private var isShowingCancelAlert = false
    @State private var isDone = false
    @State private var currentPageLoadProgress: Double?

    var body: some View {
        if let url = oneSecStanfordStudy.surveyUrl {
            NavigationStack {
                WebView(url: url, currentProgress: $currentPageLoadProgress) { request in
                    await shouldNavigate(request)
                } didNavigate: { webView in
                    didCompleteInitialNavigation = true
                    await didNavigate(webView)
                }
                .overlay {
                    if !didCompleteInitialNavigation {
                        ProgressView("Loading…")
                            .controlSize(.large)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !isDone {
                        ToolbarItem(placement: .cancellationAction) {
                            cancelButton
                        }
                    } else {
                        ToolbarItem(placement: .confirmationAction) {
                            confirmButton
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 4) {
                            Text("Stanford Study")
                                .font(.headline)
                            if let progress = currentPageLoadProgress {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                            }
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
        } else {
            ContentUnavailableView("MISSING_URL", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder private var cancelButton: some View {
        Group {
            let fallbackButton = Button("Cancel", role: .cancel) {
                isShowingCancelAlert = true
            }
            #if compiler(>=6.2)
            if #available(iOS 26, *) {
                Button(role: .cancel) {
                    isShowingCancelAlert = true
                }
            } else {
                fallbackButton
            }
            #else
            fallbackButton
            #endif
        }
        .alert("Cancel Enrollment", isPresented: $isShowingCancelAlert) {
            Button("No", role: .cancel) {
                isShowingCancelAlert = false
            }
            Button("Yes", role: .destructive) {
                dismiss()
            }
        } message: {
            Text(
                """
                Are you sure you want to cancel enrolling in the study?
                You can re-enroll at a later time if you feel like it.
                """
            )
        }
    }

    @ViewBuilder private var confirmButton: some View {
        let fallbackButton = Button("Done") {
            dismiss()
        }
        .bold()
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            Button(role: .confirm) {
                dismiss()
            }
        } else {
            fallbackButton
        }
        #else
        fallbackButton
        #endif
    }

    private func shouldNavigate(_ request: URLRequest) async -> Bool {
        guard let url = request.url, url.host() == "one-sec.app" else {
            return true
        }
        let path = url.path()
        if path.contains("survey-callback/success") {
            oneSecStanfordStudy.updateState(.completed)
        } else if path.contains("survey-callback/noteligible") {
            oneSecStanfordStudy.updateState(.unavailable)
        } else if path.contains("survey-callback/waitingforconsent") {
            oneSecStanfordStudy.updateState(.awaitingParentalConsent)
        }
        isDone = true
        dismiss()
        return false
    }

    private func didNavigate(_ webView: WebViewProxy) async {
        if await webView.pageContainsField(named: "healthkit_export_initiated") {
            oneSecStanfordStudy.updateState(.active)
            await initiateHealthExport()
        }
    }

    private func initiateHealthExport() async {
        do {
            try await oneSecStanfordStudy.triggerHealthExport(forceSessionReset: true)
        } catch {
            // Q how to handle this? (will depend on the specific error. eg for missing permissions we could throw up an alert, etc)
            oneSecStanfordStudy.logger.error("Error initiating bulk health export: \(error)")
        }
    }
}

@available(iOS 17, *)
extension WebViewProxy {
    func pageContainsField(named variableName: String) async -> Bool {
        (try? await evaluateJavaScript(
            #"document.querySelector('div[data-mlm-field="\#(variableName)"]') !== null"#
        ) as? Bool) == true
    }

    func pageContainsElement(withId id: String) async -> Bool {
        (try? await evaluateJavaScript(
            "document.getElementById('\(id)') !== null"
        ) as? Bool) == true
    }
}
