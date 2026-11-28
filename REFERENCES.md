# 项目引用与第三方声明

本文件保留当前实现的来源说明。删除历史计划文档不代表删除原作者的贡献与版权。

## ComicSparks/jasmine

- 项目：[ComicSparks/jasmine](https://github.com/ComicSparks/jasmine)。
- 固定参考提交：[`e514be163ec39a6f9e0d2799580d132324e23470`](https://github.com/ComicSparks/jasmine/commit/e514be163ec39a6f9e0d2799580d132324e23470)。
- 参考范围：Flutter 漫画浏览器结构、阅读模式组织、连续阅读的索引列表、
  `PhotoViewGallery` 图库缩放和可见页驱动的阅读进度交互。
- 对应实现：`lib/screens/comic_reader_screen.dart`、`lib/screens/reader/` 与
  `third_party/zoomable_positioned_list/`。
- 本项目补充了反向主轴手势、实际滚动边界、跳页竞态、进度串行保存、资源释放和回归测试。
- 固定参考提交的根目录没有可随代码保留的 `LICENSE` 文件，原 README 的禁止商用与
  内容资产转发约定继续在本项目 README 中标明。本项目不将整个仓库声明为 MIT。

## hect0x7/JMComic-Crawler-Python

- 项目：[hect0x7/JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python)。
- 参考范围：`jm_config.py`、`jm_client_impl.py` 中的移动端 API 协议、版本与时间戳、
  请求签名、请求头、登录表单及域名候选/回退处理。
- 对应实现：本仓库 [Rust v2 后端](rust-backend/rust/README.md) 中的 API 请求与
  响应适配；Flutter 通过 MethodChannel / C ABI 调用该后端。
- 本应用不包含 Python 解释器，也不将该项目列为运行时依赖。这里标注协议参考来源。
- 上游 [MIT 许可证](https://github.com/hect0x7/JMComic-Crawler-Python/blob/master/LICENSE)
  的版权声明为 `Copyright (c) 2023 hect0x7`；其许可证保留在上游仓库。

## zoomable_positioned_list 1.1.0

- 来源：[pub.dev 1.1.0](https://pub.dev/packages/zoomable_positioned_list/versions/1.1.0)。
- 发布归档 SHA-256：`f17148ca7be6775131737b11ab738d059b845b7e3988d0095eb5b6e41c9023e4`。
- 本地副本：`third_party/zoomable_positioned_list/`，用于连续阅读的缩放和索引定位。
- 保留 [MIT LICENSE](third_party/zoomable_positioned_list/LICENSE) 和原始
  [Fuchsia / Google BSD 声明](third_party/zoomable_positioned_list/LICENSE.fuchsia)。
- 补丁及验证说明：[PATCHES.md](third_party/zoomable_positioned_list/PATCHES.md)。

## Tencent/ncnn

- 项目：[Tencent/ncnn](https://github.com/Tencent/ncnn)。
- 使用版本：`20261020` Android shared release，包含 `arm64-v8a` 与
  `armeabi-v7a` 预编译运行库。
- 对应实现：`android/app/src/main/cpp/` 中的漫画 2× 超分 JNI，
  以及 `android/app/src/main/jniLibs/` 中的 `libncnn.so`。
- 保留 [BSD 3-Clause 及随包第三方声明](third_party/ncnn/LICENSE.txt)。

## nihui/waifu2x-ncnn-vulkan

- 项目：[nihui/waifu2x-ncnn-vulkan](https://github.com/nihui/waifu2x-ncnn-vulkan)。
- 使用模型：`models-cunet/scale2.0x_model.param` 与
  `models-cunet/scale2.0x_model.bin`，应用内标记为模型版本 `20250915`。
- 分发方式：模型单独打包为
  `models/super_resolution/packages/waifu2x-cunet-2x-20250915.zip`，
  用户需要时从 GitHub 下载，不包含在 APK 中。
- 来源文件校验和及打包信息：
  [WAIFU2X-CUNET-2X.md](models/super_resolution/WAIFU2X-CUNET-2X.md)。
- 模型归档内保留 `LICENSE.txt`，上游许可证为 MIT，
  版权声明为 `Copyright (c) 2019 nihui`。

## soutubot.moe（以图搜漫）

- 服务：[soutubot.moe](https://soutubot.moe/)。
- 使用范围：以图搜漫功能通过 `https://soutubot.moe/api/search` 提交用户主动选择的图片，
  并读取该服务返回的漫画标题、来源、相似度等识别结果。
- 数据处理：图片仅在用户主动发起识图时发送至该第三方服务；应用会在识图页面明确提示，
  服务的可用性、保存策略和数据处理规则由 `soutubot.moe` 决定。
- 对应实现：`rust-backend/rust/src/client.rs` 与
  `lib/screens/image_search_screen.dart`。
- 本项目未复制或分发 `soutubot.moe` 的源代码，因此该服务不列入开源组件许可；
  此处作为第三方服务、数据流向和功能来源声明保留。

## 其他依赖与资源

Flutter / Dart 包版本由 `pubspec.yaml` 与提交的 `pubspec.lock` 记录，使用各依赖自己的
许可证。Flutter 的许可证登记机制保留包内声明；发布时同时保留所分发第三方组件的声明。
Rust 后端源码、`Cargo.lock`、协议说明和第三方声明均保存在
`rust-backend/rust/`。漫画、图片和第三方服务内容的权利属于相应权利人。
