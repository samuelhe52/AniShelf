//
//  AnimeEntry+DetailV2_8_4.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/18.
//

import Foundation

extension SchemaV2_8_4.AnimeEntry {
    @discardableResult
    public func replaceDetail(from dto: AnimeEntryDetailDTO) -> SchemaV2_8_4.AnimeEntryDetail {
        if let detail {
            detail.apply(dto: dto)
            return detail
        }

        let detail = SchemaV2_8_4.AnimeEntryDetail(from: dto)
        self.detail = detail
        return detail
    }
}
