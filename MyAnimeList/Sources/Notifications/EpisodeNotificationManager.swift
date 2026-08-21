//
//  EpisodeNotificationManager.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/21.
//

import DataProvider
import Foundation
import Observation
@preconcurrency import UserNotifications
import os

fileprivate let episodeNotificationLogger = Logger(
    subsystem: .bundleIdentifier,
    category: "EpisodeNotifications"
)

enum EpisodeNotificationAuthorizationStatus: String, Codable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        }
    }
}

enum EpisodeNotificationLeadTime: Int, CaseIterable, Codable, Sendable {
    case atAirtime = 0
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60

    static let defaultValue = Self.fifteenMinutes
}

struct EpisodeNotificationSubscription: Codable, Equatable, Identifiable, Sendable {
    let entryIdentityRawID: String
    let tvMazeShowID: Int
    let displayTitle: String
    let seasonNumber: Int?

    var id: String { entryIdentityRawID }
}

struct EpisodeScheduledReminder: Equatable, Identifiable, Sendable {
    let id: String
    let subscriptionID: String
    let seasonNumber: Int?
    let episodeNumber: Int?
    let airStamp: Date
    let fireDate: Date
}

enum EpisodeNotificationWarning: String, Codable, Sendable {
    case queueLimit
    case schedulingFailure
}

struct EpisodeNotificationSnapshot: Equatable, Sendable {
    var authorizationStatus: EpisodeNotificationAuthorizationStatus = .notDetermined
    var subscriptions: [EpisodeNotificationSubscription] = []
    var scheduledReminders: [EpisodeScheduledReminder] = []
    var leadTime: EpisodeNotificationLeadTime = .defaultValue
    var warning: EpisodeNotificationWarning?

    func subscription(for entryIdentityRawID: String) -> EpisodeNotificationSubscription? {
        subscriptions.first { $0.entryIdentityRawID == entryIdentityRawID }
    }

    func reminders(for entryIdentityRawID: String) -> [EpisodeScheduledReminder] {
        scheduledReminders.filter { $0.subscriptionID == entryIdentityRawID }
    }
}

enum EpisodeNotificationEnableResult: Equatable, Sendable {
    case enabled
    case denied
}

struct EpisodeNotificationRefreshResult: Equatable, Sendable {
    let refreshedSubscriptionCount: Int
    let failedSubscriptionCount: Int
    let warning: EpisodeNotificationWarning?

    var completedSuccessfully: Bool {
        failedSubscriptionCount == 0 && warning != .schedulingFailure
    }
}

enum EpisodeNotificationManagerError: Error {
    case refreshFailed
    case schedulingFailed
}

struct EpisodeNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let subscriptionID: String
    let tvMazeShowID: Int
    let seasonNumber: Int?
    let episodeNumber: Int?
    let airStamp: Date
    let fireDate: Date

    var reminder: EpisodeScheduledReminder {
        EpisodeScheduledReminder(
            id: identifier,
            subscriptionID: subscriptionID,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            airStamp: airStamp,
            fireDate: fireDate
        )
    }
}

protocol EpisodeNotificationCenter: Sendable {
    func authorizationStatus() async -> EpisodeNotificationAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [EpisodeNotificationRequest]
    func add(_ request: EpisodeNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String]) async
}

struct SystemEpisodeNotificationCenter: EpisodeNotificationCenter {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> EpisodeNotificationAuthorizationStatus {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .provisional:
            .provisional
        case .ephemeral:
            .ephemeral
        @unknown default:
            .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pendingRequests() async -> [EpisodeNotificationRequest] {
        await center.pendingNotificationRequests().compactMap(Self.request(from:))
    }

    func add(_ request: EpisodeNotificationRequest) async throws {
        let trigger = Self.calendarTrigger(for: request.fireDate)
        let content = Self.notificationContent(for: request)
        var payload: [AnyHashable: Any] = [
            EpisodeNotificationPayloadKey.subscriptionID: request.subscriptionID,
            EpisodeNotificationPayloadKey.tvMazeShowID: request.tvMazeShowID,
            EpisodeNotificationPayloadKey.airStamp: request.airStamp.timeIntervalSince1970
        ]
        payload[EpisodeNotificationPayloadKey.seasonNumber] = request.seasonNumber
        payload[EpisodeNotificationPayloadKey.episodeNumber] = request.episodeNumber
        content.userInfo = payload

        try await center.add(
            UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: trigger
            )
        )
    }

