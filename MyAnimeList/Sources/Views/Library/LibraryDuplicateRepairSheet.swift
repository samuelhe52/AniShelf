//
//  LibraryDuplicateRepairSheet.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/29.
//

import DataProvider
import LibrarySync
import SwiftUI

struct LibraryDuplicateRepairSheet: View {
    let store: LibraryStore

    @State private var initialGroupCount: Int
    @State private var isShowingResolutionChoices = false
    @State private var isResolving = false
    @State private var resolutionError: String?

    init(store: LibraryStore) {
        self.store = store
        _initialGroupCount = State(initialValue: store.duplicateEntryGroups.count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let group = currentGroup {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            repairHeader(group: group)
                            duplicateEntries(group: group)
                        }
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                    }
                    .preferredNavigationBarScrollEdgeEffect()
                    .safeAreaInset(edge: .bottom) {
                        resolutionButton
                    }
                } else {
                    ProgressView()
                }
            }
            // .animation(.snappy(duration: 0.4), value: currentGroup?.id)
            .navigationTitle(LocalizedStringResource("Repair Library"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .confirmationDialog(
            LocalizedStringResource("Choose an Anime to Keep"),
            isPresented: $isShowingResolutionChoices,
            titleVisibility: .visible
        ) {
            if let group = currentGroup {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    Button(keepEntryResource(index + 1)) {
                        resolve(group: group, keeping: entry)
                    }
                }
            }
        } message: {
            Text(
                LocalizedStringResource(
                    "The other stored copies will be removed from this device."
                )
            )
        }
        .alert(
            LocalizedStringResource("Unable to Repair Library"),
            isPresented: Binding(
                get: { resolutionError != nil },
                set: { if !$0 { resolutionError = nil } }
            )
        ) {
            Button(LocalizedStringResource("OK")) {
                resolutionError = nil
            }
        } message: {
            if let resolutionError {
                Text(resolutionError)
            }
        }
    }

    private var currentGroup: LibraryDuplicateEntryGroup? {
        store.duplicateEntryGroups.first
    }

    private var resolutionButton: some View {
        Button {
            isShowingResolutionChoices = true
        } label: {
            HStack {
                if isResolving {
                    ProgressView()
                }
                Text(isResolving ? resolvingResource : resolveResource)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isResolving || currentGroup == nil)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func repairHeader(group: LibraryDuplicateEntryGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(LocalizedStringResource("Duplicate Anime Found"))
                .font(.largeTitle.bold())

            Text(
                LocalizedStringResource(
                    "AniShelf found multiple stored copies of the same anime. Review them and choose the copy you want to keep before continuing."
                )
            )
            .font(.title3)
            .foregroundStyle(.secondary)

            Text(groupProgressResource)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(group.recommendedEntry.displayName)
                .font(.headline)
        }
    }

    private func duplicateEntries(group: LibraryDuplicateEntryGroup) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                duplicateEntryRow(
                    entry,
                    number: index + 1,
                    isRecommended: entry === group.recommendedEntry
                )
            }
        }
    }

    private func duplicateEntryRow(
        _ entry: AnimeEntry,
        number: Int,
        isRecommended: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("#\(number)")
                    .font(.subheadline.monospacedDigit().bold())

                if isRecommended {
                    Text(LocalizedStringResource("Recommended"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 8)

                Text(lastChangedResource(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AnimeEntryListRow(
                entry: entry,
                tapGesturesEnabled: false,
                favoriteButtonEnabled: false
            )
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func resolve(group: LibraryDuplicateEntryGroup, keeping entry: AnimeEntry) {
        guard !isResolving else { return }
        isResolving = true
        Task { @MainActor in
            defer { isResolving = false }
            do {
                try await store.resolveDuplicateEntryGroup(group.identity, keeping: entry)
            } catch {
                resolutionError = error.localizedDescription
            }
        }
    }

    private var groupProgressResource: LocalizedStringResource {
        let remainingCount = store.duplicateEntryGroups.count
        let totalCount = max(initialGroupCount, remainingCount)
        let currentNumber = max(1, totalCount - remainingCount + 1)
        return "Duplicate anime \(currentNumber) of \(totalCount)"
    }

    private func lastChangedResource(for entry: AnimeEntry) -> LocalizedStringResource {
        let snapshot = LibraryEntrySyncSnapshot(entry: entry)
        let date = snapshot.latestUserStateClock ?? entry.dateSaved
        return "Last changed \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func keepEntryResource(_ number: Int) -> LocalizedStringResource {
        "Keep #\(number)"
    }

    private var resolveResource: LocalizedStringResource { "Resolve…" }
    private var resolvingResource: LocalizedStringResource { "Repairing…" }
}
