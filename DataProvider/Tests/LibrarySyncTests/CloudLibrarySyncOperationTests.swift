//
//  CloudLibrarySyncOperationTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/10/3.
//

import CloudKit
import Foundation
import Testing

@testable import LibrarySync

struct CloudLibrarySyncOperationTests {
    @Test func timeoutReleasesWaiterWithoutCloudKitCallback() async throws {
        let operation = CKFetchRecordZonesOperation(recordZoneIDs: [])
        let pending = CloudLibrarySyncOperation(operation)
        do {
            try await pending.run(timeout: 0.01, start: {})
            Issue.record("A stalled operation should time out")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        }
        #expect(operation.isCancelled)
        // A framework callback after the deadline must be harmless.
        pending.finish(.success(()))
    }

    @Test func cancellationReleasesWaiterWithoutCloudKitCallback() async throws {
        let operation = CKFetchRecordZonesOperation(recordZoneIDs: [])
        let pending = CloudLibrarySyncOperation(operation)
        let (started, signal) = AsyncStream<Void>.makeStream()
        let task = Task {
            try await pending.run {
                signal.yield(())
                signal.finish()
            }
        }
        for await _ in started { break }
        task.cancel()
        do {
            try await task.value
            Issue.record("A canceled operation should throw")
        } catch is CancellationError {}
        #expect(operation.isCancelled)
        pending.finish(.failure(CKError(.networkFailure)))
    }

    @Test func completedOperationPreservesResultWithoutCanceling() async throws {
        let operation = CKFetchRecordZonesOperation(recordZoneIDs: [])
        let pending = CloudLibrarySyncOperation(operation)
        try await pending.run {
            pending.finish(.success(()))
        }
        #expect(!operation.isCancelled)
    }
}
