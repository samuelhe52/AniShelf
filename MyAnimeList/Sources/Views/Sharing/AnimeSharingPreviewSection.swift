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
    @Binding var roundedExportFormat: SharingCardRoundedExportFormat
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
            .contentTransition(.interpolate)
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
        HStack(spacing: 6) {
            if usesRoundedCorners {
                roundedFormatPicker
            } else {
                Text("JPEG")
            }
            Text(verbatim: "·")
            outputStatusText
                .contentTransition(.numericText())

            if renderedPixelSize != nil {
                InfoTip(
                    title: "Source Resolution",
                    message:
                        "AniShelf never enlarges poster artwork. If the source is smaller than the selected export size, the source resolution is used instead. Some size options may therefore produce identical results.",
                    width: 280,
                    iconFont: .footnote
                )
            }
        }
    }

    private var outputStatusText: Text {
        if let renderedPixelSize {
            let width = Int(renderedPixelSize.width.rounded())
            let height = Int(renderedPixelSize.height.rounded())
            return Text(verbatim: "\(width) × \(height)")
        }
        return Text("Rendering…")
    }

    private var roundedFormatPicker: some View {
        Menu {
            Picker("Format", selection: $roundedExportFormat) {
                ForEach(SharingCardRoundedExportFormat.allCases, id: \.self) { format in
                    Text(format.localizedName).tag(format)
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(roundedExportFormat.localizedName)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(Text("Format"))
        .accessibilityValue(Text(roundedExportFormat.localizedName))
    }
}
