//
//  MacLibraryInspector.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/16.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    /// Asks the inspector's entry detail to reveal its editing section once.
    struct MacEntryEditRequest: Equatable {
        let id = UUID()
        let entryIdentity: LibraryEntryIdentity
    }

    /// The library window's inspector.
    ///
    /// Its content follows the selection: nothing selected,
    /// one entry's detail, or the batch panel. Swapping content presents or dismisses
    /// nothing; whether the inspector shows is the window's own setting.
    struct MacLibraryInspector: View {
        @Environment(\.macLibraryInspectorLayout) private var inspectorLayout
        let store: LibraryStore
        let selection: MacLibrarySelection
        /// The entries the window shows, in layout order.
        let displayItems: [LibraryEntryDisplayItem]
        let detailSessionStore: EntryDetailSessionStore
        @Binding var editRequest: MacEntryEditRequest?
        let scoringEnabled: Bool
        let applyBatchAction: ([AnimeEntry], LibraryBatchAction) -> Void
        let deleteEntries: ([AnimeEntry]) -> Void
        @Binding var isPresented: Bool
        /// The last entry selected alone, for the batch panel to open its stack on.
        @State private var lastSingleID: LibraryEntryIdentity?
        @State private var posterFlight = MacInspectorPosterFlight()

        private var selectedEntry: AnimeEntry? {
            guard isPresented, let identity = selection.single else { return nil }
            return displayItems.first { $0.id == identity }?.entry
        }

        var body: some View {
            ZStack {
                // SwiftUI keeps the inspector alive while collapsed. Remove its content
                // explicitly so arrow navigation cannot load and save hidden entry details.
                if isPresented {
                    selectionContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: { width in
                if width > 0 { inspectorLayout?.width = width }
            }
            .environment(\.macInspectorPosterFlight, posterFlight)
            .overlay { MacInspectorPosterFlightOverlay(posterFlight: posterFlight) }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: { frame in
                posterFlight.bounds = frame
            }
            // The window's one inspector toggle. Items in the inspector's toolbar stay in the
            // window toolbar while the inspector is collapsed, at its trailing edge.
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    let title: LocalizedStringKey = isPresented ? "Hide Inspector" : "Show Inspector"
                    Button(title, systemImage: "sidebar.trailing") {
                        withAnimation { isPresented.toggle() }
                    }
                    .help(Text(title))
                }
            }
            // Import can replace the object behind the selected identity. Changes to that
            // same object's metadata do not recreate its session or restart its load.
            .onChange(of: selectedEntry.map(ObjectIdentifier.init), initial: true) {
                synchronizeDetailSession(selectedEntry?.libraryIdentity)
            }
            .onChange(of: selection.ids, initial: true) {
                // A batch keeps the entry it grew from; clearing the selection forgets it.
                if let single = selection.single {
                    lastSingleID = single
                    posterFlight.cancel()
                } else if selection.isEmpty {
                    lastSingleID = nil
                    posterFlight.sourceFrame = nil
                    posterFlight.cancel()
                }
            }
            .inspectorColumnWidth(min: 340, ideal: 400, max: 560)
        }

        @ViewBuilder
        private var selectionContent: some View {
            if selection.ids.count > 1 {
                let selectedEntries = selectedEntries
                MacBatchSelectionPanel(
                    store: store,
                    selectedEntries: selectedEntries,
                    lastClickedID: selection.anchor,
                    enteringFromID: lastSingleID,
                    scoringEnabled: scoringEnabled,
                    apply: applyBatchAction,
                    deleteSelectedEntries: { deleteEntries(selectedEntries) }
                )
            } else if let identity = selection.single {
                // The session is created right after the selection changes; until then
                // show nothing rather than flash No Selection.
                if let session = detailSessionStore.session(for: identity) {
                    entryDetail(session: session)
                }
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.trailing")
            }
        }

        /// The selection in layout order.
        private var selectedEntries: [AnimeEntry] {
            let ids = selection.ids
            guard !ids.isEmpty else { return [] }
            return displayItems.lazy.filter { ids.contains($0.id) }.map(\.entry)
        }

        private func entryDetail(session: EntryDetailSession) -> some View {
            let identity = session.entryIdentity
            return NavigationStack {
                EntryDetailView(
                    session: session,
                    detailHost: .inspector,
                    // A conversion replaces the entry; it leaves the selection.
                    onClose: { selection.select(selection.ids.subtracting([$0])) },
                    editingRequestID: editRequest?.entryIdentity == identity ? editRequest?.id : nil,
                    onEditingRequestHandled: { requestID in
                        if editRequest?.id == requestID { editRequest = nil }
                    }
                )
            }
            .presentationBackground(LibraryEntryDetailHost.inspector.pageBackground)
        }

        private func synchronizeDetailSession(_ identity: LibraryEntryIdentity?) {
            detailSessionStore.synchronizePresentedDetail(
                identity: identity,
                repository: store.repository,
                resolveEntry: { id in
                    displayItems.first { $0.id == id }?.entry ?? store.repository.existingEntry(identity: id)
                }
            )
        }
    }
#endif
