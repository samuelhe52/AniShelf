//
//  LibraryCloudSyncStateController.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/3.
//

import Foundation

@MainActor
struct LibraryCloudSyncStateController {
    private let preferences: LibraryPreferences
    private let hasTMDbAPIKey: @MainActor () -> Bool

    init(
        preferences: LibraryPreferences,
        hasTMDbAPIKey: @escaping @MainActor () -> Bool
    ) {
        self.preferences = preferences
        self.hasTMDbAPIKey = hasTMDbAPIKey
    }

    func policyBlockReason(for status: LibraryCloudSyncStatus) -> LibraryCloudSyncPolicyBlockReason? {
        guard status.isEnabled else {
            return .disabled
        }
        guard status.bootstrapState == .completed else {
            return .bootstrapIncomplete
        }
        guard hasTMDbAPIKey() else {
            return .missingTMDbAPIKey
        }
        return nil
    }

    func canResolveFirstEnablementConflict(_ status: LibraryCloudSyncStatus) -> Bool {
        status.isEnabled
            && status.bootstrapState == .needsConflictChoice
            && status.pendingConflictSummary?.isEmpty == false
    }

    func canCancelFirstEnablement(_ status: LibraryCloudSyncStatus) -> Bool {
        status.isEnabled && status.bootstrapState != .completed
    }

    func hasRequiredBootstrapInputs() -> Bool {
        hasTMDbAPIKey()
    }

    func persist(
        _ status: LibraryCloudSyncStatus,
        updating update: (inout LibraryCloudSyncStatus) -> Void
    ) -> LibraryCloudSyncStatus {
        var updatedStatus = status
        update(&updatedStatus)
        preferences.saveCloudSyncStatus(updatedStatus)
        return updatedStatus
    }
}
