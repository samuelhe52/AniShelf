//
//  EntryOpenInMenu.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/20.
//

import DataProvider
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Destinations offered by the "Open In" menus on entry details and library context menus.
struct EntryOpenInLinks: Equatable {
    var infuseURL: URL?
    var kazumiURL: URL?
    var homepageURL: URL?

    init(infuseURL: URL?, kazumiURL: URL?, homepageURL: URL?) {
        self.infuseURL = infuseURL
        self.kazumiURL = kazumiURL
        self.homepageURL = homepageURL
    }

    init(entry: AnimeEntry, homepageURL: URL?) {
        self.init(
            infuseURL: Self.infuseURL(type: entry.type, tmdbID: entry.tmdbID),
            kazumiURL: Self.kazumiURL(query: Self.kazumiSearchTitle(for: entry)),
            homepageURL: homepageURL
        )
    }

    /// Infuse resolves library items by TMDB ID and shows a placeholder page for titles it doesn't have.
    static func infuseURL(type: AnimeType, tmdbID: Int) -> URL? {
        switch type {
        case .movie:
            URL(string: "infuse://movie/\(tmdbID)")
        case .series:
            URL(string: "infuse://series/\(tmdbID)")
        case .season(let seasonNumber, let parentSeriesID):
            URL(string: "infuse://series/\(parentSeriesID)-\(seasonNumber)")
        }
    }

    /// Kazumi looks titles up on Bangumi, which AniShelf has no IDs for, so it opens a title search instead.
    static func kazumiURL(query: String) -> URL? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "kazumi"
        components.host = "search"
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        // URLComponents leaves `+` literal, but Kazumi's Dart parser decodes it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Bangumi matches Chinese and Japanese titles far better than English ones, so prefer those
    /// translations of the series title before falling back to the display name.
    static func kazumiSearchTitle(for entry: AnimeEntry) -> String {
        let series = entry.parentSeriesEntry ?? entry
        for languageKey in ["zh-CN", "ja-JP"] {
            if let title = series.nameTranslations[languageKey], !title.isEmpty {
                return title
            }
        }
        return entry.displayName
    }

    var isEmpty: Bool {
        infuseURL == nil && kazumiURL == nil && homepageURL == nil
    }

    /// iOS only answers for schemes listed under `LSApplicationQueriesSchemes` in Info.plist.
    @MainActor
    static func hasHandler(for url: URL) -> Bool {
        #if os(macOS)
            NSWorkspace.shared.urlForApplication(toOpen: url) != nil
        #else
            UIApplication.shared.canOpenURL(url)
        #endif
    }
}

enum EntryOpenInL10n {
    static let openIn: LocalizedStringResource = "Open In…"
    /// Swipe actions size to their labels, so the swipe uses a short label.
    static let open: LocalizedStringResource = "Open"
    static let homepage: LocalizedStringResource = "Homepage"
    static let notInstalled: LocalizedStringResource = "Not Installed"
    static let systemImage = "arrow.up.forward.app"
}

/// Menu items for every available link. Apps that aren't installed stay listed but disabled,
/// so people can discover them.
struct EntryOpenInMenuItems: View {
    let links: EntryOpenInLinks

    var body: some View {
        if let infuseURL = links.infuseURL {
            AppItem(name: "Infuse", systemImage: "play.rectangle", url: infuseURL)
        }

        if let kazumiURL = links.kazumiURL {
            AppItem(name: "Kazumi", systemImage: "magnifyingglass", url: kazumiURL)
        }

        if let homepageURL = links.homepageURL {
            if links.infuseURL != nil || links.kazumiURL != nil {
                Divider()
            }

            Link(destination: homepageURL) {
                Label(EntryOpenInL10n.homepage, systemImage: "safari")
            }
        }
    }

    private struct AppItem: View {
        @Environment(\.openURL) private var openURL

        let name: String
        let systemImage: String
        let url: URL

        var body: some View {
            let isInstalled = EntryOpenInLinks.hasHandler(for: url)
            Button {
                openURL(url)
            } label: {
                Label {
                    Text(verbatim: name)
                    if !isInstalled {
                        Text(EntryOpenInL10n.notInstalled)
                    }
                } icon: {
                    Image(systemName: systemImage)
                }
            }
            .disabled(!isInstalled)
        }
    }
}

