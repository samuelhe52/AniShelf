//
//  LabStartup.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

#if ANISHELF_LAB
    import DataProvider
    import Foundation
    import SwiftUI

    /// AniShelf Lab (docs-ai 043) starts every launch from the copy of the live library that
    /// `scripts/lab.py` leaves in `tmp/AniShelfLab/Snapshot`, and forgets what earlier runs wrote.
    @MainActor
    enum LabStartup {
        private(set) static var failure: String?

        static func bootstrap() -> DataProviderBootstrapResult {
            // lab.py launches Lab once with this, so macOS creates Lab's sandbox to copy into.
            if ProcessInfo.processInfo.arguments.contains("--lab-create-container") { exit(0) }
            do {
                return try openSnapshot()
            } catch {
                failure = error.localizedDescription
                return DataProvider.inMemoryFixtureBootstrap()
            }
        }

        private static func openSnapshot() throws -> DataProviderBootstrapResult {
            let fileManager = FileManager.default
            let root = fileManager.temporaryDirectory.appending(path: "AniShelfLab")
            let snapshot = root.appending(path: "Snapshot")
            let working = root.appending(path: "Working")
            guard fileManager.fileExists(atPath: snapshot.appending(path: "mal.store").path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "No library snapshot."])
            }

            try? fileManager.removeItem(at: working)
            try? fileManager.removeItem(at: .applicationSupportDirectory)
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
            try fileManager.moveItem(at: snapshot, to: working)

            let preferences = NSDictionary(contentsOf: working.appending(path: "Preferences.plist"))
            for key in String.allPreferenceKeys {
                UserDefaults.standard.set(preferences?[key], forKey: key)
            }
            return DataProvider.bootstrap(url: working.appending(path: "mal.store"))
        }
    }

    struct LabStartupFailureView: View {
        var body: some View {
            if let failure = LabStartup.failure {
                ContentUnavailableView {
                    Label {
                        Text(verbatim: "Couldn’t Open AniShelf Lab")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                } description: {
                    Text(verbatim: "\(failure)\nQuit Lab and open it with make run-lab.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
        }
    }
#endif
