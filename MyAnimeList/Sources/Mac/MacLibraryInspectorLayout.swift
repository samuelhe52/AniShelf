//
//  MacLibraryInspectorLayout.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/17.
//

#if os(macOS)
    import SwiftUI

    /// The inspector content's full width, independent of its animated reveal.
    ///
    /// Only the grid consumes this measurement. It must not size the inspector
    /// or its native split host, which would create a layout feedback loop.
    @Observable
    @MainActor
    final class MacLibraryInspectorLayout {
        var width: CGFloat?
    }

    extension EnvironmentValues {
        @Entry var macLibraryInspectorLayout: MacLibraryInspectorLayout?
    }
#endif
