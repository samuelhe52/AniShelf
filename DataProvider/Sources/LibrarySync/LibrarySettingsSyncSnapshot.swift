//
//  LibrarySettingsSyncSnapshot.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/5.
//

import Foundation

/// Cloud-synced user-defaults snapshot stored alongside library records.
public struct LibrarySettingsSyncSnapshot: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var updatedAt: Date
    public var payload: [String: Value]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        updatedAt: Date,
        payload: [String: Value]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

extension LibrarySettingsSyncSnapshot {
    public enum Value: Equatable, Sendable {
        case bool(Bool)
        case string(String)
        case stringArray([String])
    }
}

extension LibrarySettingsSyncSnapshot.Value: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([String].self) {
            self = .stringArray(value)
            return
        }
        throw DecodingError.typeMismatch(
            Self.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported library settings value.")
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .stringArray(let value):
            try container.encode(value)
        }
    }
}

/// Mixed CloudKit zone payload for AniShelf library sync.
public enum CloudLibrarySyncZoneRecordChange: Equatable, Sendable {
    case entry(LibraryEntrySyncRemoteChange)
    case settings(LibrarySettingsSyncSnapshot)
}
