//
//  AnimeTypeIndicator.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/11/25.
//

import DataProvider
import SwiftUI

struct AnimeTypeIndicator: View {
    var type: AnimeType
    var padding: CGFloat = 5

    var body: some View {
        Text(type.libraryLocalizedStringResource)
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: 5))
    }
}
