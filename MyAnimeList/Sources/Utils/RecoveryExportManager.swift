//
//  RecoveryExportManager.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/19.
//

import DataProvider
import Foundation
import ZIPFoundation

enum StartupRecoveryExportKind: CaseIterable, Hashable, Sendable {
    case diagnostic
    case recoveryBundle
}

enum StartupRecoveryPresentation {
    static let availableExports = StartupRecoveryExportKind.allCases
}

enum RecoveryExportManager {
    private static let temporaryExportRootName = "AniShelf-Recovery-Exports"

    static func prepareExport(
        _ kind: StartupRecoveryExportKind,
        for recovery: PersistentStoreRecovery,
        fileManager: FileManager = .default
    ) throws -> URL {
        let exportDirectoryURL = temporaryExportDirectory(
            for: recovery,
            fileManager: fileManager
        )
        try fileManager.createDirectory(
            at: exportDirectoryURL,
            withIntermediateDirectories: true
        )

        switch kind {
        case .diagnostic:
            let exportURL = exportDirectoryURL.appendingPathComponent(
                "AniShelf-Recovery-Diagnostic.json"
            )
            try replaceItemIfNeeded(at: exportURL, fileManager: fileManager)
            try fileManager.copyItem(at: recovery.manifestURL, to: exportURL)
            return exportURL
        case .recoveryBundle:
            let exportURL = exportDirectoryURL.appendingPathComponent(
                "AniShelf-Recovery-Bundle.zip"
            )
            try replaceItemIfNeeded(at: exportURL, fileManager: fileManager)
            try fileManager.zipItem(
                at: recovery.recoveryDirectoryURL,
                to: exportURL,
                shouldKeepParent: true,
                compressionMethod: .deflate
            )
            return exportURL
        }
    }

    static func cleanupTemporaryExports(
        for recovery: PersistentStoreRecovery,
        fileManager: FileManager = .default
    ) {
        try? fileManager.removeItem(
            at: temporaryExportDirectory(for: recovery, fileManager: fileManager)
        )
    }

    static func cleanupAllTemporaryExports(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: temporaryExportRoot(fileManager: fileManager))
    }

    private static func temporaryExportDirectory(
        for recovery: PersistentStoreRecovery,
        fileManager: FileManager
    ) -> URL {
        temporaryExportRoot(fileManager: fileManager)
            .appendingPathComponent(
                recovery.recoveryDirectoryURL.lastPathComponent,
                isDirectory: true
            )
    }

    private static func temporaryExportRoot(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory.appendingPathComponent(
            temporaryExportRootName,
            isDirectory: true
        )
    }

    private static func replaceItemIfNeeded(at url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path()) {
            try fileManager.removeItem(at: url)
        }
    }
}
