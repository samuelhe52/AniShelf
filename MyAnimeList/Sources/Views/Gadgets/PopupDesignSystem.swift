//
//  PopupDesignSystem.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/4/4.
//

import SwiftUI

/// How popup panels draw.
///
/// The Mac inspector uses `.grouped`: flat grouped boxes
/// with headline titles, as in Mac inspectors, instead of the iOS glass cards.
enum PopupPanelStyle {
    case glass
    case grouped
}

extension EnvironmentValues {
    @Entry var popupPanelStyle: PopupPanelStyle = .glass
}

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

    @Environment(\.popupPanelStyle) private var panelStyle

    var body: some View {
        VStack(alignment: .leading, spacing: panelStyle == .grouped ? 10 : spacing) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(panelStyle.titleFont)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(panelStyle.contentPadding)
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
            PopupActionButtonLabel(systemImage: systemImage, verticalOffset: verticalOffset)
        }
        .popupActionButtonChrome(tint: tint)
    }
}

/// The icon of a popup action button: a large glass-circle glyph, or a body-sized
/// glyph inside a bordered button for `.grouped` panels.
struct PopupActionButtonLabel: View {
    @Environment(\.popupPanelStyle) private var panelStyle
    let systemImage: String
    var verticalOffset: CGFloat = 0

    var body: some View {
        switch panelStyle {
        case .glass:
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 20, height: 20)
                .padding(10)
                .offset(y: verticalOffset)
        case .grouped:
            Image(systemName: systemImage)
                .frame(width: 18, height: 16)
                .offset(y: verticalOffset / 2)
        }
    }
}

extension View {
    func popupActionButtonChrome(tint: Color = .primary) -> some View {
        modifier(PopupActionButtonChrome(tint: tint))
    }
}

fileprivate struct PopupActionButtonChrome: ViewModifier {
    @Environment(\.popupPanelStyle) private var panelStyle
    let tint: Color

    func body(content: Content) -> some View {
        switch panelStyle {
        case .glass:
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(tint)
        case .grouped:
            // On macOS a bordered button's tint fills its bezel, and only while the
            // window is key, so color the glyph instead to keep the bezel consistent.
            content
                .foregroundStyle(tint)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }
}

struct PopupDisclosureCard<Content: View>: View {
    @Environment(\.popupPanelStyle) private var panelStyle
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
                        .font(panelStyle.titleFont)
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
        .padding(panelStyle.contentPadding)
        .popupGlassPanel(cornerRadius: 24)
    }
}

struct PopupNestedDisclosureSection<Content: View>: View {
    @Environment(\.popupPanelStyle) private var panelStyle
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
                        .font(panelStyle.titleFont)
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

extension PopupPanelStyle {
    var titleFont: Font {
        switch self {
        case .glass: .title3.weight(.bold)
        case .grouped: .headline
        }
    }

    var contentPadding: CGFloat {
        switch self {
        case .glass: 18
        case .grouped: 12
        }
    }
}

extension View {
    func popupGlassPanel(
        cornerRadius: CGFloat,
        padding: CGFloat = 0,
        tint: Color = .white.opacity(0.05)
    ) -> some View {
        modifier(PopupGlassPanelModifier(cornerRadius: cornerRadius, padding: padding, tint: tint))
    }
}

fileprivate struct PopupGlassPanelModifier: ViewModifier {
    @Environment(\.popupPanelStyle) private var panelStyle
    let cornerRadius: CGFloat
    let padding: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        switch panelStyle {
        case .glass:
            content
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
        case .grouped:
            content
                .padding(padding)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.fill.quaternary)
                }
        }
    }
}
