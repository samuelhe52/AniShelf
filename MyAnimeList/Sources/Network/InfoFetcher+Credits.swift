//
//  InfoFetcher+Credits.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/12.
//

import DataProvider
import Foundation
import TMDb

private struct MergedAggregateCrewMember {
    var id: Int
    var name: String
    var originalName: String
    var profilePath: URL?
    var jobs: [CrewJob]
    var knownForDepartment: String?
}

extension InfoFetcher {
    func makeCharacters<S: Sequence>(
        from cast: S,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> [AnimeEntryCharacterDTO] where S.Element == CastMember {
        cast.map {
            AnimeEntryCharacterDTO(
                id: $0.id,
                characterName: $0.character.strippingVoiceQualifier.nilIfEmpty ?? "Character",
                actorName: Self.preferredActorName(
                    localizedName: $0.name,
                    originalName: nil,
                    language: language
                ),
                profileURL: imagesConfiguration.profileURL(for: $0.profilePath, idealWidth: 185)
            )
        }
    }

    func makeCharacters<S: Sequence>(
        from cast: S,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> [AnimeEntryCharacterDTO] where S.Element == AggregrateCastMember {
        cast.map {
            let primaryRole = $0.roles.max { lhs, rhs in
                lhs.episodeCount < rhs.episodeCount
            }?.character
                .strippingVoiceQualifier
                .nilIfEmpty

            return AnimeEntryCharacterDTO(
                id: $0.id,
                characterName: primaryRole ?? "Character",
                actorName: Self.preferredActorName(
                    localizedName: $0.name,
                    originalName: $0.originalName,
                    language: language
                ),
                profileURL: imagesConfiguration.profileURL(for: $0.profilePath, idealWidth: 185)
            )
        }
    }

    func makeStaff<S: Sequence>(
        from crew: S,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> [AnimeEntryStaffDTO] where S.Element == CrewMember {
        crew.map {
            AnimeEntryStaffDTO(
                id: Self.stableStaffIdentifier(creditID: $0.creditID, fallbackID: $0.id),
                name: Self.preferredActorName(
                    localizedName: $0.name,
                    originalName: nil,
                    language: language
                ),
                role: $0.job.nilIfEmpty ?? $0.department.nilIfEmpty ?? "Staff",
                department: $0.department.nilIfEmpty,
                profileURL: imagesConfiguration.profileURL(for: $0.profilePath, idealWidth: 185)
            )
        }
    }

    func makeStaff<S: Sequence>(
        from crew: S,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> [AnimeEntryStaffDTO] where S.Element == AggregrateCrewMember {
        Self.aggregateStaffDTOs(
            from: crew,
            imagesConfiguration: imagesConfiguration,
            language: language
        )
    }

    static func aggregateStaffDTOs<S: Sequence>(
        from crew: S,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> [AnimeEntryStaffDTO] where S.Element == AggregrateCrewMember {
        mergedAggregateCrewMembers(from: crew).map { member in
            let department = member.knownForDepartment?.nilIfEmpty

            return AnimeEntryStaffDTO(
                id: member.id,
                name: preferredActorName(
                    localizedName: member.name,
                    originalName: member.originalName,
                    language: language
                ),
                role: department ?? "Staff",
                department: department,
                profileURL: imagesConfiguration.profileURL(
                    for: member.profilePath,
                    idealWidth: 185
                ),
                jobs: member.jobs.map {
                    AnimeEntryStaffJobDTO(
                        creditID: $0.creditID,
                        job: $0.job,
                        episodeCount: $0.episodeCount
                    )
                }
            )
        }
    }

    static func stableStaffIdentifier(creditID: String, fallbackID: Int) -> Int {
        guard !creditID.isEmpty else { return fallbackID }

        // TMDb reuses person IDs across multiple movie crew credits, so derive a stable
        // per-credit identifier from the credit ID while keeping the stored model shape intact.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in creditID.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(truncatingIfNeeded: hash)
    }

    static func preferredActorName(localizedName: String, originalName: String?, language: Language)
        -> String
    {
        guard language == .japanese,
            let originalName,
            originalName != localizedName,
            originalName.containsJapaneseScript
        else {
            return localizedName
        }
        return originalName
    }

    private static func mergedAggregateCrewMembers<S: Sequence>(
        from crew: S
    ) -> [MergedAggregateCrewMember] where S.Element == AggregrateCrewMember {
        var mergedMembers: [MergedAggregateCrewMember] = []
        var mergedIndexByPersonID: [Int: Int] = [:]

        for member in crew {
            if let existingIndex = mergedIndexByPersonID[member.id] {
                mergedMembers[existingIndex].jobs.append(contentsOf: member.jobs)
                if mergedMembers[existingIndex].profilePath == nil {
                    mergedMembers[existingIndex].profilePath = member.profilePath
                }
                if mergedMembers[existingIndex].knownForDepartment?.isEmpty ?? true {
                    mergedMembers[existingIndex].knownForDepartment = member.knownForDepartment
                }
                if mergedMembers[existingIndex].name.isEmpty {
                    mergedMembers[existingIndex].name = member.name
                }
                if mergedMembers[existingIndex].originalName.isEmpty {
                    mergedMembers[existingIndex].originalName = member.originalName
                }
                continue
            }

            mergedIndexByPersonID[member.id] = mergedMembers.count
            mergedMembers.append(
                MergedAggregateCrewMember(
                    id: member.id,
                    name: member.name,
                    originalName: member.originalName,
                    profilePath: member.profilePath,
                    jobs: member.jobs,
                    knownForDepartment: member.knownForDepartment
                )
            )
        }

        return mergedMembers
    }
}

extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }

    var strippingVoiceQualifier: String {
        let voiceMarkerPattern = #"(?i:voice|voiced\s+by|cv|c\.?\s*v\.?)|声優|声の出演|声|吹替え|吹替|吹き替え|ボイス"#
        let patterns = [
            #"\s*[\(\（][^)\）]*(?:__VOICE_MARKERS__)[^)\）]*[\)\）]\s*$"#,
            #"\s*[\[\［][^\]\］]*(?:__VOICE_MARKERS__)[^\]\］]*[\]\］]\s*$"#
        ].map {
            $0.replacingOccurrences(of: "__VOICE_MARKERS__", with: voiceMarkerPattern)
        }

        var value = self
        while true {
            let stripped = patterns.reduce(value) { partialResult, pattern in
                partialResult.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: .regularExpression
                )
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)

            guard stripped != value else {
                return stripped
            }
            value = stripped
        }
    }

    var containsJapaneseScript: Bool {
        unicodeScalars.contains {
            switch $0.value {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x4E00...0x9FFF:
                return true
            default:
                return false
            }
        }
    }
}
