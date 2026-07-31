//
//  SharingCardExportPipeline.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/11/22.
//

import Foundation
import ImageIO
import Kingfisher
import SwiftUI
import UniformTypeIdentifiers

struct SharingCardExportResult {
    let imageURL: URL
    let pixelSize: CGSize
}

enum SharingCardExportStyle: Hashable, Sendable {
    case roundedPNG
    case squareJPEG

    var usesRoundedCorners: Bool {
        self == .roundedPNG
    }

    var fileExtension: String {
        switch self {
        case .roundedPNG:
            return "png"
        case .squareJPEG:
            return "jpg"
        }
    }
}

enum SharingCardExportSize: String, CaseIterable, Hashable, Sendable {
    case light
    case medium
    case full

    var localizedName: LocalizedStringResource {
        switch self {
        case .light:
            return "Light"
        case .medium:
            return "Medium"
        case .full:
            return "Full"
        }
    }

    var maximumPixelWidth: Int? {
        switch self {
        case .light:
            return 1_080
        case .medium:
            return 1_500
        case .full:
            return nil
        }
    }

    func outputPixelWidth(forSourceWidth sourcePixelWidth: Int) -> Int {
        let validSourceWidth = max(sourcePixelWidth, 1)
        guard let maximumPixelWidth else { return validSourceWidth }
        return min(validSourceWidth, maximumPixelWidth)
    }
}

fileprivate struct SharingCardWidthDownsamplingProcessor: ImageProcessor {
    let maximumPixelWidth: Int

    var identifier: String {
        "com.samuelhe.AniShelf.SharingCardWidthDownsamplingProcessor(\(maximumPixelWidth))"
    }

    func process(
        item: ImageProcessItem,
        options: KingfisherParsedOptionsInfo
    ) -> KFCrossPlatformImage? {
        guard let sourcePixelSize = sourcePixelSize(for: item) else { return nil }
        let targetWidth = CGFloat(maximumPixelWidth)
        let targetSize = CGSize(
            width: targetWidth,
            height: targetWidth * sourcePixelSize.height / max(sourcePixelSize.width, 1)
        )
        return DownsamplingImageProcessor(size: targetSize).process(item: item, options: options)
    }

    private func sourcePixelSize(for item: ImageProcessItem) -> CGSize? {
        switch item {
        case .image(let image):
            return CGSize(
                width: image.size.width * image.scale,
                height: image.size.height * image.scale
            )
        case .data(let data):
            guard
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
            else { return nil }

            let rawSize = CGSize(width: width.doubleValue, height: height.doubleValue)
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
            if let orientation, 5...8 ~= orientation {
                return CGSize(width: rawSize.height, height: rawSize.width)
            }
            return rawSize
        }
    }
}

/// Renders poster previews using SwiftUI's ImageRenderer while
/// normalizing color space and controlling output size/quality.
@MainActor
struct SharingCardExportPipeline {
    /// Logical width (points) the SwiftUI poster layout targets before scaling.
    private let baseWidth: CGFloat
    /// Compression ratio applied when persisting the rendered JPEG.
    private let jpegQuality: CGFloat

    /// Creates an export pipeline tuned for the given layout width and quality.
    init(
        baseWidth: CGFloat,
        jpegQuality: CGFloat
    ) {
        self.baseWidth = baseWidth
        self.jpegQuality = jpegQuality
    }

    /// Fetches an image through Kingfisher and converts it to sRGB for
    /// consistent downstream rendering.
    func loadImage(from url: URL, exportSize: SharingCardExportSize) async throws -> UIImage {
        let result = try await KingfisherManager.shared.retrieveImage(
            with: url,
            options: imageLoadingOptions(for: exportSize)
        )
        try Task.checkCancellation()
        let image = try await SharingCardExportPipeline.convertToSRGB(result.image)
        try Task.checkCancellation()
        return image
    }

