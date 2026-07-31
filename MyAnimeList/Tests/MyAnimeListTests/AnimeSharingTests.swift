//
//  AnimeSharingTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import Foundation
import ImageIO
import SwiftUI
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import DataProvider
@testable import MyAnimeList

struct AnimeSharingTests {
    @Test func exportSizeTiersCapWidthWithoutUpscaling() {
        #expect(SharingCardExportSize.light.outputPixelWidth(forSourceWidth: 700) == 700)
        #expect(SharingCardExportSize.medium.outputPixelWidth(forSourceWidth: 700) == 700)
        #expect(SharingCardExportSize.full.outputPixelWidth(forSourceWidth: 700) == 700)

        #expect(SharingCardExportSize.light.outputPixelWidth(forSourceWidth: 1_080) == 1_080)
        #expect(SharingCardExportSize.medium.outputPixelWidth(forSourceWidth: 1_080) == 1_080)
        #expect(SharingCardExportSize.full.outputPixelWidth(forSourceWidth: 1_080) == 1_080)

        #expect(SharingCardExportSize.light.outputPixelWidth(forSourceWidth: 1_081) == 1_080)
        #expect(SharingCardExportSize.medium.outputPixelWidth(forSourceWidth: 1_081) == 1_081)
        #expect(SharingCardExportSize.full.outputPixelWidth(forSourceWidth: 1_081) == 1_081)

        #expect(SharingCardExportSize.light.outputPixelWidth(forSourceWidth: 1_500) == 1_080)
        #expect(SharingCardExportSize.medium.outputPixelWidth(forSourceWidth: 1_500) == 1_500)
        #expect(SharingCardExportSize.full.outputPixelWidth(forSourceWidth: 1_500) == 1_500)

        #expect(SharingCardExportSize.light.outputPixelWidth(forSourceWidth: 1_499) == 1_080)
        #expect(SharingCardExportSize.medium.outputPixelWidth(forSourceWidth: 1_499) == 1_499)
        #expect(SharingCardExportSize.full.outputPixelWidth(forSourceWidth: 1_499) == 1_499)

        #expect(SharingCardExportSize.light.outputPixelWidth(forSourceWidth: 1_501) == 1_080)
        #expect(SharingCardExportSize.medium.outputPixelWidth(forSourceWidth: 1_501) == 1_500)
        #expect(SharingCardExportSize.full.outputPixelWidth(forSourceWidth: 1_501) == 1_501)

        #expect(SharingCardExportSize.light.outputPixelWidth(forSourceWidth: 2_000) == 1_080)
        #expect(SharingCardExportSize.medium.outputPixelWidth(forSourceWidth: 2_000) == 1_500)
        #expect(SharingCardExportSize.full.outputPixelWidth(forSourceWidth: 2_000) == 2_000)
    }

    @Test func renderTriggerIncludesExportSize() {
        let posterURL = URL(string: "https://example.com/poster.jpg")
        let light = SharingCardRenderTrigger(
            posterURL: posterURL,
            language: .english,
            exportStyle: .roundedPNG,
            exportSize: .light
        )
        let medium = SharingCardRenderTrigger(
            posterURL: posterURL,
            language: .english,
            exportStyle: .roundedPNG,
            exportSize: .medium
        )
        let full = SharingCardRenderTrigger(
            posterURL: posterURL,
            language: .english,
            exportStyle: .roundedHEIC,
            exportSize: .full
        )

        #expect(Set([light, medium, full]).count == 3)
    }

    @Test func roundedCodecsShareVisualRenderIdentity() {
        let posterURL = URL(string: "https://example.com/poster.jpg")
        let png = SharingCardRenderTrigger(
            posterURL: posterURL,
            language: .english,
            exportStyle: .roundedPNG,
            exportSize: .full
        )
        let heic = SharingCardRenderTrigger(
            posterURL: posterURL,
            language: .english,
            exportStyle: .roundedHEIC,
            exportSize: .full
        )
        let jpeg = SharingCardRenderTrigger(
            posterURL: posterURL,
            language: .english,
            exportStyle: .squareJPEG,
            exportSize: .full
        )

        #expect(png != heic)
        #expect(png.visualRenderKey == heic.visualRenderKey)
        #expect(png.visualRenderKey != jpeg.visualRenderKey)
    }

