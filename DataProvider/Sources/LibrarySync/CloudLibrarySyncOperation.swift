//
//  CloudLibrarySyncOperation.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/10/3.
//

import CloudKit
import Foundation

/// Bounds preparation even when CloudKit is waiting for authentication and its
/// network request timeout has not started. Late callbacks cannot resume twice.
final class CloudLibrarySyncOperation: @unchecked Sendable {
    private let operation: CKDatabaseOperation
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var result: Result<Void, any Error>?
    private var deadline: DispatchWorkItem?

    init(_ operation: CKDatabaseOperation) {
        self.operation = operation
    }

    func run(timeout: TimeInterval = 60, start: @Sendable () -> Void) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                    return
                }
                self.continuation = continuation
                let deadline = DispatchWorkItem { [weak self] in
                    self?.finish(.failure(URLError(.timedOut)), cancelOperation: true)
                }
                self.deadline = deadline
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                lock.unlock()
                start()
            }
        } onCancel: {
            self.finish(.failure(CancellationError()), cancelOperation: true)
        }
    }

    func finish(_ result: Result<Void, any Error>, cancelOperation: Bool = false) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        let deadline = self.deadline
        self.deadline = nil
        lock.unlock()

        deadline?.cancel()
        if cancelOperation { operation.cancel() }
        continuation?.resume(with: result)
    }
}
