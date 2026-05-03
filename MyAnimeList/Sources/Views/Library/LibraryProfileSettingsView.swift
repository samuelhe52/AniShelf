//
//  LibraryProfileSettingsView.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/3.
//

import DataProvider
import Kingfisher
import SwiftUI

struct LibraryProfileStats: Equatable {
    let totalCount: Int
    let watchedCount: Int
    let watchingCount: Int
    let planToWatchCount: Int
    let droppedCount: Int
    let favoriteCount: Int
    let movieCount: Int
    let seriesCount: Int
    let seasonCount: Int
    let entriesWithNotesCount: Int
    let runtimeMinutes: Int

    init(entries: [AnimeEntry]) {
        totalCount = entries.count
        watchedCount = entries.count { $0.watchStatus == .watched }
        watchingCount = entries.count { $0.watchStatus == .watching }
        planToWatchCount = entries.count { $0.watchStatus == .planToWatch }
        droppedCount = entries.count { $0.watchStatus == .dropped }
        favoriteCount = entries.count { $0.favorite }
        movieCount = entries.count { $0.type == .movie }
        seriesCount = entries.count { $0.type == .series }
        seasonCount = entries.count {
            if case .season = $0.type {
                true
            } else {
                false
            }
        }
        entriesWithNotesCount = entries.count { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        runtimeMinutes = entries.reduce(0) { partialResult, entry in
            guard let runtime = entry.detail?.runtimeMinutes else {
                return partialResult
            }
            let multiplier = max(entry.detail?.episodeCount ?? 1, 1)
            return partialResult + runtime * multiplier
        }
    }
}

struct LibraryProfileSettingsView: View {
    @Bindable var store: LibraryStore
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()

    @State private var changeAPIKey = false
    @State private var showCacheAlert = false
    @State private var showClearAllAlert = false
    @State private var exportError: Error? = nil
    @State private var showExportError = false
    @State private var restoreError: Error? = nil
    @State private var showRestoreError = false
    @State private var showFileImporter = false
    @State private var restoreFileURL: URL? = nil
    @State private var showRestoreConfirmation = false
    @State private var showRefreshInfoOnLanguageUpdateAlert = false
    @State private var showRefreshInfoAlert = false
    @State private var showAboutSheet = false
    @State private var cacheSizeResult: Result<UInt, KingfisherError>? = nil
    @State private var appeared = false
    @SceneStorage("LibraryProfileSettingsView.restoreCompleted") private var restoreCompleted = false

