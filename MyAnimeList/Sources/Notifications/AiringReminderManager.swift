//
//  AiringReminderManager.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/21.
//

import DataProvider
import Foundation
import Observation
@preconcurrency import UserNotifications
import os

fileprivate let airingReminderLogger = Logger(
    subsystem: .bundleIdentifier,
    category: "AiringReminders"
)

enum AiringReminderAuthorizationStatus: String, Codable, Sendable {
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

/// Signed minutes relative to airtime, shared with custom timing: negative is before, positive is after.
enum AiringReminderTimingPreset: Int, CaseIterable, Sendable {
    case oneHourBefore = -60
    case thirtyMinutesBefore = -30
    case fifteenMinutesBefore = -15
    case fiveMinutesBefore = -5
    case atAirtime = 0
    case fiveMinutesAfter = 5
    case fifteenMinutesAfter = 15
    case thirtyMinutesAfter = 30
    case oneHourAfter = 60

    static let defaultValue = Self.fifteenMinutesBefore

    var offsetMinutes: Int { rawValue }
}

struct AiringReminderSubscription: Codable, Equatable, Identifiable, Sendable {
    let entryIdentityRawID: String
    let tvMazeShowID: Int
    let displayTitle: String
    /// The TMDb season identity selected by the user.
    ///
    /// This value does not override TVMaze episode numbering.
    let seasonNumber: Int?

    /// Minutes relative to airtime: negative is before, positive is after; nil uses the default.
    var timingOffsetMinutes: Int?

    var id: String { entryIdentityRawID }

    func effectiveTimingOffsetMinutes(defaultTiming: AiringReminderTimingPreset) -> Int {
        timingOffsetMinutes ?? defaultTiming.offsetMinutes
    }
}

struct ScheduledAiringReminder: Equatable, Identifiable, Sendable {
    let id: String
    let subscriptionID: String
    let seasonNumber: Int?
    let episodeNumber: Int?
    let airStamp: Date
    let fireDate: Date
}

enum AiringReminderWarning: String, Codable, Sendable {
    case queueLimit
    case schedulingFailure

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .queueLimit:
            "Reminder Limit Reached"
        case .schedulingFailure:
            "Reminder Scheduling Issue"
        }
    }

    var localizedMessage: LocalizedStringResource {
        switch self {
        case .queueLimit:
            "iOS could not schedule every reminder. AniShelf kept the reminders for the nearest airtimes."
        case .schedulingFailure:
            "iOS rejected one or more reminders. Existing reminders were restored when possible."
        }
    }
}

struct AiringReminderSnapshot: Equatable, Sendable {
    var authorizationStatus: AiringReminderAuthorizationStatus = .notDetermined
    var subscriptions: [AiringReminderSubscription] = []
    var scheduledReminders: [ScheduledAiringReminder] = []
    var defaultTiming: AiringReminderTimingPreset = .defaultValue
    var warning: AiringReminderWarning?

    func subscription(for entryIdentityRawID: String) -> AiringReminderSubscription? {
        subscriptions.first { $0.entryIdentityRawID == entryIdentityRawID }
    }

    func reminders(for entryIdentityRawID: String) -> [ScheduledAiringReminder] {
        scheduledReminders.filter { $0.subscriptionID == entryIdentityRawID }
    }
}

enum AiringReminderEnableResult: Equatable, Sendable {
    case enabled
    case denied
}

struct AiringReminderRefreshResult: Equatable, Sendable {
    let refreshedSubscriptionCount: Int
    let failedSubscriptionCount: Int
    let warning: AiringReminderWarning?

    var completedSuccessfully: Bool {
        failedSubscriptionCount == 0 && warning != .schedulingFailure
    }
}

enum AiringReminderManagerError: Error {
    case refreshFailed
    case schedulingFailed
}

struct AiringReminderRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let subscriptionID: String
    let tvMazeShowID: Int
    /// TVMaze's season number for the scheduled episode; provider numbering is authoritative when
    /// TMDb and TVMaze use different season numbering.
    let seasonNumber: Int?
    let episodeNumber: Int?
    let airStamp: Date
    let fireDate: Date

    var reminder: ScheduledAiringReminder {
        ScheduledAiringReminder(
            id: identifier,
            subscriptionID: subscriptionID,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            airStamp: airStamp,
            fireDate: fireDate
        )
    }
}

