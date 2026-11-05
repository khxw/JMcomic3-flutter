# 兼容清单

Flutter 应用当前调用 96 个后端方法。另外 14 个方法由 Kotlin/平台层实现，
不属于 Rust 后端。

## 已完成

| 范围 | 方法或能力 |
| --- | --- |
| C ABI | `init_ffi`、`invoke_ffi`、`free_str_ffi` |
| 请求分发 | `ping_backend`、`album`、`chapter`、`comic_search`、`pre_login`、`login`、`logout` |
| 启动与配置 | `init_dart`、`load_property`、`save_property`、`app_config`、`config_links` |
| 浏览与图片 | `categories`、`comics`、`jm_3x4_cover`、`jm_square_cover`、`jm_page_image`、`jm_page_image_batch`、`image_size` |
| 浏览扩展 | `week`、`week_filter`、`games`、`jm_photo_image` |
| 账号与社区 | Cookie 持久化、旧登录名读取、收藏列表与切换、收藏夹管理、签到、论坛读取、评论和回复提交 |
| 本地历史 | `find_view_log`、`update_view_log`、`page_view_log`、`clear_view_log`、`delete_view_log_by_comic_id`、`last_search_histories`、`clear_all_search_log`、`clear_a_search_log` |
| 本地下载 | `all_downloads`、`download_album_by_id`、`download_by_id`、`create_download`、`pause_download`、`resume_download`、`dl_image_by_chapter_id`、`dl_image_local_availability`、`delete_download`、`renew_all_downloads`、下载目录读取与设置、1–8 线程图片下载，默认 3 线程 |
| 下载状态 | 区分运行中、暂停、失败、删除中和已完成；刷新不会把活动任务误判为失败，也不会把部分文件误判为已完成 |
| 断点续传 | 暂停状态本地持久化；继续时重新校正完整图片总数，并跳过章节目录中已有且非空的图片 |
| 下载迁移 | 兼容旧索引字段、自动识别漫画和章节目录；首次写入前备份为 `downloads.pre-v2.json`，未知结构拒绝覆盖 |
| 导出 | `export_jm_jpegs`、`export_jm_zip`、`export_jm_jmi`、`export_cbzs_zip_single`、`export_jm_pdf`、`export_jm_pdf2`、`export_jm_epub` 及对应单本方法 |
| 导入 | `import_jm_zip`、`import_jm_jmi`、`import_jm_dir` |
| WebDAV | `sync_webdav` 合并、覆盖上传和覆盖下载；不传输 Cookie、Token、密码、私钥和代理凭据 |
| 协议客户端 | 登录、账号信息、搜索、漫画详情、章节、收藏、周榜信息、周榜筛选、章节解密 ID、图片获取 |
| 基础设施 | 域名归一化、API/CDN 分流、HTTP 测速、代理配置、重试、Cookie、AES 响应解密、图片拼接、原子缓存、属性存储、缓存清理 |
| 存储管理 | 封面缓存限制约 48 MB、最长保留 30 天；启动时清理过期文件，运行中每写入 64 张封面淘汰最旧文件；阅读页缓存和下载内容不受影响 |
| 原生桥接 | Windows C ABI、Android JNI 导出、ARM64/ARMv7 Release 动态库 |

## 真机验证

- Android ARM64 网络请求与 TLS 通过。
- 分类接口返回 10 个分类。
- 搜索接口可返回分页结果。
- 漫画详情接口可读取。
- 章节接口可读取图片列表。
- 章节首图下载、AES 分块拼接和本地缓存成功。
- FFI 请求分发、属性持久化和匿名 `pre_login` 状态成功。
- 论坛评论读取成功。
- 阅读进度写入、按漫画查询和分页列表成功。
- 搜索历史写入和读取成功。
- 下载索引列表、下载目录读取和续扫接口成功。
- 后台下载压力测试完成 32/32 张图片，任务状态、完成进度和本地路径均正确。
- 双线程后台下载压力测试完成 32/32 张图片。
- 下载暂停、继续、活动任务刷新和部分任务完成度校正通过回归测试。
- 封面缓存上限、过期清理及阅读页缓存隔离通过回归测试。
- 周榜信息、类型筛选、游戏列表、API/CDN HTTP 测速通过。
- JPEG/ZIP/JMI/CBZ/PDF/EPUB 导出和 JM ZIP 导入回环通过。
- 旧下载索引迁移、未知索引拒绝覆盖、属性敏感字段过滤和历史/下载快照合并通过。
- 测试未输出漫画标题、图片或账号信息。

## 后续兼容性回归

- 使用旧版实际导出的 `.jm.zip`、`.jmi`、PDF 和 EPUB 样本验证兼容性。
- 使用真实 WebDAV 服务验证 Basic Auth、目录 URL、404、超时和覆盖行为。
- 验证账号登录、收藏夹管理、Pro/PAT 和签到在有效登录态下的真实响应。
- 后续升级前继续备份 `librust.so` 和用户数据，并执行跨版本数据迁移与回滚测试。

Android/平台层方法包括目录选择、文本文档读写、存储权限与目录创建、显示模式、
刷新率、版本号、生物认证和 APK 安装等。iOS 专属的 `iosGetDocumentDir` 仅在
对应平台分支使用；`saveImageFileToGallery` 桥接保留用于兼容，但当前图片
长按菜单已不再暴露“保存图片到文件”入口。
