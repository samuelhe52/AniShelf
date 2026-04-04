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
    let animationTrigger: Language

    var body: some View {
        PopupSectionCard("Preview", systemImage: "photo.stack") {
            SharingCardView(
                image: image,
                title: title,
                subtitle: subtitle,
                detail: detail,
                aspectRatio: aspectRatio
            )
            .animation(
                .spring(response: 0.35, dampingFraction: 0.85),
                value: animationTrigger
            )
            .frame(maxWidth: AnimeSharingController.previewCardWidth)
            .frame(maxWidth: .infinity)
            .padding(12)
            .popupGlassPanel(cornerRadius: 30, tint: .white.opacity(0.08))
        }
    }
}
