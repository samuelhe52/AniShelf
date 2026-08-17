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
        phase != .disabled
    }

    @ViewBuilder
    var body: some View {
        if isVisible {
            airtimeSection(header: sectionHeader) {
                primaryButton
                notificationsButton
            }
        }
    }

    private var primaryButton: some View {
        Button(action: primaryAction) {
            Label(primaryTitle, systemImage: primarySystemImage)
        }
        .disabled(primaryIsDisabled)
    }

    private var notificationsButton: some View {
        Button(action: {}) {
            Label(EntryDetailL10n.notifications, systemImage: "bell")
        }
        .disabled(true)
    }

    private var sectionHeader: String {
        switch phase {
        case .disabled, .idle, .checkingEligibility, .resolving:
            String(localized: EntryDetailL10n.findingAirtime)
        case .ineligible:
            String(localized: EntryDetailL10n.airtimeNotSupported)
        case .resolved(let availability):
            EntryDetailBroadcastFormatting.menuHeader(for: availability)
        case .requiresUserAssistance, .titleSearching, .titleCandidate:
            String(localized: EntryDetailL10n.airtime)
        case .failed:
            String(localized: EntryDetailL10n.couldNotLoadAirtime)
        }
    }

    private var primaryTitle: LocalizedStringResource {
        switch phase {
        case .requiresUserAssistance, .titleSearching, .titleCandidate:
            EntryDetailL10n.helpConfirmAirtime
        case .failed:
            EntryDetailL10n.tryAgain
        default:
            EntryDetailL10n.reviewAirtimeMatch
        }
    }

    private var primarySystemImage: String {
        switch phase {
        case .requiresUserAssistance, .titleSearching, .titleCandidate:
            "person.crop.circle.badge.questionmark"
        case .failed:
            "arrow.clockwise"
        default:
            "checkmark.bubble"
        }
    }

    private var primaryIsDisabled: Bool {
        switch phase {
        case .resolved, .requiresUserAssistance, .titleSearching, .titleCandidate, .failed:
            false
        case .disabled, .ineligible, .idle, .checkingEligibility, .resolving:
            true
        }
    }

    private func primaryAction() {
        if case .failed = phase {
            onRetry()
        } else {
            onPresentValidation()
        }
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
