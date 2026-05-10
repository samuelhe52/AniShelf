# AniShelf 简介

**当前已上线 App Store，欢迎下载体验：[App Store 链接](https://apps.apple.com/us/app/anishelf/id6759359144)。新功能将先在 TestFlight 发布，后续再推送到 App Store。TestFlight 链接：[AniShelf TestFlight](https://testflight.apple.com/join/ns3sR38X)。**

AniShelf 主要用来追踪、记录、管理看过的番剧/动画电影。核心功能：

- 从 TMDb 获取番剧/动画电影数据，展示在 App 内。
- 用户可以添加番剧/动画电影到资料库，记录观看状态
  - 未看、在看、已看、搁置
  - 起止日期
- 可以记录感想
- 可以获取每集的摘要、声优等信息
- 可以查看番剧/动画电影在 TMDb 上的评分
- 精美的 UI 设计、流畅的交互体验

**它不是：**

- **在线追/看番工具（不提供更新提醒、下载链接、在线播放等功能）**
- **小说/漫画阅读器（“书架”取比喻义，不是真的书架）**

在当前版本，暂时没有：

- 评分功能（用户无法给番剧/动画电影打分）。但是可以将特别喜欢的番剧/动画电影标记为“特别收藏/Favorite”。
- 精确到集的观看进度记录
- 与 TMDb/Bangumi/AniList 等平台观看数据同步功能

> 由于动漫信息搜刮依赖 TMDb API，其访问在大陆不太稳定，建议在添加动漫的时候挂上梯子使用。当前默认 TMDb API 是走我自建的一个代理服务器，能够保证不挂梯子前提下正常的搜索和获取元数据；但是海报等图片资源仍然可能加载失败（实测下来有些网络环境下能成功有些不行，要追求速度的话还是挂梯子）。
> 如果你长时间挂梯子，或者遇到无法搜索到结果/元数据加载失败的情况，可以在设置页面里关掉 TMDb 代理选项，这样就会（通过梯子）直接访问 TMDb API，可能会有更稳定快速的搜索和加载体验。

## 教程

### 申请 API Key

要使用 AniShelf，需要一个对个人使用免费的 TMDb API Key。请按照以下步骤申请：

1. 访问 [TMDb 官网](https://www.themoviedb.org/)，并注册一个账户。
2. 登录后，进入账户设置页面，找到 API 部分；或直接访问 [TMDb API 页面](https://www.themoviedb.org/settings/api/request)。
3. 选择 Personal Use/个人使用选项，并填写信息：
   1. 应用名称填写 "AniShelf"。v
   2. 应用网址可以填写 TestFlight 链接 (https://testflight.apple.com/join/ns3sR38X)，或者 GitHub 仓库链接 (https://github.com/samuelhe52/AniShelf)。
   3. 使用类型选择 "Mobile Application"。
   4. 应用概述建议填“A digital bookshelf for your anime – track, organize, and revisit your favorite series with ease.”
   5. Contact Info 可以随便填；同意条款后点击 "Subscribe"。
4. 再次访问 [API 页面](https://www.themoviedb.org/settings/api)，在页面最下方，复制你的 API Key 并保存好。

### App 使用

1. 下载并安装 AniShelf App。
   1. 目前已上架 App Store，直接搜索 "AniShelf" 即可；或者直接点击链接： [App Store 链接](https://apps.apple.com/us/app/anishelf/id6759359144)。
   2. 也可以加入 TestFlight 测试版，提前体验新功能：[AniShelf TestFlight](https://testflight.apple.com/join/ns3sR38X)。如果没有安装 TestFlight，需要先安装 TestFlight 应用，再重新访问链接，点击 "View in TestFlight"。
2. 如第一次打开，需要按提示输入 TMDb API Key。
3. 在应用内，点击右下方搜索按钮，输入番剧/动画电影名称，找到对应条目后可以添加到资料库。
   1. 对于番剧，可以选择添加整个系列，或者单独添加某一季（通过下面的滑块选择模式）。点击右上角的按钮即可选中系列/某一季（或多季），然后点击 "加入资料库"。
   2. 对于动画电影，直接选中后点击 "加入资料库" 即可。
   3. 有些番剧虽然从播出时间上来看是多季的，但动画官方并没有区分季的概念（集数是连续的）。典型的例子是芙莉莲，“第一季”包含了全部三十八集。遇到这种情况就只能选择添加整个系列了。
4. 点击左下角图标，可以切换不同的资料库视图。
5. 下方正中央的状态栏可以对展示的条目进行过滤，例如只显示“在看”状态的番剧/动画电影。
6. 双击主页面中的条目可以进入详情页，在那里可以查看条目的详细信息，并记录观看状态、起止日期、感想等信息。
   1. 点击详情页中“···”按钮，可以进行系列条目和单季条目互转，标记为中断/搁置等操作。
   2. 点击分享按钮，可以生成一张用于安利的海报。
   3. 下滑可以查看摘要、声优、每集的摘要等信息。
7. 长按主页面中的条目可以触发更多操作。在列表视图中，可以右滑/左滑条目来快速更新观看状态/删除条目。
8. 点击右上角的设置图标可以进入设置页面，在那里可以看到资料库的总览，以及修改 App 设置。

## 常见问题

- TMDb API 是什么？API Key 是什么？**AniShelf 使用 TMDb API 来获取番剧/动画电影的数据，例如标题、简介、海报等信息。TMDb API Key 是你从 TMDb 官网申请的一个密钥，用来授权 AniShelf 访问 TMDb 的数据。因为本 App 完全免费，故不提供公用的 API Key，用户必须按照教程自行申请**
- API Key 验证不通过？加载缓慢，搜索不到结果？**如果挂了梯子，建议先关掉梯子再输入 API Key；如果没有挂梯子，建议打开梯子再输入 API Key。两种都尝试一下，有些梯子默认的规则可能导致访问失败。**
- 如何反馈 Bug/功能建议？**欢迎通过 GitHub Issues 反馈 Bug 或者提出功能建议。也可以在群里讨论，我会不定期的查看**
- 是否会上架 App Store？**已经上架。[App Store 链接](https://apps.apple.com/us/app/anishelf/id6759359144)。大多数情况下，新功能仍然将先在 TestFlight 发布，后续再推送到 App Store。**
- 是否支持 26 以下系统？**目前不支持。App 中使用了大量液态玻璃效果，26 以下系统不支持。并且我手上也没有 26 以下系统的测试机，如果有愿意做内部测试的同学，可以私信我，我可以尝试做适配，但是 UI 美观性应该会差一些**
- 是否支持安卓/鸿蒙？**暂时没有这方面计划～**

## 未来计划

**这个项目本来是个人使用的，我了解当前版本的功能不能满足许多用户的需求，但毕竟这是为爱发电的项目，我也有学业和工作要忙，所以更新不会很频繁，希望大家理解。我会优先解决影响体验的 Bug，并酌情添加新功能。**

预计的更新计划：

- 持续的 Bug 修复
- 更细的观看进度记录（例如精确到集）
- 与 TMDb/Bangumi/AniList 等平台的观看数据同步功能（画大饼，这个比较复杂，不知道什么时候有时间来做）

注：以上列表顺序不代表实际功能实现顺序
