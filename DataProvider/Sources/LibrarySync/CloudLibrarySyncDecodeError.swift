//
//  CloudLibrarySyncDecodeError.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import Foundation

/// Validation failures while decoding a CloudKit library sync record.
public enum CloudLibrarySyncDecodeError: Error, Equatable, Sendable {
    case wrongRecordType(actual: String)
    case unsupportedSchemaVersion(Int)
    case missingRequiredField(String)
    case invalidScalarValue(field: String)
    case invalidEnumValue(field: String)
    case invalidIdentityCombination(recordName: String)
    case corruptEpisodeProgressPayload
    case corruptSettingsPayload
}
