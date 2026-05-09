//
//  AnimeEntry+DetailV2_7_1.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/9.
//

import Foundation

extension SchemaV2_7_1.AnimeEntry {
    @discardableResult
    public func replaceDetail(from dto: AnimeEntryDetailDTO) -> SchemaV2_7_1.AnimeEntryDetail {
        if let detail {
            detail.apply(dto: dto)
            return detail
        }

        let detail = SchemaV2_7_1.AnimeEntryDetail(from: dto)
        self.detail = detail
        return detail
    }
}