    private var stats: LibraryProfileStats {
        LibraryProfileStats(entries: store.library)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LibraryProfileBackdrop(reduceMotion: reduceMotion)

                ScrollView {
                    VStack(spacing: 16) {
                        heroCard
                            .profileReveal(index: 0, appeared: appeared, reduceMotion: reduceMotion)
                        primaryStatsGrid
                            .profileReveal(index: 1, appeared: appeared, reduceMotion: reduceMotion)
                        libraryDetailsCard
                            .profileReveal(index: 2, appeared: appeared, reduceMotion: reduceMotion)
                        settingsCard
                            .profileReveal(index: 3, appeared: appeared, reduceMotion: reduceMotion)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(profileTitleResource)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let onDismiss {
                            onDismiss()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(closeTitleResource))
                }
            }
            .onAppear {
                store.language = effectiveLanguage
                withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
                    appeared = true
                }
            }
            .onChange(of: preferredLanguage) { old, new in
                guard old != new, !followsSystemLanguage else { return }
                store.language = new
                showRefreshInfoOnLanguageUpdateAlert = true
            }
            .onChange(of: followsSystemLanguage) { old, new in
                guard old != new else { return }
                let oldLanguage = resolvedLanguage(
                    followsSystem: old,
                    preferredLanguage: preferredLanguage
                )
                let newLanguage = resolvedLanguage(
                    followsSystem: new,
                    preferredLanguage: preferredLanguage
                )
                store.language = new ? .current : preferredLanguage
                guard oldLanguage != newLanguage else { return }
                showRefreshInfoOnLanguageUpdateAlert = true
            }
        }
        .alert("Delete all animes?", isPresented: $showClearAllAlert) {
            Button("Delete", role: .destructive) {
                store.clearLibrary()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Refresh Info Language?",
            isPresented: $showRefreshInfoOnLanguageUpdateAlert
        ) {
            Button("Refresh") {
                store.refreshInfos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let message: LocalizedStringResource = """
                Changing the metadata language setting will not refresh existing infos.
                Refresh all anime infos now? This may take considerable time.
                """

            Text(message)
        }
        .alert(
            "Refresh all anime infos?",
            isPresented: $showRefreshInfoAlert
        ) {
            Button("Refresh") {
                store.refreshInfos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This may take considerable time.")
        }
        .alert(
            "Error exporting library",
            isPresented: $showExportError,
            presenting: exportError
        ) { _ in
            Button("Cancel", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .alert(
            "Error restoring library",
            isPresented: $showRestoreError,
            presenting: restoreError
        ) { _ in
            Button("Cancel", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .alert("Overwrite the current library?", isPresented: $showRestoreConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm", role: .destructive, action: restore)
        } message: {
            Text("Please backup the current library before proceeding.")
        }
        .alert(
            "Metadata Cache Size", isPresented: $showCacheAlert, presenting: cacheSizeResult,
            actions: { result in
                switch result {
                case .success:
                    Button("Clear Cache") {
                        KingfisherManager.shared.cache.clearCache()
                    }
                    Button("Cancel", role: .cancel) {}
                case .failure:
                    Button("OK") {}
                }
            },
            message: { result in
                switch result {
                case .success(let size):
                    Text("Size: \(Double(size) / 1024 / 1024, specifier: "%.2f") MB")
                case .failure(let error):
                    Text(error.localizedDescription)
                }
            }
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.mallib]
        ) { result in
            processFileImport(result)
        }
        .sheet(isPresented: $changeAPIKey) {
            TMDbAPIConfigurator()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAboutSheet) {
            NavigationStack {
                AboutAniShelfSheet()
            }
            .presentationDetents([.fraction(0.85), .large])
        }
    }

    private var heroCard: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                Image(.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.orange.gradient, in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.7), lineWidth: 1)
                    }
                    .offset(x: 6, y: 6)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(stats.totalCount)")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(animeTitleResource)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(20)
        .popupGlassPanel(cornerRadius: 30, tint: .white.opacity(0.045))
    }

    private var primaryStatsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            LibraryProfileMetricCard(
                title: "Watched",
                value: stats.watchedCount,
                systemImage: "checkmark.circle.fill",
                tint: AnimeEntry.WatchStatus.watched.libraryTintColor
            )
            LibraryProfileMetricCard(
                title: "Watching",
                value: stats.watchingCount,
                systemImage: "play.circle.fill",
                tint: AnimeEntry.WatchStatus.watching.libraryTintColor
            )
            LibraryProfileMetricCard(
                title: "Favorites",
                value: stats.favoriteCount,
                systemImage: "heart.fill",
                tint: .pink
            )
            LibraryProfileMetricCard(
                title: "Planned",
                value: stats.planToWatchCount,
                systemImage: "bookmark.fill",
                tint: AnimeEntry.WatchStatus.planToWatch.libraryTintColor
            )
        }
    }

    private var libraryDetailsCard: some View {
        PopupSectionCard("Library Details", systemImage: "sparkles.rectangle.stack", spacing: 14) {
            VStack(spacing: 10) {
                LibraryProfileDetailRow(title: "Movies", value: "\(stats.movieCount)", systemImage: "film")
                LibraryProfileDetailRow(title: "Series", value: "\(stats.seriesCount)", systemImage: "tv")
                LibraryProfileDetailRow(
                    title: "Seasons", value: "\(stats.seasonCount)", systemImage: "square.stack.3d.up")
                LibraryProfileDetailRow(
                    title: "With Notes", value: "\(stats.entriesWithNotesCount)", systemImage: "note.text")
                LibraryProfileDetailRow(title: "Runtime", value: runtimeDescription, systemImage: "clock")
            }
        }
    }

    private var settingsCard: some View {
        PopupSectionCard("Settings", systemImage: "gearshape.2", spacing: 12) {
            VStack(spacing: 10) {
                languagePickerRow
                backupManagementRow
                LibraryProfileActionRow(
                    title: "Change API Key",
                    subtitle: "Update the TMDb key used for metadata.",
                    systemImage: "person.badge.key"
                ) {
                    changeAPIKey = true
                }
                LibraryProfileActionRow(
                    title: "Check Metadata Cache Size",
                    subtitle: "Review image and metadata cache usage.",
                    systemImage: "archivebox"
                ) {
                    calculateCacheSize()
                }
                LibraryProfileActionRow(
                    title: "Refresh Infos",
                    subtitle: "Fetch latest TMDb metadata for every entry.",
                    systemImage: "arrow.clockwise"
                ) {
                    showRefreshInfoAlert = true
                }
                LibraryProfileActionRow(
                    title: "About AniShelf",
                    subtitle: "Version, links, and credits.",
                    systemImage: "info.circle"
                ) {
                    showAboutSheet = true
                }
                LibraryProfileActionRow(
                    title: "Delete All Animes",
                    subtitle: "Remove every saved library entry.",
                    systemImage: "trash",
                    role: .destructive,
                    tint: .red
                ) {
                    showClearAllAlert = true
                }
            }
        }
    }

