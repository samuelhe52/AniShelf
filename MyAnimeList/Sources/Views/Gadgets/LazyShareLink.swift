//
//  LazyShareLink.swift
//  MyAnimeList
//
//  Created by Samuel He on 2024/10/3.
//

import SwiftUI

struct LazyShareLink<LabelView: View>: View {
    let label: () -> LabelView
    let prepareData: () -> [Any]?

    init(_ text: LocalizedStringKey = "Share", prepareData: @escaping () -> [Any]?)
    where LabelView == Label<Text, Image> {
        self.label = { Label(text, systemImage: "square.and.arrow.up") }
        self.prepareData = prepareData
    }

    init(
        prepareData: @escaping () -> [Any]?,
        @ViewBuilder label: @escaping () -> LabelView
    ) {
        self.prepareData = prepareData
        self.label = label
    }

    var body: some View {
        Button(action: openShare, label: label)
    }

    private func openShare() {
        guard let data = prepareData() else {
            return
        }
        ShareSheetPresenter.present(items: data)
    }
}