protocol AiringReminderCenter: Sendable {
    func authorizationStatus() async -> AiringReminderAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [AiringReminderRequest]
    func add(_ request: AiringReminderRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String]) async
}

struct SystemAiringReminderCenter: AiringReminderCenter {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> AiringReminderAuthorizationStatus {
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

    func pendingRequests() async -> [AiringReminderRequest] {
        await center.pendingNotificationRequests().compactMap(Self.request(from:))
    }

    func add(_ request: AiringReminderRequest) async throws {
        let trigger = Self.calendarTrigger(for: request.fireDate)
        let content = Self.notificationContent(for: request)
        var payload: [AnyHashable: Any] = [
            AiringReminderPayloadKey.subscriptionID: request.subscriptionID,
            AiringReminderPayloadKey.tvMazeShowID: request.tvMazeShowID,
            AiringReminderPayloadKey.airStamp: request.airStamp.timeIntervalSince1970
        ]
        payload[AiringReminderPayloadKey.seasonNumber] = request.seasonNumber
        payload[AiringReminderPayloadKey.episodeNumber] = request.episodeNumber
        content.userInfo = payload

        try await center.add(
            UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: trigger
            )
        )
    }

    static func notificationContent(for request: AiringReminderRequest) -> UNMutableNotificationContent {
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

    private static func request(from request: UNNotificationRequest) -> AiringReminderRequest? {
        guard request.identifier.hasPrefix(AiringReminderManager.requestIdentifierPrefix) else {
            return nil
        }
        let payload = request.content.userInfo
        guard
            let subscriptionID = payload[AiringReminderPayloadKey.subscriptionID] as? String,
            let tvMazeShowID = payload[AiringReminderPayloadKey.tvMazeShowID] as? Int,
            let airStampInterval = payload[AiringReminderPayloadKey.airStamp] as? Double,
            let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger,
            let fireDate = calendarTrigger.nextTriggerDate()
        else {
            return nil
        }

        return AiringReminderRequest(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body,
            subscriptionID: subscriptionID,
            tvMazeShowID: tvMazeShowID,
            seasonNumber: payload[AiringReminderPayloadKey.seasonNumber] as? Int,
            episodeNumber: payload[AiringReminderPayloadKey.episodeNumber] as? Int,
            airStamp: Date(timeIntervalSince1970: airStampInterval),
            fireDate: fireDate
        )
    }
}

enum AiringReminderPayloadKey {
    static let subscriptionID = "entryIdentityRawID"
    static let tvMazeShowID = "tvMazeShowID"
    static let seasonNumber = "seasonNumber"
    static let episodeNumber = "episodeNumber"
    static let airStamp = "airStamp"
}

actor AiringReminderManager {
    static let requestIdentifierPrefix = "AniShelf.AiringReminder."
    static let maximumPendingRequestCount = 64
    static let maximumConcurrentProviderRequestCount = 6

    private struct Candidate: Equatable, Sendable {
        let subscription: AiringReminderSubscription
        let episode: TVMazeNextEpisodeAiring
        let fireDate: Date

        var identifier: String {
            AiringReminderManager.requestIdentifier(subscriptionID: subscription.id)
        }
    }

    private struct ProviderRefreshResult: Sendable {
        let showID: Int
        let episode: TVMazeNextEpisodeAiring?
        let failed: Bool
    }

    private let defaults: UserDefaults
    private let notificationCenter: any AiringReminderCenter
    private let fetchNextEpisode: @Sendable (Int) async throws -> TVMazeNextEpisodeAiring?
    private let now: @Sendable () -> Date
    private var subscriptions: [String: AiringReminderSubscription]

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: any AiringReminderCenter = SystemAiringReminderCenter(),
        tvMazeClient: TVMazeClient = TVMazeClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        Self.migrateLegacyDefaultTiming(in: defaults)
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
        notificationCenter: any AiringReminderCenter,
        now: @escaping @Sendable () -> Date = Date.init,
        fetchNextEpisode: @escaping @Sendable (Int) async throws -> TVMazeNextEpisodeAiring?
    ) {
        Self.migrateLegacyDefaultTiming(in: defaults)
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.fetchNextEpisode = fetchNextEpisode
        self.now = now
        self.subscriptions = Self.loadSubscriptions(from: defaults)
    }

