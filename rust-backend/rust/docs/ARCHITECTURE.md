# 后端 v2 架构

## 兼容边界

迁移期间 Flutter 应用保持不变。

```text
Flutter MethodChannel("methods")
  -> Kotlin MainActivity
  -> JNI `opensource.jenny.Jni.invoke`
  -> JSON 请求分发器
  -> backend-v2 服务
```

响应协议保持一致：

```json
{
  "error_message": "",
  "response_data": "JSON 编码后的数据"
}
```

## 模块

- `client`：JM HTTP 协议、请求签名、Cookie、重试和解密数据。
- `crypto`：AES-256-ECB API 数据解密。
- `contract`：与 Flutter 兼容的请求和响应封装。
- `ffi`：Windows C ABI 入口，Android JNI 适配器后续复用同一分发器。
- 后续 `store`：带版本号的本地配置、阅读历史和迁移。
- 后续 `downloader`：章节与图片下载队列。
- 后续 `export`：ZIP、PDF、EPUB、JMI 和 CBZ 兼容。
- 后续 `webdav`：快照合并与上传。

## 迁移规则

1. 契约测试和真机测试通过前，保留旧 `.so`。
2. 数据迁移成功并生成回滚快照前，不删除旧存储。
3. 对相同输入比较旧后端和新后端归一化后的输出。
4. 未实现的方法返回明确错误，不能静默返回空数据。
5. 密钥和真实账号数据不得进入 Git 或 CI 日志。
