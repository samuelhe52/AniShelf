//
//  LibraryDetailHostCoordination.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import DataProvider
import LibrarySync
import SwiftUI

// iOS moves entry detail between a sheet and the iPad inspector. The Mac inspector follows
// the window selection instead (`MacLibraryInspector`).
#if !os(macOS)
    struct LibraryDetailHostCoordination: ViewModifier {
        @Environment(\.self) private var environment
        let store: LibraryStore
        let interaction: LibraryEntryInteractionState
        let detailSessionStore: EntryDetailSessionStore
        let horizontalSizeClass: PlatformHorizontalSizeClass?
        let isSearching: Bool
        let isShowingProfileSettings: Bool
        @Binding var workspaceState: LibraryInspectorDetailWorkspaceState
        @Binding var persistedLastInspectorDetailEntryIdentity: String?
        @Binding var adaptsInspectorNatively: Bool

        func body(content: Content) -> some View {
            content
                .onAppear {
                    updateDetailHost()
                    restorePresentedDetailIfNeeded()
                }
                .onChange(of: horizontalSizeClass) {
                    updateDetailHost()
                }
                .onChange(of: systemAdaptsInspector, initial: true) { _, adapts in
                    // Unfolding briefly reports no vertical bar while the width is still compact;
                    // following that would migrate detail to the app's sheet mid-transition and
                    // crash UIKit's own sheet-to-column move. A scene that has had a vertical bar
                    // keeps native adaptation.
                    guard adapts, !adaptsInspectorNatively else { return }
                    adaptsInspectorNatively = true
                    updateDetailHost()
                }
                .onChange(of: detailHostMigrationBlocked) { _, isBlocked in
                    guard !isBlocked else { return }
                    interaction.reconcileDetailHostIfPossible(migrationBlocked: false)
                }
                .onInteractiveResizeChange { isResizing in
                    interaction.interactiveResizeDidChange(
                        isResizing,
                        migrationBlocked: detailHostMigrationBlocked
                    )
                }
                .onChange(of: interaction.presentedDetailEntryID, initial: true) { _, identity in
                    synchronizePresentedDetail(identity)
                }
                .onChange(of: interaction.detailHostPresentation) {
                    reconcileInspectorDetailPersistence()
                }
                .onChange(of: store.libraryRevision) {
                    synchronizePresentedDetail(interaction.presentedDetailEntryID)
                }
        }

        static func updateDetailHost(
            interaction: LibraryEntryInteractionState,
            detailSessionStore: EntryDetailSessionStore,
            desiredHost: LibraryEntryDetailHost,
            migrationBlocked: Bool,
            rootPresentationActive: Bool
        ) {
            if !rootPresentationActive,
                let presentation = interaction.detailHostPresentation,
                presentation.host != desiredHost || !presentation.isHostPresented
            {
                detailSessionStore.session(for: interaction.presentedDetailEntryID)?
                    .dismissActiveSheetForHostChange()
            }

            interaction.requestDetailHost(
                desiredHost,
                migrationBlocked: migrationBlocked,
                rootPresentationActive: rootPresentationActive
            )
        }

        static func prepareDetailSession(
            for entry: AnimeEntry,
            detailSessionStore: EntryDetailSessionStore,
            repository: LibraryRepository
        ) {
            detailSessionStore.synchronizePresentedDetail(
                identity: entry.libraryIdentity,
                repository: repository,
                resolveEntry: { identity in
                    identity == entry.libraryIdentity
                        ? entry : repository.existingEntry(identity: identity)
                }
            )
        }

        private var detailHostPolicy: LibraryEntryDetailHostPolicy {
            LibraryEntryDetailHostPolicy(
                horizontalSizeClass: horizontalSizeClass,
                adaptsInspectorNatively: adaptsInspectorNatively || systemAdaptsInspector
            )
        }

        /// Whether the system currently places a vertical bar, as on iPhone Duo.
        ///
        /// iPhone Duo folds between compact and regular widths with a vertical bar in compact
        /// poses, and the native inspector carries detail across those changes itself. The first
        /// vertical bar a scene sees is kept in `adaptsInspectorNatively`.
        private var systemAdaptsInspector: Bool {
            if #available(iOS 27.1, *) {
                return environment.toolbarVerticalEdge != nil
            }
            return false
        }

        private var detailHostMigrationBlocked: Bool {
            detailSessionStore.session(
                for: interaction.presentedDetailEntryID
            )?.blocksHostMigration == true
        }

        private var isRootPresentationActive: Bool {
            isSearching
                || isShowingProfileSettings
                || interaction.actions.workflowPresentation != nil
        }

        private func updateDetailHost() {
            Self.updateDetailHost(
                interaction: interaction,
                detailSessionStore: detailSessionStore,
                desiredHost: detailHostPolicy.host,
                migrationBlocked: detailHostMigrationBlocked,
                rootPresentationActive: isRootPresentationActive
            )
        }

        private func synchronizePresentedDetail(_ identity: LibraryEntryIdentity?) {
            let didResolveDetail = detailSessionStore.synchronizePresentedDetail(
                identity: identity,
                repository: store.repository,
                resolveEntry: { store.repository.existingEntry(identity: $0) }
            )
            if identity != nil, !didResolveDetail {
                interaction.dismissDetails()
            }
        }

        private func reconcileInspectorDetailPersistence() {
            switch LibraryInspectorDetailWorkspaceState.persistenceAction(
                for: interaction.presentedDetailEntryID,
                committedHostPresentation: interaction.detailHostPresentation
            ) {
            case .clear:
                persistedLastInspectorDetailEntryIdentity = nil
            case .persist(let identity):
                persistedLastInspectorDetailEntryIdentity = identity.rawID
            case .preserve:
                break
            }
        }

        private func restorePresentedDetailIfNeeded() {
            let restorationAction = workspaceState.initialRestorationAction(
                for: interaction.desiredDetailHost,
                presentedDetailEntryIdentity: interaction.presentedDetailEntryID,
                savedIdentityRawID: persistedLastInspectorDetailEntryIdentity,
                isRestorableIdentity: { identityRawID in
                    guard let entry = store.repository.existingEntry(identityRawID: identityRawID) else {
                        return false
                    }
                    return entry.onDisplay
                }
            )

            switch restorationAction {
            case .clearInvalidSavedIdentity:
                persistedLastInspectorDetailEntryIdentity = nil
                interaction.dismissDetails()
            case .none:
                return
            case .restore(let identityRawID):
                guard let entry = store.repository.existingEntry(identityRawID: identityRawID),
                    entry.onDisplay
                else {
                    persistedLastInspectorDetailEntryIdentity = nil
                    interaction.dismissDetails()
                    return
                }
                Self.prepareDetailSession(
                    for: entry,
                    detailSessionStore: detailSessionStore,
                    repository: store.repository
                )
                interaction.openDetails(for: entry)
            }
        }
    }

    extension View {
        func libraryDetailHostCoordination(
            store: LibraryStore,
            interaction: LibraryEntryInteractionState,
            detailSessionStore: EntryDetailSessionStore,
            horizontalSizeClass: PlatformHorizontalSizeClass?,
            isSearching: Bool,
            isShowingProfileSettings: Bool,
            workspaceState: Binding<LibraryInspectorDetailWorkspaceState>,
            persistedLastInspectorDetailEntryIdentity: Binding<String?>,
            adaptsInspectorNatively: Binding<Bool>
        ) -> some View {
            modifier(
                LibraryDetailHostCoordination(
                    store: store,
                    interaction: interaction,
                    detailSessionStore: detailSessionStore,
                    horizontalSizeClass: horizontalSizeClass,
                    isSearching: isSearching,
                    isShowingProfileSettings: isShowingProfileSettings,
                    workspaceState: workspaceState,
                    persistedLastInspectorDetailEntryIdentity: persistedLastInspectorDetailEntryIdentity,
                    adaptsInspectorNatively: adaptsInspectorNatively
                )
            )
        }
    }
#endif
