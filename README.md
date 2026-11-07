# JMComic3 Mod

简体中文 · [English](https://github.com/khxw/JMcomic3-flutter/blob/main/README-en.md)

> 本仓库是 JMComic3 Flutter 的**非官方修改分支**，与上游项目维护者无隶属关系。
> 当前修改版聚焦界面重做、下载与导出流程、存储权限、阅读性能和响应式布局。

Android 包标识为 `io.github.khxw.jmcomic3mod`。修改版使用独立包标识，可与上游
JMComic3 并存安装。

## 当前版本

**v1.8.78+207** · Android ARM64 · API 24+

- 最新发布：[GitHub Releases](https://github.com/khxw/JMcomic3-flutter/releases/latest)
- 完整更新记录：[CHANGELOG.md](https://github.com/khxw/JMcomic3-flutter/blob/main/CHANGELOG.md)
- 源码分支：[`main`](https://github.com/khxw/JMcomic3-flutter/tree/main)

## 下载

| 文件 | 用途 |
| --- | --- |
| `JMComic3-Mod-v1.8.78-arm64-v8a-release.apk` | 适用于支持 ARM64 的 Android 设备 |
| `SHA256SUMS.txt` | 校验 APK 文件完整性 |

当前 Fork 只发布 **Android ARM64 APK**。本仓库没有为这个修改版提供 ARM32、
Windows 或 AAB 安装包。

升级前请备份书架、阅读记录和下载设置。

## 修改版特性

- 重做首页、搜索、个人中心、书架、下载详情、批量导出和设置页布局。
- 重做每周必看页面，采用固定三列等尺寸卡片和自动加载的无限流。
- 支持长按“加入书架”选择或新建书架分组。
- 使用响应式导航和更紧凑的信息层级，适配窄屏、大字体及明暗主题。
- 重做下载漫画卡片，统一显示下载状态、封面、百分比和图片数量。
- 下载任务创建成功后直接进入下载列表，并高亮刚创建的漫画任务。
- 支持章节选择、全选、清除、批量导出和导出结果状态反馈。
- 下载任务支持暂停、继续、断点续传和 1–8 线程，继续时跳过已有图片。
- 支持自定义下载目录、存储权限申请、目录可写性检测和旧路径恢复。
- 支持普通连续、自由缩放连续、单页与双页阅读。
- 重做阅读页顶栏、底部翻页控制、章节列表和阅读设置面板。
- 支持可配置图片预加载，可选择前后双向或仅向后预加载。
- 保存实际可见页阅读进度，并在返回详情页后继续阅读。
- 支持封面与页图解码缓存控制、分页补全及阅读器资源释放。
- 封面缓存自动限制为约 48 MB、最长保留 30 天，不影响下载漫画和阅读记录。
- 支持主题、语言、字体、刷新率、网络线路和 WebDAV 设置。
- 启动时优先使用最先响应的 API 与图片线路，并并行预取首页内容。
- Rust v2 后端源码位于 `rust-backend/rust/`，与 Flutter 应用在同一仓库维护。

## 安装

1. 从 [最新 Release](https://github.com/khxw/JMcomic3-flutter/releases/latest)
   下载 ARM64 APK。
2. 下载 `SHA256SUMS.txt` 并校验 APK。
3. 允许文件管理器安装未知来源应用。
4. 升级前请备份书架、阅读记录和下载设置。

Windows PowerShell 校验示例：

```powershell
Get-FileHash .\JMComic3-Mod-v1.8.78-arm64-v8a-release.apk -Algorithm SHA256
```

当前 APK SHA-256：

```text
CD2A47D401ABAD148CA61BAB89CCA0D50CF29BDA42454FECD4DE5BF57DA20EAF
```

## 构建

构建环境与发布步骤见
[docs/BUILDING.md](https://github.com/khxw/JMcomic3-flutter/blob/main/docs/BUILDING.md)
和
[docs/RELEASING.md](https://github.com/khxw/JMcomic3-flutter/blob/main/docs/RELEASING.md)。

基本要求：

- Flutter 版本由
  [.fvmrc](https://github.com/khxw/JMcomic3-flutter/blob/main/.fvmrc) 固定。
- JDK 17 或更高版本。
- Android SDK 36 和 Android NDK `25.2.9519653`。
- Rust v2 后端源码位于 `rust-backend/rust/`，已验证的预构建 JNI 库位于
  `android/app/src/main/jniLibs/`。

常用命令：

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos lib test integration_test test_driver
flutter test --no-pub
flutter build apk --release --no-pub --target-platform android-arm64 --split-per-abi
```

## 安全与隐私

- 登录信息、下载目录、阅读历史和 WebDAV 配置保存在应用本地或用户选择的目录中。
- 仓库不提交 keystore、`key.properties`、`android/local.properties`、APK 或构建缓存。
- 应用访问第三方服务，服务可用性和数据处理规则由对应服务提供方决定。
- 请只从本仓库 Release 页面下载 APK，避免使用来源不明的转载文件。

## 已知限制

- 自定义下载目录目前是应用内部下载之外的副本；删除任务不一定会清理旧目录中的副本。
- 封面缓存会自动清理，但当前界面没有单独显示封面缓存大小或只清理封面的按钮。

## 引用与声明

- [ComicSparks/jasmine](https://github.com/ComicSparks/jasmine)：阅读器结构、连续阅读、
  图库缩放和阅读进度交互参考，固定提交
  [`e514be1`](https://github.com/ComicSparks/jasmine/commit/e514be163ec39a6f9e0d2799580d132324e23470)。
- [hect0x7/JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python)：
  Rust 后端的移动端 API 协议、请求签名、登录与域名回退参考，不作为运行时依赖。
- `zoomable_positioned_list` 1.1.0：连续阅读组件，许可证与本地补丁见
  [PATCHES.md](https://github.com/khxw/JMcomic3-flutter/blob/main/third_party/zoomable_positioned_list/PATCHES.md)。

完整来源范围见
[REFERENCES.md](https://github.com/khxw/JMcomic3-flutter/blob/main/REFERENCES.md)。
相关项目名称、代码和内容权利归各自作者所有。

## 使用约定

使用本项目前，请确认你已理解并同意以下约定：

- **合法使用**：仅将本项目用于所在地法律法规允许的用途，不得访问、下载、保存或传播违法内容。
- **内容权利**：本项目只提供程序修改和构建说明，不提供、托管或授权任何漫画、图片、评论或其他内容。相关内容权利归原作者、平台或相应权利人所有，下载和使用前应自行取得必要授权。
- **禁止未经授权的商业使用**：沿用原项目约定，不得将本项目或内容资产用于未经授权的商业传播、出售、出租、付费代下载或打包再分发。
- **软件分发**：请优先从本仓库 Releases 获取安装包并核对 SHA-256，不要使用来源不明的转载包。修改、构建或再分发程序代码前，应确认上游版权和各第三方组件的许可证；本仓库没有通过根目录许可证对整个项目授予额外权利。
- **无担保与责任**：软件按现状提供，不保证第三方服务持续可用、内容准确或兼容所有设备。使用者应自行承担使用、下载和分发行为产生的风险与责任，并遵守对应服务条款。