/// A pending choice from a list row's Open In swipe action.
///
/// A plain button preserves native swipe sizing. The alert keeps unavailable apps
/// visible as disabled choices, unlike the confirmation dialog.
struct EntryOpenInRequest: Identifiable {
    let id = UUID()
    let entryID: LibraryEntryIdentity
    let title: String
    let links: EntryOpenInLinks

    init(entry: AnimeEntry) {
        entryID = entry.libraryIdentity
        title = entry.displayName
        links = EntryOpenInLinks(entry: entry, homepageURL: entry.linkToDetails)
    }
}

extension View {
    /// Shows the Open In alert when `request` belongs to
    /// `entryID`.
    func entryOpenInAlert(
        request: Binding<EntryOpenInRequest?>,
        entryID: LibraryEntryIdentity
    ) -> some View {
        modifier(EntryOpenInAlertModifier(request: request, entryID: entryID))
    }
}

fileprivate struct EntryOpenInAlertModifier: ViewModifier {
    @Environment(\.openURL) private var openURL
    @Binding var request: EntryOpenInRequest?
    let entryID: LibraryEntryIdentity

    func body(content: Content) -> some View {
        let presentedRequest = request?.entryID == entryID ? request : nil
        let isPresented = Binding(
            get: { presentedRequest != nil && request?.id == presentedRequest?.id },
            set: { isPresented in
                if !isPresented, request?.id == presentedRequest?.id {
                    request = nil
                }
            }
        )

        content.alert(
            Text(EntryOpenInL10n.openIn),
            isPresented: isPresented,
            presenting: presentedRequest
        ) { request in
            actions(for: request)
        } message: { request in
            Text(verbatim: request.title)
        }
    }

    @ViewBuilder
    private func actions(for request: EntryOpenInRequest) -> some View {
        appButton(name: "Infuse", url: request.links.infuseURL)
        appButton(name: "Kazumi", url: request.links.kazumiURL)
        if let homepageURL = request.links.homepageURL {
            Button {
                openURL(homepageURL)
            } label: {
                Text(EntryOpenInL10n.homepage)
            }
            .keyboardShortcut(nil)
        }
        Button("Cancel", role: .cancel) {}
            .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private func appButton(name: String, url: URL?) -> some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                Text(verbatim: name)
            }
            .disabled(!EntryOpenInLinks.hasHandler(for: url))
            .keyboardShortcut(nil)
        }
    }
}

/// A list row's Open In swipe action, which hands the request to its alert.
struct EntryOpenInSwipeButton: View {
    let entry: AnimeEntry
    let action: (EntryOpenInRequest) -> Void

    var body: some View {
        Button {
            action(EntryOpenInRequest(entry: entry))
        } label: {
            Label(EntryOpenInL10n.open, systemImage: EntryOpenInL10n.systemImage)
        }
    }
}

/// The "Open In" submenu for library context menus.
struct EntryOpenInSubmenu: View {
    let entry: AnimeEntry

    var body: some View {
        let links = EntryOpenInLinks(entry: entry, homepageURL: entry.linkToDetails)
        if !links.isEmpty {
            Menu {
                EntryOpenInMenuItems(links: links)
            } label: {
                Label(EntryOpenInL10n.openIn, systemImage: EntryOpenInL10n.systemImage)
            }
        }
    }
}

/// The "Open In" button in the entry detail quick actions row.
struct EntryDetailOpenInMenu: View {
    @Environment(\.popupPanelStyle) private var panelStyle

    let links: EntryOpenInLinks

    var body: some View {
        if !links.isEmpty {
            Menu {
                EntryOpenInMenuItems(links: links)
            } label: {
                PopupActionButtonLabel(systemImage: EntryOpenInL10n.systemImage)
            }
            .popupActionButtonChrome()
            .menuIndicator(panelStyle == .grouped ? .hidden : .automatic)
            .accessibilityLabel(Text(EntryOpenInL10n.openIn))
            .macHelp(Text(EntryOpenInL10n.openIn))
        }
    }
}
