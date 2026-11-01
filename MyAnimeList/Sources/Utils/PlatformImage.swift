//
//  PlatformImage.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/15.
//

import SwiftUI

#if os(macOS)
    import AppKit

    typealias PlatformImage = NSImage

    extension NSImage {
        /// Export calculations use pixels, independent of the image's logical point size.
        var pixelSize: CGSize {
            guard let cgImage = exportCGImage else { return size }
            return CGSize(width: cgImage.width, height: cgImage.height)
        }

        var exportCGImage: CGImage? {
            cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }
#else
    import UIKit

    typealias PlatformImage = UIImage

    extension UIImage {
        var pixelSize: CGSize { CGSize(width: size.width * scale, height: size.height * scale) }
        var exportCGImage: CGImage? { cgImage }
    }
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
            self.init(nsImage: platformImage)
        #else
            self.init(uiImage: platformImage)
        #endif
    }
}
