//
//  PlatformViewModifiers.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/10/15.
//

import SwiftUI

#if os(macOS)
    enum PlatformHorizontalSizeClass { case compact, regular }
#else
    typealias PlatformHorizontalSizeClass = UserInterfaceSizeClass
#endif

extension EnvironmentValues {
    var platformHorizontalSizeClass: PlatformHorizontalSizeClass? {
        #if os(macOS)
            .regular
        #else
            horizontalSizeClass
        #endif
    }
}

extension View {
    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(macOS)
            self
        #else
            navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder func hiddenNavigationBarBackground() -> some View {
        #if os(macOS)
            self
        #else
            toolbarBackground(.hidden, for: .navigationBar)
        #endif
    }

    @ViewBuilder func noInputAutocapitalization() -> some View {
        #if os(macOS)
            self
        #else
            textInputAutocapitalization(.never)
        #endif
    }

    @ViewBuilder func selectionEditMode(_ active: Bool) -> some View {
        #if os(macOS)
            self
        #else
            environment(\.editMode, .constant(active ? .active : .inactive))
        #endif
    }
}

extension ToolbarItemPlacement {
    static var platformTrailing: Self {
        #if os(macOS)
            .primaryAction
        #else
            .topBarTrailing
        #endif
    }
    static var platformLeading: Self {
        #if os(macOS)
            .navigation
        #else
            .topBarLeading
        #endif
    }
    static var platformBottomBar: Self {
        #if os(macOS)
            .automatic
        #else
            .bottomBar
        #endif
    }
}

extension Color {
    static var platformSystemBackground: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #else
            Color(uiColor: .systemBackground)
        #endif
    }
    static var platformSecondarySystemBackground: Color {
        #if os(macOS)
            Color(nsColor: .controlBackgroundColor)
        #else
            Color(uiColor: .secondarySystemBackground)
        #endif
    }
    static var platformSystemGroupedBackground: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #else
            Color(uiColor: .systemGroupedBackground)
        #endif
    }
    static var platformSecondarySystemGroupedBackground: Color {
        #if os(macOS)
            Color(nsColor: .controlBackgroundColor)
        #else
            Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    static var platformSecondarySystemFill: Color {
        #if os(macOS)
            Color(nsColor: .controlColor)
        #else
            Color(uiColor: .secondarySystemFill)
        #endif
    }
    static var platformTertiarySystemFill: Color {
        #if os(macOS)
            Color(nsColor: .quaternaryLabelColor)
        #else
            Color(uiColor: .tertiarySystemFill)
        #endif
    }
    static var platformQuaternarySystemFill: Color {
        #if os(macOS)
            Color(nsColor: .quaternaryLabelColor)
        #else
            Color(uiColor: .quaternarySystemFill)
        #endif
    }
    static var platformSystemGray5: Color {
        #if os(macOS)
            Color(nsColor: .separatorColor)
        #else
            Color(uiColor: .systemGray5)
        #endif
    }
}

extension SearchFieldPlacement {
    static var platformDrawerAutomatic: Self {
        #if os(macOS)
            .toolbar
        #else
            .navigationBarDrawer(displayMode: .automatic)
        #endif
    }
    static var platformDrawerAlways: Self {
        #if os(macOS)
            .toolbar
        #else
            .navigationBarDrawer(displayMode: .always)
        #endif
    }
}

extension View {
    @ViewBuilder func keepsMenuPresentedAfterAction() -> some View {
        #if os(macOS)
            self
        #else
            menuActionDismissBehavior(.disabled)
        #endif
    }
}
