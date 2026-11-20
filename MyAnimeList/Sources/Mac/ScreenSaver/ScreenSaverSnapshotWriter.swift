//
//  ScreenSaverSnapshotWriter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

#if os(macOS)
    import Foundation
    import OSLog
    import ScreenSaverKit

    actor ScreenSaverSnapshotWriter {
        private let directory: URL

        init(directory: URL) {
            self.directory = directory
        }

        private var manifestURL: URL {
            directory.appending(component: ScreenSaverSnapshotReader.manifestFilename, directoryHint: .notDirectory)
        }

        private var imagesURL: URL {
            directory.appending(component: ScreenSaverSnapshotReader.imagesDirectoryName, directoryHint: .isDirectory)
        }

        func readManifest() -> ScreenSaverManifest? {
            guard let data = try? Data(contentsOf: manifestURL) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let manifest = try? decoder.decode(ScreenSaverManifest.self, from: data),
                manifest.schemaVersion == ScreenSaverManifest.currentSchemaVersion
            else { return nil }
            return manifest
        }

        func hasManifest() -> Bool {
            FileManager.default.fileExists(atPath: manifestURL.path())
        }

        func existingImage(named filename: String) -> ScreenSaverImageExporter.Image? {
            let file = imagesURL.appending(component: filename, directoryHint: .notDirectory)
            guard Self.isImageFilename(filename),
                (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                (try? imagesURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                Self.isRegularFile(file)
            else { return nil }
            return ScreenSaverImageExporter.Image.read(from: file)
        }

        func publish(_ manifest: ScreenSaverManifest, stagedImages: URL? = nil) throws {
            try Task.checkCancellation()
            let previous = readManifest()
            let mayPrune = previous != nil || !hasManifest()
            let referenced = try Self.imageFilenames(in: manifest)
            let fileManager = FileManager.default
            for folder in [directory, imagesURL]
            where (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)

            var added: [URL] = []
            do {
                for name in referenced {
                    try Task.checkCancellation()
                    let destination = imagesURL.appending(component: name, directoryHint: .notDirectory)
                    let exists = Self.isRegularFile(destination)
                    if !exists,
                        fileManager.fileExists(atPath: destination.path())
                            || (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
                    {
                        throw CocoaError(.fileWriteInvalidFileName)
                    }
                    let source = stagedImages?.appending(component: name, directoryHint: .notDirectory)
                    if let source, Self.isRegularFile(source) {
                        let data = try Data(contentsOf: source, options: .mappedIfSafe)
                        try data.write(to: destination, options: .atomic)
                        if !exists { added.append(destination) }
                    } else if !exists {
                        throw CocoaError(.fileReadNoSuchFile)
                    }
                }

                try Task.checkCancellation()
                try manifest.encoded().write(to: manifestURL, options: .atomic)
            } catch {
                for file in added { try? fileManager.removeItem(at: file) }
                throw error
            }

            if mayPrune {
                let previousFiles = previous.flatMap { try? Self.imageFilenames(in: $0) } ?? []
                prune(keeping: referenced.union(previousFiles))
            }
        }

        private func prune(keeping filenames: Set<String>) {
            let fileManager = FileManager.default
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: imagesURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                for file in contents {
                    let name = file.lastPathComponent
                    guard Self.isImageFilename(name), !filenames.contains(name),
                        (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                    else { continue }
                    try fileManager.removeItem(at: file)
                }
            } catch {
                Logger(subsystem: .bundleIdentifier, category: "ScreenSaver").error(
                    "Could not prune screen saver assets: \(error.localizedDescription, privacy: .private)"
                )
            }
        }

        private static func imageFilenames(in manifest: ScreenSaverManifest) throws -> Set<String> {
            let prefix = ScreenSaverSnapshotReader.imagesDirectoryName + "/"
            let paths = manifest.entries.flatMap { [$0.poster, $0.backdrop, $0.logo].compactMap(\.self) }
            return try Set(
                paths.map { path in
                    let name = String(path.dropFirst(prefix.count))
                    guard path.hasPrefix(prefix), isImageFilename(name) else {
                        throw CocoaError(.fileWriteInvalidFileName)
                    }
                    return name
                })
        }

        private static func isRegularFile(_ url: URL) -> Bool {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
                return false
            }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }

        private static func isImageFilename(_ name: String) -> Bool {
            let parts = name.split(separator: ".", omittingEmptySubsequences: false)
            return parts.count == 2 && (parts[1] == "heic" || parts[1] == "png")
                && parts[0].utf8.count == 64
                && parts[0].utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }
#endif
