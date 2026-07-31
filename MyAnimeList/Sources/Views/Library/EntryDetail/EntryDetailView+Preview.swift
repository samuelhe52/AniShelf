//
//  EntryDetailView+Preview.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/1.
//

import DataProvider
import SwiftUI

fileprivate struct EntryDetailPreviewHost: View {
    @State private var showDetail = false
    @State private var session: EntryDetailSession

    init() {
        let dataProvider = DataProvider.forPreview
        _session = State(
            initialValue: EntryDetailSession(
                entry: .frieren,
                repository: LibraryRepository(dataProvider: dataProvider)
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack {
                Button(String(localized: EntryDetailL10n.showDetail)) {
                    showDetail = true
                }
            }
            .sheet(isPresented: $showDetail) {
                NavigationStack {
                    EntryDetailView(
                        session: session,
                        detailHost: .sheet
                    )
                }
            }
            .onAppear {
                showDetail = true
            }
        }
    }
}

#Preview {
    EntryDetailPreviewHost()
        .environment(AppReviewPromptController())
}
