# AniShelf Overview

**AniShelf is available on the App Store: [App Store link](https://apps.apple.com/app/id6759359144). New features ship to TestFlight first and reach the App Store later. TestFlight link: [AniShelf TestFlight](https://testflight.apple.com/join/ns3sR38X).**

AniShelf helps you track, record, and manage the anime series and films you've watched. Core features:

- Fetch anime series and film data from TMDb and display it in the app.
- Add series and films to your library and track your watch status
  - Planned, Watching, Watched, Dropped
  - Start and finish dates
  - Episode-level watch progress
- Write notes and give ratings
- Favorite entries, then filter or group the library by favorite status
- Batch add from search: add multiple entries at once by title or TMDb ID
- Multi-select entries in list and grid views to change watch status, rating, favorite, and date tracking in bulk, or delete them in bulk
- View per-episode summaries, voice cast, and more
- View an entry's TMDb rating
- View air times for eligible series and set reminders for each new episode of currently airing shows
- Sync your library, settings, and watch progress across devices with iCloud Sync
- Back up and restore your AniShelf library and settings, or export the library as TXT, CSV, TSV, JSON, or XLSX
- A polished UI and smooth interactions

AniShelf also has a companion command-line tool, [anishelf-cli](https://github.com/samuelhe52/anishelf-cli). With iCloud Sync enabled, the `ani` command gives you read-only access to your AniShelf library. See the [anishelf-cli README](https://github.com/samuelhe52/anishelf-cli#readme) for installation and usage.

**What it is not:**

- **A streaming or download tool (it provides no download links or playback)**
- **A novel or manga reader (the "shelf" is a metaphor, not an actual bookshelf)**

Not yet available:

- Syncing watch data with platforms such as TMDb, AniList, or Bangumi

> AniShelf relies on the TMDb API for anime data, and direct access to TMDb can be unreliable on some networks. The app connects to TMDb directly by default. If search or metadata loading fails, you can turn on "Use TMDb Proxy" in Settings to route TMDb API requests through a self-hosted proxy server. Posters and other images do not go through this proxy, so they may still fail to load depending on your network.
> If you use a VPN or another network proxy, it's usually best to leave "Use TMDb Proxy" off; connecting to TMDb directly tends to be more reliable and faster.

## Guide

### Get an API Key

AniShelf requires a TMDb API key, which is free for personal use. To get one:

1. Go to the [TMDb website](https://www.themoviedb.org/) and create an account.
2. After signing in, open your account settings and find the API section, or go directly to the [TMDb API page](https://www.themoviedb.org/settings/api/request).
3. Choose Personal Use and fill in the form:
   1. Application Name: "AniShelf".
   2. Application URL: the TestFlight link (https://testflight.apple.com/join/ns3sR38X) or the GitHub repository (https://github.com/samuelhe52/AniShelf).
   3. Type of Use: "Mobile Application".
   4. Application Summary: we suggest "A digital bookshelf for your anime – track, organize, and revisit your favorite series with ease."
   5. Contact info can be anything you like. Accept the terms and click "Subscribe".
4. Go back to the [API page](https://www.themoviedb.org/settings/api), copy your API key at the bottom of the page, and keep it somewhere safe.

### Using the App

1. Download and install AniShelf.
   1. Search for "AniShelf" on the App Store, or use this link: [App Store link](https://apps.apple.com/app/id6759359144).
   2. You can also join the TestFlight beta to try new features early: [AniShelf TestFlight](https://testflight.apple.com/join/ns3sR38X). If you don't have TestFlight installed, install the TestFlight app first, then open the link again and tap "View in TestFlight".
2. On first launch, enter your TMDb API key when prompted.
3. Tap the search button at the bottom right, enter the name of a series or film, and add the matching entry to your library.
   1. For series, you can add the whole series or individual seasons (switch modes with the slider below). Use the button at the top right to select the series or one or more seasons, then tap "Add To Library...".
   2. For films, select the entry and tap "Add To Library...".
   3. Some shows air in multiple seasons, but the official release doesn't separate them into seasons (episode numbering is continuous). A typical example is *Frieren: Beyond Journey's End*, where "Season 1" contains all 38 episodes. In cases like this, add the whole series instead.
   4. To add several entries at once, tap "Batch Add" at the top right of the search page and enter multiple titles or TMDb IDs.
4. Tap the icon at the bottom left to switch between library views.
5. Use the status bar at the bottom center to filter entries, for example to show only entries you're Watching.
6. Double-tap an entry on the main screen to open its detail page, where you can view details and record watch status, start and finish dates, notes, and more.
   1. Tap the "···" button on the detail page to convert between series and season entries, mark an entry as Dropped, and more.
   2. Tap the heart button to favorite or unfavorite an entry.
   3. Tap the share button to generate a poster for recommending the show to friends.
   4. Scroll down to see the overview, voice cast, episode summaries, and more.
   5. Eligible series show their air times; use the "···" menu to set reminders for each new episode of a currently airing show.
7. Long-press an entry on the main screen for more actions. In list view, swipe right or left on an entry to quickly update its watch status or delete it.
8. In list or grid view, tap "Select" at the top right to enter multi-select mode, where you can change status, rating, favorite, and date tracking in bulk, or delete entries in bulk.
9. Tap the settings icon at the top right to open Settings, where you can see a library overview and change app settings.
   1. To sync your library, settings, and watch progress across devices, turn on iCloud Sync in Settings and make sure every device is signed in to the same Apple Account.
   2. In "Backup & Restore", you can create or restore backups of your library and settings; "Export as..." exports the library to common file formats.

## FAQ

- What is the TMDb API? What is an API key? **AniShelf uses the TMDb API to fetch data for series and films, such as titles, overviews, and posters. A TMDb API key is a credential you request from the TMDb website that authorizes AniShelf to access TMDb data. Because the app is completely free, there is no shared API key; you need to request your own by following the guide above.**
- My API key won't validate, loading is slow, or search returns nothing? **Try turning your VPN on or off, since some network proxy rules can interfere with access. The app connects to TMDb directly by default; if that's unreliable, turn on "Use TMDb Proxy" in Settings. If you already use a VPN or another network proxy, it's usually best to leave that option off.**
- How do I sync my library across devices? **Turn on iCloud Sync in Settings and make sure every device is signed in to the same Apple Account. It syncs your library, related settings, and watch progress. Syncing watch data with TMDb, AniList, Bangumi, and similar platforms isn't supported yet.**
- How do I report a bug or request a feature? **Please open a GitHub Issue for bug reports and feature requests.**
- Is it on the App Store? **Yes: [App Store link](https://apps.apple.com/app/id6759359144). In most cases, new features will still ship to TestFlight first and reach the App Store later.**
- Does it support OS versions earlier than 26? **Not at the moment. The app makes heavy use of Liquid Glass, which isn't available before iOS/iPadOS 26, and I don't have a test device running an earlier version. If you'd like to help with internal testing, open a GitHub Issue and I can try adding support, though the UI probably won't look as good.**
- Is there an Android version? **There are no plans for one at the moment.**

## Roadmap

**AniShelf started as a personal project. I know the current version doesn't cover everything many users need, but this is a passion project and I also have school and work, so updates won't be very frequent. Thanks for understanding. I'll prioritize bugs that affect the experience and add new features where it makes sense.**

Planned updates:

- Ongoing bug fixes
- Syncing watch data with platforms such as TMDb, AniList, or Bangumi (an ambitious goal; this is fairly complex, and I'm not sure when I'll have time for it)

Note: The order of this list does not reflect the order in which features will be implemented.
