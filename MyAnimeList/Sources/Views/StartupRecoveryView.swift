//
//  StartupRecoveryView.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/19.
//

import DataProvider
import SwiftUI

struct StartupRecoveryView: View {
    let recovery: PersistentStoreRecovery
    let onContinue: () -> Void

    @Environment(\.windowSceneIdentifier) private var windowSceneIdentifier
    @State private var preparingExport: StartupRecoveryExportKind?
    @State private var exportError: LocalizedStringResource?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.16),
                    Color.platformSystemBackground,
                    Color.yellow.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    recoveryHeader
                    explanation
                    exportActions
                    continueButton
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
        }
        .interactiveDismissDisabled()
        .alert(
            "Unable to Prepare Export",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            ),
            actions: {
                Button("OK") {
                    exportError = nil
                }
            },
            message: {
                if let exportError {
                    Text(exportError)
                }
            }
        )
    }

    private var recoveryHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Library Recovery Required")
                .font(.largeTitle.bold())

            Text(
                "AniShelf was unable to open your database because it is corrupted or unreadable."
            )
            .font(.title3)
            .foregroundStyle(.secondary)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            recoveryPoint(
                icon: "archivebox",
                title: "Your original files were preserved",
                detail: "AniShelf quarantined the unreadable database files instead of deleting them."
            )
            recoveryPoint(
                icon: "sparkles",
                title: "A clean library was created",
                detail:
                    "The replacement library is empty. A backup from an earlier build or iCloud Sync may help recover your data."
            )
            recoveryPoint(
                icon: "envelope",
                title: "Developer assistance",
                detail:
                    "Contact samuelhe52@outlook.com and attach an export below if you want the developer to investigate."
            )
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var exportActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optional Exports")
                .font(.headline)
            Text(
                "Nothing is uploaded automatically. An export is prepared only when you choose an action."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            ForEach(StartupRecoveryPresentation.availableExports, id: \.self) { kind in
                exportButton(kind: kind)
            }
        }
    }

    private var continueButton: some View {
        Button {
            RecoveryExportManager.cleanupTemporaryExports(for: recovery)
            onContinue()
        } label: {
            Text("Continue with Empty Library")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(preparingExport != nil)
        .animation(.default, value: preparingExport)
    }

    private func recoveryPoint(
        icon: String,
        title: LocalizedStringResource,
        detail: LocalizedStringResource
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exportButton(kind: StartupRecoveryExportKind) -> some View {
        Button {
            prepareExport(kind)
        } label: {
            HStack {
                Label {
                    Text(kind.title)
                } icon: {
                    Image(systemName: kind.icon)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(preparingExport != nil)
        .animation(.default, value: preparingExport)
    }

    private func prepareExport(_ kind: StartupRecoveryExportKind) {
        preparingExport = kind
        // Capture the invoking window before the await; focus may move while the export prepares.
        let sceneIdentifier = windowSceneIdentifier
        Task {
            do {
                let exportURL = try await Task.detached(priority: .userInitiated) {
                    try RecoveryExportManager.prepareExport(kind, for: recovery)
                }.value
                ShareSheetPresenter.present(items: [exportURL], sceneIdentifier: sceneIdentifier)
            } catch {
                exportError = "AniShelf could not prepare this export. Please try again."
            }
            preparingExport = nil
        }
    }
}

extension StartupRecoveryExportKind {
    fileprivate var title: LocalizedStringResource {
        switch self {
        case .diagnostic:
            "Export Diagnostic"
        case .recoveryBundle:
            "Export Recovery Bundle"
        }
    }

    fileprivate var icon: String {
        switch self {
        case .diagnostic:
            "doc.text"
        case .recoveryBundle:
            "archivebox"
        }
    }
}
