# JMComic3 Mod

[![最新版本](https://img.shields.io/github/v/release/khxw/JMcomic3-flutter)](https://github.com/khxw/JMcomic3-flutter/releases/latest)
[![Android](https://img.shields.io/badge/Android-ARM64-3DDC84?logo=android&logoColor=white)](https://github.com/khxw/JMcomic3-flutter/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.41.2-02569B?logo=flutter)](https://flutter.dev/)
[![Rust](https://img.shields.io/badge/Backend-Rust-000000?logo=rust)](https://www.rust-lang.org/)

简体中文 · [English](README-en.md)

> 本仓库是 JMComic3 Flutter 的**非官方修改分支**，与上游项目维护者无隶属关系。
> 当前修改版聚焦界面重做、下载与导出流程、存储权限、阅读性能和响应式布局。

Android 包标识为 `io.github.khxw.jmcomic3mod`。修改版使用独立包标识，可与上游
JMComic3 并存安装。

<p align="center">
  <img src="mockup/home-redesign.png" width="330" alt="JMComic3 Mod 首页">
</p>

## 当前版本

**v1.7.53+82** · Android ARM64 · API 24+

- 最新发布：[GitHub Releases](https://github.com/khxw/JMcomic3-flutter/releases/latest)
- 完整更新记录：[CHANGELOG.md](CHANGELOG.md)
- 源码分支：[`main`](https://github.com/khxw/JMcomic3-flutter/tree/main)

## 下载

| 文件 | 用途 |
| --- | --- |
| `JMComic3-Mod-v1.7.53-arm64-v8a-release.apk` | 适用于支持 ARM64 的 Android 设备 |
| `SHA256SUMS.txt` | 校验 APK 文件完整性 |

当前 Fork 只发布 **Android ARM64 APK**。本仓库没有为这个修改版提供 ARM32、Windows 或 AAB 安装包。

升级前请备份书架、阅读记录和下载设置。

## 修改版特性

- 重做首页、搜索、个人中心、书架、下载详情、批量导出和设置页布局。
- 使用响应式导航和更紧凑的信息层级，适配窄屏、大字体及明暗主题。
- 重做下载漫画卡片，统一显示下载状态、封面、百分比和图片数量。
- 下载任务创建成功后直接进入下载列表，并高亮刚创建的漫画任务。
- 支持章节选择、全选、清除、批量导出和导出结果状态反馈。
- 支持自定义下载目录、存储权限申请、目录可写性检测和旧路径恢复。
- 支持普通连续、自由缩放连续、单页与双页阅读。
- 保存实际可见页阅读进度，并在返回详情页后继续阅读。
- 支持封面与页图解码缓存控制、分页补全及阅读器资源释放。
- 支持主题、语言、字体、刷新率、网络线路和 WebDAV 设置。

## 安装

1. 从 [最新 Release](https://github.com/khxw/JMcomic3-flutter/releases/latest)
   下载 ARM64 APK。
2. 下载 `SHA256SUMS.txt` 并校验 APK。
3. 允许文件管理器安装未知来源应用。
4. 升级前请备份书架、阅读记录和下载设置。

Windows PowerShell 校验示例：

```powershell
Get-FileHash .\JMComic3-Mod-v1.7.53-arm64-v8a-release.apk -Algorithm SHA256
```

当前 APK SHA-256：

```text
99BE7FEFB31C09E980A1293DB34F51F40F3859A06F0B4364FECFD939C51BADEE
```

## 构建

构建环境与发布步骤见 [docs/BUILDING.md](docs/BUILDING.md) 和
[docs/RELEASING.md](docs/RELEASING.md)。

基本要求：

- Flutter 版本由 [.fvmrc](.fvmrc) 固定。
- JDK 17 或更高版本。
- Android SDK 36 和 Android NDK `25.2.9519653`。
- 完整 Rust 后端源码或预构建 JNI 库。

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

- 当前 Rust JNI 后端未提供漫画任务级暂停/恢复接口，因此暂不支持暂停下载。
- 自定义下载目录目前是应用内部下载之外的副本；删除任务不一定会清理旧目录中的副本。
- Rust 后端源码未包含在当前仓库中，当前发布包使用仓库内跟踪的预构建 JNI 库。

## 引用与声明

- [ComicSparks/jasmine](https://github.com/ComicSparks/jasmine)：阅读器结构、连续阅读、
  图库缩放和阅读进度交互参考，固定提交
  [`e514be1`](https://github.com/ComicSparks/jasmine/commit/e514be163ec39a6f9e0d2799580d132324e23470)。
- [hect0x7/JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python)：
  Rust 后端的移动端 API 协议、请求签名、登录与域名回退参考，不作为运行时依赖。
- `zoomable_positioned_list` 1.1.0：连续阅读组件，许可证与本地补丁见
  [PATCHES.md](third_party/zoomable_positioned_list/PATCHES.md)。

完整来源范围见 [REFERENCES.md](REFERENCES.md)。相关项目名称、代码和内容权利归各自作者所有。

## 使用约定

请遵守所在地法律法规、服务条款和内容版权。沿用原项目的禁止商用及禁止转发内容资产约定。
本项目只提供程序修改与构建说明，不提供漫画内容。
