//
//  LibraryEntryDetailHost.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

import SwiftUI

/// Where entry detail is shown. iOS uses both; the Mac shows detail only in its inspector.
enum LibraryEntryDetailHost: Equatable, Sendable {
    case sheet
    case inspector

    var pageBackground: Color {
        switch self {
        case .sheet:
            Color.platformSystemGroupedBackground
        case .inspector:
            Color.platformSystemBackground
        }
    }
}

enum LibraryEntryDetailActivation: Equatable, Sendable {
    case userPreference
    case singleTap

    func usesSingleTap(userPreference: Bool) -> Bool {
        self == .singleTap || userPreference
    }
}

fileprivate struct LibraryEntryDetailActivationKey: EnvironmentKey {
    static let defaultValue = LibraryEntryDetailActivation.userPreference
}

extension EnvironmentValues {
    var libraryEntryDetailActivation: LibraryEntryDetailActivation {
        get { self[LibraryEntryDetailActivationKey.self] }
        set { self[LibraryEntryDetailActivationKey.self] = newValue }
    }
}
