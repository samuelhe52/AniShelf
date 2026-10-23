//
//  LibraryFixture.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
//

#if DEBUG || LIBRARY_FIXTURES
    import CoreGraphics
    import DataProvider
    import Foundation
    import ImageIO
    import Kingfisher
    import Security
    import UniformTypeIdentifiers
    import os

    fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "LibraryFixture")

    /// A generated library for scale checks and the UI benchmarks; see docs-ai 026.
    ///
    /// `-library-fixture <N>` boots the real UI on N deterministic entries in an in-memory store.
    /// Library preferences, the TMDb key, What's New, review prompts, and the poster pipeline are
    /// isolated, and the app turns sync and airing reminders off, so nothing reaches the real
    /// library or iCloud.
    @MainActor
    struct LibraryFixture {
        static let launchArgument = "-library-fixture"
        static let defaultSize = 800
        /// Far above real TMDb IDs, so fixture identities can never match a real entry.
        static let firstTMDbID = 900_000_000

        /// The fixture this launch runs on, set before any shared service is created.
        private(set) static var active: LibraryFixture?

        /// Full entry details by TMDb ID, served in place of TMDb, which has no fixture IDs.
        nonisolated private static let details = OSAllocatedUnfairLock<[Int: AnimeEntryDetailDTO]>(
            initialState: [:]
        )

        /// The detail TMDb would return for a fixture entry, so the detail view shows its
        /// complete layout: hero artwork and logo, metadata, stats, cast, and staff.
        nonisolated static func detail(tmdbID: Int, language: Language) throws -> AnimeEntryDetailDTO {
            guard var detail = details.withLock({ $0[tmdbID] }) else { throw URLError(.fileDoesNotExist) }
            detail.language = language.rawValue
            return detail
        }

        let size: Int
        let defaults: UserDefaults

        static func fromLaunchArguments(
            _ arguments: [String] = ProcessInfo.processInfo.arguments
        ) -> LibraryFixture? {
            guard let index = arguments.firstIndex(of: launchArgument) else { return nil }
            let value = arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
            return LibraryFixture(size: max(0, value ?? defaultSize))
        }

        /// Starts every launch from empty fixture preferences.
        private static let defaultsSuiteName = "\(String.bundleIdentifier).library-fixture"

        private init(size: Int) {
            UserDefaults.standard.removePersistentDomain(forName: Self.defaultsSuiteName)
            self.size = size
            self.defaults = UserDefaults(suiteName: Self.defaultsSuiteName) ?? .standard
        }

        /// Seeds the store and the fixture preferences, and routes poster loading to generated images.
        func makeBootstrap() -> DataProviderBootstrapResult {
            // First, so every key storage, including each `InfoFetcher`'s, sees only the fixture
            // keychain; `-reset-tmdb-api-key` then cannot delete the real key either.
            TMDbAPIKeyStorage.defaultKeychain = Self.keychain
            Self.active = self
            let bootstrap = DataProvider.inMemoryFixtureBootstrap()
            let preferences = LibraryPreferences(defaults: defaults)
            preferences.saveCategoriesEnabled(true)
            preferences.saveCategoryStripEnabled(true)
            preferences.saveCategories(Self.categories)
            seed(bootstrap.provider)
            Self.configurePosterLoading()
            LibraryBenchmarkSignposts.isEnabled = true
            logger.info("Seeded a library fixture with \(size) entries.")
            return bootstrap
        }

        /// A keychain that always holds a placeholder TMDb key and never touches the real one.
        private static var keychain: TMDbAPIKeyStorageKeychainClient {
            TMDbAPIKeyStorageKeychainClient(
                add: { _ in errSecSuccess },
                update: { _, _ in errSecSuccess },
                delete: { _ in errSecSuccess },
                copyMatching: { _ in (errSecSuccess, Data("library-fixture".utf8) as AnyObject) }
            )
        }

        /// Reminders on the fixture defaults, with no notifications or TVMaze requests, so
        /// Settings cannot change the real subscriptions or pending notifications.
        func makeAiringReminderManager() -> AiringReminderManager {
            // A separate instance on the same suite: the manager is an actor, and the shared
            // `defaults` instance cannot be sent to it. The suite is never the app's own domain,
            // so the initializer cannot return nil.
            AiringReminderManager(
                defaults: UserDefaults(suiteName: Self.defaultsSuiteName)!,
                notificationCenter: FixtureAiringReminderCenter(),
                fetchNextEpisode: { _ in nil }
            )
        }

        // MARK: - Entries

        static let categories: [LibraryCategory] = [
            "Seasonal", "Rewatch", "Movie Night", "Classics", "Long Running", "Backlog"
        ].enumerated().map { index, name in
            LibraryCategory(id: "library-fixture-category-\(index)", name: name)
        }

        private func seed(_ provider: DataProvider) {
            var generator = SplitMix64(seed: 0xA115_4E1F)
            let context = provider.dataHandler.modelContext
            for index in 0..<size {
                context.insert(Self.makeEntry(index: index, generator: &generator))
            }
            do {
                try context.save()
            } catch {
                logger.fault("Saving the library fixture failed: \(error)")
            }
        }

        private static let referenceDate = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09

        private static func makeEntry(index: Int, generator: inout SplitMix64) -> AnimeEntry {
            let type: AnimeType = generator.chance(0.25) ? .movie : .series
            let saved = referenceDate.addingTimeInterval(-Double(index) * 36_000 - generator.unit() * 30_000)
            let entry = AnimeEntry(
                name: makeTitle(index: index, generator: &generator),
                overview: makeOverview(generator: &generator),
                onAirDate: referenceDate.addingTimeInterval(-generator.unit() * 36 * 365 * 86_400),
                type: type,
                posterPath: "/library-fixture-\(index).jpg",
                tmdbID: firstTMDbID + index,
                dateSaved: saved,
                score: generator.chance(0.6) ? Int(generator.next() % 5) + 1 : nil
            )
            // Every third scored entry gets a half star, without another generator draw.
            if index.isMultiple(of: 3), let half = entry.entryScore?.stepped(by: 1) {
                entry.setEntryScore(half)
            }
            let roll = generator.unit()
            switch roll {
            case ..<0.4:
                entry.watchStatus = .watched
                entry.dateStarted = saved.addingTimeInterval(86_400 * 3)
                entry.dateFinished = saved.addingTimeInterval(86_400 * (10 + generator.unit() * 60))
            case ..<0.55:
                entry.watchStatus = .watching
                entry.dateStarted = saved.addingTimeInterval(86_400 * 2)
            case ..<0.9:
                entry.watchStatus = .planToWatch
            default:
                entry.watchStatus = .dropped
                entry.dateStarted = saved.addingTimeInterval(86_400)
            }
            entry.favorite = generator.chance(0.12)
            entry.categoryIDs = categories.filter { _ in generator.chance(0.2) }.map(\.id)
            // Most entries have landscape artwork; the rest exercise the poster fallback.
            if index % 4 != 3 {
                entry.backdropPath = "/library-fixture-backdrop-\(index).jpg"
            }
            if type == .series {
                seedSeasons(of: entry, index: index, saved: saved)
            }
            let detail = makeDetail(for: entry, index: index)
            details.withLock { [tmdbID = entry.tmdbID] in $0[tmdbID] = detail }
            return entry
        }

        private static func makeSeasons(index: Int) -> [AnimeEntrySeasonSummaryDTO] {
            (1...(1 + index % 3)).map { seasonNumber in
                AnimeEntrySeasonSummaryDTO(
                    id: (firstTMDbID + index) * 10 + seasonNumber,
                    seasonNumber: seasonNumber,
                    title: "Season \(seasonNumber)",
                    episodeCount: seasonNumber.isMultiple(of: 2) ? 24 : 12
                )
            }
        }

        /// Gives a series one to three seasons, and a watching series progress in its latest one,
        /// so the progress controls and badges have something to show.
        ///
        /// Derived from the index rather than the generator, so the entries' other values match
        /// earlier fixtures.
        private static func seedSeasons(of entry: AnimeEntry, index: Int, saved: Date) {
            let seasonCount = 1 + index % 3
            let seasons = makeSeasons(index: index).map {
                AnimeEntrySeasonSummary(
                    id: $0.id,
                    seasonNumber: $0.seasonNumber,
                    title: $0.title,
                    episodeCount: $0.episodeCount
                )
            }
            entry.detail = AnimeEntryDetail(
                language: "en-US",
                title: entry.name,
                episodeCount: seasons.compactMap(\.episodeCount).reduce(0, +),
                seasonCount: seasonCount,
                seasons: seasons
            )
            guard entry.watchStatus == .watching else { return }
            for season in seasons {
                let episodeCount = season.episodeCount ?? 12
                let watched = season.seasonNumber < seasonCount ? episodeCount : 1 + index % (episodeCount - 1)
                entry.applyEpisodeProgressSnapshot(
                    seasonNumber: season.seasonNumber,
                    watchedThroughEpisode: watched,
                    updatedAt: saved.addingTimeInterval(86_400 * Double(2 + season.seasonNumber))
                )
            }
        }

        // MARK: - Details

        private static let givenNames = ["Aoi", "Haru", "Ren", "Mio", "Sora", "Yuki", "Kai", "Rin", "Nao", "Emi"]
        private static let familyNames = ["Tanaka", "Sato", "Mori", "Kimura", "Ishida", "Fujii", "Ono", "Hayashi"]
        private static let studios = ["Studio Lumen", "Kagerou Works", "Northwind Animation", "Hoshizora Pictures"]
        private static let seriesGenreIDs = [16, 10759, 35, 18, 10765, 9648]
        private static let movieGenreIDs = [16, 28, 12, 14, 878, 10749]
        private static let staffJobs = ["Director", "Series Composition", "Character Design", "Music"]

        /// A complete detail, drawn from its own generator so the entries' other values match
        /// earlier fixtures.
        ///
        /// Every other entry has a title logo; the rest use the text title.
        private static func makeDetail(for entry: AnimeEntry, index: Int) -> AnimeEntryDetailDTO {
            var generator = SplitMix64(seed: UInt64(entry.tmdbID))
            func pick<T>(_ values: [T]) -> T { values[Int(generator.next() % UInt64(values.count))] }
            func personName() -> String { "\(pick(givenNames)) \(pick(familyNames))" }

            let isSeries = entry.type == .series
            let seasons = isSeries ? makeSeasons(index: index) : []
            let genres = isSeries ? seriesGenreIDs : movieGenreIDs
            let personID = entry.tmdbID * 10
            return AnimeEntryDetailDTO(
                language: Language.english.rawValue,
                title: entry.name,
                subtitle: generator.chance(0.5) ? (0..<2).map { _ in pick(cjkWords) }.joined() : nil,
                overview: entry.overview,
                status: isSeries ? pick(["Ended", "Returning Series"]) : "Released",
                airDate: entry.onAirDate,
                logoImagePath: index.isMultiple(of: 2) ? "/library-fixture-logo-\(index).png" : nil,
                genreIDs: Array(genres.shuffled(using: &generator).prefix(2 + index % 2)),
                voteAverage: (60 + Double(generator.next() % 31)) / 10,
                runtimeMinutes: isSeries ? 22 + Int(generator.next() % 4) : 85 + Int(generator.next() % 46),
                episodeCount: isSeries ? seasons.compactMap(\.episodeCount).reduce(0, +) : nil,
                seasonCount: isSeries ? seasons.count : nil,
                productionCompanies: [AnimeEntryProductionCompanyDTO(id: entry.tmdbID, name: pick(studios))],
                characters: (0..<6).map { offset in
                    AnimeEntryCharacterDTO(
                        id: personID + offset,
                        characterName: pick(givenNames),
                        actorName: personName(),
                        profilePath: "/library-fixture-person-\(offset).jpg"
                    )
                },
                staff: staffJobs.enumerated().map { offset, job in
                    AnimeEntryStaffDTO(
                        id: personID + 6 + offset,
                        name: personName(),
                        role: job,
                        department: offset == 3 ? "Sound" : "Production",
                        profilePath: "/library-fixture-person-\(6 + offset).jpg",
                        jobs: [
                            AnimeEntryStaffJobDTO(
                                creditID: "library-fixture-\(entry.tmdbID)-\(offset)",
                                job: job,
                                episodeCount: seasons.compactMap(\.episodeCount).reduce(0, +)
                            )
                        ]
                    )
                },
                seasons: seasons
            )
        }

        private static let latinWords = [
            "Starlight", "Chronicle", "Blade", "Garden", "Requiem", "Horizon", "Spiral", "Academy",
            "Signal", "Ember", "Labyrinth", "Tide", "Harvest", "Paradox", "Lantern", "Voyage"
        ]
        private static let cjkWords = [
            "星の", "物語", "剣", "庭園", "鎮魂歌", "地平線", "螺旋", "学園", "信号", "残り火", "迷宮", "潮"
        ]
        private static let overviewSentences = [
            "A quiet town hides a secret that only the night shift seems to notice.",
            "Two rivals are forced to share a dormitory during the hardest exam season in decades.",
            "After the war ends, a retired pilot takes odd jobs ferrying strangers across the sea.",
            "An apprentice mage keeps a journal of every spell that goes wrong.",
            "The last train of the evening never arrives at the same station twice."
        ]

        private static func makeTitle(index: Int, generator: inout SplitMix64) -> String {
            let usesCJK = generator.chance(0.35)
            let words = usesCJK ? cjkWords : latinWords
            let wordCount = 1 + Int(generator.next() % (usesCJK ? 3 : 5))
            let title = (0..<wordCount).map { _ in words[Int(generator.next() % UInt64(words.count))] }
                .joined(separator: usesCJK ? "" : " ")
            return generator.chance(0.3) ? "\(title) \(index % 4 + 2)" : title
        }

        private static func makeOverview(generator: inout SplitMix64) -> String? {
            let sentenceCount = Int(generator.next() % 4)
            guard sentenceCount > 0 else { return nil }
            return (0..<sentenceCount).map { _ in
                overviewSentences[Int(generator.next() % UInt64(overviewSentences.count))]
            }
            .joined(separator: " ")
        }

        // MARK: - Posters

        /// Keeps the real Kingfisher path (download, decode, downsample, cache) but serves
        /// generated posters from a separate cache instead of the network.
        private static func configurePosterLoading() {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [LibraryFixturePosterProtocol.self]
            let downloader = ImageDownloader(name: "library-fixture")
            downloader.sessionConfiguration = configuration
            KingfisherManager.shared.downloader = downloader
            let cache = ImageCache(name: "library-fixture")
            cache.clearMemoryCache()
            cache.clearDiskCache()
            KingfisherManager.shared.cache = cache
        }
    }

    /// A notification center that schedules nothing and reports notifications as denied.
    struct FixtureAiringReminderCenter: AiringReminderCenter {
        func authorizationStatus() async -> AiringReminderAuthorizationStatus { .denied }
        func requestAuthorization() async throws -> Bool { false }
        func pendingRequests() async -> [AiringReminderRequest] { [] }
        func add(_ request: AiringReminderRequest) async throws {}
        func removePendingRequests(withIdentifiers identifiers: [String]) async {}
    }

    /// A deterministic generator, so every fixture launch builds the same library.
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }

        mutating func unit() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }

        mutating func chance(_ probability: Double) -> Bool {
            unit() < probability
        }
    }

    /// Serves a generated image for any request, sized like the TMDb rendition it names: a JPEG
    /// poster or backdrop, or a transparent PNG title logo.
    final class LibraryFixturePosterProtocol: URLProtocol {
        private static let posters = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])
        private static let variantCount = 8

        override class func canInit(with request: URLRequest) -> Bool { true }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let data = Self.poster(for: url)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(data.count)"]
            )
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private static func poster(for url: URL) -> Data {
            // TMDb rendition segments look like `w342`; `original` maps to a large poster.
            let width =
                url.pathComponents.lazy.compactMap { component -> Int? in
                    guard component.first == "w" else { return nil }
                    return Int(component.dropFirst())
                }
                .first ?? 1_000
            // FNV-1a: `hashValue` is seeded per process and would change posters between runs.
            let hash = url.lastPathComponent.utf8.reduce(UInt64(0xCBF2_9CE4_8422_2325)) {
                ($0 ^ UInt64($1)) &* 0x100_0000_01B3
            }
            let variant = Int(hash % UInt64(variantCount))
            let name = url.lastPathComponent
            let shape =
                name.hasPrefix("library-fixture-logo")
                ? "logo"
                : name.hasPrefix("library-fixture-backdrop") ? "backdrop" : "poster"
            let key = "\(width)-\(variant)-\(shape)"
            if let cached = posters.withLock({ $0[key] }) { return cached }
            let data =
                switch shape {
                case "logo": makeLogo(width: width, variant: variant)
                case "backdrop": makePoster(width: width, height: width * 9 / 16, variant: variant)
                default: makePoster(width: width, height: width * 3 / 2, variant: variant)
                }
            posters.withLock { $0[key] = data }
            return data
        }

        private static func makePoster(width: Int, height: Int, variant: Int) -> Data {
            guard
                let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                )
            else { return Data() }
            var generator = SplitMix64(seed: UInt64(variant + 1))
            let hue = Double(variant) / Double(variantCount)
            context.setFillColor(color(hue: hue, brightness: 0.35))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Texture so the JPEG carries detail, as real posters do.
            for _ in 0..<120 {
                let size = Double(width) * (0.05 + generator.unit() * 0.3)
                context.setFillColor(
                    color(hue: hue + generator.unit() * 0.2, brightness: 0.3 + generator.unit() * 0.6)
                )
                context.fillEllipse(
                    in: CGRect(
                        x: generator.unit() * Double(width),
                        y: generator.unit() * Double(height),
                        width: size,
                        height: size
                    )
                )
            }
            return encode(context, as: .jpeg)
        }

        /// A transparent wordmark-shaped logo: a bold line over a thinner one, like a title logo.
        private static func makeLogo(width: Int, variant: Int) -> Data {
            let height = width / 3
            guard
                let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return Data() }
            let unit = Double(height) / 10
            let lines = [
                (y: 4.5 * unit, height: 4.5 * unit, inset: 0.0, color: CGColor(gray: 1, alpha: 1)),
                (
                    y: 0.5 * unit, height: 2.5 * unit, inset: Double(width) * 0.18,
                    color: color(hue: Double(variant) / Double(variantCount), brightness: 1)
                )
            ]
            for line in lines {
                context.setFillColor(line.color)
                context.addPath(
                    CGPath(
                        roundedRect: CGRect(
                            x: line.inset, y: line.y, width: Double(width) - line.inset * 2, height: line.height),
                        cornerWidth: line.height / 3,
                        cornerHeight: line.height / 3,
                        transform: nil
                    )
                )
                context.fillPath()
            }
            return encode(context, as: .png)
        }

        private static func encode(_ context: CGContext, as type: UTType) -> Data {
            guard let image = context.makeImage() else { return Data() }
            let data = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    data, type.identifier as CFString, 1, nil)
            else { return Data() }
            CGImageDestinationAddImage(
                destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            CGImageDestinationFinalize(destination)
            return data as Data
        }

        private static func color(hue: Double, brightness: Double) -> CGColor {
            // A simple hue wheel; exact colors don't matter, only that variants differ.
            let hue = hue.truncatingRemainder(dividingBy: 1) * 6
            let x = 1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1)
            let (red, green, blue): (Double, Double, Double) =
                switch Int(hue) {
                case 0: (1, x, 0)
                case 1: (x, 1, 0)
                case 2: (0, 1, x)
                case 3: (0, x, 1)
                case 4: (x, 0, 1)
                default: (1, 0, x)
                }
            return CGColor(red: red * brightness, green: green * brightness, blue: blue * brightness, alpha: 1)
        }
    }
#endif
