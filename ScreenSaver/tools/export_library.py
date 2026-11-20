#!/usr/bin/env python3
"""把 AniShelf 的 Core Data 资料库导出成屏保可用的清单 + 封面缓存。

用法: python3 export.py [--limit N] [--skip-images]
输出: ~/Library/Application Support/AniShelfCovers/{library.json, covers/, stills/}
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sqlite3
import sys
import plistlib
import re
import time
from datetime import datetime
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

STORE = Path.home() / "Library/Containers/com.samuelhe.MyAnimeList/Data/Library/Application Support/DataProvider/mal.store"
OUT = Path.home() / "Library/Application Support/AniShelfCovers"   # 可被 --out 覆盖
IMG_BASE = "https://image.tmdb.org/t/p"
COVER_SIZE = "w500"
STILL_SIZE = "w780"
BACKDROP_SIZE = "w1280"
LOGO_SIZE = "w500"
UA = {"User-Agent": "AniShelfCovers/0.1 (personal screensaver)"}

COUNTRY_I18N = {
    "日本": {"zh": "日本", "en": "Japan", "ja": "日本"},
    "美国": {"zh": "美国", "en": "United States", "ja": "アメリカ"},
    "中国": {"zh": "中国", "en": "China", "ja": "中国"},
    "韩国": {"zh": "韩国", "en": "South Korea", "ja": "韓国"},
    "拉脱维亚": {"zh": "拉脱维亚", "en": "Latvia", "ja": "ラトビア"},
    "法国": {"zh": "法国", "en": "France", "ja": "フランス"},
    "德国": {"zh": "德国", "en": "Germany", "ja": "ドイツ"},
    "意大利": {"zh": "意大利", "en": "Italy", "ja": "イタリア"},
    "西班牙": {"zh": "西班牙", "en": "Spain", "ja": "スペイン"},
    "俄罗斯": {"zh": "俄罗斯", "en": "Russia", "ja": "ロシア"},
    "泰国": {"zh": "泰国", "en": "Thailand", "ja": "タイ"},
}

COUNTRY = {
    "ja": "日本", "en": "美国", "zh": "中国", "ko": "韩国",
    "fr": "法国", "de": "德国", "it": "意大利", "es": "西班牙",
    "lv": "拉脱维亚", "ru": "俄罗斯", "th": "泰国",
}

# Core Data 的 TIMESTAMP 以 2001-01-01 为纪元
COCOA_EPOCH = 978307200


LANGS = [("zh", "zh-CN", ""), ("en", "en-US", " Season %d"), ("ja", "ja-JP", " 第%dシーズン")]
SEASON_SUFFIX = {"zh": " 第 %d 季", "en": " Season %d", "ja": " 第%dシーズン"}


def _load_map(blob):
    if not blob:
        return {}
    try:
        return json.loads(blob)
    except Exception:
        return {}


def _pick(mapping, key, fallback=""):
    v = (mapping.get(key) or mapping.get(key.split("-")[0]) or "").strip()
    return v or fallback


def _app_language():
    try:
        pf = Path.home() / "Library/Containers/com.samuelhe.MyAnimeList/Data/Library/Preferences/com.samuelhe.MyAnimeList.plist"
        with open(pf, "rb") as fh:
            prefs = plistlib.load(fh)
        lang = str(prefs.get("PreferredAnimeInfoLanguage", "zh"))
        return lang if lang in ("zh", "en", "ja") else "zh"
    except Exception:
        return "zh"


def _i18n_block(row) -> dict:
    name_tr = _load_map(row["name_tr"])
    parent_tr = _load_map(row["parent_tr"])
    ov_tr = _load_map(row["ov_tr"])
    parent_ov_tr = _load_map(row["parent_ov_tr"])
    base = (row["name"] or "").strip()
    parent = (row["parent_name"] or "").strip()
    season = row["season"] or 0
    is_season = bool(parent) and base.startswith("第") and "季" in base

    out = {}
    for code, key, _ in LANGS:
        if is_season:
            title = _pick(parent_tr, key, parent)
            if season:
                title = title + (SEASON_SUFFIX[code] % season)
        else:
            title = _pick(name_tr, key, base)
        lang_code = (row["lang"] or "").lower()
        cname = COUNTRY.get(lang_code, lang_code.upper())
        cmap = COUNTRY_I18N.get(cname, {})
        country = cmap.get(code, cname)
        overview = _pick(ov_tr, key, "")
        if not overview and is_season:
            overview = _pick(parent_ov_tr, key, "")
        if not overview:
            overview = (row["overview"] or "").strip()
        out[code] = {"title": title, "overview": overview, "country": country}
    return out


def _decode_genres(blob) -> list:
    """ZGENREIDS 是 NSKeyedArchiver 归档的 NSArray<NSNumber>。"""
    if not blob:
        return []
    try:
        pl = plistlib.loads(blob)
        objs = pl.get("$objects", [])
        top = pl.get("$top", {}).get("root")

        def dec(o):
            if isinstance(o, plistlib.UID):
                return dec(objs[o.data]) if o.data < len(objs) else None
            if isinstance(o, dict):
                if "NS.objects" in o:
                    return [dec(x) for x in o["NS.objects"]]
                if "NS.string" in o:
                    return o["NS.string"]
                return None
            return o

        vals = dec(top)
        return [int(v) for v in vals if isinstance(v, (int, float))] if isinstance(vals, list) else []
    except Exception:
        return []


def _air_status(raw: str) -> str:
    v = (raw or "").strip().lower()
    if v in ("ended", "released", "canceled", "cancelled"):
        return "ended"
    if v == "returning series":
        return "returning"
    if v in ("in production", "post production", "planned", "pilot"):
        return "production"
    return ""


def _watch_state(row) -> str:
    for key, val in (("w_watching", "watching"), ("w_watched", "watched"),
                     ("w_planned", "planned"), ("w_dropped", "dropped")):
        try:
            if (row[key] or "").strip():
                return val
        except (IndexError, KeyError):
            continue
    return ""


def _clean_tagline(text: str, name: str) -> str:
    t = (text or "").strip()
    if not t or len(t) < 2:
        return ""
    if t == name or re.fullmatch(r"第\s*\d+\s*季", t):
        return ""
    return t


def _display_name(row) -> str:
    name = (row["name"] or "").strip()
    parent = (row["parent_name"] or "").strip()
    season = row["season"] or 0
    if parent and name.startswith("第") and "季" in name:
        return f"{parent} 第 {season} 季" if season else parent
    return name


def status_of(row) -> str:
    if row["watching"]:
        return "watching"
    if row["watched"]:
        return "watched"
    if row["planned"]:
        return "planned"
    if row["dropped"]:
        return "dropped"
    return "unknown"


def target_for(kind: str, remote: str) -> Path:
    ext = os.path.splitext(remote)[1] or ".jpg"
    digest = hashlib.sha1(remote.encode()).hexdigest()[:16]
    sub = {"cover": "covers", "still": "stills", "backdrop": "backdrops", "logo": "logos"}[kind]
    return OUT / sub / f"{digest}{ext}"


def fetch(job) -> tuple[str, bool, str]:
    kind, remote, size = job
    dest = target_for(kind, remote)
    if dest.exists() and dest.stat().st_size > 4096:
        return remote, True, "cached"
    url = f"{IMG_BASE}/{size}{remote}"
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
            if len(data) < 4096:
                raise ValueError(f"too small: {len(data)}")
            dest.parent.mkdir(parents=True, exist_ok=True)
            tmp = dest.with_suffix(dest.suffix + ".part")
            tmp.write_bytes(data)
            tmp.replace(dest)
            return remote, True, f"{len(data)//1024}KB"
        except Exception as exc:  # noqa: BLE001
            if attempt == 2:
                return remote, False, str(exc)
            time.sleep(1.5 * (attempt + 1))
    return remote, False, "unreachable"


APP_LANG = _app_language()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--skip-images", action="store_true")
    ap.add_argument("--out", default="", help="输出目录，默认 Application Support")
    ap.add_argument("--with-stills", action="store_true", help="额外下载剧集静帧（当前模式未使用）")
    args = ap.parse_args()
    global OUT
    if args.out:
        OUT = Path(args.out).expanduser()

    if not STORE.exists():
        print(f"找不到资料库: {STORE}", file=sys.stderr)
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    probe = Path("/tmp/anishelf_export/mal.store")
    probe.parent.mkdir(parents=True, exist_ok=True)
    for suffix in ("", "-wal", "-shm"):
        src = Path(str(STORE) + suffix)
        if src.exists():
            shutil.copy2(src, Path(str(probe) + suffix))

    con = sqlite3.connect(probe)
    con.row_factory = sqlite3.Row
    rows = con.execute(
        """
        SELECT e.Z_PK AS pk, e.ZNAME AS name, e.ZSEASONNUMBER AS season,
               e.ZPOSTERPATH AS poster, e.ZBACKDROPPATH AS backdrop,
               e.ZSCORE AS score, e.ZFAVORITE AS fav, e.ZTMDBID AS tmdb,
               e.ZWATCHING AS watching, e.ZWATCHED AS watched,
               e.ZPLANTOWATCH AS planned, e.ZDROPPED AS dropped,
               e.ZPARENTSERIESID AS parent, e.ZORIGINALLANGUAGECODE AS lang, e.ZONAIRDATE AS onair,
               d.ZVOTEAVERAGE AS vote, d.ZAIRDATE AS airdate,
               d.ZLOGOIMAGEPATH AS logo, d.ZSUBTITLE AS tagline, d.ZOVERVIEW AS overview,
               d.ZGENREIDS AS genre_blob, d.ZSTATUS AS air_status, pd.ZGENREIDS AS parent_genre_blob,
               e.ZMOVIE AS is_movie, e.ZSERIES AS is_series,
               e.ZWATCHING AS w_watching, e.ZWATCHED AS w_watched,
               e.ZPLANTOWATCH AS w_planned, e.ZDROPPED AS w_dropped, p.ZNAME AS parent_name,
               e.ZNAMETRANSLATIONS AS name_tr, e.ZOVERVIEWTRANSLATIONS AS ov_tr,
               p.ZNAMETRANSLATIONS AS parent_tr, p.ZOVERVIEWTRANSLATIONS AS parent_ov_tr
        FROM ZANIMEENTRY e
        LEFT JOIN ZANIMEENTRYDETAIL d ON d.ZENTRY = e.Z_PK
        LEFT JOIN ZANIMEENTRY p ON p.Z_PK = e.ZPARENTSERIESENTRY
        LEFT JOIN ZANIMEENTRYDETAIL pd ON pd.ZENTRY = p.Z_PK
        WHERE e.ZPOSTERPATH IS NOT NULL AND e.ZPOSTERPATH <> ''
        ORDER BY e.ZFAVORITE DESC, e.ZSCORE DESC
        """
    ).fetchall()

    if args.limit:
        rows = rows[: args.limit]

    items = []
    seen_ids = set()
    for r in rows:
        if r["pk"] in seen_ids:
            continue
        seen_ids.add(r["pk"])
        items.append(
            {
                "id": r["pk"],
                "title": (r["name"] or "").strip(),
                "display": _display_name(r),
                "i18n": _i18n_block(r),
                "taglineLang": APP_LANG,
                "genres": ([g for g in _decode_genres(r["genre_blob"]) if g != 16]
                        or [g for g in _decode_genres(r["parent_genre_blob"]) if g != 16]),
                "airStatus": _air_status(r["air_status"]),
                "kind": "movie" if (r["is_movie"] or "") == "movie" else "tv",
                "watch": _watch_state(r),
                "season": r["season"] if r["season"] is not None else 0,
                "score": r["score"] or 0,
                "favorite": bool(r["fav"]),
                "status": status_of(r),
                "tmdb": r["tmdb"],
                "cover": str(target_for("cover", r["poster"]).relative_to(OUT)),
                "cover_remote": r["poster"],
                "backdrop": str(target_for("backdrop", r["backdrop"]).relative_to(OUT)) if r["backdrop"] else None,
                "backdrop_remote": r["backdrop"],
                "logo": str(target_for("logo", r["logo"]).relative_to(OUT)) if r["logo"] and r["logo"].endswith(".png") else None,
                "logo_remote": r["logo"] if r["logo"] and r["logo"].endswith(".png") else None,
                "overview": (r["overview"] or "").strip(),
                "tagline": _clean_tagline(r["tagline"], (r["name"] or "").strip()),
                "vote": round(float(r["vote"]), 1) if r["vote"] else 0.0,
                "year": datetime.utcfromtimestamp((r["airdate"] or r["onair"]) + COCOA_EPOCH).year if (r["airdate"] or r["onair"]) else 0,
                "country": COUNTRY.get((r["lang"] or "").lower(), (r["lang"] or "").upper()),
            }
        )

    episodes = []
    for e in con.execute(
        """
        SELECT s.ZTITLE AS title, s.ZIMAGEPATH AS image, s.ZEPISODENUMBER AS ep,
               s.ZDISPLAYORDER AS ord, s.ZDETAIL AS detail
        FROM ZANIMEENTRYEPISODESUMMARY s
        WHERE s.ZIMAGEPATH IS NOT NULL AND s.ZIMAGEPATH <> ''
        """
    ):
        episodes.append(
            {
                "title": (e["title"] or "").strip(),
                "episode": e["ep"],
                "still": str(target_for("still", e["image"]).relative_to(OUT)),
                "still_remote": e["image"],
            }
        )
    con.close()

    jobs = [("cover", i["cover_remote"], COVER_SIZE) for i in items]
    jobs += [("backdrop", i["backdrop_remote"], BACKDROP_SIZE) for i in items if i.get("backdrop_remote")]
    jobs += [("logo", i["logo_remote"], LOGO_SIZE) for i in items if i.get("logo_remote")]

    if args.with_stills:
        jobs += [("still", e["still_remote"], STILL_SIZE) for e in episodes[:60]]

    ok = 0
    if not args.skip_images:
        with ThreadPoolExecutor(max_workers=8) as pool:
            for n, (remote, success, info) in enumerate(pool.map(fetch, jobs), 1):
                ok += 1 if success else 0
                if n % 20 == 0 or n == len(jobs):
                    print(f"  图片 {n}/{len(jobs)}  (成功 {ok})", flush=True)

    manifest = {
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "source": "AniShelf mal.store",
        "items": items,
        "episodes": episodes,
    }
    (OUT / "library.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8"
    )

    have = sum(1 for i in items if (OUT / i["cover"]).exists())
    print(f"清单: {len(items)} 条（本地封面 {have}） / 剧集静帧 {len(episodes)} 条")
    print(f"输出目录: {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
