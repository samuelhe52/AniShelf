//
//  EntryDetailViewModel+Localization.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/9.
//

import DataProvider
import Foundation

@MainActor
extension EntryDetailViewModel {
    static func seasonCountText(_ count: Int) -> String {
        count == 1
            ? String(localized: "\(count) season")
            : String(localized: "\(count) seasons")
    }

    static func episodeCountText(_ count: Int) -> String {
        String(localized: "\(count) episodes")
    }

    static func orderedSeasonSummaries(
        _ seasons: [AnimeEntrySeasonSummary]
    ) -> [AnimeEntrySeasonSummary] {
        seasons.sorted {
            // Intentionally place TMDb season 0 ("Specials") after numbered seasons in detail view.
            if $0.seasonNumber == 0 { return false }
            if $1.seasonNumber == 0 { return true }
            return $0.seasonNumber < $1.seasonNumber
        }
    }

    static func seasonLabelText(_ seasonNumber: Int) -> String {
        if seasonNumber == 0 {
            return String(localized: "Specials")
        }
        return String(localized: "Season \(seasonNumber)")
    }

    static func minutesText(_ minutes: Int) -> String {
        String(localized: "\(minutes) min")
    }

    static func localizedStaffRole(_ role: String, language: Language) -> String {
        let translations: [String: String]
        switch language {
        case .english:
            return role
        case .japanese:
            translations = japaneseStaffRoleNames
        case .chinese:
            translations = chineseStaffRoleNames
        }

        return role
            .components(separatedBy: " / ")
            .map { translations[$0] ?? $0 }
            .joined(separator: " / ")
    }

    static func localizedGenreNames(_ genreIDs: [Int], language: Language) -> [String] {
        genreIDs.compactMap { localizedGenreName(for: $0, language: language) }
    }

    static func localizedGenreName(for genreID: Int, language: Language) -> String? {
        switch language {
        case .english:
            englishGenreNames[genreID]
        case .japanese:
            japaneseGenreNames[genreID]
        case .chinese:
            chineseGenreNames[genreID]
        }
    }

    private static let englishGenreNames: [Int: String] = [
        12: "Adventure", 14: "Fantasy", 16: "Animation", 18: "Drama", 27: "Horror",
        28: "Action", 35: "Comedy", 36: "History", 37: "Western", 53: "Thriller",
        80: "Crime", 99: "Documentary", 878: "Science Fiction", 9648: "Mystery",
        10402: "Music", 10749: "Romance", 10751: "Family", 10752: "War",
        10759: "Action & Adventure", 10762: "Kids", 10763: "News", 10764: "Reality",
        10765: "Sci-Fi & Fantasy", 10766: "Soap", 10767: "Talk", 10768: "War & Politics",
        10770: "TV Movie"
    ]

    private static let japaneseGenreNames: [Int: String] = [
        12: "アドベンチャー", 14: "ファンタジー", 16: "アニメーション", 18: "ドラマ", 27: "ホラー",
        28: "アクション", 35: "コメディ", 36: "歴史", 37: "西部劇", 53: "スリラー",
        80: "犯罪", 99: "ドキュメンタリー", 878: "SF", 9648: "ミステリー", 10402: "音楽",
        10749: "ロマンス", 10751: "ファミリー", 10752: "戦争",
        10759: "アクション・アドベンチャー", 10762: "キッズ", 10763: "ニュース",
        10764: "リアリティ", 10765: "SF・ファンタジー", 10766: "ソープ",
        10767: "トーク", 10768: "戦争・政治", 10770: "テレビ映画"
    ]

    private static let chineseGenreNames: [Int: String] = [
        12: "冒险", 14: "奇幻", 16: "动画", 18: "剧情", 27: "恐怖", 28: "动作", 35: "喜剧",
        36: "历史", 37: "西部", 53: "惊悚", 80: "犯罪", 99: "纪录", 878: "科幻", 9648: "悬疑",
        10402: "音乐", 10749: "爱情", 10751: "家庭", 10752: "战争", 10759: "动作冒险",
        10762: "儿童", 10763: "新闻", 10764: "真人秀", 10765: "科幻奇幻",
        10766: "肥皂剧", 10767: "脱口秀", 10768: "战争政治", 10770: "电视电影"
    ]

