#!/usr/bin/env python3
"""Opens AniShelf Lab on a fresh copy of the live Mac library, or exports the live
preferences (docs-ai 043).

  lab.py run <Lab.app> [language]
  lab.py export-defaults <output.plist>
"""

import os
import plistlib
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

LIVE_ID = "com.samuelhe.MyAnimeList"
LAB_ID = "com.samuelhe.MyAnimeList.lab"


def fail(message) -> NoReturn:
    sys.exit(f"AniShelf Lab: {message}")


def is_running(bundle_id):
    result = subprocess.run(["/usr/bin/lsappinfo", "find", f"bundleid={bundle_id}"], capture_output=True, text=True)
    return bool(result.stdout.strip())


def container(bundle_id):
    """The app's sandbox data directory, or None. An app that once ran on the Mac as an
    iPad app keeps a UUID-named container, so match on the registered identifier."""
    for path in (Path.home() / "Library/Containers").iterdir():
        try:
            with open(path / ".com.apple.containermanagerd.metadata.plist", "rb") as file:
                if plistlib.load(file).get("MCMMetadataIdentifier") == bundle_id:
                    return path / "Data"
        except (OSError, plistlib.InvalidFileException):
            continue
    return None


def live_container():
    live = container(LIVE_ID)
    if live is None:
        fail("Cannot find the live AniShelf sandbox. If macOS asked, allow your terminal to access app data.")
    return live


def run(app, language):
    if is_running(LAB_ID):
        fail("Quit AniShelf Lab first; each launch starts from a fresh copy.")
    live = live_container()
    lab = container(LAB_ID)
    if lab is None:
        subprocess.run(["/usr/bin/open", "-W", "-g", "-j", app, "--args", "--lab-create-container"], check=True)
        lab = container(LAB_ID) or fail("macOS did not create the Lab sandbox.")

    snapshot = lab / "tmp/AniShelfLab/Snapshot"
    shutil.rmtree(snapshot, ignore_errors=True)
    snapshot.mkdir(parents=True)
    # A read-only SQLite connection takes a consistent snapshot even while AniShelf is open.
    store = live / "Library/Application Support/DataProvider/mal.store"
    database = sqlite3.connect(f"{store.as_uri()}?mode=ro", uri=True)
    database.execute("VACUUM INTO ?", (str(snapshot / "mal.store"),))
    database.close()
    preferences = live / f"Library/Preferences/{LIVE_ID}.plist"
    if preferences.exists():
        shutil.copyfile(preferences, snapshot / "Preferences.plist")

    arguments = ["-AppleLanguages", f"({language})"] if language else []
    subprocess.run(["/usr/bin/open", app, "--args", *arguments], check=True)


def export_defaults(output):
    if is_running(LIVE_ID):
        fail("Quit AniShelf first, so its preferences are saved to disk.")
    source = live_container() / f"Library/Preferences/{LIVE_ID}.plist"
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as file, open(source, "rb") as preferences:
        shutil.copyfileobj(preferences, file)
    print(f"Exported the live preferences to {output}. It can contain account state; keep it private.")


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if len(arguments) in (2, 3) and arguments[0] == "run":
        run(arguments[1], arguments[2] or None if len(arguments) == 3 else None)
    elif len(arguments) == 2 and arguments[0] == "export-defaults":
        export_defaults(arguments[1])
    else:
        sys.exit(__doc__)
