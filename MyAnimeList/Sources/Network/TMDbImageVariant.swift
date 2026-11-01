//
//  TMDbImageVariant.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/30.
//

import CoreGraphics
import Foundation
import Kingfisher
import TMDb

/// Every cached size of a TMDb image the library displays.
///
/// Kingfisher keys its caches on URL plus processor identifier. A variant fixes both: the TMDb
/// rendition in the URL and the decoded bitmap's size. Display, prefetch, and cache removal all
/// derive from these cases, so they cannot disagree. To show an image at a new size, pick an
/// existing variant whose `maxPixelDimension` covers the frame at screen scale, or add a case.
enum TMDbImageVariant: CaseIterable, Hashable, Sendable {
    /// List rows, grid cells, and the other small library posters.
    case posterThumbnail
    /// The gallery card and entry previews.
    case posterFull
    case backdrop
    case logo
    case profile
    case still

    var role: TMDbImageRole {
        switch self {
        case .posterThumbnail, .posterFull: .poster
        case .backdrop: .backdrop
        case .logo: .logo
        case .profile: .profile
        case .still: .still
        }
    }

    /// The TMDb size requested; it must be in the role's catalog in
    /// `ImagesConfiguration.tmdbStandardFallback`.
    var rendition: ImageSize {
        switch self {
        case .posterThumbnail: .width(500)
        case .posterFull: .original
        case .backdrop: .width(1_280)
        case .logo: .width(500)
        case .profile: .width(185)
        case .still: .width(300)
        }
    }

    /// The longest edge, in pixels, of the decoded and cached bitmap.
    var maxPixelDimension: CGFloat {
        switch self {
        case .posterThumbnail: 540
        case .posterFull: 1_500
        case .backdrop: 1_200
        case .logo: 500
        case .profile: 278
        case .still: 300
        }
    }

    func processor(for url: URL) -> any ImageProcessor {
        LibraryImageProcessorFactory.processor(for: url, maxPixelDimension: maxPixelDimension)
    }
}

/// A TMDb image URL paired with the variant it is displayed and cached as.
struct TMDbImage: Hashable, Sendable {
    let url: URL
    let variant: TMDbImageVariant

    /// Resolves a persisted TMDb `file_path` at the variant's rendition.
    init?(path: String?, variant: TMDbImageVariant) {
        guard let url = TMDbImageURLResolver.current.url(for: path, variant: variant) else { return nil }
        self.url = url
        self.variant = variant
    }

    /// Wraps a fully resolved URL, for fetch results that carry only a legacy URL.
    init?(fallbackURL: URL?, variant: TMDbImageVariant) {
        guard let fallbackURL else { return nil }
        self.url = fallbackURL
        self.variant = variant
    }

    var processor: any ImageProcessor {
        variant.processor(for: url)
    }
}