    // TMDb still returns English anime crew job labels in localized credits responses, so
    // keep a local fallback map for the common roles observed in live movie/series samples.
    private static let japaneseStaffRoleNames: [String: String] = [
        "2D Artist": "2Dアーティスト",
        "3D Animator": "3Dアニメーター",
        "3D Artist": "3Dアーティスト",
        "3D Director": "3Dディレクター",
        "3D Supervisor": "3Dスーパーバイザー",
        "Action Director": "アクションディレクター",
        "Additional Storyboarding": "追加絵コンテ",
        "Animation": "アニメーション",
        "Animation Director": "作画監督",
        "Art": "美術",
        "Art Department Manager": "美術部マネージャー",
        "Art Designer": "美術設定",
        "Art Direction": "美術監督",
        "Assistant Art Director": "美術監督補佐",
        "Assistant Director": "助監督",
        "Assistant Director of Photography": "撮影監督補佐",
        "Assistant Editor": "編集助手",
        "Assistant Production Manager": "制作デスク",
        "Background Designer": "背景デザイン",
        "Camera": "撮影",
        "CG Artist": "CGアーティスト",
        "CG Supervisor": "CGスーパーバイザー",
        "CGI Director": "CGIディレクター",
        "Character Designer": "キャラクターデザイン",
        "CGI Supervisor": "CGIスーパーバイザー",
        "Co-Director": "共同監督",
        "Co-Executive Producer": "共同製作総指揮",
        "Co-Producer": "共同プロデューサー",
        "Color Designer": "色彩設計",
        "Colorist": "カラリスト",
        "Compositing Artist": "撮影",
        "Compositing Lead": "撮影チーフ",
        "Compositor": "コンポジター",
        "Conceptual Design": "コンセプトデザイン",
        "Concept Artist": "コンセプトアーティスト",
        "Costume Design": "衣装デザイン",
        "Costume Supervisor": "衣装監修",
        "Creature Design": "クリーチャーデザイン",
        "Crew": "スタッフ",
        "Creative Director": "クリエイティブディレクター",
        "Development Manager": "開発マネージャー",
        "Development Producer": "開発プロデューサー",
        "Director": "監督",
        "Director of Photography": "撮影監督",
        "Directing": "演出",
        "Editing": "編集",
        "Editor": "編集",
        "Editorial Coordinator": "編集進行",
        "Effects Supervisor": "特効監督",
        "Executive Producer": "製作総指揮",
        "Foley": "フォーリー",
        "Foley Artist": "フォーリーアーティスト",
        "Key Animation": "原画",
        "Lead Animator": "メインアニメーター",
        "Line Producer": "ラインプロデューサー",
        "Lyricist": "作詞",
        "Main Title Theme Composer": "メインテーマ作曲",
        "Mechanical Designer": "メカニックデザイン",
        "Medical Consultant": "医療監修",
        "Mixing Engineer": "ミキシングエンジニア",
        "Modeling": "モデリング",
        "Motion Capture Artist": "モーションキャプチャーアーティスト",
        "Music": "音楽",
        "Music Director": "音楽ディレクター",
        "Music Producer": "音楽プロデューサー",
        "Music Supervisor": "音楽スーパーバイザー",
        "Musician": "ミュージシャン",
        "Novel": "原作小説",
        "Online Editor": "オンライン編集",
        "Opening/Ending Animation": "オープニング・エンディングアニメーション",
        "Original Concept": "原案",
        "Original Music Composer": "音楽",
        "Original Series Design": "原作シリーズデザイン",
        "Original Story": "原作",
        "Other": "その他",
        "Painter": "ペインター",
        "Producer": "プロデューサー",
        "Production": "制作",
        "Production Assistant": "制作進行",
        "Production Design": "プロダクションデザイン",
        "Production Manager": "制作担当",
        "Production Supervisor": "制作統括",
        "Prop Designer": "プロップデザイン",
        "Publicist": "パブリシティ",
        "Researcher": "リサーチャー",
        "Screenplay": "脚本",
        "Second Unit Director": "セカンドユニット監督",
        "Second Unit First Assistant Director": "セカンドユニット助監督",
        "Series Composition": "シリーズ構成",
        "Series Director": "シリーズ監督",
        "Songs": "楽曲",
        "Sound": "音響",
        "Sound Assistant": "音響助手",
        "Sound Director": "音響監督",
        "Sound Effects": "効果",
        "Sound Mixer": "ミキサー",
        "Sound Re-Recording Assistant": "リレコーディング助手",
        "Sound Recordist": "録音",
        "Special Effects": "特効",
        "Staff": "スタッフ",
        "Settings": "設定",
        "Storyboard Artist": "絵コンテ",
        "Storyboard Assistant": "絵コンテ補佐",
        "Supervising Art Director": "総美術監督",
        "Supervising Animation Director": "総作画監督",
        "Supervising Producer": "統括プロデューサー",
        "Technical Supervisor": "テクニカルスーパーバイザー",
        "Theme Song Performance": "主題歌",
        "Title Designer": "タイトルデザイン",
        "Visual Effects": "ビジュアルエフェクト",
        "Writer": "脚本",
        "Writing": "脚本",
        "Associate Producer": "アソシエイトプロデューサー",
        "Comic Book": "漫画原作",
        "Graphic Designer": "グラフィックデザイナー"
    ]

