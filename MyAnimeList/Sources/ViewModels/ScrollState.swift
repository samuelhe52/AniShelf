//
//  ScrollState.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/4.
//

import Combine
import DataProvider
import Foundation

@Observable @MainActor
class ScrollState {
    var scrolledID: LibraryEntryIdentity? {
        didSet {
            writer.updateValue(scrolledID?.rawID)
        }
    }

    @ObservationIgnored private let writer: DebouncedStringUserDefaultsWriter

    init() {
        let persistedScrollPosition = UserDefaults.standard.string(forKey: .persistedScrolledID)
            .flatMap(LibraryEntryIdentity.init(rawID:))
        self.scrolledID = persistedScrollPosition
        self.writer = DebouncedStringUserDefaultsWriter(forKey: .persistedScrolledID)
    }
}
