//
//  MacLibraryFind.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

#if os(macOS)
    import Foundation
    import Observation

    /// A library window's toolbar Find.
    ///
    /// The field edits `text`; the library filters by `query`,
    /// which follows `text` once typing pauses so each keystroke doesn't re-filter the library.
    @Observable @MainActor
    final class MacLibraryFind {
        /// The trimmed text the library is filtered by.
        ///
        /// Empty shows the whole scope.
        private(set) var query = ""

        private var storedText = ""
        @ObservationIgnored private var pendingQuery: Task<Void, Never>?

        /// The search field's text.
        var text: String {
            get { storedText }
            set {
                storedText = newValue
                scheduleQuery()
            }
        }

        /// Empties the field and shows the whole scope at once.
        func clear() {
            text = ""
        }

        private func scheduleQuery() {
            pendingQuery?.cancel()
            let next = storedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard next != query else { return }
            // Clearing applies at once: restoring the full library shouldn't lag.
            guard !next.isEmpty else {
                query = ""
                return
            }
            pendingQuery = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                self?.query = next
            }
        }
    }
#endif
