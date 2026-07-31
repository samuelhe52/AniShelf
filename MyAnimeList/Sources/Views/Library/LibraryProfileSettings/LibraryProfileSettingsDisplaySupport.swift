//
//  LibraryProfileSettingsDisplaySupport.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import DataProvider
import SwiftUI

extension LibraryCloudSyncStatus {
    struct DisplayStatus {
        let title: LocalizedStringResource
        let systemImage: String
        let tint: Color
    }

    var isFailureDisplay: Bool {
        if bootstrapState == .failed {
            return true
        }
        switch lastResult {
        case .retryableFailure, .permanentFailure:
            return true
        case .success, .skipped, .conflictChoiceRequired, nil:
            return false
        }
    }

    var statusDisplay: DisplayStatus {
        if bootstrapState == .running {
            return DisplayStatus(title: "Preparing iCloud", systemImage: "arrow.triangle.2.circlepath", tint: .indigo)
        }
        if isSyncInProgress {
            return DisplayStatus(title: "Syncing", systemImage: "arrow.triangle.2.circlepath", tint: .indigo)
        }

        switch bootstrapState {
        case .notStarted:
            return DisplayStatus(title: "Ready to Sync", systemImage: "icloud", tint: .indigo)
        case .needsConflictChoice:
            return DisplayStatus(title: "Needs Choice", systemImage: "exclamationmark.triangle", tint: .orange)
        case .running:
            return DisplayStatus(title: "Preparing iCloud", systemImage: "arrow.triangle.2.circlepath", tint: .indigo)
        case .completed:
            switch lastResult {
            case .success:
                return DisplayStatus(title: "Synced", systemImage: "checkmark.icloud", tint: .green)
            case .skipped:
                return DisplayStatus(title: "Sync Skipped", systemImage: "pause.circle", tint: .secondary)
            case .retryableFailure, .permanentFailure:
                return DisplayStatus(title: "Sync Failed", systemImage: "xmark.icloud", tint: .red)
            case .conflictChoiceRequired:
                return DisplayStatus(title: "Needs Choice", systemImage: "exclamationmark.triangle", tint: .orange)
            case nil:
                return DisplayStatus(title: "Sync Enabled", systemImage: "icloud", tint: .indigo)
            }
        case .failed:
            return DisplayStatus(title: "Setup Failed", systemImage: "xmark.icloud", tint: .red)
        }
    }

    var detailDisplayResource: LocalizedStringResource {
        if bootstrapState == .needsConflictChoice || lastResult == .conflictChoiceRequired {
            return conflictSummaryResource
        }
        if isFailureDisplay {
            if let lastAttemptDate {
                return "Last attempt: \(lastAttemptDate.libraryCloudSyncRelativeDescription)"
            }
            return "No sync yet."
        }
        if let lastSuccessfulSyncDate {
            return "Last sync: \(lastSuccessfulSyncDate.libraryCloudSyncRelativeDescription)"
        } else if let lastAttemptDate {
            return "Last attempt: \(lastAttemptDate.libraryCloudSyncRelativeDescription)"
        } else {
            return "No sync yet."
        }
    }

    var failureReasonDisplay: String? {
        guard isFailureDisplay, let lastFailureReason, !lastFailureReason.isEmpty else {
            return nil
        }
        return lastFailureReason
    }

    var actionTitleResource: LocalizedStringResource {
        isFailureDisplay ? "Retry" : "Sync Now"
    }

    var conflictSummaryResource: LocalizedStringResource {
        guard let summary = pendingConflictSummary else {
            return "Choose which library data to keep."
        }
        return
            "\(summary.entryCount) entries. Library: \(summary.libraryDomainCount), tracking: \(summary.trackingDomainCount), episodes: \(summary.episodeProgressDomainCount)."
    }
}

extension Date {
    var libraryCloudSyncRelativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

extension LibraryExportFormat {
    var menuTitleResource: LocalizedStringResource {
        switch self {
        case .plainText:
            "Plain Text (.txt)"
        case .csv:
            "Comma-Separated Values (.csv)"
        case .tsv:
            "Tab-Separated Values (.tsv)"
        case .json:
            "JSON (.json)"
        case .excel:
            "Excel Workbook (.xlsx)"
        }
    }

    var menuSystemImage: String {
        switch self {
        case .plainText:
            "doc.plaintext"
        case .csv:
            "tablecells"
        case .tsv:
            "tablecells.badge.ellipsis"
        case .json:
            "curlybraces"
        case .excel:
            "tablecells.fill"
        }
    }
}
