//
//  ScreenSaverManifest.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import Foundation

public struct ScreenSaverManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public enum Layout: String, Codable, CaseIterable, Sendable {
        case coverWall
        case posterFocus
        case heroStill
    }

    public struct Settings: Codable, Equatable, Sendable {
        public let layout: Layout
        public let showsTitles: Bool
        public let interval: TimeInterval

        public init(layout: Layout, showsTitles: Bool, interval: TimeInterval) {
            self.layout = layout
            self.showsTitles = showsTitles
            self.interval = interval
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public struct PixelSize: Codable, Equatable, Sendable {
            public let width: Int
            public let height: Int

            public init(width: Int, height: Int) {
                self.width = width
                self.height = height
            }
        }

        public let id: String
        public let title: String?
        public let subtitle: String?
        public let meta: String?
        public let poster: String
        public let posterPixelSize: PixelSize
        public let backdrop: String?
        public let logo: String?

        public init(
            id: String,
            title: String? = nil,
            subtitle: String? = nil,
            meta: String? = nil,
            poster: String,
            posterPixelSize: PixelSize,
            backdrop: String? = nil,
            logo: String? = nil
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.meta = meta
            self.poster = poster
            self.posterPixelSize = posterPixelSize
            self.backdrop = backdrop
            self.logo = logo
        }
    }

    public let schemaVersion: Int
    public let generation: UUID
    public let createdAt: Date
    public let settings: Settings
    public let entries: [Entry]

    public init(generation: UUID = UUID(), createdAt: Date = .now, settings: Settings, entries: [Entry]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generation = generation
        // The snapshot wire format uses UTC ISO 8601 dates with second precision.
        self.createdAt = Date(timeIntervalSince1970: floor(createdAt.timeIntervalSince1970))
        self.settings = settings
        self.entries = entries
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
