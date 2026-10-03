//
//  AnimeEntry+DetailV2_8_2.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/2.
//

import Foundation

extension SchemaV2_8_2.AnimeEntry {
    @discardableResult
    public func replaceDetail(from dto: AnimeEntryDetailDTO) -> SchemaV2_8_2.AnimeEntryDetail {
        if let detail {
            detail.apply(dto: dto)
            return detail
        }

        let detail = SchemaV2_8_2.AnimeEntryDetail(from: dto)
        self.detail = detail
        return detail
    }
}
