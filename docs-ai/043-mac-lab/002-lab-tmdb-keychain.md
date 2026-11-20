# 043.002 — Lab TMDb key

## Context

The plan first had Lab take its TMDb key at every launch, so it stored no credential.
Entering it each time was too much friction.

## Change

Lab asks for the key once and keeps it in its own Keychain item, which survives between
runs. Rejected: reading the live app's key, which would couple Lab to live AniShelf.

## Refs

`MyAnimeList/Sources/Utils/TMDbAPIKeyStorage.swift`