    @Test @MainActor func sharingViewModelDefaultsToMediumExportSize() {
        let suiteName = "AnimeSharingTests.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = AnimeSharingViewModel(entry: .frieren, defaults: defaults)

        #expect(viewModel.exportSize == .medium)
        #expect(viewModel.roundedExportFormat == .png)
        #expect(viewModel.renderTrigger.exportSize == .medium)
        #expect(viewModel.renderTrigger.exportStyle == .roundedPNG)
    }

    @Test @MainActor func enabledSharingMemoryWithoutStoredLanguageUsesAppPreference() {
        let suiteName = "AnimeSharingTests.missingLanguage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: .rememberShareSheetSettings)
        let entry = AnimeEntry(
            name: "Test",
            nameTranslations: [
                Language.english.rawValueWithRegion: "Test",
                Language.japanese.rawValueWithRegion: "テスト",
            ],
            type: .series,
            tmdbID: 91_000
        )
        let viewModel = AnimeSharingViewModel(entry: entry, defaults: defaults)

        #expect(viewModel.hasRestoredRememberedLanguage == false)
        viewModel.applyPreferredLanguage(
            .japanese,
            respectingCurrentSelection: viewModel.hasRestoredRememberedLanguage
        )
        #expect(viewModel.selectedLanguage == .japanese)
    }

    @Test @MainActor func sharingViewModelRestoresAndPersistsRememberedSettings() {
        let suiteName = "AnimeSharingTests.remembered.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: .rememberShareSheetSettings)
        defaults.set(Language.japanese.rawValue, forKey: .shareSheetLanguage)
        defaults.set(false, forKey: .shareSheetUsesRoundedCorners)
        defaults.set(SharingCardRoundedExportFormat.heic.rawValue, forKey: .shareSheetRoundedExportFormat)
        defaults.set(SharingCardExportSize.full.rawValue, forKey: .shareSheetExportSize)

        let viewModel = AnimeSharingViewModel(entry: .frieren, defaults: defaults)

        #expect(viewModel.hasRestoredRememberedLanguage == true)
        #expect(viewModel.selectedLanguage == .japanese)
        #expect(viewModel.usesRoundedCorners == false)
        #expect(viewModel.roundedExportFormat == .heic)
        #expect(viewModel.exportSize == .full)
        #expect(viewModel.renderTrigger.exportStyle == .squareJPEG)

        viewModel.usesRoundedCorners = true
        viewModel.exportSize = .light

        #expect(defaults.bool(forKey: .shareSheetUsesRoundedCorners) == true)
        #expect(defaults.string(forKey: .shareSheetExportSize) == SharingCardExportSize.light.rawValue)
        #expect(viewModel.renderTrigger.exportStyle == .roundedHEIC)
    }

    @Test func disabledSharingMemoryUsesDefaultsAndResetClearsOnlyRememberedValues() {
        let suiteName = "AnimeSharingTests.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Language.japanese.rawValue, forKey: .shareSheetLanguage)
        defaults.set(false, forKey: .shareSheetUsesRoundedCorners)
        defaults.set(SharingCardRoundedExportFormat.heic.rawValue, forKey: .shareSheetRoundedExportFormat)
        defaults.set(SharingCardExportSize.full.rawValue, forKey: .shareSheetExportSize)

        let preferences = AnimeSharingPreferences(defaults: defaults)
        let settings = preferences.load(defaultLanguage: .chinese)

        #expect(settings == .defaultValue(language: .chinese))
        preferences.resetRememberedSettings()
        #expect(defaults.object(forKey: .shareSheetLanguage) == nil)
        #expect(defaults.object(forKey: .shareSheetUsesRoundedCorners) == nil)
        #expect(defaults.object(forKey: .shareSheetRoundedExportFormat) == nil)
        #expect(defaults.object(forKey: .shareSheetExportSize) == nil)
    }

