//
//  MacSelectionClick.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/16.
//

#if os(macOS)
    import AppKit

    /// How a click changes the desktop selection, from the modifier keys held during the click.
    enum MacSelectionClick {
        case replace
        case toggle
        case extend

        @MainActor static var current: MacSelectionClick {
            // The click's own flags; the global state can miss modifiers on synthesized events.
            let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
            if flags.contains(.command) { return .toggle }
            if flags.contains(.shift) { return .extend }
            return .replace
        }
    }
#endif
