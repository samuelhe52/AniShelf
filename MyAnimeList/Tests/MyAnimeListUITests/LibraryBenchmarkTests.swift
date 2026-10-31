//
//  LibraryBenchmarkTests.swift
//  MyAnimeListUITests
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
//

import XCTest

/// Library performance benchmarks on a generated fixture library; see docs-ai 026.
///
/// Run them with `make bench-sim`, which builds Release with `LIBRARY_FIXTURES` and sets the
/// fixture size through `LIBRARY_FIXTURE_SIZE`. A Debug run works but measures Debug code.
/// The interaction signposts come from `LibraryBenchmarkSignposts` in the app.
final class LibraryBenchmarkTests: XCTestCase {
    private static let subsystem = "com.samuelhe.MyAnimeList"
    private static let category = "LibraryBenchmark"
    private static let launchTimeout: TimeInterval = 60

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Selection

    func testSelectionToggleList() throws {
        let app = launch(style: "list")
        let rows = waitForContainer("library-list", in: app).cells
        enterSelection(in: app)
        measureTaps(on: rows)
    }

    func testSelectionToggleGrid() throws {
        let app = launch(style: "grid")
        _ = waitForContainer("library-grid", in: app)
        enterSelection(in: app)
        measureTaps(on: gridItems(in: app))
    }

    // MARK: - Scrolling

    func testScrollList() throws {
        measureScrolling(style: "list", container: "library-list", horizontal: false)
    }

    func testScrollGrid() throws {
        measureScrolling(style: "grid", container: "library-grid", horizontal: false)
    }

    func testScrollGallery() throws {
        measureScrolling(style: "gallery", container: "library-gallery", horizontal: true)
    }

    // MARK: - Display changes

    func testCategorySwitchList() throws {
        measureCategorySwitches(style: "list", container: "library-list")
    }

    func testCategorySwitchGrid() throws {
        measureCategorySwitches(style: "grid", container: "library-grid")
    }

    func testBatchFavoriteList() throws {
        let app = launch(style: "list")
        let rows = waitForContainer("library-list", in: app).cells
        let favoriteButton = app.buttons["library-batch-favorite"].firstMatch
        // The signpost metrics count only batch-action intervals, so selecting rows inside the
        // block adds nothing. (`.manuallyStart` dropped most iterations' intervals.)
        measure(metrics: signposts("BatchAction", "BatchActionCommit"), options: measureOptions) {
            // Favorite ends selection, so each iteration selects again.
            enterSelection(in: app)
            for index in 0..<6 {
                rows.element(boundBy: index).tap()
            }
            XCTAssertTrue(favoriteButton.waitForExistence(timeout: 10))
            XCTAssertTrue(favoriteButton.isEnabled, "No rows were selected")
            favoriteButton.tap()
            settle(seconds: 1)  // The long batch iteration needed a full second.
        }
    }

    // MARK: - Helpers

    private var fixtureSize: Int {
        Int(ProcessInfo.processInfo.environment["LIBRARY_FIXTURE_SIZE"] ?? "") ?? 800
    }

