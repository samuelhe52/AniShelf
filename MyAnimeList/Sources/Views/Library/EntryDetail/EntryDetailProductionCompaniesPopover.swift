//
//  EntryDetailProductionCompaniesPopover.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/6.
//

import SwiftUI

struct EntryDetailProductionCompaniesPopover: View {
    @ScaledMetric(relativeTo: .footnote) private var companyNameFontSize: CGFloat = 14

    let companies: [EntryDetailProductionCompanyCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(EntryDetailL10n.productionCompanies, systemImage: "building.2")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(companies) { company in
                        HStack(spacing: 12) {
                            companyLogo(company)
                                .frame(width: 48, height: 32)

                            Text(company.name)
                                .font(.system(size: companyNameFontSize, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .padding([.horizontal, .top])
        .frame(width: 240, height: popoverHeight)
    }

    private var popoverHeight: CGFloat {
        min(71 + CGFloat(companies.count) * 46, 380)
    }

    @ViewBuilder
    private func companyLogo(_ company: EntryDetailProductionCompanyCard) -> some View {
        if let logoURL = company.logoURL {
            KFImageView(
                url: logoURL,
                targetSize: CGSize(width: 500, height: 500),
                diskCacheExpiration: .shortTerm
            )
            .scaledToFit()
        } else {
            Image(systemName: "building.2")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
