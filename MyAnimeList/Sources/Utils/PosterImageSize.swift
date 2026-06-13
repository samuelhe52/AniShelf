//
//  PosterImageSize.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/6/14.
//

import CoreGraphics

/// Shared geometry for poster images so prefetch and display agree on the target
/// size. If these diverge, prefetched variants are stored at one size and looked
/// up at another, forcing redundant re-downloads.
enum PosterImageSize {
    static let heightRatio: CGFloat = 1.5

    static func targetSize(width: CGFloat) -> CGSize {
        CGSize(width: width, height: width * heightRatio)
    }
}
