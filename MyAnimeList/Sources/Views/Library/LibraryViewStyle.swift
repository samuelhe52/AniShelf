//
//  LibraryViewStyle.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
//

import SwiftUI

/// The library's layout.
///
/// The Mac offers only List and Grid (`macCases`).
enum LibraryViewStyle: String, CaseIterable, Codable {
    case gallery
    case list
    case grid

    var nameKey: LocalizedStringKey {
        switch self {
        case .gallery: "Gallery"
        case .list: "List"
        case .grid: "Grid"
        }
    }

    var systemImageName: String {
        switch self {
        case .gallery: "photo.on.rectangle.angled"
        case .list: "list.bullet.rectangle.portrait"
        case .grid: "rectangle.grid.3x2.fill"
        }
    }
}
