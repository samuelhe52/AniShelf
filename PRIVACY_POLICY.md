# Privacy Policy for AniShelf

Effective date: October 2, 2026

AniShelf is an anime library management app for iPhone, iPad, and Mac. This
Privacy Policy explains what information the app handles, how that information
is used, and the choices available to you.

## Summary

- AniShelf stores your library data primarily on your device.
- Optional iCloud Sync stores library tracking data and selected preferences in
  your private iCloud database.
- AniShelf does not require an AniShelf account. iCloud Sync uses your Apple
  Account, and TMDb features use a TMDb API key you provide.
- Search, metadata, artwork, and broadcast features contact external services.
- AniShelf does not sell your personal information.
- AniShelf does not use third-party advertising SDKs.
- AniShelf does not use cross-app tracking.
- AniShelf does not include an analytics or automatic crash-reporting service.
  Recovery diagnostics stay on your device unless you choose to share them.

## Information AniShelf Handles

AniShelf may handle the following categories of information:

### 1. Library Data You Create

When you use AniShelf, the app stores information you choose to add, such as:

- anime titles and entries saved to your library
- watch status, progress, ratings, notes, or other library metadata
- favorites, viewing dates, and poster selections
- viewing, sorting, and language preferences, and the saved search query

This information is stored locally on your device using Apple's system
storage technologies. If you enable iCloud Sync, the data described below also
syncs through Apple's CloudKit service.

### 2. Optional iCloud Sync

When you enable iCloud Sync, AniShelf uploads library identifiers, watch status,
episode progress, ratings, favorites, notes, viewing dates, poster selections,
and synchronization timestamps to a private CloudKit database associated with
your Apple Account. Selected preferences, including language, sorting, filters,
and the TMDb relay setting, also sync across your devices.

Fetched title descriptions and artwork are retrieved again from content
providers when needed. Your TMDb API key, saved search query, and device-specific
airing reminder subscriptions are not included in AniShelf's CloudKit sync.
Apple's services may deliver background notifications so AniShelf can check for
library changes.

### 3. TMDb API Key You Provide

If you choose to use TMDb-powered search and metadata features, you may enter
your own TMDb API key. AniShelf stores this key in the system Keychain on your
device so the app can authenticate requests to TMDb. The key is sent with API
requests, including requests routed through the optional relay described below.
AniShelf does not include the Keychain key in its library backup files or
CloudKit sync.

### 4. Search, Metadata, and Broadcast Requests

When you search for titles or fetch anime details, AniShelf sends the relevant
request data to The Movie Database (TMDb) or TMDb-related endpoints used by the
app so it can return search results, descriptions, posters, and related
metadata.

These requests may include information such as:

- search terms you enter
- requested title identifiers
- language or localization preferences needed to fetch results

TMDb and any services involved in delivering that content may receive your IP
address and standard network metadata as part of those requests.

When broadcast schedules are enabled, AniShelf also contacts TVMaze to match
shows and retrieve broadcast times and upcoming episodes. These requests may
include show titles and IMDb, TVDB, or TVMaze identifiers. TVMaze receives your
IP address and standard request information. Schedule lookups do not send your
notes, ratings, or watch progress.

Requests can occur when you browse, add or restore entries, refresh library
metadata, or refresh airing reminders, including background reminder refreshes.

### 5. Optional TMDb Relay

The TMDb relay setting is off by default. If you enable it, AniShelf routes TMDb
API requests through `tmdb-api.konakona.dev` instead of directly to TMDb's API
host. The relay receives the request contents and authentication information,
including your TMDb API key, as well as your IP address and standard network
metadata. Disabling the relay returns subsequent TMDb API requests to the
direct route.

### 6. Images and Cached Media

AniShelf downloads poster or artwork images associated with titles you browse.
These images may be cached locally on your device to improve performance and
reduce repeated downloads.

### 7. Airing Reminders

If you enable airing reminders, AniShelf stores your selected shows, reminder
timing, and scheduling state on the device and requests notification permission.
It fetches upcoming episode information from TVMaze and schedules local
notifications. Notifications can display show titles and episode information,
including on the lock screen depending on your system settings. Reminder
subscriptions and timing settings are not included in AniShelf's CloudKit sync
or library backup preferences.

### 8. Backup, Import, Export, and Sharing Data

If you use backup, restore, export, import, or sharing features, AniShelf may
create files containing your library data and selected app preferences,
including your saved search query. These exports are created when you initiate
those actions. Full library backups copy the local database directory and may
also include preserved recovery files described below.

