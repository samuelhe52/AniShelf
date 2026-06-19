//
//  DataProvider+StartupRecovery.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/19.
//

import Foundation
import SwiftData
import os

public struct PersistentStoreRecoveryFile: Codable, Equatable, Sendable {
    public let name: String
    public let size: Int64
}

public struct PersistentStoreRecoveryManifest: Codable, Equatable, Sendable {
    public let recoveredAt: Date
    public let errorDescription: String
    public let appVersion: String
    public let appBuild: String
    public let operatingSystem: String
    public let files: [PersistentStoreRecoveryFile]
}

public struct PersistentStoreRecovery: Equatable, Sendable {
    public let recoveredAt: Date
    public let recoveryDirectoryURL: URL
    public let manifestURL: URL
    public let files: [PersistentStoreRecoveryFile]
}

@MainActor
public struct DataProviderBootstrapResult {
    public let provider: DataProvider
    public let recovery: PersistentStoreRecovery?
}

extension DataProvider {
    private static let recoveryAcknowledgementFileName = ".pending-acknowledgement"

    typealias ModelContainerFactory = (_ inMemory: Bool, _ url: URL) throws -> ModelContainer

    public static func bootstrap(url: URL = persistenStoreURL) -> DataProviderBootstrapResult {
        bootstrap(
            url: url,
            fileManager: .default,
            now: Date(),
            containerFactory: createModelContainer(inMemory:url:)
        )
    }

    static func bootstrap(
        url: URL,
        fileManager: FileManager,
        now: Date,
        containerFactory: ModelContainerFactory
    ) -> DataProviderBootstrapResult {
        do {
            let container = try containerFactory(false, url)
            return DataProviderBootstrapResult(
                provider: DataProvider(container: container, inMemory: false, url: url),
                recovery: pendingPersistentStoreRecovery(at: url, fileManager: fileManager)
            )
        } catch {
            logContainerCreationFailure(error, url: url, operation: "create")
            do {
                let recovery = try quarantinePersistentStore(
                    at: url,
                    error: error,
                    now: now,
                    fileManager: fileManager
                )
                let replacementContainer = try containerFactory(false, url)
                return DataProviderBootstrapResult(
                    provider: DataProvider(
                        container: replacementContainer,
                        inMemory: false,
                        url: url
                    ),
                    recovery: recovery
                )
            } catch let recoveryError {
                dataProviderLogger.critical(
                    "Failed to recover SwiftData store: \(String(describing: recoveryError), privacy: .public)"
                )
                fatalError(
                    "Could not preserve failed ModelContainer and create a replacement: \(recoveryError)"
                )
            }
        }
    }

    static func quarantinePersistentStore(
        at storeURL: URL,
        error: Error,
        now: Date,
        fileManager: FileManager
    ) throws -> PersistentStoreRecovery {
        let storeDirectoryURL = storeURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: storeDirectoryURL,
            withIntermediateDirectories: true
        )

        let recoveryRootURL = storeDirectoryURL.appendingPathComponent(
            "Recovery",
            isDirectory: true
        )
        let recoveryDirectoryURL = recoveryRootURL.appendingPathComponent(
            recoveryDirectoryName(for: now),
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: recoveryDirectoryURL,
            withIntermediateDirectories: true
        )

        let storeName = storeURL.lastPathComponent
        let storeArtifacts = try fileManager.contentsOfDirectory(
            at: storeDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            let name = url.lastPathComponent
            return name == storeName || name.hasPrefix("\(storeName)-")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var files: [PersistentStoreRecoveryFile] = []
        for sourceURL in storeArtifacts {
            let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
            let destinationURL = recoveryDirectoryURL.appendingPathComponent(
                sourceURL.lastPathComponent
            )
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            files.append(
                PersistentStoreRecoveryFile(
                    name: sourceURL.lastPathComponent,
                    size: Int64(values.fileSize ?? 0)
                )
            )
        }

        let manifest = PersistentStoreRecoveryManifest(
            recoveredAt: now,
            errorDescription: String(describing: error),
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            appBuild: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            files: files
        )
        let manifestURL = recoveryDirectoryURL.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: [.atomic])
        try Data().write(
            to: recoveryDirectoryURL.appendingPathComponent(
                recoveryAcknowledgementFileName
            ),
            options: [.atomic]
        )

        for sourceURL in storeArtifacts {
            try fileManager.removeItem(at: sourceURL)
        }

        return PersistentStoreRecovery(
            recoveredAt: now,
            recoveryDirectoryURL: recoveryDirectoryURL,
            manifestURL: manifestURL,
            files: files
        )
    }

    public static func acknowledgePersistentStoreRecovery(
        _ recovery: PersistentStoreRecovery
    ) {
        do {
            try FileManager.default.removeItem(
                at: recovery.recoveryDirectoryURL.appendingPathComponent(
                    recoveryAcknowledgementFileName
                )
            )
        } catch {
            dataProviderLogger.error(
                "Failed to acknowledge persistent store recovery: \(String(describing: error), privacy: .public)"
            )
        }
    }

    static func pendingPersistentStoreRecovery(
        at storeURL: URL,
        fileManager: FileManager
    ) -> PersistentStoreRecovery? {
        let recoveryRootURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("Recovery", isDirectory: true)
        guard
            let recoveryDirectories = try? fileManager.contentsOfDirectory(
                at: recoveryRootURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for directoryURL in recoveryDirectories.sorted(
            by: { $0.lastPathComponent > $1.lastPathComponent }
        ) {
            let acknowledgementURL = directoryURL.appendingPathComponent(
                recoveryAcknowledgementFileName
            )
            guard fileManager.fileExists(atPath: acknowledgementURL.path()) else {
                continue
            }

            let manifestURL = directoryURL.appendingPathComponent("manifest.json")
            guard
                let data = try? Data(contentsOf: manifestURL),
                let manifest = try? decoder.decode(
                    PersistentStoreRecoveryManifest.self,
                    from: data
                )
            else {
                continue
            }
            return PersistentStoreRecovery(
                recoveredAt: manifest.recoveredAt,
                recoveryDirectoryURL: directoryURL,
                manifestURL: manifestURL,
                files: manifest.files
            )
        }
        return nil
    }

    private static func recoveryDirectoryName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "\(formatter.string(from: date))-\(UUID().uuidString.lowercased())"
    }
}
