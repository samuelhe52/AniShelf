//
//  ScreenSaverSnapshotReader.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import Foundation
import ImageIO

public struct ScreenSaverSnapshotReader: Sendable {
    public static let manifestFilename = "manifest.json"
    public static let imagesDirectoryName = "images"
    public static let snapshotDirectoryName = "AniShelf Screen Saver"

    public enum Snapshot: Equatable, Sendable {
        case ready(ScreenSaverManifest)
        case empty
        case requiresUpdate

        func isSamePublication(as other: Self) -> Bool {
            switch (self, other) {
            case (.empty, .empty), (.requiresUpdate, .requiresUpdate):
                return true
            case (.ready(let first), .ready(let second)):
                return first.generation == second.generation
            default:
                return false
            }
        }
    }

    public let directory: URL
    /// The reading saver's own build ID; nil skips the build check.
    public let build: String?

    public init(directory: URL, build: String? = nil) {
        self.directory = directory
        self.build = build
    }

    public static func snapshotDirectory(in userHome: URL) -> URL {
        userHome.appending(component: "Pictures", directoryHint: .isDirectory)
            .appending(component: snapshotDirectoryName, directoryHint: .isDirectory)
    }

    public func read() -> Snapshot {
        struct Header: Decodable {
            let schemaVersion: Int
            let saverBuild: String?
        }

        let url = directory.appending(component: Self.manifestFilename, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: url) else { return .empty }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: data) else { return .empty }
        if header.schemaVersion > ScreenSaverManifest.currentSchemaVersion { return .requiresUpdate }
        // AniShelf embeds a different saver than the one installed: ask for a reinstall rather than
        // keep drawing with old code.
        if let expected = header.saverBuild, let build, expected != build {
            return .requiresUpdate
        }
        guard header.schemaVersion == ScreenSaverManifest.currentSchemaVersion,
            let manifest = try? decoder.decode(ScreenSaverManifest.self, from: data),
            !manifest.entries.isEmpty
        else { return .empty }
        return .ready(manifest)
    }

    package func image(at relativePath: String, maximumPixelSize: Int) -> CGImage? {
        let path = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 2, path[0] == Self.imagesDirectoryName,
            !path[1].isEmpty, path[1] != ".", path[1] != ".."
        else { return nil }

        let images = directory.resolvingSymlinksInPath()
            .appending(component: Self.imagesDirectoryName, directoryHint: .isDirectory)
        let url = images.appending(component: String(path[1]), directoryHint: .notDirectory)
        guard url.resolvingSymlinksInPath().path == url.path,
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
            let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
