//
//  AnimeEntry+DetailV2_7_9.swift
//  DataProvider
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import Foundation

extension SchemaV2_7_9.AnimeEntry {
    @discardableResult
    public func replaceDetail(from dto: AnimeEntryDetailDTO) -> SchemaV2_7_9.AnimeEntryDetail {
        if let detail {
            detail.apply(dto: dto)
            return detail
        }

        let detail = SchemaV2_7_9.AnimeEntryDetail(from: dto)
        self.detail = detail
        return detail
    }
}
