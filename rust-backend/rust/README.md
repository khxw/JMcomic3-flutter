# JMComic3 Rust 后端 v2

用于 JMComic3 Flutter 应用的兼容型 Rust 后端。

本项目已作为新的 `librust.so` 接入 JMComic3 Flutter 应用。后端保持原有
MethodChannel 调用协议，并重新实现网络请求、本地存储、下载、导入导出和
缓存管理能力，同时兼容旧版属性、历史、下载索引和用户数据。

## 当前状态

- 独立 JM API 客户端
- Token 生成和 AES 响应解密
- Cookie 登录与账号信息请求
- 登录 Cookie 本地持久化、`pre_login`、退出和旧登录名兼容
- 搜索、漫画详情、章节、收藏、周榜和章节解密 ID
- 收藏切换、评论读取与评论提交接口
- 收藏夹创建、删除、重命名和漫画移动
- 图片 URL 获取
- 分类、漫画列表、每周必看、游戏、封面与章节图片解密缓存
- 配置属性持久化
- API/CDN 分流、代理、HTTP 测速和线路列表刷新
- Windows C ABI 与 Android JNI 导出
- 命令行冒烟测试工具
- Android ARM64/ARMv7 JNI 动态库
- Android 真机网络、章节图片与 AES 图片解密验证
- 真机 FFI 分发、属性持久化、匿名登录检测和评论读取验证
- 阅读历史、搜索历史、分页和本地清除接口
- 兼容旧后端的 `properties.json`、`view_logs.json` 和 `search_histories.json`
- 下载索引、下载目录切换、本地图片扫描和后台章节下载
- 1–8 线程章节图片下载，默认 3 线程；章节图片信息并行获取
- 下载暂停、继续和断点续传；继续时跳过已有图片
- 下载任务状态校正，区分运行中、暂停、失败、删除中和已完成
- 旧 `downloads.json` 安全迁移：首次写入前保留 `downloads.pre-v2.json`，
  无法识别的索引拒绝覆盖
- 封面缓存自动限制为约 48 MB、最长保留 30 天，不影响阅读页缓存和下载内容
- JPEG、JM ZIP、JMI、CBZ、PDF 和 EPUB 导出
- JM ZIP/JMI 导入和目录批量导入
- WebDAV 合并、覆盖上传和覆盖下载

Flutter 侧当前 96 个 `_invoke` 后端方法均有分发实现，另有 14 个方法由
Kotlin/平台层处理。发布包同时跟踪 `arm64-v8a` 和 `armeabi-v7a` ABI。
后续兼容性回归仍应覆盖旧归档样本、真实 WebDAV、有效账号态和升级数据迁移。

## 命令行

```powershell
cargo run --bin jmcomic3-backend-cli -- search "关键词" 1 mr
cargo run --bin jmcomic3-backend-cli -- album 123456
cargo run --bin jmcomic3-backend-cli -- chapter 123457
```

可选环境变量：

- `JM_API_HOST`
- `JM_IMAGE_HOST`
- `JM_APP_VERSION`
- `JM_PROXY`
- `JM_USERNAME` 和 `JM_PASSWORD`，供 `login-info` 使用

## Windows 本地检查

当前电脑可能缺少 Visual C++ 链接器。如果已经安装 Rust GNU 工具链和 Android NDK：

```powershell
$env:ANDROID_NDK_HOME = "<android-ndk>"
.\scripts\check-windows.ps1
```

脚本使用 NDK 自带的 Clang 和 Rust 自带的链接器。完整单元测试在 Linux CI 中运行。

构建 ARM64 动态库：

```powershell
$env:ANDROID_NDK_HOME = "<android-ndk>"
.\scripts\build-android-arm64.ps1
```

输出文件：

```text
target/aarch64-linux-android/release/libjmcomic3_rust_backend_v2.so
```

脚本会检查 AArch64 ELF 架构以及 JNI/C ABI 导出符号。

主应用同时跟踪 ARM64 和 ARMv7。完整 JNI 同步时，需要为两种 ABI 生成同版本
动态库，并在应用的 `android` 目录执行：

```powershell
.\gradlew.bat app:syncRustJniLibs app:validateRustJniLibs
```

构建可在 Android 真机执行的网络验证程序：

```powershell
.\scripts\build-android-arm64.ps1 -Artifact Cli
.\scripts\build-android-arm64.ps1 -Artifact Smoke
```

连接已授权设备后运行不输出漫画内容的网络冒烟测试：

```powershell
$env:ANDROID_NDK_HOME = "<android-ndk>"
.\scripts\run-android-smoke.ps1 -Adb "<adb>"
```

该测试只输出状态和数量，不输出漫画标题、图片或账号信息。

## 来源声明

初始协议实现参考
[`lanyeeee/jmcomic-downloader`](https://github.com/lanyeeee/jmcomic-downloader)，
版权归 2024-2026 lanyeeee 所有，使用 MIT 许可证。详细说明见
`THIRD_PARTY_NOTICES.md` 和 `LICENSE.lanyeeee`。