    /// Renders the SwiftUI sharing card to disk, returning the file
    /// location for later sharing.
    func renderPoster(
        image: UIImage,
        metadata: PosterMetadata,
        aspectRatio: CGFloat,
        fileName: String,
        style: SharingCardExportStyle,
        exportSize: SharingCardExportSize
    ) async throws -> SharingCardExportResult {
        let baseHeight = baseWidth / max(aspectRatio, 0.0001)
        let sourcePixelWidth = Int((image.size.width * image.scale).rounded())
        let outputPixelWidth = exportSize.outputPixelWidth(forSourceWidth: sourcePixelWidth)
        let scaleFactor = CGFloat(outputPixelWidth) / baseWidth

        let renderer = ImageRenderer(
            content: SharingCardView(
                image: image,
                title: metadata.title,
                subtitle: metadata.subtitle,
                detail: metadata.detail,
                aspectRatio: aspectRatio,
                usesRoundedCorners: style.usesRoundedCorners,
                showsShadow: false
            )
            .frame(width: baseWidth, height: baseHeight)
        )
        renderer.scale = scaleFactor
        renderer.isOpaque = !style.usesRoundedCorners

        guard let renderedImage = renderer.uiImage else {
            throw SharingCardRenderError.renderFailed
        }

        let normalizedImage = try await SharingCardExportPipeline.convertToSRGB(renderedImage)
        try Task.checkCancellation()
        let imageURL = try await persist(normalizedImage, fileName: fileName, style: style)
        let pixelSize =
            normalizedImage.cgImage.map {
                CGSize(width: $0.width, height: $0.height)
            }
            ?? CGSize(
                width: normalizedImage.size.width * normalizedImage.scale,
                height: normalizedImage.size.height * normalizedImage.scale
            )
        return SharingCardExportResult(imageURL: imageURL, pixelSize: pixelSize)
    }

    private func imageLoadingOptions(
        for exportSize: SharingCardExportSize
    ) -> KingfisherOptionsInfo {
        guard let maximumPixelWidth = exportSize.maximumPixelWidth else { return [] }
        return [
            .processor(
                SharingCardWidthDownsamplingProcessor(maximumPixelWidth: maximumPixelWidth)
            ),
            .scaleFactor(1)
        ]
    }

    /// Persists the rendered image to a temporary file on a background queue.
    private func persist(
        _ image: UIImage,
        fileName: String,
        style: SharingCardExportStyle
    ) async throws -> URL {
        let persistenceTask = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(fileName)

            guard let cgImage = image.cgImage else {
                throw SharingCardRenderError.invalidImage
            }

            let type: UTType
            let options: [CFString: Any]
            switch style {
            case .roundedPNG:
                type = .png
                options = [:]
            case .squareJPEG:
                type = .jpeg
                options = [
                    kCGImageDestinationLossyCompressionQuality: jpegQuality
                ]
            }

            guard
                let destination = CGImageDestinationCreateWithURL(
                    fileURL as CFURL,
                    type.identifier as CFString,
                    1,
                    nil
                )
            else {
                throw SharingCardRenderError.persistFailed
            }

            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

            guard CGImageDestinationFinalize(destination) else {
                try? FileManager.default.removeItem(at: fileURL)
                throw SharingCardRenderError.persistFailed
            }

            do {
                try Task.checkCancellation()
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                throw error
            }
            return fileURL
        }

        return try await withTaskCancellationHandler {
            try await persistenceTask.value
        } onCancel: {
            persistenceTask.cancel()
        }
    }

    nonisolated private static let srgbColorSpace: CGColorSpace =
        CGColorSpace(name: CGColorSpace.sRGB)!
    nonisolated private static let ciContext: CIContext = CIContext(options: [
        .workingColorSpace: SharingCardExportPipeline.srgbColorSpace,
        .outputColorSpace: SharingCardExportPipeline.srgbColorSpace
    ])

    /// Forces any UIImage into sRGB so colors match across devices/exports.
    nonisolated private static func convertToSRGB(_ image: UIImage) async throws -> UIImage {
        let conversionTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let convertedImage = convertToSRGBSynchronously(image)
            try Task.checkCancellation()
            return convertedImage
        }

        return try await withTaskCancellationHandler {
            try await conversionTask.value
        } onCancel: {
            conversionTask.cancel()
        }
    }

    nonisolated private static func convertToSRGBSynchronously(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        let extent = ciImage.extent.integral
        guard
            let cgImage = SharingCardExportPipeline
                .ciContext
                .createCGImage(
                    ciImage,
                    from: extent,
                    format: .RGBA8,
                    colorSpace: SharingCardExportPipeline.srgbColorSpace
                )
        else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

/// Identity of a render request across poster, metadata, format, and size inputs.
struct SharingCardRenderTrigger: Hashable {
    let posterURL: URL?
    let language: Language
    let exportStyle: SharingCardExportStyle
    let exportSize: SharingCardExportSize
}

/// Bundle of attributed strings that decorate the rendered sharing poster.
struct PosterMetadata {
    let title: AttributedString
    let subtitle: AttributedString?
    let detail: String?
}

/// Errors that can occur while rendering or persisting the sharing poster.
enum SharingCardRenderError: LocalizedError {
    case renderFailed
    case persistFailed
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "Unable to render poster preview."
        case .persistFailed:
            return "Unable to persist rendered poster to disk."
        case .invalidImage:
            return "Poster data is invalid."
        }
    }
}
