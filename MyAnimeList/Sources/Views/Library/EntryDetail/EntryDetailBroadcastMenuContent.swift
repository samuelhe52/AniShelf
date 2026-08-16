//
//  EntryDetailBroadcastMenuContent.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/16.
//

import Foundation
import SwiftUI

struct EntryDetailBroadcastMenuContent: View {
    let phase: EntryDetailBroadcastModel.Phase
    let onPresentValidation: () -> Void
    let onRetry: () -> Void

    var isVisible: Bool {
        switch phase {
        case .disabled, .ineligible, .idle:
            false
        default:
            true
        }
    }

    @ViewBuilder
    var body: some View {
        switch phase {
        case .disabled, .ineligible, .idle:
            EmptyView()
        case .checkingEligibility, .resolving:
            airtimeSection(header: String(localized: EntryDetailL10n.findingAirtime)) {
                notificationsButton
            }
        case .resolved(let availability):
            airtimeSection(
                header: EntryDetailBroadcastFormatting.menuHeader(for: availability)
            ) {
                Button(action: onPresentValidation) {
                    Label(EntryDetailL10n.reviewAirtimeMatch, systemImage: "checkmark.bubble")
                }
                notificationsButton
            }
        case .requiresUserAssistance:
            airtimeSection(header: String(localized: EntryDetailL10n.airtime)) {
                Button(action: onPresentValidation) {
                    Label(EntryDetailL10n.helpConfirmAirtime, systemImage: "person.crop.circle.badge.questionmark")
                }
            }
        case .titleSearching, .titleCandidate:
            airtimeSection(header: String(localized: EntryDetailL10n.airtime)) {
                Button(action: onPresentValidation) {
                    Label(
                        EntryDetailL10n.helpConfirmAirtime,
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                }
            }
        case .failed:
            airtimeSection(header: String(localized: EntryDetailL10n.couldNotLoadAirtime)) {
                Button(action: onRetry) {
                    Label(EntryDetailL10n.tryAgain, systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var notificationsButton: some View {
        Button(action: {}) {
            Label(EntryDetailL10n.notifications, systemImage: "bell")
        }
        .disabled(true)
    }

    private func airtimeSection<Content: View>(
        header: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            Text(header)
        }
    }
}
