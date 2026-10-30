//
//  MacLibraryEntryDrag.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/30.
//

#if os(macOS)
    import DataProvider
    import SwiftUI
    import UniformTypeIdentifiers

    /// Library entries dragged from the grid or list, dropped onto a sidebar category.
    ///
    /// A dedicated type keeps arbitrary dropped text from being read as entry IDs.
    struct LibraryEntryDragPayload: Codable, Transferable {
        static let contentType = UTType(exportedAs: "com.samuelhe.myanimelist.library-entries")

        let rawIDs: [String]

        static var transferRepresentation: some TransferRepresentation {
            CodableRepresentation(contentType: contentType)
        }
    }

    extension View {
        /// Drags the entry, or the whole selection when the entry is part of it, as Finder does.
        func macLibraryEntryDraggable(
            _ id: LibraryEntryIdentity,
            selection: MacLibrarySelection
        ) -> some View {
            // The payload is built when the drag starts, so it reads the selection then.
            draggable(
                LibraryEntryDragPayload(
                    rawIDs: selection.ids.contains(id) ? selection.ids.map(\.rawID) : [id.rawID]
                )
            )
        }
    }

    extension LibraryStore {
        /// Adds dropped entries to a category.
        func addDroppedEntries(_ payloads: [LibraryEntryDragPayload], to categoryID: LibraryCategory.ID) {
            let rawIDs = Set(payloads.flatMap(\.rawIDs))
            let entries = rawIDs.compactMap { rawID in
                LibraryEntryIdentity(rawID: rawID).flatMap(repository.existingEntry(identity:))
            }
            LibraryBatchAction.category(categoryID, isMember: true, knownCategoryIDs: knownCategoryIDs)
                .apply(to: entries)
        }
    }
#endif
