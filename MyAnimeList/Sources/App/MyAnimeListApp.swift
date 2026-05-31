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
    @State var libraryStore: LibraryStore = .init(dataProvider: .default)
    @State var keyStorage: TMDbAPIKeyStorage = .init()
    @State var whatsNew: WhatsNewController = .init()
    @State var supportStore: SupportStore = .init()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(.preferredAnimeInfoLanguage) var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) var followsSystemLanguage: Bool =
        Language.followsSystemPreference()

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
                notificationBridge.onSyncRequested = { [libraryStore, keyStorage] in
                    guard let key = keyStorage.key,
                          !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else {
                        return .noData
                    }
                    return await libraryStore.performLibrarySync(trigger: .cloudNotification) ? .newData : .failed
                }
                requestSync(trigger: .appLaunch)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    requestSync(trigger: .foreground)
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
        guard hasTMDbAPIKey else { return }
        libraryStore.syncLibrary(trigger: trigger)
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
