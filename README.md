# AniShelf 📺

A beautiful, native iOS app for tracking and managing your anime library.

[中文](README.zh-CN.md) · [使用教程](docs/anishelf_overview.md)

## 📸 Screenshots

<div style="overflow-x: auto; padding: 0.25rem 0 1rem;">
  <table cellpadding="0" cellspacing="12">
    <tr>
      <td><img src=".app-store-assets/screenshots/ios/featured-library-card.jpeg" alt="AniShelf featured library card" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/library-list-view.jpeg" alt="AniShelf library list view" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/poster-grid-view.jpeg" alt="AniShelf poster grid view" width="240" /></td>
    </tr>
    <tr>
      <td><img src=".app-store-assets/screenshots/ios/anime-detail-overview.jpeg" alt="AniShelf anime detail overview" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/watch-management-sheet.jpeg" alt="AniShelf watch management sheet" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/library-stats-overview.jpeg" alt="AniShelf library stats overview" width="240" /></td>
    </tr>
  </table>
</div>

## ✨ Features

- **📚 Library Management** - Keep track of all your anime in one place
- **🔍 Smart Search** - Find anime using The Movie Database (TMDb) with multi-language support
- **🎨 Beautiful UI** - Native SwiftUI interface, polished and consistent design language
- **📊 Track Progress** - Track watch status, scores, and episode-level progress
- **👤 Library Profile** - Overview your library with a dedicated profile page
- **💾 Backup & Restore** - Export and import your library data
- **☁️ iCloud Sync** - Keep your library, settings, and episode progress in sync across your devices
- **🌍 Multi-language** - Support for anime titles and descriptions in multiple languages

## 📱 Availability

AniShelf is currently available on the iOS App Store. You can download it here: [App Store Link](https://apps.apple.com/us/app/anishelf/id6759359144). The app is available in all countries except for China Mainland.

Note that new features will first be released on TestFlight before being pushed to the App Store. You can join the TestFlight beta here: [AniShelf TestFlight](https://testflight.apple.com/join/ns3sR38X).

> You still need a TMDb API key to use the app, which can be obtained for free from [The Movie Database](https://www.themoviedb.org/settings/api).

## 🛠 Tech Stack

- **Swift 6.0+** with strict concurrency
- **SwiftUI** for modern, declarative UI
- **SwiftData** for data persistence
- **TMDb API** integration for anime metadata
- **Kingfisher** for efficient image loading and caching

## 🗺 Plans

- Watch-data sync with platforms such as TMDb, Bangumi, and AniList; this is a large feature and may take time

## 📋 Build/Run Requirements

- iOS 26.0+
- Xcode 26.0+
- Swift 6.0+
- TMDb API key (free from [The Movie Database](https://www.themoviedb.org/settings/api))

## 🚀 Getting Started

1. **Clone the repository**

   ```bash
   git clone https://github.com/samuelhe52/AniShelf.git
   cd AniShelf
   ```

2. **Open in Xcode**

   ```bash
   open MyAnimeList.xcodeproj
   ```

3. **Build and run**
   - Select your target device or simulator
   - Press `⌘R` to build and run
   - On first launch, you'll be prompted to enter your TMDb API key

## 🔧 Development

### Build Commands

```bash
# Clean build artifacts
make clean

# Refresh Swift package dependencies
make refresh-packages

# Format code
make format

# Lint code
make lint

# Build the app for iOS
make build

# Run the app on a booted simulator
make run-sim

# Run the app and DataProvider test suites on a booted simulator
make test-sim

# Build, install, and launch on a connected iPhone
make run-device

# Reset the TMDb API key before launching on a connected iPhone
make run-device-reset-tmdb-api-key
```

### Project Structure

> **Note:** The app was renamed from **MyAnimeList** to **AniShelf**. Only the display name and the top-level repository folder were changed; internal directory and file names still use `MyAnimeList` for simplicity and backward compatibility.

- `MyAnimeList/` - Main iOS application
- `DataProvider/` - SwiftData persistence layer (Swift Package)

For detailed architecture and development guidelines, see [AGENTS.md](AGENTS.md).

### CLI & Agentic Access

AniShelf's command-line companion lives in
[samuelhe52/anishelf-cli](https://github.com/samuelhe52/anishelf-cli). It
provides the `ani` command for read-only access to a user-authorized AniShelf
CloudKit library (requires the user to enable iCloud Sync in the app).

For agents, go to [SKILL.md](https://github.com/samuelhe52/anishelf-cli/blob/main/skills/anishelf-cli/SKILL.md) for details on how to install and use the `ani` command.

For humans, installation/bootstrap requires Python 3.13+ and `uv`:

```bash
uv tool install --python 3.13 git+https://github.com/samuelhe52/anishelf-cli.git@v0.1.0
ani auth login
ani config set-tmdb-api-key
ani lib init
ani lib list
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Commit Message Guidelines

This project follows the Conventional Commits format:

- Start with a type such as `feat`, `fix`, `docs`, `test`, `refactor`, or `style`
- Use an imperative, capitalized, concise subject
- Do not end the subject with a period
- Add a short body only when it clarifies the change

Examples:

```git
feat: Add library search

fix: Restore library backups correctly

refactor: Simplify library views
```

## 📝 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [The Movie Database (TMDb)](https://www.themoviedb.org/) for their comprehensive anime database
- [Kingfisher](https://github.com/onevcat/Kingfisher) for image loading and caching

---

**Built with ❤️ using Swift and SwiftUI**
