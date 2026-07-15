# AniShelf 📺

一个美观的原生 iOS 应用，用来追踪和管理你的动画资料库。

[English](README.md) · [使用教程](docs/anishelf_overview.md)

## 📸 截图

<div style="overflow-x: auto; padding: 0.25rem 0 1rem;">
  <table cellpadding="0" cellspacing="12">
    <tr>
      <td><img src=".app-store-assets/screenshots/ios/featured-library-card.jpeg" alt="AniShelf 精选收藏卡片" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/library-list-view.jpeg" alt="AniShelf 收藏列表视图" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/poster-grid-view.jpeg" alt="AniShelf 海报网格视图" width="240" /></td>
    </tr>
    <tr>
      <td><img src=".app-store-assets/screenshots/ios/anime-detail-overview.jpeg" alt="AniShelf 动画详情概览" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/watch-management-sheet.jpeg" alt="AniShelf 观看管理面板" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/library-stats-overview.jpeg" alt="AniShelf 收藏统计概览" width="240" /></td>
    </tr>
  </table>
</div>

## ✨ 功能

- 从 TMDb 获取番剧/动画电影数据，展示在 App 内。
- 用户可以添加番剧/动画电影到资料库，记录观看状态
  - 未看、在看、已看、搁置
  - 起止日期
- 记录每集观看进度
- 记录感想
- 获取每集的摘要、声优等信息
- 查看番剧/动画电影在 TMDb 上的评分
- 通过 iCloud 在设备之间同步资料库、设置和每集观看进度
- 精美的 UI 设计、流畅的交互体验

## 📱 获取方式

AniShelf 现已上架 iOS App Store，你可以在这里下载：[App Store Link](https://apps.apple.com/us/app/anishelf/id6759359144)。目前除中国大陆外，其他国家和地区均可下载。

新功能会先通过 TestFlight 发布，之后再推送到 App Store。你也可以在这里加入 TestFlight 测试版：[AniShelf TestFlight](https://testflight.apple.com/join/ns3sR38X)。

> 使用应用仍然需要 TMDb API key，可以从 [The Movie Database](https://www.themoviedb.org/settings/api) 免费获取。

## 🛠 技术栈

- **Swift 6.0+**
- **SwiftUI**
- **SwiftData**
- **TMDb API**
- **Kingfisher**

## 🗺 计划

- 与 TMDb、Bangumi、AniList 等平台的观看数据同步功能；这个比较复杂，可能会比较晚再做

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

# 构建 iOS App
make build

# 在已启动的模拟器上运行 App
make run-sim

# 在已启动的模拟器上运行 App 和 DataProvider 测试套件
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

### CLI 与 Agent 访问

AniShelf 的命令行伴侣位于
[samuelhe52/anishelf-cli](https://github.com/samuelhe52/anishelf-cli)。它提供
`ani` 命令，用于只读访问用户已授权的 AniShelf CloudKit 资料库（用户需要先在
App 中启用 iCloud 同步）。

Agent 可参阅 [SKILL.md](https://github.com/samuelhe52/anishelf-cli/blob/main/skills/anishelf-cli/SKILL.md)，了解如何安装和使用 `ani` 命令。

对于普通用户，安装和初始化需要 Python 3.13+ 与 `uv`：

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

本项目遵循 Conventional Commits 提交格式：

- 使用 `feat`、`fix`、`docs`、`test`、`refactor` 或 `style` 等类型作为前缀
- 使用祈使语气、首字母大写且简洁的主题
- 主题末尾不要使用句号
- 仅在有助于说明改动时添加简短正文

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