    static func notificationContent(for request: EpisodeNotificationRequest) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        return content
    }

    static func calendarTrigger(for fireDate: Date) -> UNCalendarNotificationTrigger {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var dateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        dateComponents.calendar = calendar
        dateComponents.timeZone = calendar.timeZone
        return UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: false
        )
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func request(from request: UNNotificationRequest) -> EpisodeNotificationRequest? {
        guard request.identifier.hasPrefix(EpisodeNotificationManager.requestIdentifierPrefix) else {
            return nil
        }
        let payload = request.content.userInfo
        guard
            let subscriptionID = payload[EpisodeNotificationPayloadKey.subscriptionID] as? String,
            let tvMazeShowID = payload[EpisodeNotificationPayloadKey.tvMazeShowID] as? Int,
            let airStampInterval = payload[EpisodeNotificationPayloadKey.airStamp] as? Double,
            let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger,
            let fireDate = calendarTrigger.nextTriggerDate()
        else {
            return nil
        }

        return EpisodeNotificationRequest(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body,
            subscriptionID: subscriptionID,
            tvMazeShowID: tvMazeShowID,
            seasonNumber: payload[EpisodeNotificationPayloadKey.seasonNumber] as? Int,
            episodeNumber: payload[EpisodeNotificationPayloadKey.episodeNumber] as? Int,
            airStamp: Date(timeIntervalSince1970: airStampInterval),
            fireDate: fireDate
        )
    }
}

enum EpisodeNotificationPayloadKey {
    static let subscriptionID = "entryIdentityRawID"
    static let tvMazeShowID = "tvMazeShowID"
    static let seasonNumber = "seasonNumber"
    static let episodeNumber = "episodeNumber"
    static let airStamp = "airStamp"
}

