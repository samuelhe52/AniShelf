//
//  SharingCardView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/11/22.
//

import SwiftUI

struct SharingCardView: View {
    let image: UIImage?
    let title: AttributedString
    let subtitle: AttributedString?
    let detail: String?
    let aspectRatio: CGFloat
    let usesRoundedCorners: Bool
    let showsShadow: Bool

    private struct Constants {
        static let minAspectRatio: CGFloat = 0.45
        static let maxAspectRatio: CGFloat = 0.85
    }

    private var safeAspectRatio: CGFloat {
        max(Constants.minAspectRatio, min(aspectRatio, Constants.maxAspectRatio))
    }

    private var cornerRadius: CGFloat {
        usesRoundedCorners ? 24 : 0
    }

    private var titleLineLimit: Int { subtitle == nil ? 3 : 2 }
    private let subtitleLineLimit: Int = 2

    var body: some View {
        ZStack {
            backdropLayer
            overlayGradient
            VStack(alignment: .leading, spacing: 8) {
                detailLine
                titleLine
                subtitleLine
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(24)
        }
        .aspectRatio(safeAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(
            color: showsShadow ? .black.opacity(0.25) : .clear,
            radius: showsShadow ? 30 : 0,
            x: 0,
            y: showsShadow ? 25 : 0
        )
    }

    @ViewBuilder
    private var detailLine: some View {
        if let detail {
            Text(detail.uppercased())
                .font(.caption2.smallCaps().weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.white.opacity(0.12), in: Capsule())
        }
    }

    @ViewBuilder
    private var titleLine: some View {
        Text(title)
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(titleLineLimit)
            .minimumScaleFactor(0.8)
            .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private var subtitleLine: some View {
        if let subtitle {
            Text(subtitle)
                .font(.system(size: 16).weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(subtitleLineLimit)
                .minimumScaleFactor(0.9)
        }
    }

    private var backdropLayer: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(Color.black.opacity(0.05))
        .overlay(
            Rectangle()
                .fill(.black.opacity(0.2))
                .blendMode(.overlay)
        )
    }

    private var overlayGradient: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.0),
                Color.black.opacity(0.1),
                Color.black.opacity(0.65),
                Color.black.opacity(0.85)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
