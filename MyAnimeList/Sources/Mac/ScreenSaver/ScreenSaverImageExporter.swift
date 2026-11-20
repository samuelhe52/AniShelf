//
//  ScreenSaverImageExporter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

#if os(macOS)
    import CryptoKit
    import Foundation
    import ImageIO
    import Kingfisher
    import ScreenSaverKit
    import UniformTypeIdentifiers

    struct ScreenSaverImageExporter {
        enum Request: Hashable {
            case poster(TMDbImage)
            case backdrop(URL)
            case logo(TMDbImage)

            fileprivate var recipe: (url: URL, processor: any ImageProcessor, type: UTType) {
                switch self {
                case .poster(let image): (image.url, image.processor, .heic)
                case .backdrop(let url):
                    (url, LibraryImageProcessorFactory.processor(for: url, maxPixelDimension: 2_560), .heic)
                case .logo(let image): (image.url, image.processor, .png)
                }
            }

            var filename: String {
                let (url, processor, type) = recipe
                let identity = [url.absoluteString, processor.identifier, type.identifier].joined(separator: "\0")
                let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
                return "\(hash).\(type == .heic ? "heic" : "png")"
            }
        }

        struct Image: Sendable {
            let filename: String
            let pixelSize: ScreenSaverManifest.Entry.PixelSize

            var path: String { "\(ScreenSaverSnapshotReader.imagesDirectoryName)/\(filename)" }

            nonisolated static func read(from url: URL) -> Self? {
                guard
                    let source = CGImageSourceCreateWithURL(
                        url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                    let width = properties[kCGImagePropertyPixelWidth] as? Int, width > 0,
                    let height = properties[kCGImagePropertyPixelHeight] as? Int, height > 0
                else { return nil }
                return Self(filename: url.lastPathComponent, pixelSize: .init(width: width, height: height))
            }
        }

        enum ExportError: Error {
            case invalidImage
            case encodingFailed
        }

        static func export(_ request: Request, to directory: URL) async throws -> Image {
            let (url, processor, type) = request.recipe
            let filename = request.filename
            let result = try await KingfisherManager.shared.retrieveImage(
                with: url,
                options: [.processor(processor), .scaleFactor(1), .cacheMemoryOnly]
            )
            try Task.checkCancellation()
            guard let image = result.image.exportCGImage else { throw ExportError.invalidImage }

            let encoding = Task.detached(priority: .utility) {
                try encode(image, type: type, filename: filename, to: directory)
            }
            return try await withTaskCancellationHandler {
                try await encoding.value
            } onCancel: {
                encoding.cancel()
            }
        }

        nonisolated private static func encode(
            _ image: CGImage, type: UTType, filename: String, to directory: URL
        ) throws -> Image {
            try Task.checkCancellation()
            let buffer = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(buffer, type.identifier as CFString, 1, nil) else {
                throw ExportError.encodingFailed
            }
            let options = type == .heic ? [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary : nil
            CGImageDestinationAddImage(destination, image, options)
            guard CGImageDestinationFinalize(destination) else {
                throw ExportError.encodingFailed
            }
            try Task.checkCancellation()
            try (buffer as Data).write(to: directory.appending(component: filename), options: .atomic)
            return Image(filename: filename, pixelSize: .init(width: image.width, height: image.height))
        }
    }
#endif
