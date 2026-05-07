//
//  TMDbAPIKeyEntryController.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/7.
//

import Foundation
import SwiftUI

enum TMDbAPIKeyCheckStatus {
    case checking
    case valid
    case invalid
}

@Observable @MainActor
final class TMDbAPIKeyEntryController {
    var apiKeyInput: String = "" {
        didSet {
            guard apiKeyInput != oldValue else { return }
            validationTask?.cancel()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                status = nil
            }
        }
    }
    var status: TMDbAPIKeyCheckStatus?

    @ObservationIgnored private var validationTask: Task<Void, Never>?

    var checking: Bool { status == .checking }

    var isFieldEmpty: Bool {
        apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadCurrentKey(from keyStorage: TMDbAPIKeyStorage) {
        apiKeyInput = keyStorage.key ?? ""
    }

    func validate(using keyStorage: TMDbAPIKeyStorage) {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !checking else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            status = .checking
        }
        validationTask?.cancel()
        validationTask = Task {
            await checkKey(trimmedKey, using: keyStorage)
        }
    }

    @discardableResult
    func checkKey(_ key: String, using keyStorage: TMDbAPIKeyStorage) async -> Bool {
        let result = await TMDbAPIKeyValidator.check(key)
        guard isCurrentValidation(for: key) else { return false }
        guard result else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                status = .invalid
            }
            validationTask = nil
            return false
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            status = .valid
        }
        await saveKeyAfterFeedback(key, using: keyStorage)
        return true
    }

    private func saveKeyAfterFeedback(_ key: String, using keyStorage: TMDbAPIKeyStorage) async {
        try? await Task.sleep(for: .milliseconds(500))
        guard isCurrentValidation(for: key) else { return }

        let result = keyStorage.saveKey(key)
        validationTask = nil
        if result {
            NotificationCenter.default.post(
                name: .tmdbAPIConfigurationDidChange,
                object: nil
            )
        }
    }

    private func isCurrentValidation(for key: String) -> Bool {
        !Task.isCancelled && apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines) == key
    }
}

struct TMDbAPIKeyValidator {
    static func check(_ key: String) async -> Bool {
        guard !key.isEmpty else { return false }
        let hosts = [
            "api.themoviedb.org",
            "tmdb-api.konakona52.com"
        ]

        return await withTaskGroup(of: Bool.self) { group in
            for host in hosts {
                group.addTask {
                    await check(key, host: host)
                }
            }

            while let isValid = await group.next() {
                if isValid {
                    group.cancelAll()
                    return true
                }
            }

            return false
        }
    }

    private static func check(_ key: String, host: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/3/configuration"
        components.queryItems = [URLQueryItem(name: "api_key", value: key)]

        guard let url = components.url else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
}
