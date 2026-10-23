//
//  MacLibraryLifecycle.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/15.
//

#if os(macOS)
    import AppKit
    import SwiftUI
    import UserNotifications
    import os

    fileprivate let macLifecycleLogger = Logger(
        subsystem: .bundleIdentifier,
        category: "LibrarySync.MacLifecycle"
    )

    /// The Mac application delegate: CloudKit pushes, airing-reminder notifications, periodic
    /// reminder refresh, and finishing local sync work before quitting.
    @MainActor
    final class LibrarySyncNotificationBridge: NSObject, NSApplicationDelegate {
        enum SyncResult { case noData, newData, failed }

        static let airingReminderRefreshActivityIdentifier =
            "com.samuelhe.MyAnimeList.airing-reminder-refresh"
        /// Matches the iOS background refresh cadence.
        static let airingReminderRefreshInterval: TimeInterval = 6 * 60 * 60
        /// How long quitting waits for pending local changes to reach iCloud.
        static let terminationSyncTimeout: Duration = .seconds(10)

        private static var syncHandler: (@MainActor () async -> SyncResult)?
        private static var terminationFlushHandler: (@MainActor () async -> Void)?
        private static var needsTerminationFlush: @MainActor () -> Bool = { false }
        private static var reminderRefreshActivity: NSBackgroundActivityScheduler?
        private static var sleepWakeObservers: [NSObjectProtocol] = []
        private static var activationObserver: NSObjectProtocol?

        static func configureSyncHandler(_ handler: @escaping @MainActor () async -> SyncResult) {
            syncHandler = handler
        }

        /// Lets quitting finish pending local sync work first, as iOS does when backgrounding.
        static func configureTerminationFlush(
            isNeeded: @escaping @MainActor () -> Bool,
            flush: @escaping @MainActor () async -> Void
        ) {
            needsTerminationFlush = isNeeded
            terminationFlushHandler = flush
        }

        /// Pushes pending edits before the Mac sleeps and catches up after it wakes, once per
        /// event and independent of how many windows are open.
        static func configureSleepAndWake(
            willSleep: @escaping @MainActor () -> Void,
            didWake: @escaping @MainActor () -> Void
        ) {
            let center = NSWorkspace.shared.notificationCenter
            sleepWakeObservers.forEach(center.removeObserver)
            sleepWakeObservers = [
                center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { willSleep() }
                },
                center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { didWake() }
                }
            ]
        }

        /// Runs foreground work each time the app becomes active, whether or not any library
        /// window is open; closing the last window keeps the app running (docs-ai 028).
        static func configureActivation(didBecomeActive: @escaping @MainActor () -> Void) {
            let center = NotificationCenter.default
            activationObserver.map(center.removeObserver)
            activationObserver = center.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { didBecomeActive() }
            }
        }

        /// macOS has no BGTaskScheduler; refresh periodically while the app runs instead.
        ///
        /// Notifications already scheduled are delivered even after the app quits.
        static func updateAiringReminderBackgroundRefresh(hasSubscriptions: Bool) {
            reminderRefreshActivity?.invalidate()
            reminderRefreshActivity = nil
            guard hasSubscriptions else { return }

            let activity = NSBackgroundActivityScheduler(
                identifier: airingReminderRefreshActivityIdentifier
            )
            activity.repeats = true
            activity.interval = airingReminderRefreshInterval
            activity.tolerance = airingReminderRefreshInterval / 6
            activity.qualityOfService = .utility
            activity.schedule { completion in
                Task { @MainActor in
                    _ = await AiringReminderCoordinator.shared.refreshAll()
                    completion(.finished)
                }
            }
            reminderRefreshActivity = activity
        }

        func applicationWillFinishLaunching(_ notification: Notification) {
            // Set before launch finishes so a click that launched the app is still delivered.
            UNUserNotificationCenter.current().delegate = self
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            NSApplication.shared.registerForRemoteNotifications()
        }

        func application(
            _ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
        ) {
            macLifecycleLogger.info("Registered for remote notifications with APNs.")
        }

        func application(
            _ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error
        ) {
            macLifecycleLogger.error(
                "Failed to register for remote notifications with APNs: \(error.localizedDescription, privacy: .public)"
            )
        }

        func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
            macLifecycleLogger.info("Received remote notification for iCloud library sync.")
            Task { _ = await Self.syncHandler?() }
        }

        /// Closing the last window keeps sync and reminder refresh running; reopen from the Dock.
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            false
        }

        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            guard Self.needsTerminationFlush(), let flush = Self.terminationFlushHandler else {
                return .terminateNow
            }
            // The flush may wait on a CloudKit pass that ignores cancellation, so the timeout
            // replies on its own instead of awaiting the cancelled flush.
            let reply = TerminationReply(application: sender)
            let flushTask = Task { @MainActor in
                await flush()
                reply.send()
            }
            Task { @MainActor in
                try? await Task.sleep(for: Self.terminationSyncTimeout)
                flushTask.cancel()
                reply.send()
            }
            return .terminateLater
        }
    }

    /// Answers a deferred termination request exactly once.
    @MainActor
    fileprivate final class TerminationReply {
        private let application: NSApplication
        private var hasReplied = false

        init(application: NSApplication) {
            self.application = application
        }

        func send() {
            guard !hasReplied else { return }
            hasReplied = true
            application.reply(toApplicationShouldTerminate: true)
        }
    }

    extension LibrarySyncNotificationBridge {
        nonisolated func openAiringReminder(
            entryIdentityRawID: String,
            response: UNNotificationResponse
        ) async {
            await MainActor.run {
                // macOS reports no target scene: the most recently active library window opens
                // the entry, even when hidden or minimized, or a new one does when every library
                // window is closed.
                let window = MacLibraryWindows.frontmost
                AiringReminderCoordinator.shared.receiveNotificationRoute(
                    entryIdentityRawID: entryIdentityRawID,
                    targetSceneIdentifier: window?.sceneIdentifier
                )
                NSApplication.shared.activate()
                if let window {
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    window.makeKeyAndOrderFront(nil)
                } else {
                    MacLibraryWindows.openNew()
                }
            }
        }
    }

    /// Library windows for app-level events: the one to target, and a way to open one after
    /// the last is closed. Which windows are open comes from `AppWindowCoordinator`.
    @MainActor
    enum MacLibraryWindows {
        /// SwiftUI only hands `openWindow` to views, so library windows provide it.
        private static var openWindow: OpenWindowAction?

        static func provideOpenWindow(_ openWindow: OpenWindowAction) {
            self.openWindow = openWindow
        }

        /// The most recently active library window that is still open, even if it is
        /// minimized or the app is hidden.
        static var frontmost: NSWindow? {
            guard let identifier = AppWindowCoordinator.shared.frontmostLibraryWindowID else { return nil }
            return NSApplication.shared.windows.first { $0.sceneIdentifier == identifier }
        }

        static func openNew() {
            openWindow?(id: MacWindowID.library)
        }
    }

    /// Keeps a library sync operation running while the app is hidden or the Mac idles.
    ///
    /// macOS does not suspend apps like iOS, but App Nap can throttle them and sudden
    /// termination can kill them; the activity assertion prevents both until the work ends.
    @MainActor
    final class LibrarySyncBackgroundExecutionController {
        private var operationTask: Task<Void, Never>?

        func run(
            onExpiration: @escaping @MainActor () -> Void,
            operation: @escaping @MainActor () async -> Void
        ) {
            guard operationTask == nil else { return }
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .suddenTerminationDisabled],
                reason: "Finish iCloud Library Sync"
            )
            operationTask = Task { [weak self] in
                await operation()
                ProcessInfo.processInfo.endActivity(activity)
                self?.operationTask = nil
            }
        }
    }
#endif
