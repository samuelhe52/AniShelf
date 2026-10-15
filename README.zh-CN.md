<div align="center">
  <img src="docs/images/anishelf-icon.webp" alt="AniShelf 应用图标" width="160" />

  <h1>AniShelf</h1>

  <p>一款适用于 iPhone、iPad 和 Mac 的原生动漫收藏管理应用。</p>

  <p>
    <img src="https://img.shields.io/badge/platform-iOS%20%C2%B7%20iPadOS%2026%2B-34C759" alt="支持 iOS 和 iPadOS 26 及以上版本" />
    <img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="Apache 2.0 许可证" />
    <a href="https://apps.apple.com/app/id6759359144"><img src="https://img.shields.io/badge/App%20Store-%E7%AB%8B%E5%8D%B3%E4%B8%8B%E8%BD%BD-007AFF?logo=apple&logoColor=white" alt="从 App Store 下载 AniShelf" /></a>
  </p>

  <p><a href="README.md">English</a> · <a href="https://anishelf.konakona.dev/zh/">官方网站</a> · <a href="docs/anishelf_overview.md">使用教程</a> · <a href="https://testflight.apple.com/join/ns3sR38X">TestFlight 测试版</a></p>
</div>

---

## 📸 截图

<div style="overflow-x: auto; padding: 0.25rem 0 1rem;">
  <table cellpadding="0" cellspacing="12">
    <tr>
      <td><img src=".app-store-assets/screenshots/ios/01-poster-grid-view.jpeg" alt="AniShelf poster grid view" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/02-featured-library-card.jpeg" alt="AniShelf featured library card" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/03-library-list-view.jpeg" alt="AniShelf library list view" width="240" /></td>
    </tr>
    <tr>
      <td><img src=".app-store-assets/screenshots/ios/04-anime-detail-overview.jpeg" alt="AniShelf anime detail overview" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/05-watch-management-sheet.jpeg" alt="AniShelf watch management sheet" width="240" /></td>
      <td><img src=".app-store-assets/screenshots/ios/06-library-stats-overview.jpeg" alt="AniShelf library stats overview" width="240" /></td>
    </tr>
  </table>
</div>

## 📱 获取方式

AniShelf 现已上架 [App Store](https://apps.apple.com/app/id6759359144)，支持运行 iOS 或 iPadOS 26 及以上版本的 iPhone 和 iPad，以及搭载 Apple 芯片的 Mac（运行 iPad 版应用）。

新功能会先通过 TestFlight 发布，之后再推送到 App Store。你可以加入 [TestFlight 测试版](https://testflight.apple.com/join/ns3sR38X)，抢先体验新功能并提供反馈。

> 使用应用需要一个 TMDb API 密钥，可以从 [The Movie Database](https://www.themoviedb.org/settings/api) 免费获取。

## ✨ 功能

- **📚 资料库管理** - 整理收藏所有动漫作品
- **🔍 智能检索** - 依托 TMDb 数据库多语言检索动漫资源
- **🎨 精致界面** - 基于原生 SwiftUI 搭建，视觉风格统一精致
- **📊 进度追踪** - 标记观看状态、打分，精准记录单集观看进度和重看次数
- **⏰ 播出与提醒** - 查看符合条件番剧的播出时间，并为新番每集设置播出前或播出后的提醒
- **💾 备份还原** - 备份和恢复资料库与设置，也可以将资料库导出为常用文件格式
- **☁️ iCloud同步** - 跨设备同步资料库数据与偏好设置
- **🌍 多语言适配** - 动漫元数据支持英文、中文、日文

## CLI 与 Agent 集成

AniShelf 还提供配套 CLI：[anishelf-cli](https://github.com/samuelhe52/anishelf-cli)。它提供 `ani` 命令，让你以只读方式访问你的 AniShelf 资料库。请先在 AniShelf 中开启 iCloud 同步。

如果你是 Agent，请阅读 [SKILL.md](https://github.com/samuelhe52/anishelf-cli/blob/main/skills/anishelf-cli/SKILL.md) 了解安装和使用详情。

如需手动安装和设置，请参考 [anishelf-cli README](https://github.com/samuelhe52/anishelf-cli#readme)。

## 🔧 开发

### 📋 构建与运行要求

- iOS/iPadOS 26.0+
- Xcode 26.0+
- Swift 6.0+
- TMDb API 密钥（可从 [The Movie Database](https://www.themoviedb.org/settings/api) 免费获取）

### 🚀 快速开始

1. **克隆仓库**

   ```bash
   git clone https://github.com/samuelhe52/AniShelf.git
   cd AniShelf
   ```

2. **在 Xcode 中打开项目**

   ```bash
   open MyAnimeList.xcodeproj
   ```

3. **构建并运行**
   - 选择目标设备或模拟器
   - 按下 `⌘R` 构建并运行
   - 首次启动时，系统会提示你输入 TMDb API 密钥

### 常用命令

```bash
make build
make run-sim  # 在已启动的模拟器上构建并运行
make test-sim # 在已启动的模拟器上运行 App 和 DataProvider 测试套件
make lint
```

> **注意：**应用曾从 **MyAnimeList** 更名为 **AniShelf**。App 显示名称已更新，但内部目录和 Xcode 项目仍使用 `MyAnimeList`，以保持向后兼容。

## 🤝 贡献

欢迎贡献代码！请随时提交 Pull Request。

### Commit Message 规范

本项目遵循 Conventional Commits 格式。

示例：

```git
feat: Add library search

fix: Restore library backups correctly

refactor: Simplify library views
```

## 📝 许可证

本项目采用 Apache License 2.0；详情请参阅 [LICENSE](LICENSE)。

## 🙏 致谢

- 感谢 [The Movie Database (TMDb)](https://www.themoviedb.org/) 提供全面的动画数据库
- 感谢 [Kingfisher](https://github.com/onevcat/Kingfisher) 提供图片加载与缓存功能

---

**Made with ❤️ using Swift and SwiftUI**