    private var languagePickerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                LibraryProfileSettingIcon(systemImage: "globe", tint: .blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Anime Info Language")
                        .font(.subheadline.weight(.semibold))
                    Text("Choose the language used for future metadata fetches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Toggle("Follow System", isOn: $followsSystemLanguage)
                .font(.subheadline.weight(.semibold))

            if !followsSystemLanguage {
                Picker("Anime Info Language", selection: $preferredLanguage) {
                    ForEach(Language.allCases, id: \.rawValue) { language in
                        Text(language.localizedStringResource).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var backupManagementRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                LibraryProfileSettingIcon(
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    tint: .orange
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Backup & Restore")
                        .font(.subheadline.weight(.semibold))
                    Text("Export or restore your local library.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    exportButton
                    restoreButton
                }
                VStack(spacing: 10) {
                    exportButton
                    restoreButton
                }
            }
            .disabled(restoreCompleted)

            if restoreCompleted {
                Text("Restore completed! Restart app to see changes.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            Text("* For security reasons, your TMDb API Key will not be exported.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var exportButton: some View {
        LazyShareLink {
            do {
                let url = try store.backupManager.createBackup()
                return [url]
            } catch {
                presentExportError(error)
                return nil
            }
        } label: {
            Label("Export", systemImage: "document.badge.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private var restoreButton: some View {
        Button("Restore", systemImage: "document.badge.clock", role: .destructive) {
            restoreCompleted = false
            showFileImporter = true
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
    }

    private var effectiveLanguage: Language {
        followsSystemLanguage ? .current : preferredLanguage
    }

    private func resolvedLanguage(followsSystem: Bool, preferredLanguage: Language) -> Language {
        followsSystem ? .current : preferredLanguage
    }

    private var runtimeDescription: String {
        guard stats.runtimeMinutes > 0 else { return String(localized: "N/A") }
        let hours = stats.runtimeMinutes / 60
        let minutes = stats.runtimeMinutes % 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    private func calculateCacheSize() {
        KingfisherManager.shared.cache.calculateDiskStorageSize { result in
            DispatchQueue.main.async {
                cacheSizeResult = result
                showCacheAlert = true
            }
        }
    }

    private func processFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            restoreFileURL = url
            showRestoreConfirmation = true
        case .failure(let error):
            presentRestoreError(error)
        }
    }

    private func presentExportError(_ error: Error) {
        exportError = error
        showExportError = true
    }

    private func presentRestoreError(_ error: Error) {
        restoreError = error
        showRestoreError = true
    }

    private func restore() {
        restoreCompleted = false
        guard let url = restoreFileURL else { return }
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(
                    domain: .bundleIdentifier,
                    code: 1,
                    userInfo: [url.path(): "Access denied to URL"]
                )
            }
            defer { url.stopAccessingSecurityScopedResource() }
            try store.backupManager.restoreBackup(from: url)
            withAnimation {
                restoreCompleted = true
            }
        } catch {
            presentRestoreError(error)
        }
    }

    private var profileTitleResource: LocalizedStringResource {
        "AniShelf Library"
    }

    private var animeTitleResource: LocalizedStringResource {
        "Anime"
    }

    private var closeTitleResource: LocalizedStringResource {
        "Close"
    }
}

fileprivate struct LibraryProfileBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    let reduceMotion: Bool

    var body: some View {
        ZStack {
            backdropGradient
                .ignoresSafeArea()

            Circle()
                .fill(primaryOrbColor)
                .frame(width: 360, height: 360)
                .blur(radius: colorScheme == .dark ? 58 : 72)
                .offset(x: -145, y: -230)
                .blendMode(orbBlendMode)
                .opacity(reduceMotion ? primaryOrbReducedOpacity : primaryOrbOpacity)

            Circle()
                .fill(secondaryOrbColor)
                .frame(width: 330, height: 330)
                .blur(radius: colorScheme == .dark ? 62 : 74)
                .offset(x: 155, y: 35)
                .blendMode(orbBlendMode)
                .opacity(reduceMotion ? secondaryOrbReducedOpacity : secondaryOrbOpacity)

            Circle()
                .fill(tertiaryOrbColor)
                .frame(width: 380, height: 380)
                .blur(radius: colorScheme == .dark ? 66 : 78)
                .offset(x: -125, y: 320)
                .blendMode(orbBlendMode)
                .opacity(reduceMotion ? tertiaryOrbReducedOpacity : tertiaryOrbOpacity)

            Rectangle()
                .fill(backdropVeilColor)
                .ignoresSafeArea()
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var backdropGradient: LinearGradient {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.10, blue: 0.16),
                    Color(red: 0.17, green: 0.11, blue: 0.08),
                    Color(red: 0.06, green: 0.08, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 1.00),
                    Color(red: 1.00, green: 0.97, blue: 0.95),
                    Color(red: 0.96, green: 0.98, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var primaryOrbColor: Color {
        if colorScheme == .dark {
            .orange.opacity(0.58)
        } else {
            Color(red: 1.00, green: 0.71, blue: 0.47).opacity(0.36)
        }
    }

    private var secondaryOrbColor: Color {
        if colorScheme == .dark {
            .pink.opacity(0.48)
        } else {
            Color(red: 0.98, green: 0.60, blue: 0.76).opacity(0.30)
        }
    }

    private var tertiaryOrbColor: Color {
        if colorScheme == .dark {
            .cyan.opacity(0.40)
        } else {
            Color(red: 0.48, green: 0.82, blue: 1.00).opacity(0.26)
        }
    }

    private var primaryOrbOpacity: Double {
        colorScheme == .dark ? 0.90 : 0.84
    }

    private var secondaryOrbOpacity: Double {
        colorScheme == .dark ? 0.86 : 0.82
    }

    private var tertiaryOrbOpacity: Double {
        colorScheme == .dark ? 0.80 : 0.78
    }

    private var primaryOrbReducedOpacity: Double {
        colorScheme == .dark ? 0.58 : 0.56
    }

    private var secondaryOrbReducedOpacity: Double {
        colorScheme == .dark ? 0.54 : 0.52
    }

    private var tertiaryOrbReducedOpacity: Double {
        colorScheme == .dark ? 0.48 : 0.46
    }

    private var orbBlendMode: BlendMode {
        colorScheme == .dark ? .screen : .normal
    }

    private var backdropVeilColor: Color {
        colorScheme == .dark ? .black.opacity(0.16) : .white.opacity(0.18)
    }
}

fileprivate struct LibraryProfileMetricCard: View {
    let title: LocalizedStringResource
    let value: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: value)
                Spacer(minLength: 0)
            }
            Text("\(value)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .libraryProfileMetricPanel(cornerRadius: 24, tint: tint)
    }
}

fileprivate struct LibraryProfileDetailRow: View {
    let title: LocalizedStringResource
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            LibraryProfileSettingIcon(systemImage: systemImage, tint: .secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

fileprivate struct LibraryProfileActionRow: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let systemImage: String
    var role: ButtonRole? = nil
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                LibraryProfileSettingIcon(systemImage: systemImage, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(role == .destructive ? .red : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

fileprivate struct LibraryProfileSettingIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

fileprivate struct LibraryProfileRevealModifier: ViewModifier {
    let index: Int
    let appeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(reduceMotion || appeared ? 1 : 0.965)
            .offset(y: reduceMotion || appeared ? 0 : 18)
            .blur(radius: reduceMotion || appeared ? 0 : 10)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.44, dampingFraction: 0.86).delay(Double(index) * 0.055),
                value: appeared
            )
    }
}

extension View {
    fileprivate func profileReveal(index: Int, appeared: Bool, reduceMotion: Bool) -> some View {
        modifier(
            LibraryProfileRevealModifier(
                index: index,
                appeared: appeared,
                reduceMotion: reduceMotion
            )
        )
    }

    fileprivate func libraryProfileMetricPanel(cornerRadius: CGFloat, tint: Color) -> some View {
        modifier(LibraryProfileMetricPanelModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

fileprivate struct LibraryProfileMetricPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if colorScheme == .dark {
            content
                .background {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.12),
                                tint.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.stroke(.white.opacity(0.22), lineWidth: 1)
                }
        } else {
            content
                .background {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.20),
                                tint.opacity(0.11)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.stroke(tint.opacity(0.14), lineWidth: 1)
                }
        }
    }
}

#Preview {
    @Previewable let store = LibraryStore(dataProvider: .forPreview)

    LibraryProfileSettingsView(store: store)
        .onAppear {
            DataProvider.forPreview.generateEntriesForPreview()
        }
}
