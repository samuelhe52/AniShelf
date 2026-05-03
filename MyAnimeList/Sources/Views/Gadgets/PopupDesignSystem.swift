//
//  PopupDesignSystem.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/4/4.
//

import SwiftUI

struct PopupSectionCard<Content: View>: View {
    let title: LocalizedStringResource
    var systemImage: String? = nil
    var spacing: CGFloat = 14
    var panelTint: Color? = nil
    @ViewBuilder let content: Content

    init(
        _ title: LocalizedStringResource,
        systemImage: String? = nil,
        spacing: CGFloat = 14,
        panelTint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.spacing = spacing
        self.panelTint = panelTint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.title3.weight(.bold))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .popupGlassPanel(cornerRadius: 24, tint: resolvedPanelTint)
    }

    private var resolvedPanelTint: Color {
        panelTint ?? .white.opacity(0.05)
    }
}

struct PopupActionCircleButton: View {
    let systemImage: String
    var tint: Color = .primary
    var verticalOffset: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 20, height: 20)
                .padding(10)
                .offset(y: verticalOffset)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(tint)
    }
}

struct PopupDisclosureCard<Content: View>: View {
    let title: LocalizedStringResource
    var systemImage: String? = nil
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    init(
        _ title: LocalizedStringResource,
        systemImage: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .zIndex(1)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .zIndex(0)
                .clipped()
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                        removal: .opacity
                    )
                )
                .mask {
                    Rectangle()
                        .padding(.top, -2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .popupGlassPanel(cornerRadius: 24)
    }
}

struct PopupInlineDisclosureSection<Content: View>: View {
    let title: LocalizedStringResource
    var systemImage: String? = nil
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    init(
        _ title: LocalizedStringResource,
        systemImage: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(.white.opacity(0.14))
                        .frame(height: 1)
                        .padding(.bottom, 16)
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipped()
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                        removal: .opacity
                    )
                )
                .mask {
                    Rectangle()
                        .padding(.top, -2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func popupGlassPanel(
        cornerRadius: CGFloat,
        padding: CGFloat = 0,
        tint: Color = .white.opacity(0.05)
    ) -> some View {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            }
    }
}
