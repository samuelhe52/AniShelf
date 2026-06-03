//
//  LibraryCloudSyncStatus.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/3.
//

import Foundation

enum LibraryCloudSyncBootstrapState: String, Codable, Equatable {
    case notStarted
    case needsConflictChoice
    case running
    case completed
    case failed
}

enum LibraryCloudSyncConflictPreference: String, Codable, Equatable {
    case preferCloud
    case preferLocal
}

enum LibraryCloudSyncConflictDomain: String, Codable, Equatable, Hashable {
    case library
    case tracking
    case episodeProgress
}

enum LibraryCloudSyncPhase: Codable, Equatable, RawRepresentable {
    case preparing
    case syncing
    case exporting

    init?(rawValue: String) {
        switch rawValue {
        case "preparing", "prepareZoneSubscription", "namespaceResolution":
            self = .preparing
        case "syncing", "remoteFetch", "conflictDetection", "dirtyQueueSeeding", "hydrationApply",
            "tokenCommit", "libraryRefresh", "dirtyQueueReconciliation":
            self = .syncing
        case "exporting", "export":
            self = .exporting
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .preparing:
            "preparing"
        case .syncing:
            "syncing"
        case .exporting:
            "exporting"
        }
    }

    static let prepareZoneSubscription = LibraryCloudSyncPhase.preparing
    static let namespaceResolution = LibraryCloudSyncPhase.preparing
    static let remoteFetch = LibraryCloudSyncPhase.syncing
    static let conflictDetection = LibraryCloudSyncPhase.syncing
    static let dirtyQueueSeeding = LibraryCloudSyncPhase.syncing
    static let hydrationApply = LibraryCloudSyncPhase.syncing
    static let tokenCommit = LibraryCloudSyncPhase.syncing
    static let libraryRefresh = LibraryCloudSyncPhase.syncing
    static let dirtyQueueReconciliation = LibraryCloudSyncPhase.syncing
    static let export = LibraryCloudSyncPhase.exporting

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let phase = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown library cloud sync phase: \(rawValue)"
            )
        }
        self = phase
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum LibraryCloudSyncResultClass: String, Codable, Equatable {
    case success
    case skipped
    case conflictChoiceRequired
    case retryableFailure
    case permanentFailure
}

enum LibraryCloudKitAvailability: String, Codable, Equatable {
    case unknown
    case available
    case noAccount
    case restricted
    case couldNotDetermine
}

enum LibraryCloudSyncPolicyBlockReason: String, Codable, Equatable {
    case disabled
    case bootstrapIncomplete
    case missingTMDbAPIKey
}

struct LibraryCloudSyncConflictSummary: Codable, Equatable {
    var entryCount: Int
    var libraryDomainCount: Int
    var trackingDomainCount: Int
    var episodeProgressDomainCount: Int

    static let empty = LibraryCloudSyncConflictSummary(
        entryCount: 0,
        libraryDomainCount: 0,
        trackingDomainCount: 0,
        episodeProgressDomainCount: 0
    )

    var isEmpty: Bool {
        entryCount == 0
            && libraryDomainCount == 0
            && trackingDomainCount == 0
            && episodeProgressDomainCount == 0
    }
}

struct LibraryCloudSyncRetryState: Codable, Equatable {
    var failureRetryAttempt: Int
    var nextRetryAllowedAt: Date?
    var automaticRetriesExhausted: Bool

    static let idle = LibraryCloudSyncRetryState(
        failureRetryAttempt: 0,
        nextRetryAllowedAt: nil,
        automaticRetriesExhausted: false
    )
}

struct LibraryCloudSyncStatus: Equatable {
    var isEnabled: Bool
    var bootstrapState: LibraryCloudSyncBootstrapState
    var cloudKitAvailability: LibraryCloudKitAvailability
    var pendingConflictSummary: LibraryCloudSyncConflictSummary?
    var retryState: LibraryCloudSyncRetryState
    var currentPhase: LibraryCloudSyncPhase?
    var lastResult: LibraryCloudSyncResultClass?
    var lastTrigger: String?
    var lastAttemptDate: Date?
    var lastSuccessfulSyncDate: Date?
    var lastFailureReason: String?
    var degradedReason: String?

    static let defaultValue = LibraryCloudSyncStatus(
        isEnabled: false,
        bootstrapState: .notStarted,
        cloudKitAvailability: .unknown,
        pendingConflictSummary: nil,
        retryState: .idle,
        currentPhase: nil,
        lastResult: nil,
        lastTrigger: nil,
        lastAttemptDate: nil,
        lastSuccessfulSyncDate: nil,
        lastFailureReason: nil,
        degradedReason: nil
    )
}