    private static let chineseStaffRoleNames: [String: String] = [
        "2D Artist": "2D美术师",
        "3D Animator": "3D动画师",
        "3D Artist": "3D美术师",
        "3D Director": "3D导演",
        "3D Supervisor": "3D总监",
        "Action Director": "动作导演",
        "Additional Storyboarding": "追加分镜",
        "Animation": "动画",
        "Animation Director": "作画监督",
        "Art": "美术",
        "Art Department Manager": "美术部门经理",
        "Art Designer": "美术设定",
        "Art Direction": "美术监督",
        "Assistant Art Director": "美术监督助理",
        "Assistant Director": "副导演",
        "Assistant Director of Photography": "摄影监督助理",
        "Assistant Editor": "剪辑助理",
        "Assistant Production Manager": "制作主任",
        "Background Designer": "背景设计",
        "Camera": "摄影",
        "CG Artist": "CG美术师",
        "CG Supervisor": "CG总监",
        "CGI Director": "CGI导演",
        "Character Designer": "角色设计",
        "CGI Supervisor": "CGI总监",
        "Co-Director": "联合导演",
        "Co-Executive Producer": "联合执行制片人",
        "Co-Producer": "联合制片人",
        "Color Designer": "色彩设计",
        "Colorist": "调色师",
        "Compositing Artist": "合成",
        "Compositing Lead": "合成主管",
        "Compositor": "合成师",
        "Conceptual Design": "概念设计",
        "Concept Artist": "概念美术",
        "Costume Design": "服装设计",
        "Costume Supervisor": "服装监修",
        "Creature Design": "生物设计",
        "Crew": "工作人员",
        "Creative Director": "创意总监",
        "Development Manager": "开发经理",
        "Development Producer": "开发制片人",
        "Director": "导演",
        "Director of Photography": "摄影监督",
        "Directing": "导演",
        "Editing": "剪辑",
        "Editor": "剪辑",
        "Editorial Coordinator": "编辑统筹",
        "Effects Supervisor": "特效监督",
        "Executive Producer": "执行制片人",
        "Foley": "拟音",
        "Foley Artist": "拟音师",
        "Key Animation": "原画",
        "Lead Animator": "主动画师",
        "Line Producer": "统筹制片人",
        "Lyricist": "作词",
        "Main Title Theme Composer": "主题曲作曲",
        "Mechanical Designer": "机械设计",
        "Medical Consultant": "医疗监修",
        "Mixing Engineer": "混音工程师",
        "Modeling": "建模",
        "Motion Capture Artist": "动作捕捉师",
        "Music": "音乐",
        "Music Director": "音乐总监",
        "Music Producer": "音乐制作人",
        "Music Supervisor": "音乐监制",
        "Musician": "音乐家",
        "Novel": "原作小说",
        "Online Editor": "在线剪辑",
        "Opening/Ending Animation": "片头/片尾动画",
        "Original Concept": "原案",
        "Original Music Composer": "原创音乐",
        "Original Series Design": "原作系列设计",
        "Original Story": "原作",
        "Other": "其他",
        "Painter": "绘师",
        "Producer": "制片人",
        "Production": "制作",
        "Production Assistant": "制作进行",
        "Production Design": "制作设计",
        "Production Manager": "制作担当",
        "Production Supervisor": "制作统筹",
        "Prop Designer": "道具设计",
        "Publicist": "宣传",
        "Researcher": "资料研究",
        "Screenplay": "剧本",
        "Second Unit Director": "第二组导演",
        "Second Unit First Assistant Director": "第二组副导演",
        "Series Composition": "系列构成",
        "Series Director": "系列导演",
        "Songs": "歌曲",
        "Sound": "音响",
        "Sound Assistant": "音响助理",
        "Sound Director": "音响监督",
        "Sound Effects": "音效",
        "Sound Mixer": "混音师",
        "Sound Re-Recording Assistant": "混录助理",
        "Sound Recordist": "录音",
        "Special Effects": "特效",
        "Staff": "工作人员",
        "Settings": "设定",
        "Storyboard Artist": "分镜",
        "Storyboard Assistant": "分镜助理",
        "Supervising Art Director": "总美术监督",
        "Supervising Animation Director": "总作画监督",
        "Supervising Producer": "总制片人",
        "Technical Supervisor": "技术总监",
        "Theme Song Performance": "主题曲演唱",
        "Title Designer": "标题设计",
        "Visual Effects": "视觉效果",
        "Writer": "编剧",
        "Writing": "编剧",
        "Associate Producer": "副制片人",
        "Comic Book": "漫画原作",
        "Graphic Designer": "平面设计"
    ]
}
