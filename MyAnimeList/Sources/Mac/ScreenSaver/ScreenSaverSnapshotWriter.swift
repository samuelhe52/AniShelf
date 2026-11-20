//
//  ScreenSaverSnapshotWriter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

#if os(macOS)
    import Foundation
    import ScreenSaverKit

    actor ScreenSaverSnapshotWriter {
        private let directory: URL
        private var lastCompletedFiles: Set<String>?

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
                (1...ScreenSaverManifest.currentSchemaVersion).contains(manifest.schemaVersion),
                manifest.rendererVersion ?? 1 <= ScreenSaverManifest.currentRendererVersion
            else { return nil }
            return manifest
        }

        func hasManifest() -> Bool {
            FileManager.default.fileExists(atPath: manifestURL.path())
        }

        func existingImage(named filename: String) throws -> ScreenSaverImageExporter.Image? {
            try validateDirectories()
            let file = try imageURL(named: filename)
            guard Self.isRegularFile(file) else { return nil }
            return ScreenSaverImageExporter.Image.read(from: file)
        }

        func store(_ encoded: ScreenSaverImageExporter.EncodedImage) throws {
            try Task.checkCancellation()
            try validateDirectories()
            let destination = try imageURL(named: encoded.image.filename)
            let properties = try? destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if properties?.isSymbolicLink == true
                || (FileManager.default.fileExists(atPath: destination.path()) && properties?.isRegularFile != true)
            {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
            try encoded.data.write(to: destination, options: .atomic)
        }

        /// Partial manifests leave the image cache alone. A completed update retains the previous
        /// completed snapshot for a renderer that is still displaying it.
        func publish(
            _ manifest: ScreenSaverManifest, complete: Bool = false, keeping extraFiles: Set<String> = []
        ) throws -> ScreenSaverManifest {
            try Task.checkCancellation()
            try validateDirectories()
            let previous = readManifest()
            let hasManifest = hasManifest()
            let referenced = try Self.imageFilenames(in: manifest)
            let previousFiles = previous.flatMap { try? Self.imageFilenames(in: $0) } ?? []
            let mayPrune = previous != nil || !hasManifest
            if lastCompletedFiles == nil, mayPrune { lastCompletedFiles = previousFiles }

            let unchanged =
                previous?.schemaVersion == manifest.schemaVersion
                && previous?.rendererVersion == manifest.rendererVersion
                && previous?.settings == manifest.settings && previous?.entries == manifest.entries
                // A new AniShelf build must restamp the snapshot so an old installed saver notices.
                && previous?.saverBuild == manifest.saverBuild
            if !unchanged {
                for name in referenced.subtracting(previousFiles) {
                    guard Self.isRegularFile(try imageURL(named: name)) else { throw CocoaError(.fileReadNoSuchFile) }
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try manifest.encoded().write(to: manifestURL, options: .atomic)
            }

            if complete, mayPrune {
                try prune(keeping: referenced.union(previousFiles).union(lastCompletedFiles ?? []).union(extraFiles))
                lastCompletedFiles = referenced
            }
            return unchanged ? previous ?? manifest : manifest
        }

        func removeArtwork(settings: ScreenSaverManifest.Settings) throws {
            try Task.checkCancellation()
            try validateDirectories()
            if hasManifest() {
                _ = try publish(.init(settings: settings, entries: []))
            }
            try prune(keeping: [])
            lastCompletedFiles = []
        }

        private func validateDirectories() throws {
            for folder in [directory, imagesURL]
            where (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw CocoaError(.fileWriteInvalidFileName)
            }
        }

        private func imageURL(named filename: String) throws -> URL {
            guard Self.isImageFilename(filename) else { throw CocoaError(.fileWriteInvalidFileName) }
            return imagesURL.appending(component: filename, directoryHint: .notDirectory)
        }

        private func prune(keeping filenames: Set<String>) throws {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: imagesURL.path()) else { return }
            let contents = try fileManager.contentsOfDirectory(
                at: imagesURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            for file in contents {
                let name = file.lastPathComponent
                guard Self.isImageFilename(name), !filenames.contains(name), Self.isRegularFile(file)
                else { continue }
                try fileManager.removeItem(at: file)
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
