//
//  TMDbImagePath.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/13.
//

import Foundation

public enum TMDbImagePath {
    private static let imageHost = "image.tmdb.org"
    private static let imagePathPrefix = ["t", "p"]

    public static func storagePath(from path: String?) -> String? {
        guard
            let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            return nil
        }

        if path.hasPrefix("/") {
            return path
        }

        return "/" + path
    }

    public static func storagePath(from url: URL?) -> String? {
        guard let url else { return nil }

        if let tmdbPath = storagePathFromTMDbImageURL(url) {
            return tmdbPath
        }

        if url.scheme == nil, url.host == nil {
            return storagePath(from: url.relativeString)
        }

        return nil
    }

    private static func storagePathFromTMDbImageURL(_ url: URL) -> String? {
        guard
            url.host?.caseInsensitiveCompare(imageHost) == .orderedSame
        else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 4 else { return nil }
        guard Array(components.prefix(2)) == imagePathPrefix else { return nil }

        let filePathComponents = components.dropFirst(3)
        guard !filePathComponents.isEmpty else { return nil }
        return "/" + filePathComponents.joined(separator: "/")
    }

    public static func urlPath(from path: String?) -> URL? {
        guard let path = storagePath(from: path) else { return nil }
        return URL(string: path)
    }
}
