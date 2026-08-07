//
//  AnimeEntry+DetailV2_8_1.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/6.
//

import Foundation

extension SchemaV2_8_1.AnimeEntry {
    @discardableResult
    public func replaceDetail(from dto: AnimeEntryDetailDTO) -> SchemaV2_8_1.AnimeEntryDetail {
        if let detail {
            detail.apply(dto: dto)
            return detail
        }

        let detail = SchemaV2_8_1.AnimeEntryDetail(from: dto)
        self.detail = detail
        return detail
    }
}
