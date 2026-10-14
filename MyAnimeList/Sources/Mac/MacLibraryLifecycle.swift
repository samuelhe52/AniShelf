//
//  MacLibraryLifecycle.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/10/15.
//

#if os(macOS)
    import AppKit

    /// Slice 1 keeps foreground sync and push delivery. Periodic scheduling and
    /// termination/sleep protection and local-notification delegate routing are deferred to slice 3.
    @MainActor
    final class LibrarySyncNotificationBridge: NSObject, NSApplicationDelegate {
        enum SyncResult { case noData, newData, failed }
        private static var syncHandler: (@MainActor () async -> SyncResult)?

        static func configureSyncHandler(_ handler: @escaping @MainActor () async -> SyncResult) {
            syncHandler = handler
        }

        static func updateAiringReminderBackgroundRefresh(hasSubscriptions: Bool) {
            // Slice 3: NSBackgroundActivityScheduler; launch/activation refresh remains enabled.
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            NSApplication.shared.registerForRemoteNotifications()
        }

        func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
            Task { _ = await Self.syncHandler?() }
        }
    }

    @MainActor
    final class LibrarySyncBackgroundExecutionController {
        private var operationTask: Task<Void, Never>?

        // Slice 3 adds lifetime protection and an expiration policy; this only drains while running.
        func run(
            onExpiration: @escaping @MainActor () -> Void,
            operation: @escaping @MainActor () async -> Void
        ) {
            guard operationTask == nil else { return }
            operationTask = Task {
                await operation()
                operationTask = nil
            }
        }
    }
#endif
