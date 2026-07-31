//
//  AnimeSharingPreviewSection.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/11/22.
//

import DataProvider
import SwiftUI

struct AnimeSharingPreviewSection: View {
    let title: AttributedString
    let subtitle: AttributedString?
    let detail: String?
    let aspectRatio: CGFloat
    let image: UIImage?
    let renderedPixelSize: CGSize?
    let usesRoundedCorners: Bool
    let animationTrigger: Int

    var body: some View {
        VStack(spacing: 12) {
            SharingCardView(
                image: image,
                title: title,
                subtitle: subtitle,
                detail: detail,
                aspectRatio: aspectRatio,
                usesRoundedCorners: usesRoundedCorners,
                showsShadow: true
            )
            .id(animationTrigger)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
            .frame(maxWidth: AnimeSharingViewModel.previewCardWidth)
            .frame(maxWidth: .infinity)

            outputDescription
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(height: 20)
        }
        .animation(.easeInOut(duration: 0.22), value: animationTrigger)
        .animation(.easeInOut(duration: 0.18), value: renderedPixelSize == nil)
        .animation(.easeInOut(duration: 0.22), value: usesRoundedCorners)
    }

    @ViewBuilder
    private var outputDescription: some View {
        if let renderedPixelSize {
            let width = Int(renderedPixelSize.width.rounded())
            let height = Int(renderedPixelSize.height.rounded())
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if usesRoundedCorners {
                    Text("PNG · \(width) × \(height)")
                } else {
                    Text("JPEG · \(width) × \(height)")
                }

                InfoTip(
                    title: "Source Resolution",
                    message:
                        "AniShelf never enlarges poster artwork. If the source is smaller than the selected export size, the source resolution is used instead. Some size options may therefore produce identical results.",
                    width: 280,
                    iconFont: .footnote
                )
            }
            .id(usesRoundedCorners ? "rendered-png" : "rendered-jpeg")
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if usesRoundedCorners {
            Text("PNG · Rendering…")
                .id("rendering-png")
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Text("JPEG · Rendering…")
                .id("rendering-jpeg")
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