actor EpisodeNotificationManager {
    static let requestIdentifierPrefix = "AniShelf.Episode."
    static let maximumPendingRequestCount = 64
    static let maximumConcurrentProviderRequestCount = 6

    private struct Candidate: Equatable, Sendable {
        let subscription: EpisodeNotificationSubscription
        let episode: TVMazeNextEpisodeAiring
        let fireDate: Date

        var identifier: String {
            EpisodeNotificationManager.requestIdentifier(subscriptionID: subscription.id)
        }
    }

    private struct ProviderRefreshResult: Sendable {
        let showID: Int
        let episode: TVMazeNextEpisodeAiring?
        let failed: Bool
    }

    private let defaults: UserDefaults
    private let notificationCenter: any EpisodeNotificationCenter
    private let fetchNextEpisode: @Sendable (Int) async throws -> TVMazeNextEpisodeAiring?
    private let now: @Sendable () -> Date
    private var subscriptions: [String: EpisodeNotificationSubscription]

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: any EpisodeNotificationCenter = SystemEpisodeNotificationCenter(),
        tvMazeClient: TVMazeClient = TVMazeClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.fetchNextEpisode = { showID in
            try await tvMazeClient.show(id: showID)?.nextEpisodeAiring
        }
        self.now = now
        self.subscriptions = Self.loadSubscriptions(from: defaults)
    }

    init(
        defaults: UserDefaults,
        notificationCenter: any EpisodeNotificationCenter,
        now: @escaping @Sendable () -> Date = Date.init,
        fetchNextEpisode: @escaping @Sendable (Int) async throws -> TVMazeNextEpisodeAiring?
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.fetchNextEpisode = fetchNextEpisode
        self.now = now
        self.subscriptions = Self.loadSubscriptions(from: defaults)
    }

    func snapshot() async -> EpisodeNotificationSnapshot {
        let pending = await notificationCenter.pendingRequests()
        return EpisodeNotificationSnapshot(
            authorizationStatus: await notificationCenter.authorizationStatus(),
            subscriptions: subscriptions.values.sorted { $0.displayTitle < $1.displayTitle },
            scheduledReminders: pending.map(\.reminder).sorted { $0.fireDate < $1.fireDate },
            leadTime: leadTime,
            warning: storedWarning
        )
    }

    func enable(
        entryIdentity: LibraryEntryIdentity,
        showID: Int,
        displayTitle: String,
        seasonNumber: Int?
    ) async throws -> EpisodeNotificationEnableResult {
        var authorizationStatus = await notificationCenter.authorizationStatus()
        if authorizationStatus == .notDetermined {
            _ = try await notificationCenter.requestAuthorization()
            authorizationStatus = await notificationCenter.authorizationStatus()
        }
        guard authorizationStatus.allowsScheduling else { return .denied }

        subscriptions[entryIdentity.rawID] = EpisodeNotificationSubscription(
            entryIdentityRawID: entryIdentity.rawID,
            tvMazeShowID: showID,
            displayTitle: displayTitle,
            seasonNumber: seasonNumber
        )
        persistSubscriptions()
        let refreshResult = try await refreshAll()
        if refreshResult.failedSubscriptionCount > 0 {
            throw EpisodeNotificationManagerError.refreshFailed
        }
        return .enabled
    }

    @discardableResult
    func disable(entryIdentityRawID: String) async -> Bool {
        !(await removeSubscriptions(withEntryIdentityRawIDs: Set([entryIdentityRawID]))).isEmpty
    }

    @discardableResult
    func disableSubscriptions(
        forSeriesTMDbID seriesTMDbID: Int,
        matchingTVMazeShowID: Int? = nil
    ) async -> Bool {
        let matchingIDs = Set(
            subscriptions.keys.filter { rawID in
                if let matchingTVMazeShowID,
                    subscriptions[rawID]?.tvMazeShowID != matchingTVMazeShowID
                {
                    return false
                }
                guard let identity = LibraryEntryIdentity(rawID: rawID) else { return false }
                switch identity.entryType {
                case .series:
                    return identity.tmdbID == seriesTMDbID
                case .season:
                    return identity.parentSeriesID == seriesTMDbID
                case .movie:
                    return false
                }
            }
        )
        return !(await removeSubscriptions(withEntryIdentityRawIDs: matchingIDs)).isEmpty
    }

    private func removeSubscriptions(
        withEntryIdentityRawIDs requestedIDs: Set<String>
    ) async -> Set<String> {
        let removedIDs = requestedIDs.filter { subscriptions.removeValue(forKey: $0) != nil }
        guard !removedIDs.isEmpty else {
            return []
        }
        persistSubscriptions()
        let identifiers = await notificationCenter.pendingRequests()
            .filter { removedIDs.contains($0.subscriptionID) }
            .map(\.identifier)
        await notificationCenter.removePendingRequests(withIdentifiers: identifiers)
        clearWarningWhenUnderLimit()
        episodeNotificationLogger.info(
            "Removed \(removedIDs.count, privacy: .public) episode notification subscriptions and \(identifiers.count, privacy: .public) pending reminders."
        )
        for removedID in removedIDs.sorted() {
            episodeNotificationLogger.debug(
                "Removed episode notification subscription \(removedID, privacy: .private)."
            )
        }
        return Set(removedIDs)
    }

    func cancelAll() async {
        subscriptions.removeAll()
        persistSubscriptions()
        let identifiers = await notificationCenter.pendingRequests().map(\.identifier)
        await notificationCenter.removePendingRequests(withIdentifiers: identifiers)
        storedWarning = nil
    }

    @discardableResult
    func removeSubscriptions(notIn validEntryIdentityRawIDs: Set<String>) async -> Set<String> {
        let staleIDs = Set(subscriptions.keys.filter { !validEntryIdentityRawIDs.contains($0) })
        return await removeSubscriptions(withEntryIdentityRawIDs: staleIDs)
    }

    func setLeadTime(_ newValue: EpisodeNotificationLeadTime) async throws {
        try await rebuildPendingRequests(for: newValue)
        defaults.set(newValue.rawValue, forKey: .episodeNotificationLeadTimeMinutes)
        let refreshResult = try await refreshAll()
        if refreshResult.failedSubscriptionCount > 0 {
            throw EpisodeNotificationManagerError.refreshFailed
        }
    }

    @discardableResult
    func refreshAll() async throws -> EpisodeNotificationRefreshResult {
        let currentSubscriptions = subscriptions.values.sorted { $0.id < $1.id }
        let currentSubscriptionIDs = Set(currentSubscriptions.map(\.id))
        let existingRequests = await notificationCenter.pendingRequests()
        let orphanedRequestIdentifiers =
            existingRequests
            .filter { !currentSubscriptionIDs.contains($0.subscriptionID) }
            .map(\.identifier)
        await notificationCenter.removePendingRequests(withIdentifiers: orphanedRequestIdentifiers)

        guard await notificationCenter.authorizationStatus().allowsScheduling else {
            return EpisodeNotificationRefreshResult(
                refreshedSubscriptionCount: 0,
                failedSubscriptionCount: 0,
                warning: storedWarning
            )
        }

        guard !currentSubscriptions.isEmpty else {
            storedWarning = nil
            return EpisodeNotificationRefreshResult(
                refreshedSubscriptionCount: 0,
                failedSubscriptionCount: 0,
                warning: nil
            )
        }

        let showIDs = Set(currentSubscriptions.map(\.tvMazeShowID)).sorted()
        let fetchNextEpisode = fetchNextEpisode
        var refreshedSubscriptions: [String: EpisodeNotificationSubscription] = [:]
        var failedSubscriptions: [String: EpisodeNotificationSubscription] = [:]
        var refreshedCandidates: [String: Candidate] = [:]
        var overflowed = false

        do {
            try await withThrowingTaskGroup(of: ProviderRefreshResult.self) { group in
                var showIDIterator = showIDs.makeIterator()

                for _ in 0..<min(Self.maximumConcurrentProviderRequestCount, showIDs.count) {
                    guard let showID = showIDIterator.next() else { break }
                    group.addTask {
                        try await Self.providerRefreshResult(
                            for: showID,
                            fetchNextEpisode: fetchNextEpisode
                        )
                    }
                }

                while let result = try await group.next() {
                    try Task.checkCancellation()
                    let matchingSubscriptions = currentSubscriptions.filter {
                        $0.tvMazeShowID == result.showID && subscriptions[$0.id] == $0
                    }

                    if result.failed {
                        for subscription in matchingSubscriptions {
                            failedSubscriptions[subscription.id] = subscription
                        }
                    } else {
                        for subscription in matchingSubscriptions {
                            refreshedSubscriptions[subscription.id] = subscription
                            if let candidate = candidate(for: subscription, episode: result.episode) {
                                refreshedCandidates[subscription.id] = candidate
                            } else {
                                refreshedCandidates.removeValue(forKey: subscription.id)
                            }
                        }
                        overflowed = try await reconcileRequests(
                            refreshedSubscriptions: refreshedSubscriptions,
                            candidates: refreshedCandidates
                        )
                        storedWarning = overflowed ? .queueLimit : nil
                    }

                    if let showID = showIDIterator.next() {
                        group.addTask {
                            try await Self.providerRefreshResult(
                                for: showID,
                                fetchNextEpisode: fetchNextEpisode
                            )
                        }
                    }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            storedWarning = .schedulingFailure
            throw EpisodeNotificationManagerError.schedulingFailed
        }

        let refreshedSubscriptionCount = refreshedSubscriptions.values.count {
            subscriptions[$0.id] == $0
        }
        let failedSubscriptionCount = failedSubscriptions.values.count {
            subscriptions[$0.id] == $0
        }

        storedWarning = overflowed ? .queueLimit : nil
        return EpisodeNotificationRefreshResult(
            refreshedSubscriptionCount: refreshedSubscriptionCount,
            failedSubscriptionCount: failedSubscriptionCount,
            warning: storedWarning
        )
    }

    private static func providerRefreshResult(
        for showID: Int,
        fetchNextEpisode: @Sendable (Int) async throws -> TVMazeNextEpisodeAiring?
    ) async throws -> ProviderRefreshResult {
        do {
            let episode = try await fetchNextEpisode(showID)
            try Task.checkCancellation()
            return ProviderRefreshResult(showID: showID, episode: episode, failed: false)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ProviderRefreshResult(showID: showID, episode: nil, failed: true)
        }
    }

    private var leadTime: EpisodeNotificationLeadTime {
        guard defaults.object(forKey: .episodeNotificationLeadTimeMinutes) != nil else {
            return .defaultValue
        }
        return EpisodeNotificationLeadTime(
            rawValue: defaults.integer(forKey: .episodeNotificationLeadTimeMinutes)
        ) ?? .defaultValue
    }

    private var storedWarning: EpisodeNotificationWarning? {
        get {
            defaults.string(forKey: .episodeNotificationWarning)
                .flatMap(EpisodeNotificationWarning.init(rawValue:))
        }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: .episodeNotificationWarning)
            } else {
                defaults.removeObject(forKey: .episodeNotificationWarning)
            }
        }
    }

    private func candidate(
        for subscription: EpisodeNotificationSubscription,
        episode: TVMazeNextEpisodeAiring?
    ) -> Candidate? {
        guard let episode else { return nil }
        let leadSeconds = TimeInterval(leadTime.rawValue * 60)
        let fireDate = episode.airStamp.addingTimeInterval(-leadSeconds)
        guard fireDate > now() else { return nil }
        return Candidate(subscription: subscription, episode: episode, fireDate: fireDate)
    }

    private func reconcileRequests(
        refreshedSubscriptions: [String: EpisodeNotificationSubscription],
        candidates: [String: Candidate]
    ) async throws -> Bool {
        let activeRefreshedSubscriptionIDs = Set(
            refreshedSubscriptions.values
                .filter { subscriptions[$0.id] == $0 }
                .map(\.id)
        )
        let existingRequests = await notificationCenter.pendingRequests()
        let retainedRequests = existingRequests.filter {
            !activeRefreshedSubscriptionIDs.contains($0.subscriptionID)
                && $0.fireDate > now()
                && currentSubscription(for: $0) != nil
        }
        let replacementRequests = candidates.values
            .filter { subscriptions[$0.subscription.id] == $0.subscription }
            .map(makeRequest)
        let requestedQueue = (retainedRequests + replacementRequests)
            .sorted(by: Self.requestOrdering)
        let selectedRequests = Array(requestedQueue.prefix(Self.maximumPendingRequestCount))

        try await replaceRequests(with: selectedRequests, preserving: existingRequests)
        return selectedRequests.count < requestedQueue.count
    }

    private func replaceRequests(
        with desiredRequests: [EpisodeNotificationRequest],
        preserving existingRequests: [EpisodeNotificationRequest]
    ) async throws {
        let desiredRequestsByID = Dictionary(
            uniqueKeysWithValues: desiredRequests.map { ($0.identifier, $0) }
        )
        let existingRequestsByID = Dictionary(
            uniqueKeysWithValues: existingRequests.map { ($0.identifier, $0) }
        )
        let removedRequests = existingRequests.filter {
            desiredRequestsByID[$0.identifier] == nil
        }
        let replacementRequests = desiredRequests.filter {
            existingRequestsByID[$0.identifier] != $0
        }
        let previousReplacementRequests = replacementRequests.compactMap {
            existingRequestsByID[$0.identifier]
        }
        var scheduledRequestIdentifiers: [String] = []

        await notificationCenter.removePendingRequests(
            withIdentifiers: removedRequests.map(\.identifier)
        )

        do {
            for request in replacementRequests {
                guard let subscription = currentSubscription(for: request) else { continue }
                if try await schedule(request, whileSubscriptionRemains: subscription) {
                    scheduledRequestIdentifiers.append(request.identifier)
                }
            }
        } catch {
            await notificationCenter.removePendingRequests(
                withIdentifiers: scheduledRequestIdentifiers
            )
            for request in removedRequests + previousReplacementRequests where request.fireDate > now() {
                guard let subscription = currentSubscription(for: request) else { continue }
                _ = try? await schedule(request, whileSubscriptionRemains: subscription)
            }
            throw error
        }
    }

    private func rebuildPendingRequests(for leadTime: EpisodeNotificationLeadTime) async throws {
        let pendingRequests = await notificationCenter.pendingRequests()
        let leadSeconds = TimeInterval(leadTime.rawValue * 60)
        let rebuilt = pendingRequests.compactMap { request -> EpisodeNotificationRequest? in
            let fireDate = request.airStamp.addingTimeInterval(-leadSeconds)
            guard fireDate > now() else { return nil }
            return EpisodeNotificationRequest(
                identifier: request.identifier,
                title: request.title,
                body: Self.notificationBody(
                    seasonNumber: request.seasonNumber,
                    episodeNumber: request.episodeNumber,
                    leadTime: leadTime
                ),
                subscriptionID: request.subscriptionID,
                tvMazeShowID: request.tvMazeShowID,
                seasonNumber: request.seasonNumber,
                episodeNumber: request.episodeNumber,
                airStamp: request.airStamp,
                fireDate: fireDate
            )
        }
        await notificationCenter.removePendingRequests(
            withIdentifiers: pendingRequests.map(\.identifier)
        )
        do {
            for request in rebuilt {
                guard let subscription = currentSubscription(for: request) else { continue }
                _ = try await schedule(request, whileSubscriptionRemains: subscription)
            }
        } catch {
            await notificationCenter.removePendingRequests(
                withIdentifiers: rebuilt.map(\.identifier)
            )
            for request in pendingRequests where request.fireDate > now() {
                guard let subscription = currentSubscription(for: request) else { continue }
                _ = try? await schedule(request, whileSubscriptionRemains: subscription)
            }
            storedWarning = .schedulingFailure
            throw EpisodeNotificationManagerError.schedulingFailed
        }
    }

    @discardableResult
    private func schedule(
        _ request: EpisodeNotificationRequest,
        whileSubscriptionRemains subscription: EpisodeNotificationSubscription
    ) async throws -> Bool {
        guard subscriptions[subscription.id] == subscription else { return false }
        try await notificationCenter.add(request)
        guard subscriptions[subscription.id] == subscription else {
            await notificationCenter.removePendingRequests(withIdentifiers: [request.identifier])
            return false
        }
        return true
    }

    private func currentSubscription(
        for request: EpisodeNotificationRequest
    ) -> EpisodeNotificationSubscription? {
        guard let subscription = subscriptions[request.subscriptionID] else { return nil }
        guard subscription.tvMazeShowID == request.tvMazeShowID else { return nil }
        return subscription
    }

    private func makeRequest(_ candidate: Candidate) -> EpisodeNotificationRequest {
        EpisodeNotificationRequest(
            identifier: candidate.identifier,
            title: candidate.subscription.displayTitle,
            body: Self.notificationBody(
                seasonNumber: candidate.episode.seasonNumber,
                episodeNumber: candidate.episode.episodeNumber,
                leadTime: leadTime
            ),
            subscriptionID: candidate.subscription.id,
            tvMazeShowID: candidate.subscription.tvMazeShowID,
            seasonNumber: candidate.episode.seasonNumber,
            episodeNumber: candidate.episode.episodeNumber,
            airStamp: candidate.episode.airStamp,
            fireDate: candidate.fireDate
        )
    }

    private static func notificationBody(
        seasonNumber: Int?,
        episodeNumber: Int?,
        leadTime: EpisodeNotificationLeadTime
    ) -> String {
        let episodeLabel: String
        if let seasonNumber, let episodeNumber {
            episodeLabel = String(format: "S%02dE%02d", seasonNumber, episodeNumber)
        } else {
            episodeLabel = String(localized: "New episode")
        }

        if leadTime == .atAirtime {
            return String.localizedStringWithFormat(
                String(localized: "%@ is airing now."),
                episodeLabel
            )
        }
        return String.localizedStringWithFormat(
            String(localized: "%@ airs in %lld minutes."),
            episodeLabel,
            Int64(leadTime.rawValue)
        )
    }

    private static func requestOrdering(
        _ lhs: EpisodeNotificationRequest,
        _ rhs: EpisodeNotificationRequest
    ) -> Bool {
        if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
        return lhs.subscriptionID < rhs.subscriptionID
    }

    private static func requestIdentifier(subscriptionID: String) -> String {
        let safeSubscriptionID = subscriptionID.replacingOccurrences(of: ":", with: "-")
        return "\(requestIdentifierPrefix)\(safeSubscriptionID)"
    }

    private static func loadSubscriptions(
        from defaults: UserDefaults
    ) -> [String: EpisodeNotificationSubscription] {
        guard
            let data = defaults.data(forKey: .episodeNotificationSubscriptions),
            let decoded = try? JSONDecoder().decode([EpisodeNotificationSubscription].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func persistSubscriptions() {
        let ordered = subscriptions.values.sorted { $0.id < $1.id }
        guard let data = try? JSONEncoder().encode(ordered) else { return }
        defaults.set(data, forKey: .episodeNotificationSubscriptions)
    }

    private func clearWarningWhenUnderLimit() {
        if subscriptions.isEmpty {
            storedWarning = nil
        }
    }
}

@MainActor
@Observable
final class EpisodeNotificationCoordinator {
    static let shared = EpisodeNotificationCoordinator(
        manager: EpisodeNotificationManager()
    )

    private let manager: EpisodeNotificationManager
    private(set) var snapshot = EpisodeNotificationSnapshot()
    private(set) var isRefreshing = false
    private(set) var lastRefreshFailed = false
    var pendingRouteEntryIdentityRawID: String?
    var presentedWarning: EpisodeNotificationWarning?

    private init(manager: EpisodeNotificationManager) {
        self.manager = manager
    }

    static func makeForTesting(
        manager: EpisodeNotificationManager
    ) -> EpisodeNotificationCoordinator {
        EpisodeNotificationCoordinator(manager: manager)
    }

    func reloadState() async {
        let previousWarning = snapshot.warning
        snapshot = await manager.snapshot()
        if snapshot.warning != nil, snapshot.warning != previousWarning {
            presentedWarning = snapshot.warning
        }
        updateBackgroundRefreshRequest()
    }

    func enable(
        entryIdentity: LibraryEntryIdentity,
        showID: Int,
        displayTitle: String,
        seasonNumber: Int?
    ) async -> EpisodeNotificationEnableResult? {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await manager.enable(
                entryIdentity: entryIdentity,
                showID: showID,
                displayTitle: displayTitle,
                seasonNumber: seasonNumber
            )
            lastRefreshFailed = false
            await reloadState()
            return result
        } catch is CancellationError {
            return nil
        } catch {
            lastRefreshFailed = true
            await reloadState()
            return nil
        }
    }

    func disable(entryIdentityRawID: String) async {
        guard await manager.disable(entryIdentityRawID: entryIdentityRawID) else {
            return
        }
        _ = await refreshAll()
    }

    func disableSubscriptions(
        forSeriesTMDbID seriesTMDbID: Int,
        matchingTVMazeShowID: Int? = nil
    ) async {
        guard
            await manager.disableSubscriptions(
                forSeriesTMDbID: seriesTMDbID,
                matchingTVMazeShowID: matchingTVMazeShowID
            )
        else {
            return
        }
        _ = await refreshAll()
    }

    func cancelAll() async {
        await manager.cancelAll()
        lastRefreshFailed = false
        await reloadState()
    }

    func setLeadTime(_ leadTime: EpisodeNotificationLeadTime) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await manager.setLeadTime(leadTime)
            lastRefreshFailed = false
        } catch is CancellationError {
            return
        } catch {
            lastRefreshFailed = true
        }
        await reloadState()
    }

    @discardableResult
    func refreshAll() async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await manager.refreshAll()
            lastRefreshFailed = !result.completedSuccessfully
            await reloadState()
            return result.completedSuccessfully
        } catch is CancellationError {
            return false
        } catch {
            lastRefreshFailed = true
            await reloadState()
            return false
        }
    }

    func pruneSubscriptions(validEntryIdentityRawIDs: Set<String>) async {
        let removedIDs = await manager.removeSubscriptions(notIn: validEntryIdentityRawIDs)
        if removedIDs.isEmpty {
            episodeNotificationLogger.debug(
                "Episode notification subscription reconciliation found no stale subscriptions among \(validEntryIdentityRawIDs.count, privacy: .public) visible library entries."
            )
        } else {
            episodeNotificationLogger.info(
                "Pruned \(removedIDs.count, privacy: .public) episode notification subscriptions missing from the visible library."
            )
        }
        await reloadState()
    }

    func receiveNotificationRoute(entryIdentityRawID: String) {
        pendingRouteEntryIdentityRawID = entryIdentityRawID
    }

    func consumePendingRoute() {
        pendingRouteEntryIdentityRawID = nil
    }

    func dismissPresentedWarning() {
        presentedWarning = nil
    }

    private func updateBackgroundRefreshRequest() {
        LibrarySyncNotificationBridge.updateEpisodeNotificationBackgroundRefresh(
            hasSubscriptions: !snapshot.subscriptions.isEmpty
        )
    }
}
