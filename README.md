# AniShelf 📺

A native iOS app for tracking and managing your anime library.

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

## 📱 Availability

AniShelf is currently available on the [App Store](https://apps.apple.com/us/app/anishelf/id6759359144).

New features will be released on TestFlight before being pushed to the App Store. You can join the [TestFlight Beta](https://testflight.apple.com/join/ns3sR38X) to get early access to new features and provide feedback.

> You need a TMDb API key to use the app, which can be obtained for free from [The Movie Database](https://www.themoviedb.org/settings/api).

## ✨ Features

- **📚 Library Management** - Keep track of all your anime in one place
- **🔍 Smart Search** - Find anime using The Movie Database (TMDb) with multi-language support
- **🎨 Beautiful UI** - Native SwiftUI interface, polished and consistent design language
- **📊 Track Progress** - Track watch status, scores, and episode-level progress
- **💾 Backup & Restore** - Export and import your library data
- **☁️ iCloud Sync** - Keep your library and preferences in sync across your devices
- **🌍 Multi-language** - Support for anime metadata in English, Chinese, and Japanese.

## CLI & Agentic Access

AniShelf also has a companion CLI: [anishelf-cli](https://github.com/samuelhe52/anishelf-cli). It provides the `ani` command for read-only access to your AniShelf library. Turn on iCloud Sync in AniShelf first.

If you are an agent, follow [SKILL.md](https://github.com/samuelhe52/anishelf-cli/blob/main/skills/anishelf-cli/SKILL.md) for installation and usage details.

For manual installation and setup, follow the [anishelf-cli README](https://github.com/samuelhe52/anishelf-cli#readme).

## 🔧 Development

### 📋 Build/Run Requirements

- iOS/iPadOS 26.0+
- Xcode 26.0+
- Swift 6.0+
- TMDb API key (free from [The Movie Database](https://www.themoviedb.org/settings/api))

### 🚀 Getting Started

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

### Common Commands

```bash
make build
make run-sim # Build and run on a booted simulator
make test-sim # Run the app and DataProvider test suites on a booted simulator
make lint
```

> **Note:** The app was renamed from **MyAnimeList** to **AniShelf**. The app display name changed, but internal directories and the Xcode project still use `MyAnimeList` for backward compatibility.

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

**Made with ❤️ using Swift and SwiftUI**
