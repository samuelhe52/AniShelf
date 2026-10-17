//
//  InfoTip.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/18.
//

import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct InfoTip: View {
    @State private var showTip = false
    @State private var copyHapticTrigger = false
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    var copyText: LocalizedStringResource?
    var width: CGFloat?
    var height: CGFloat?
    var iconFont: Font?

    var body: some View {
        Button(action: {
            showTip.toggle()
        }) {
            Image(systemName: "info.circle")
                .font(iconFont)
        }
        .popover(isPresented: $showTip) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.callout)
                    .bold()
                    .foregroundStyle(.blue)
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: copyTipText)
            .frame(width: width, height: height)
            .padding()
            .presentationCompactAdaptation(.popover)
        }
        .sensoryFeedback(.lighterImpact, trigger: copyHapticTrigger)
    }

    private func copyTipText() {
        guard let copyText else { return }
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(localized: copyText), forType: .string)
        #else
            UIPasteboard.general.string = String(localized: copyText)
        #endif
        copyHapticTrigger.toggle()
    }
}
