//
//  LibraryProfileSettingsComponents.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/3.
//

import SwiftUI

struct LibraryProfileMetricCard: View {
    let title: LocalizedStringResource
    let value: Int
    let systemImage: String
    let tint: Color
    var fillsAvailableHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: value)
                Spacer(minLength: 0)
            }
            Text("\(value)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsAvailableHeight ? .infinity : nil,
            alignment: .leading
        )
        .padding(16)
        .libraryProfileMetricPanel(cornerRadius: 24, tint: tint)
    }
}

struct LibraryProfileDetailRow: View {
    let title: LocalizedStringResource
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            LibraryProfileSettingIcon(systemImage: systemImage, tint: .secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 2)
    }
}

struct LibraryProfileActionRow: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let systemImage: String
    var role: ButtonRole? = nil
    var tint: Color = .secondary
    /// Zero when the row sits in a padded section card beside toggle rows.
    var horizontalPadding: CGFloat = 12
    /// Off for a single row among toggles, where an icon tile breaks the text column.
    var showsIcon = true
    let action: () -> Void

    var body: some View {
        #if os(macOS)
            macRow
        #else
            touchRow
        #endif
    }

    #if os(macOS)
        /// A form row with a push button, as in System Settings. A chevron would read as
        /// navigation, but every action row runs a command or opens a sheet.
        private var macRow: some View {
            LabeledContent {
                Button(role: role, action: action) {
                    Text(title)
                }
                .fixedSize()
            } label: {
                Text(subtitle)
            }
        }
    #endif

    private var touchRow: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                if showsIcon {
                    LibraryProfileSettingIcon(systemImage: systemImage, tint: tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(role == .destructive ? LibraryProfileSettingsPalette.destructive : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LibraryProfileActionDivider: View {
    var leadingInset: CGFloat = 58

    var body: some View {
        // Mac form rows draw their own separators.
        #if !os(macOS)
            Rectangle()
                .fill(.primary.opacity(0.075))
                .frame(height: 1)
                .padding(.leading, leadingInset)
        #endif
    }
}

struct LibraryProfileSettingHeader: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource? = nil
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            LibraryProfileSettingIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct LibraryProfileSettingIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            }
    }
}

struct LibraryProfileSelectionCapsule: View {
    let title: LocalizedStringResource
    let tint: Color

    var body: some View {
        #if os(macOS)
            // A pop-up button's look, which a form row expects, instead of a tinted chip.
            HStack(spacing: 5) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 5)
            .padding(.vertical, 3)
            .background(.fill.tertiary, in: .rect(cornerRadius: 5))
        #else
            capsuleContent(title: title)
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.12))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.18), lineWidth: 1)
                }
        #endif
    }

    @ViewBuilder
    private func capsuleContent(title: LocalizedStringResource) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
    }
}

struct LibraryProfileCommandButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    let tint: Color
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
            // A desktop push button: regular text in a quiet rounded bezel.
            configuration.label
                .foregroundStyle(filled ? .white : tint)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    filled ? AnyShapeStyle(tint) : AnyShapeStyle(.fill.tertiary),
                    in: .rect(cornerRadius: 6)
                )
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.42)
        #else
            touchBody(configuration: configuration)
        #endif
    }

    private func touchBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filled ? .white : tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 32)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(backgroundStyle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.42)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.16), value: isEnabled)
    }

    private var backgroundStyle: LinearGradient {
        if filled {
            LinearGradient(
                colors: [
                    tint,
                    tint.opacity(colorScheme == .dark ? 0.76 : 0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    tint.opacity(colorScheme == .dark ? 0.16 : 0.11),
                    tint.opacity(colorScheme == .dark ? 0.08 : 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        filled ? .white.opacity(0.24) : tint.opacity(0.18)
    }
}

struct LibraryProfileSettingsToggleRow: View {
    @Environment(\.libraryProfilePageTint) private var pageTint

    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    @Binding var isOn: Bool
    var tint: Color? = nil

    var body: some View {
        #if os(macOS)
            // A standard form switch with its description below the title.
            Toggle(isOn: $isOn) {
                Text(title)
                Text(subtitle)
            }
            .toggleStyle(.switch)
        #else
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .tint(tint ?? pageTint)
                    .scaleEffect(0.78, anchor: .trailing)
                    .frame(width: 42, height: 26, alignment: .trailing)
            }
            .padding(.vertical, 2)
        #endif
    }
}

extension EnvironmentValues {
    /// The pushed settings page's destination tint; toggles without an explicit tint use it.
    @Entry var libraryProfilePageTint: Color = .mint
}

/// Settings rows stacked in an iOS card; on the Mac each stays its own form row.
struct LibraryProfileSettingsRows<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 10
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
            Group(content: content)
        #else
            VStack(alignment: alignment, spacing: spacing, content: content)
        #endif
    }
}

extension View {
    /// A settings row title: regular body text in a Mac form, compact semibold in iOS cards.
    @ViewBuilder func settingsRowTitleFont() -> some View {
        #if os(macOS)
            self
        #else
            font(.subheadline.weight(.semibold))
        #endif
    }
}
