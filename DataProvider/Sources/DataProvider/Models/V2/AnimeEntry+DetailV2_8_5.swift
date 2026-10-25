//
//  AnimeEntry+DetailV2_8_5.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/26.
//

import Foundation

extension SchemaV2_8_5.AnimeEntry {
    @discardableResult
    public func replaceDetail(from dto: AnimeEntryDetailDTO) -> SchemaV2_8_5.AnimeEntryDetail {
        if let detail {
            detail.apply(dto: dto)
            return detail
        }

        let detail = SchemaV2_8_5.AnimeEntryDetail(from: dto)
        self.detail = detail
        return detail
    }
}