    private var measureOptions: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        // `make bench-quick` runs fewer iterations; see `BENCH_ITERATIONS` in the Makefile.
        let iterations = ProcessInfo.processInfo.environment["LIBRARY_BENCH_ITERATIONS"] ?? ""
        options.iterationCount = Int(iterations) ?? 10
        return options
    }

    private func launch(style: String) -> XCUIApplication {
        let app = XCUIApplication()
        // English labels and a fixed layout, so runs match. Fixture launches ignore restored
        // window state, and the scroll position is never persisted.
        app.launchArguments = [
            "-library-fixture", "\(fixtureSize)",
            "-LibraryViewStyle", style,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        // Without `LIBRARY_FIXTURES` (for example, the benchmark scheme run from Xcode in
        // Release), the app ignores the fixture argument and opens the real library. Stop
        // before touching anything unless the fixture-only frame-stats element is present.
        let fixtureMarker = app.descendants(matching: .any)["library-frame-stats"].firstMatch
        guard fixtureMarker.waitForExistence(timeout: Self.launchTimeout) else {
            app.terminate()
            XCTFail("The library fixture is not active; run the benchmarks with `make bench-sim`.")
            return app
        }
        return app
    }

    private func waitForContainer(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let container = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(
            container.waitForExistence(timeout: Self.launchTimeout),
            "Missing \(identifier):\n\(app.debugDescription)"
        )
        // Let the first posters load so the first iteration is not an outlier.
        sleep(2)
        return container
    }

    private func gridItems(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "library-grid-item")
    }

    private func enterSelection(in app: XCUIApplication) {
        let button = app.buttons["Anime Multi-selection"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing Select:\n\(app.debugDescription)")
        button.tap()
    }

    /// Keeps the iteration open briefly after a measured action.
    ///
    /// Without it, XCTest sometimes
    /// dropped an interval the app had emitted and, with it, the whole iteration (seen in the
    /// batch test, and in category switches at 2,000 entries). The cause is unconfirmed.
    private func settle(seconds: TimeInterval = 0.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func signposts(_ names: String...) -> [XCTMetric] {
        names.map { XCTOSSignpostMetric(subsystem: Self.subsystem, category: Self.category, name: $0) }
    }

    /// Taps the first few visible entries in turn; each tap toggles one selection.
    private func measureTaps(on elements: XCUIElementQuery) {
        XCTAssertTrue(elements.firstMatch.waitForExistence(timeout: 10))
        var tapIndex = 0
        measure(metrics: signposts("SelectionUpdate", "SelectionUpdateCommit"), options: measureOptions) {
            elements.element(boundBy: tapIndex % 4).tap()
            settle()
            tapIndex += 1
        }
    }

    /// Alternates direction so every size scrolls the same distance over the same rows.
    private func measureScrolling(style: String, container identifier: String, horizontal: Bool) {
        let app = launch(style: style)
        let container = waitForContainer(identifier, in: app)
        var forward = true
        // The simulator records no system scroll-hitch metrics; see `FrameStatsMetric`.
        measure(metrics: [FrameStatsMetric(app: app)], options: measureOptions) {
            switch (horizontal, forward) {
            case (true, true): container.swipeLeft(velocity: .fast)
            case (true, false): container.swipeRight(velocity: .fast)
            case (false, true): container.swipeUp(velocity: .fast)
            case (false, false): container.swipeDown(velocity: .fast)
            }
            forward.toggle()
        }
    }

    private func measureCategorySwitches(style: String, container identifier: String) {
        let app = launch(style: style)
        _ = waitForContainer(identifier, in: app)
        let categories = ["Seasonal", "Rewatch", "Movie Night", "All"]
        var index = 0
        measure(
            metrics: signposts("DisplayUpdate", "DisplayUpdateCommit") + [FrameStatsMetric(app: app)],
            options: measureOptions
        ) {
            app.buttons[categories[index % categories.count]].firstMatch.tap()
            settle()
            index += 1
        }
    }
}

/// Main-thread hitches over one iteration, from the fixture app's `LibraryFrameMonitor` totals.
///
/// Reports hitch time per second of the iteration (Apple's hitch-time ratio, in ms/s) and the
/// number of late frames. The totals are read through an accessibility element before and after
/// the measured block, outside the measured window.
final class FrameStatsMetric: NSObject, XCTMetric {
    private let app: XCUIApplication
    private var start: [String: Double] = [:]
    private var end: [String: Double] = [:]

    init(app: XCUIApplication) {
        self.app = app
    }

    func copy(with zone: NSZone? = nil) -> Any {
        FrameStatsMetric(app: app)
    }

    func willBeginMeasuring() {
        start = readTotals()
    }

    func didStopMeasuring() {
        end = readTotals()
    }

    func reportMeasurements(
        from startTime: XCTPerformanceMeasurementTimestamp,
        to endTime: XCTPerformanceMeasurementTimestamp
    ) throws -> [XCTPerformanceMeasurement] {
        func delta(_ key: String) -> Double { (end[key] ?? 0) - (start[key] ?? 0) }
        let elapsed = max(delta("time"), 0.001)
        return [
            XCTPerformanceMeasurement(
                identifier: "com.samuelhe.anishelf.hitch-time-ratio",
                displayName: "Hitch Time Ratio",
                doubleValue: delta("hitchTime") * 1_000 / elapsed,
                unitSymbol: "ms per s",
                polarity: .prefersSmaller
            ),
            XCTPerformanceMeasurement(
                identifier: "com.samuelhe.anishelf.hitch-count",
                displayName: "Hitch Count",
                doubleValue: delta("hitches"),
                unitSymbol: "hitches",
                polarity: .prefersSmaller
            )
        ]
    }

    private func readTotals() -> [String: Double] {
        let element = app.descendants(matching: .any)["library-frame-stats"].firstMatch
        guard element.waitForExistence(timeout: 5), let value = element.value as? String else {
            XCTFail("Missing frame stats element")
            return [:]
        }
        var totals: [String: Double] = [:]
        for pair in value.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, let number = Double(parts[1]) {
                totals[String(parts[0])] = number
            }
        }
        return totals
    }
}