Shared or exported content is handled through Apple's system share sheet or
other destination you choose. Once you share data outside the app, its handling
is governed by the recipient service or app.

### 9. Recovery Files and Diagnostics

If AniShelf cannot open its local database, it may automatically preserve a copy
of the affected database files on your device before creating a replacement.
It also saves a diagnostic report containing the recovery time, error details,
app version and build, operating system version, and file names and sizes.

You can choose to export the diagnostic report or a recovery bundle. The bundle
includes the preserved database and may contain your library and notes; error
details in the report may include local file paths. AniShelf does not
automatically upload these files to the publisher. Share them only with a
recipient you intend to receive that information.

## How AniShelf Uses Information

AniShelf uses the information it handles to:

- store and display your anime library
- remember your settings and in-app preferences
- search TMDb and fetch title metadata, posters, and translations
- synchronize library tracking data and selected preferences through iCloud
  when enabled
- retrieve TVMaze broadcast information and schedule reminders you enable
- create backups and restore your library when you request it
- generate images or files for sharing and export when you request it
- maintain app functionality and performance
- preserve local data and help diagnose database recovery problems

## What AniShelf Does Not Do

AniShelf currently does not:

- create user accounts
- run targeted advertising
- sell personal information
- perform cross-app tracking
- intentionally collect usage analytics for marketing purposes
- intentionally collect precise location data, contacts, photos, microphone
  input, or camera data for ordinary app operation

## Data Storage and Retention

- Library data and preferences are generally stored on your device.
- If iCloud Sync is enabled, the synced data also remains in your private
  CloudKit database. Turning off sync stops synchronization on that device;
  it does not erase data already stored in iCloud.
- Library deletions propagate to your other devices when sync completes.
  Minimal deletion records, including entry identifiers and deletion times,
  remain to prevent deleted entries from being restored by an older device.
  Removing a series while keeping its seasons can retain the parent record
  needed by those seasons.
- TMDb API keys are stored in your device Keychain.
- Cached images and temporary export files may remain on device storage until
  they are cleared by the app or the operating system.
- Backups you create are stored wherever you choose to save or share them.
- Preserved recovery databases remain on the device after you dismiss the
  recovery notice. Deleting current library entries does not remove those
  preserved copies or separately exported files.
- If you delete the app, some locally stored data may also be deleted by the
  operating system, but files you exported or shared separately will not be
  removed automatically. Uninstalling the app does not itself erase its iCloud
  records, and Keychain items may persist separately from app storage.

## Third-Party Services

AniShelf relies on third-party services to provide some functionality.

### The Movie Database (TMDb)

AniShelf uses TMDb to provide anime search results, metadata, and artwork.
Your use of TMDb-backed features may also be subject to TMDb's terms and
privacy practices.

[TMDb Privacy Policy](https://www.themoviedb.org/privacy-policy)

### TVMaze

AniShelf uses TVMaze for show matching, broadcast schedules, and upcoming
episode information.

[TVMaze Privacy Policy](https://www.tvmaze.com/site/privacy)

### Apple iCloud and System Services

AniShelf uses Apple's CloudKit service for optional iCloud Sync and Apple's
system services for notifications, Keychain storage, and file sharing. Apple's
handling of information is governed by its own privacy policy and your Apple
Account and device settings.

[Apple Privacy Policy](https://www.apple.com/legal/privacy/en-ww/)

## Children

AniShelf is not directed to children under 13, and the app does not knowingly
collect personal information from children.

## Your Choices

You can choose to:

- avoid entering a TMDb API key
- avoid using network-based search and metadata features
- turn iCloud Sync on or off in AniShelf settings
- disable the TMDb relay to send API requests directly to TMDb
- turn off broadcast schedules and remove airing reminder subscriptions
- control notification permission and previews in system settings
- delete your library entries within the app
- delete cached data where such controls are provided
- avoid using backup, export, import, or sharing features
- choose whether to export or share recovery diagnostics and database files
- uninstall the app

## International Users

If you use AniShelf, requests to Apple iCloud, TMDb, TVMaze, the optional relay,
or related content providers may be processed in countries other than your own,
subject to those providers'
infrastructure and policies.

## Changes to This Privacy Policy

This Privacy Policy may be updated from time to time. If it changes, the
updated version will be posted with a new effective date.

## Contact

For privacy questions about AniShelf, email the app publisher at
[samuelhe52@outlook.com](mailto:samuelhe52@outlook.com). For other help, see the
[AniShelf support page](https://anishelf.konakona.dev/support/).
