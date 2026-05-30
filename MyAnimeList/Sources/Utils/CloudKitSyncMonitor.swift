//
//  CloudKitSyncMonitor.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/30.
//

import CoreData
import Foundation

@Observable
@MainActor
final class CloudKitSyncMonitor {
    enum Status: Equatable {
        case idle
        case importing
        case exporting
        case error(String)
    }

    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?

    private(set) var status: Status = .idle

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let status = Self.status(from: notification)
            Task { @MainActor [weak self] in
                self?.status = status
            }
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    private nonisolated static func status(from notification: Notification) -> Status {
        guard
            let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
        else {
            return .idle
        }

        if let error = event.error {
            return .error(error.localizedDescription)
        }

        if event.endDate != nil {
            return .idle
        }

        switch event.type {
        case .import:
            return .importing
        case .export:
            return .exporting
        default:
            return .idle
        }
    }
}
