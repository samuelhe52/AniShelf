//
//  MyAnimeListApp.swift
//  MyAnimeList
//
//  Created by Samuel He on 2024/12/8.
//

import DataProvider
import SwiftData
import SwiftUI
import UIKit

@main
struct MyAnimeListApp: App {
    @UIApplicationDelegateAdaptor(LibrarySyncNotificationBridge.self) private var notificationBridge
    @State var libraryStore: LibraryStore
    @State var keyStorage: TMDbAPIKeyStorage
    @State var whatsNew: WhatsNewController
    @State var supportStore: SupportStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(.preferredAnimeInfoLanguage) var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) var followsSystemLanguage: Bool =
        Language.followsSystemPreference()

    init() {
        let keyStorage = TMDbAPIKeyStorage()
        let libraryStore = LibraryStore(
            dataProvider: .default,
            hasTMDbAPIKey: {
                guard let key = keyStorage.key else { return false }
                return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
        let whatsNew = WhatsNewController()
        let supportStore = SupportStore()

        _libraryStore = State(initialValue: libraryStore)
        _keyStorage = State(initialValue: keyStorage)
        _whatsNew = State(initialValue: whatsNew)
        _supportStore = State(initialValue: supportStore)

        LibrarySyncNotificationBridge.configureSyncHandler { [libraryStore] in
            let result = await libraryStore.performLibrarySyncResult(trigger: .cloudNotification)
            switch result {
            case .success:
                return .newData
            case .skipped(_):
                return .noData
            case .conflictChoiceRequired, .retryableFailure, .permanentFailure:
                return .failed
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let key = keyStorage.key, !key.isEmpty {
                    LibraryView()
                        .onAppear {
                            libraryStore.language = followsSystemLanguage ? .current : preferredLanguage
                        }
                        .transition(.opacity.animation(.easeInOut(duration: 1)))
                } else {
                    TMDbAPIOnboardingView()
                        .transition(.opacity.animation(.easeInOut(duration: 1)))
                }
            }
            .environment(libraryStore)
            .environment(keyStorage)
            .environment(whatsNew)
            .environment(supportStore)
            .environment(\.dataHandler, DataProvider.default.dataHandler)
            .onAppear {
                requestSync(trigger: .appLaunch)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    requestSync(trigger: .foreground)
                } else if newPhase == .background {
                    flushPendingLocalSync()
                }
            }
            .sheet(item: presentedWhatsNewEntry) { entry in
                NavigationStack {
                    WhatsNewRootSheet(
                        entry: entry,
                        settingsActions: .init(store: libraryStore),
                        onDismiss: { whatsNew.dismissPresentedEntry() }
                    )
                }
                .presentationDetents([.large])
            }
            .onAppear(perform: updateWhatsNewPresentation)
            .onChange(of: keyStorage.key) { _, _ in
                updateWhatsNewPresentation()
            }
            .globalToasts()
        }
    }

    private var presentedWhatsNewEntry: Binding<WhatsNewEntry?> {
        Binding(
            get: { whatsNew.presentedEntry },
            set: { newValue in
                if let newValue {
                    whatsNew.presentedEntry = newValue
                } else {
                    whatsNew.dismissPresentedEntry()
                }
            }
        )
    }

    private func updateWhatsNewPresentation() {
        whatsNew.presentIfNeeded(allowsAutoPresentation: hasTMDbAPIKey)
    }

    private func requestSync(trigger: LibrarySyncCoordinator.Trigger) {
        libraryStore.syncLibrary(trigger: trigger)
    }

    private func flushPendingLocalSync() {
        libraryStore.flushPendingLocalLibrarySync()
    }

    private var hasTMDbAPIKey: Bool {
        guard let key = keyStorage.key else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

fileprivate struct WhatsNewRootSheet: View {
    let entry: WhatsNewEntry
    let onDismiss: () -> Void

    @State private var actionRunner: WhatsNewActionRunner

    init(
        entry: WhatsNewEntry,
        settingsActions: LibraryProfileSettingsActions,
        onDismiss: @escaping () -> Void
    ) {
        self.entry = entry
        self.onDismiss = onDismiss
        _actionRunner = State(initialValue: settingsActions.makeWhatsNewActionRunner())
    }

    var body: some View {
        WhatsNewView(
            entry: entry,
            actionRunner: actionRunner,
            onDismiss: onDismiss
        )
    }
}
