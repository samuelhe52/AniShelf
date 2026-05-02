#!/usr/bin/env python3
"""Convert Xcode .xcstrings catalogs to CSV and back."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Any


DEFAULT_CATALOG = Path("MyAnimeList/Resources/Localizable.xcstrings")
BASE_COLUMNS = ["key", "extractionState"]


def load_catalog(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as file:
        catalog = json.load(file)

    if not isinstance(catalog.get("strings"), dict):
        raise ValueError(f"{path} does not look like an .xcstrings file")

    return catalog


def find_languages(catalog: dict[str, Any]) -> list[str]:
    source_language = catalog.get("sourceLanguage")
    languages: set[str] = set()

    if isinstance(source_language, str) and source_language:
        languages.add(source_language)

    for entry in catalog["strings"].values():
        localizations = entry.get("localizations", {})
        if isinstance(localizations, dict):
            languages.update(localizations.keys())

    return sorted(languages)


def string_unit(entry: dict[str, Any], language: str) -> dict[str, Any] | None:
    localization = entry.get("localizations", {}).get(language)
    if not isinstance(localization, dict):
        return None

    unit = localization.get("stringUnit")
    if not isinstance(unit, dict):
        raise ValueError("Only stringUnit localizations are supported")

    return unit


def export_catalog(catalog_path: Path, csv_path: Path) -> None:
    catalog = load_catalog(catalog_path)
    source_language = catalog.get("sourceLanguage")
    languages = find_languages(catalog)
    fieldnames = BASE_COLUMNS[:]

    for language in languages:
        fieldnames.extend([f"{language}.state", f"{language}.value"])

    with csv_path.open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()

        for key, entry in catalog["strings"].items():
            if not isinstance(entry, dict):
                raise ValueError(f"String entry {key!r} is not an object")

            row = {
                "key": key,
                "extractionState": entry.get("extractionState", ""),
            }

            for language in languages:
                unit = string_unit(entry, language)
                row[f"{language}.state"] = unit.get("state", "") if unit else ""

                if unit:
                    row[f"{language}.value"] = unit.get("value", "")
                elif language == source_language:
                    row[f"{language}.value"] = key
                else:
                    row[f"{language}.value"] = ""

            writer.writerow(row)


def languages_from_header(fieldnames: list[str]) -> list[str]:
    languages: set[str] = set()

    for fieldname in fieldnames:
        if fieldname.endswith(".state"):
            languages.add(fieldname[: -len(".state")])
        elif fieldname.endswith(".value"):
            languages.add(fieldname[: -len(".value")])

    return sorted(languages)


def remove_empty_localizations(entry: dict[str, Any]) -> None:
    localizations = entry.get("localizations")
    if isinstance(localizations, dict) and not localizations:
        entry.pop("localizations")


def import_catalog(template_path: Path, csv_path: Path, output_path: Path) -> None:
    catalog = load_catalog(template_path)
    source_language = catalog.get("sourceLanguage")

    with csv_path.open("r", encoding="utf-8", newline="") as file:
        reader = csv.DictReader(file)
        if not reader.fieldnames or "key" not in reader.fieldnames:
            raise ValueError("CSV must contain a key column")

        languages = languages_from_header(reader.fieldnames)
        strings: dict[str, Any] = {}

        for row in reader:
            key = row.get("key", "")
            if key in strings:
                raise ValueError(f"Duplicate key in CSV: {key!r}")

            original_entry = catalog["strings"].get(key, {})
            if not isinstance(original_entry, dict):
                original_entry = {}

            entry = json.loads(json.dumps(original_entry, ensure_ascii=False))
            extraction_state = row.get("extractionState", "")
            if extraction_state:
                entry["extractionState"] = extraction_state
            else:
                entry.pop("extractionState", None)

            localizations = entry.setdefault("localizations", {})
            if not isinstance(localizations, dict):
                raise ValueError(f"String entry {key!r} has unsupported localizations")

            for language in languages:
                state = row.get(f"{language}.state", "")
                value = row.get(f"{language}.value", "")

                if not state and value == "":
                    localizations.pop(language, None)
                    continue

                if language == source_language and not state and value == key:
                    localizations.pop(language, None)
                    continue

                localizations[language] = {
                    "stringUnit": {
                        "state": state or "translated",
                        "value": value,
                    }
                }

            remove_empty_localizations(entry)
            strings[key] = entry

    catalog["strings"] = strings

    with output_path.open("w", encoding="utf-8") as file:
        json.dump(catalog, file, ensure_ascii=False, indent=2)
        file.write("\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert Localizable.xcstrings to CSV and import CSV changes back."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    export_parser = subparsers.add_parser("export", help="Export an .xcstrings file to CSV")
    export_parser.add_argument(
        "-i",
        "--input",
        type=Path,
        default=DEFAULT_CATALOG,
        help=f"Input .xcstrings file, defaults to {DEFAULT_CATALOG}",
    )
    export_parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("Localizable.csv"),
        help="Output CSV file",
    )

    import_parser = subparsers.add_parser("import", help="Import CSV rows into an .xcstrings file")
    import_parser.add_argument("csv", type=Path, help="Input CSV file")
    import_parser.add_argument(
        "-t",
        "--template",
        type=Path,
        default=DEFAULT_CATALOG,
        help=f"Template .xcstrings file to preserve metadata, defaults to {DEFAULT_CATALOG}",
    )
    import_parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=DEFAULT_CATALOG,
        help=f"Output .xcstrings file, defaults to {DEFAULT_CATALOG}",
    )

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        if args.command == "export":
            export_catalog(args.input, args.output)
        elif args.command == "import":
            import_catalog(args.template, args.csv, args.output)
        else:
            raise ValueError(f"Unknown command: {args.command}")
    except (OSError, ValueError, json.JSONDecodeError, csv.Error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