    func snapshot() async -> AiringReminderSnapshot {
        let pending = await notificationCenter.pendingRequests()
        return AiringReminderSnapshot(
            authorizationStatus: await notificationCenter.authorizationStatus(),
            subscriptions: subscriptions.values.sorted { $0.displayTitle < $1.displayTitle },
            scheduledReminders: pending.map(\.reminder).sorted { $0.fireDate < $1.fireDate },
            defaultTiming: defaultTiming,
            warning: storedWarning
        )
    }

    func enable(
        entryIdentity: LibraryEntryIdentity,
        showID: Int,
        displayTitle: String,
        seasonNumber: Int?
    ) async throws -> AiringReminderEnableResult {
        var authorizationStatus = await notificationCenter.authorizationStatus()
        if authorizationStatus == .notDetermined {
            _ = try await notificationCenter.requestAuthorization()
            authorizationStatus = await notificationCenter.authorizationStatus()
        }
        guard authorizationStatus.allowsScheduling else { return .denied }

        subscriptions[entryIdentity.rawID] = AiringReminderSubscription(
            entryIdentityRawID: entryIdentity.rawID,
            tvMazeShowID: showID,
            displayTitle: displayTitle,
            seasonNumber: seasonNumber,
            timingOffsetMinutes: subscriptions[entryIdentity.rawID]?.timingOffsetMinutes
        )
        persistSubscriptions()
        let refreshResult = try await refreshAll()
        if refreshResult.failedSubscriptionCount > 0 {
            throw AiringReminderManagerError.refreshFailed
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
        airingReminderLogger.info(
            "Removed \(removedIDs.count, privacy: .public) airing reminder subscriptions and \(identifiers.count, privacy: .public) pending reminders."
        )
        for removedID in removedIDs.sorted() {
            airingReminderLogger.debug(
                "Removed airing reminder subscription \(removedID, privacy: .private)."
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

    func setTimingOffset(_ minutes: Int?, entryIdentityRawID: String) async throws {
        guard let previous = subscriptions[entryIdentityRawID] else { return }
        var updated = previous
        updated.timingOffsetMinutes = minutes.map { min(max($0, -1439), 1439) }
        subscriptions[entryIdentityRawID] = updated
        do {
            try await rebuildPendingRequests(for: defaultTiming, subscriptionID: entryIdentityRawID)
        } catch {
            if subscriptions[entryIdentityRawID] == updated {
                subscriptions[entryIdentityRawID] = previous
            }
            throw error
        }
        persistSubscriptions()
    }

    private func timingOffset(for subscription: AiringReminderSubscription) -> Int {
        subscription.effectiveTimingOffsetMinutes(defaultTiming: defaultTiming)
    }

    func setDefaultTiming(_ newValue: AiringReminderTimingPreset) async throws {
        try await rebuildPendingRequests(for: newValue)
        defaults.set(newValue.offsetMinutes, forKey: .airingReminderDefaultTimingOffsetMinutes)
        let refreshResult = try await refreshAll()
        if refreshResult.failedSubscriptionCount > 0 {
            throw AiringReminderManagerError.refreshFailed
        }
    }

    @discardableResult
    func refreshAll() async throws -> AiringReminderRefreshResult {
        let currentSubscriptions = subscriptions.values.sorted { $0.id < $1.id }
        let currentSubscriptionIDs = Set(currentSubscriptions.map(\.id))
        let existingRequests = await notificationCenter.pendingRequests()
        let orphanedRequestIdentifiers =
            existingRequests
            .filter { !currentSubscriptionIDs.contains($0.subscriptionID) }
            .map(\.identifier)
        await notificationCenter.removePendingRequests(withIdentifiers: orphanedRequestIdentifiers)

        guard await notificationCenter.authorizationStatus().allowsScheduling else {
            return AiringReminderRefreshResult(
                refreshedSubscriptionCount: 0,
                failedSubscriptionCount: 0,
                warning: storedWarning
            )
        }

        guard !currentSubscriptions.isEmpty else {
            storedWarning = nil
            return AiringReminderRefreshResult(
                refreshedSubscriptionCount: 0,
                failedSubscriptionCount: 0,
                warning: nil
            )
        }

        let showIDs = Set(currentSubscriptions.map(\.tvMazeShowID)).sorted()
        let fetchNextEpisode = fetchNextEpisode
        var refreshedSubscriptions: [String: AiringReminderSubscription] = [:]
        var failedSubscriptions: [String: AiringReminderSubscription] = [:]
        var refreshedCandidates: [String: Candidate] = [:]
        var refreshedEpisodes: [String: TVMazeNextEpisodeAiring] = [:]
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
                            refreshedEpisodes[subscription.id] = result.episode
                            if let candidate = candidate(for: subscription, episode: result.episode) {
                                refreshedCandidates[subscription.id] = candidate
                            } else {
                                refreshedCandidates.removeValue(forKey: subscription.id)
                            }
                        }
                        overflowed = try await reconcileRequests(
                            refreshedSubscriptions: refreshedSubscriptions,
                            candidates: refreshedCandidates,
                            episodes: refreshedEpisodes
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
            throw AiringReminderManagerError.schedulingFailed
        }

        let refreshedSubscriptionCount = refreshedSubscriptions.values.count {
            subscriptions[$0.id] == $0
        }
        let failedSubscriptionCount = failedSubscriptions.values.count {
            subscriptions[$0.id] == $0
        }

        storedWarning = overflowed ? .queueLimit : nil
        return AiringReminderRefreshResult(
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

    private var defaultTiming: AiringReminderTimingPreset {
        guard defaults.object(forKey: .airingReminderDefaultTimingOffsetMinutes) != nil else {
            return .defaultValue
        }
        return AiringReminderTimingPreset(
            rawValue: defaults.integer(forKey: .airingReminderDefaultTimingOffsetMinutes)
        ) ?? .defaultValue
    }

    private static func migrateLegacyDefaultTiming(in defaults: UserDefaults) {
        guard defaults.object(forKey: .airingReminderDefaultTimingOffsetMinutes) == nil,
            defaults.object(forKey: .legacyAiringReminderLeadTimeMinutes) != nil
        else { return }

        let legacyLeadTime = defaults.integer(forKey: .legacyAiringReminderLeadTimeMinutes)
        guard legacyLeadTime >= 0,
            let migratedTiming = AiringReminderTimingPreset(rawValue: -legacyLeadTime)
        else { return }

        defaults.set(
            migratedTiming.offsetMinutes,
            forKey: .airingReminderDefaultTimingOffsetMinutes
        )
        defaults.removeObject(forKey: .legacyAiringReminderLeadTimeMinutes)
    }

    private var storedWarning: AiringReminderWarning? {
        get {
            defaults.string(forKey: .airingReminderWarning)
                .flatMap(AiringReminderWarning.init(rawValue:))
        }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: .airingReminderWarning)
            } else {
                defaults.removeObject(forKey: .airingReminderWarning)
            }
        }
    }

    private func candidate(
        for subscription: AiringReminderSubscription,
        episode: TVMazeNextEpisodeAiring?
    ) -> Candidate? {
        guard let episode else { return nil }
        // Keep TVMaze's season and episode numbers in the reminder. TMDb and TVMaze can use
        // different season numbering for the same show, while the provider supplies the airing.
        let fireDate = episode.airStamp.addingTimeInterval(TimeInterval(timingOffset(for: subscription) * 60))
        guard fireDate > now() else { return nil }
        return Candidate(subscription: subscription, episode: episode, fireDate: fireDate)
    }

    private func reconcileRequests(
        refreshedSubscriptions: [String: AiringReminderSubscription],
        candidates: [String: Candidate],
        episodes: [String: TVMazeNextEpisodeAiring]
    ) async throws -> Bool {
        let activeRefreshedSubscriptionIDs = Set(
            refreshedSubscriptions.values
                .filter { subscriptions[$0.id] == $0 }
                .map(\.id)
        )
        let existingRequests = await notificationCenter.pendingRequests()
        // Once broadcast has started, TVMaze may advance to the following episode or return nil.
        // Keep an already queued delayed reminder until it fires, even across those refreshes.
        let delayedRequests = existingRequests.filter { request in
            guard request.airStamp <= now(), request.fireDate > now(),
                currentSubscription(for: request).map({ timingOffset(for: $0) > 0 }) == true
            else { return false }

            // A corrected airtime for this episode supersedes its old request, including when
            // the corrected reminder time is already past and no replacement can be scheduled.
            if activeRefreshedSubscriptionIDs.contains(request.subscriptionID),
                let episode = episodes[request.subscriptionID],
                let seasonNumber = request.seasonNumber,
                let episodeNumber = request.episodeNumber,
                episode.seasonNumber == seasonNumber, episode.episodeNumber == episodeNumber
            {
                return episode.airStamp == request.airStamp
            }
            return true
        }
        let delayedSubscriptionIDs = Set(delayedRequests.map(\.subscriptionID))
        let retainedRequests = existingRequests.filter {
            (!activeRefreshedSubscriptionIDs.contains($0.subscriptionID)
                || delayedSubscriptionIDs.contains($0.subscriptionID))
                && $0.fireDate > now()
                && currentSubscription(for: $0) != nil
        }
        let replacementRequests = candidates.values
            .filter {
                subscriptions[$0.subscription.id] == $0.subscription
                    && !delayedSubscriptionIDs.contains($0.subscription.id)
            }
            .map(makeRequest)
        let requestedQueue = (retainedRequests + replacementRequests)
            .sorted(by: Self.requestOrdering)
        let selectedRequests = Array(requestedQueue.prefix(Self.maximumPendingRequestCount))

        try await replaceRequests(with: selectedRequests, preserving: existingRequests)
        return selectedRequests.count < requestedQueue.count
    }

    private func replaceRequests(
        with desiredRequests: [AiringReminderRequest],
        preserving existingRequests: [AiringReminderRequest]
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

    private func rebuildPendingRequests(
        for defaultTiming: AiringReminderTimingPreset,
        subscriptionID: String? = nil
    ) async throws {
        let pendingRequests = await notificationCenter.pendingRequests().filter {
            subscriptionID == nil || $0.subscriptionID == subscriptionID
        }
        let rebuilt = pendingRequests.compactMap { request -> AiringReminderRequest? in
            guard let subscription = currentSubscription(for: request) else { return nil }
            let offset = subscription.effectiveTimingOffsetMinutes(defaultTiming: defaultTiming)
            let fireDate = request.airStamp.addingTimeInterval(TimeInterval(offset * 60))
            guard fireDate > now() else { return nil }
            return AiringReminderRequest(
                identifier: request.identifier,
                title: request.title,
                body: Self.notificationBody(
                    seasonNumber: request.seasonNumber,
                    episodeNumber: request.episodeNumber,
                    timingOffsetMinutes: offset
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
            throw AiringReminderManagerError.schedulingFailed
        }
    }

    @discardableResult
    private func schedule(
        _ request: AiringReminderRequest,
        whileSubscriptionRemains subscription: AiringReminderSubscription
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
        for request: AiringReminderRequest
    ) -> AiringReminderSubscription? {
        guard let subscription = subscriptions[request.subscriptionID] else { return nil }
        guard subscription.tvMazeShowID == request.tvMazeShowID else { return nil }
        return subscription
    }

    private func makeRequest(_ candidate: Candidate) -> AiringReminderRequest {
        AiringReminderRequest(
            identifier: candidate.identifier,
            title: candidate.subscription.displayTitle,
            body: Self.notificationBody(
                seasonNumber: candidate.episode.seasonNumber,
                episodeNumber: candidate.episode.episodeNumber,
                timingOffsetMinutes: timingOffset(for: candidate.subscription)
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
        timingOffsetMinutes: Int
    ) -> String {
        let episodeLabel: String
        if let seasonNumber, let episodeNumber {
            episodeLabel = String(format: "S%02dE%02d", seasonNumber, episodeNumber)
        } else {
            episodeLabel = String(localized: "New episode")
        }

        if timingOffsetMinutes == 0 {
            return String.localizedStringWithFormat(
                String(localized: "%@ is airing now."),
                episodeLabel
            )
        }
        return String.localizedStringWithFormat(
            timingOffsetMinutes > 0
                ? String(localized: "%@ aired %lld minutes ago.")
                : String(localized: "%@ airs in %lld minutes."),
            episodeLabel,
            Int64(abs(timingOffsetMinutes))
        )
    }

    private static func requestOrdering(
        _ lhs: AiringReminderRequest,
        _ rhs: AiringReminderRequest
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
    ) -> [String: AiringReminderSubscription] {
        guard
            let data = defaults.data(forKey: .airingReminderSubscriptions),
            let decoded = try? JSONDecoder().decode([AiringReminderSubscription].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func persistSubscriptions() {
        let ordered = subscriptions.values.sorted { $0.id < $1.id }
        guard let data = try? JSONEncoder().encode(ordered) else { return }
        defaults.set(data, forKey: .airingReminderSubscriptions)
    }

    private func clearWarningWhenUnderLimit() {
        if subscriptions.isEmpty {
            storedWarning = nil
        }
    }
}

struct AiringReminderNotificationRoute: Equatable {
    let entryIdentityRawID: String
    /// Persistent identifier of the scene the system activated for the notification response.
    /// `nil` lets whichever library window claims the route first open it.
    let targetSceneIdentifier: String?
}

@MainActor
@Observable
final class AiringReminderCoordinator {
    static let shared = AiringReminderCoordinator(
        manager: AiringReminderManager()
    )

    private let manager: AiringReminderManager
    private(set) var snapshot = AiringReminderSnapshot()
    private(set) var isRefreshing = false
    private(set) var lastRefreshFailed = false
    private(set) var pendingRoute: AiringReminderNotificationRoute?
    var presentedWarning: AiringReminderWarning?

    private init(manager: AiringReminderManager) {
        self.manager = manager
    }

    static func makeForTesting(
        manager: AiringReminderManager
    ) -> AiringReminderCoordinator {
        AiringReminderCoordinator(manager: manager)
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
    ) async -> AiringReminderEnableResult? {
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

    @discardableResult
    func setTimingOffset(_ minutes: Int?, entryIdentityRawID: String) async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await manager.setTimingOffset(minutes, entryIdentityRawID: entryIdentityRawID)
        } catch {
            lastRefreshFailed = true
            await reloadState()
            return false
        }

        // Saving and rebuilding succeeded. Refresh health must not turn that saved edit into
        // a failure in the editor, even if this or another subscription cannot be refreshed.
        do {
            let result = try await manager.refreshAll()
            lastRefreshFailed = !result.completedSuccessfully
        } catch {
            lastRefreshFailed = true
        }
        await reloadState()
        return true
    }

    func setDefaultTiming(_ defaultTiming: AiringReminderTimingPreset) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await manager.setDefaultTiming(defaultTiming)
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
            airingReminderLogger.debug(
                "Airing reminder subscription reconciliation found no stale subscriptions among \(validEntryIdentityRawIDs.count, privacy: .public) visible library entries."
            )
        } else {
            airingReminderLogger.info(
                "Pruned \(removedIDs.count, privacy: .public) airing reminder subscriptions missing from the visible library."
            )
        }
        await reloadState()
    }

    func receiveNotificationRoute(entryIdentityRawID: String, targetSceneIdentifier: String?) {
        pendingRoute = AiringReminderNotificationRoute(
            entryIdentityRawID: entryIdentityRawID,
            targetSceneIdentifier: targetSceneIdentifier
        )
    }

    /// Consumes the pending route when it belongs to the given scene, so exactly one window opens it.
    ///
    /// A route whose target scene has disconnected falls back to any window.
    func claimPendingRoute(
        forSceneIdentifier sceneIdentifier: String?,
        isSceneConnected: (String) -> Bool
    ) -> String? {
        guard let pendingRoute else { return nil }
        if let targetSceneIdentifier = pendingRoute.targetSceneIdentifier,
            isSceneConnected(targetSceneIdentifier)
        {
            guard sceneIdentifier == targetSceneIdentifier else { return nil }
        }
        self.pendingRoute = nil
        return pendingRoute.entryIdentityRawID
    }

    func dismissPresentedWarning() {
        presentedWarning = nil
    }

    private func updateBackgroundRefreshRequest() {
        LibrarySyncNotificationBridge.updateAiringReminderBackgroundRefresh(
            hasSubscriptions: !snapshot.subscriptions.isEmpty
        )
    }
}