    @Test @MainActor func unavailableRememberedLanguageFallsBackWithoutReplacingPreference() {
        let suiteName = "AnimeSharingTests.languageFallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: .rememberShareSheetSettings)
        defaults.set(Language.chinese.rawValue, forKey: .shareSheetLanguage)
        let entry = AnimeEntry(
            name: "Test",
            nameTranslations: [Language.english.rawValueWithRegion: "Test"],
            type: .series,
            tmdbID: 91_001
        )

        let viewModel = AnimeSharingViewModel(
            entry: entry,
            defaultLanguage: .english,
            defaults: defaults
        )
        viewModel.exportSize = .light

        #expect(viewModel.hasRestoredRememberedLanguage == false)
        #expect(viewModel.selectedLanguage == .english)
        #expect(defaults.string(forKey: .shareSheetLanguage) == Language.chinese.rawValue)
    }

    @Test func sharingMemoryKeysStayDeviceLocal() {
        let keys: [String] = [
            .rememberShareSheetSettings,
            .shareSheetLanguage,
            .shareSheetUsesRoundedCorners,
            .shareSheetRoundedExportFormat,
            .shareSheetExportSize
        ]

        #expect(keys.allSatisfy { !String.cloudSyncedPreferenceKeys.contains($0) })
        #expect(keys.allSatisfy { !String.allPreferenceKeys.contains($0) })
    }

    @Test @MainActor func roundedExportUsesPNGAndPreservesTransparentCorners() async throws {
        let result = try await render(style: .roundedPNG, exportSize: .medium)
        defer { try? FileManager.default.removeItem(at: result.imageURL) }

        let source = try #require(CGImageSourceCreateWithURL(result.imageURL as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(result.imageURL.pathExtension == "png")
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        #expect(result.pixelSize == CGSize(width: 180, height: 270))
        #expect(cornerAlpha(of: image) == 0)
    }

    @Test @MainActor func squareExportUsesJPEGAndOpaqueCorners() async throws {
        let result = try await render(style: .squareJPEG, exportSize: .medium)
        defer { try? FileManager.default.removeItem(at: result.imageURL) }

        let source = try #require(CGImageSourceCreateWithURL(result.imageURL as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(result.imageURL.pathExtension == "jpg")
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        #expect(result.pixelSize == CGSize(width: 180, height: 270))
        #expect(cornerAlpha(of: image) == 255)
    }

    @Test @MainActor func roundedExportUsesHEICAndPreservesTransparentCorners() async throws {
        let result = try await render(style: .roundedHEIC, exportSize: .medium)
        defer { try? FileManager.default.removeItem(at: result.imageURL) }

        let source = try #require(CGImageSourceCreateWithURL(result.imageURL as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(result.imageURL.pathExtension == "heic")
        #expect(CGImageSourceGetType(source) as String? == UTType.heic.identifier)
        #expect(result.pixelSize == CGSize(width: 180, height: 270))
        #expect(cornerAlpha(of: image) == 0)
    }

    @Test @MainActor func exportDoesNotUpscaleSmallerSources() async throws {
        let result = try await render(
            style: .squareJPEG,
            exportSize: .medium,
            sourceSize: CGSize(width: 60, height: 90)
        )
        defer { try? FileManager.default.removeItem(at: result.imageURL) }

        #expect(result.pixelSize == CGSize(width: 60, height: 90))
    }

    @MainActor
    private func render(
        style: SharingCardExportStyle,
        exportSize: SharingCardExportSize,
        sourceSize: CGSize = CGSize(width: 180, height: 270)
    ) async throws -> SharingCardExportResult {
        let layoutSize = CGSize(width: 90, height: 135)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sourceImage = UIGraphicsImageRenderer(size: sourceSize, format: format).image { context in
            UIColor.systemBlue.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: sourceSize))
        }
        let pipeline = SharingCardExportPipeline(
            baseWidth: layoutSize.width,
            jpegQuality: 0.9,
            heicQuality: 0.95
        )
        let fileName = "sharing-card-export-test-\(UUID().uuidString).\(style.fileExtension)"

        return try await pipeline.renderPoster(
            image: sourceImage,
            metadata: PosterMetadata(
                title: AttributedString("Test"),
                subtitle: nil,
                detail: "2026 • TV SERIES"
            ),
            aspectRatio: layoutSize.width / layoutSize.height,
            fileName: fileName,
            style: style,
            exportSize: exportSize
        )
    }

    private func cornerAlpha(of image: CGImage) -> UInt8 {
        guard let corner = image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) else {
            return 0
        }

        var pixel: [UInt8] = [0, 0, 0, 0]
        guard
            let context = CGContext(
                data: &pixel,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return 0 }
        context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel[3]
    }
}

