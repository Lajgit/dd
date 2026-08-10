# 点滴记忆

Flutter Android V1。App 直接读取 WechatExplorer 导出的完整 HTML 档案 ZIP，不经过额外 PC 转换器。

## 当前能力

选择一个 WechatExplorer ZIP 后，App 会：

1. 在 ZIP 任意顶层目录中查找 `data/messages.js`；
2. 解析 `window.__WECHAT_EXPORT__ = {...};`；
3. 核对图片、视频、语音、表情和文件资源；
4. 将参与者、消息和媒体引用写入本地 SQLite；
5. 保留原始 `messages.js`，便于以后重新构建规范化数据；
6. 将可用媒体流式解压到 App 私有目录，并按内容计算 SHA-256；
7. 相同 SHA-256 的媒体只保留一个本地文件；
8. 回忆页按天展示总结，展开后直接读取 SQLite 中的真实聊天记录；
9. 已保存图片可全屏缩放，已保存视频可在本地播放器中播放；
10. APK 默认内置 Qwen3 0.6B Q4_K_M，并可高级选择自定义 GGUF，在 Android 本机生成日 / 周 / 月 / 年 AI 总结。

没有生成 AI 总结的日期继续使用离线关键词提取作为兜底；生成日 AI 总结后会优先展示 AI 结果。

## 本地 AI 总结

底部 `AI总结` 页默认使用随 APK 打包的 `Qwen3-0.6B-Q4_K_M`。首次进入时，Android 会在后台把约 397 MB 的 GGUF 从 APK 资源流式复制到 App 私有目录并校验 SHA-256；以后直接复用，不要求用户额外下载模型。

高级用户仍可选择自己的 `.gguf`。自定义模型同样按块复制到 App 私有目录；可随时切回内置轻量模型。聊天文字和模型推理都留在设备上，不上传网络。

当前总结链路：

```text
当天真实聊天
  ↓ 按 45 分钟间隔 / 上下文大小切段
本地 GGUF 模型提取片段事件 + message_id 证据
  ↓
日总结
  ↓
周总结（聚合日总结）
月总结（聚合当月日总结，避免跨月周污染）
  ↓
年总结（聚合月总结）
```

总结缓存在 SQLite；只有底层消息、发送方或使用的模型发生变化时才需要重新生成。AI 提取出的事件会保存关联的真实 `message_id`，原始聊天始终是证据源。

当前 Android 本地推理层使用固定版本 `llama_flutter_android 0.2.6` 调用 llama.cpp。构建脚本会把生成 Android 工程的 `minSdk` 调整为 26。

内置模型来自官方 `Qwen/Qwen3-0.6B-GGUF` 的固定 revision `1208e45d782fe18602c5eaf10e5758d5b0f24c03`，文件 `Qwen3-0.6B-Q4_K_M.gguf`，构建时强制核对 SHA-256 `b0638f08417a2d3c8652760462eb5407c6e30173cf9608ad0820757a281eea0e`。模型采用 Apache License 2.0；对应许可和归属说明保存在 `legal/`，并会一起打包进 Android assets。

## 本地数据库

SQLite schema v2 包含：

- `import_sources`：每次 WechatExplorer 来源、来源指纹、原始 `messages.js` 路径和导入统计；
- `participants`：微信发送者 ID、显示名称和是否本人；
- `messages`：稳定消息键、微信原始 ID、发送者、类型、正文、时间和 `contentData`；
- `media`：按 SHA-256 去重后的 App 私有媒体文件；
- `message_media`：消息、来源与媒体之间的证据关系和本地保存状态；
- `app_settings`：自定义本地模型路径等设备设置；
- `ai_summaries`：日 / 周 / 月 / 年总结、来源哈希、模型版本与生成时间；
- `ai_events` / `ai_event_messages`：日总结提取事件以及对应真实消息证据；
- `ai_summary_children`：上级总结与下级总结之间的可追溯关系。

规范化表不会重复保存头像 Base64；完整原始数据保留在私有 `messages.js` 文件中。

## 数据边界

V1 的 ZIP、SQLite、媒体文件和本地 AI 推理都在设备上处理。当前本地 AI 功能不需要把聊天文字发送到云端。

## Windows 首次环境准备

如果 `flutter doctor` 提示找不到 `flutter`，先在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\install_flutter_windows.ps1
```

完成后关闭并重新打开 PowerShell，再进入仓库目录。如果 `flutter doctor` 提示 Android toolchain 缺失，按 doctor 的具体提示补齐 Android SDK / Command-line Tools / licenses。

## 本地构建

仓库暂不提交 Flutter 自动生成的 Android 平台模板，也不把约 397 MB 的 GGUF 二进制提交进 Git。第一次构建时，bootstrap 会从官方 Qwen 固定 revision 下载模型到 `.local_models/` 本地缓存，校验 SHA-256 后再打进 APK；后续构建直接复用已校验缓存。

在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\bootstrap_android.ps1
```

脚本依次执行：

```text
flutter clean
flutter create . --platforms=android --project-name=diandi_memory --org=com.lajgit
配置 Android minSdk 26 / Kotlin 兼容项
flutter pub get
flutter analyze
flutter test
下载或复用并校验内置 Qwen3 GGUF
写入 Android 本地模型桥接代码并打包模型/许可
flutter build apk --debug
```

Windows 项目和 Pub Cache 位于不同盘符时，脚本会为生成的 Android 工程关闭 Kotlin incremental compilation，规避跨盘符缓存路径问题。

成功后 APK 位于：

```text
build\app\outputs\flutter-apk\app-debug.apk
```

由于内置约 397 MB 模型，APK 会比之前明显增大；终端用户安装该 APK 后不需要再下载 GGUF。

## 目录

```text
lib/
├── app/
│   └── app.dart
├── core/
│   └── database/app_database.dart
└── features/
    ├── home/ui/home_page.dart
    ├── import/
    │   ├── data/
    │   │   ├── archive_media_store.dart
    │   │   ├── messages_js_parser.dart
    │   │   ├── wechat_archive_importer.dart
    │   │   └── wechat_archive_scanner.dart
    │   └── ui/import_page.dart
    └── memories/
        ├── data/
        │   ├── ai_summary_repository.dart
        │   ├── bundled_local_ai_model.dart
        │   ├── daily_activity_summarizer.dart
        │   ├── hierarchical_summary_service.dart
        │   ├── local_ai_engine.dart
        │   ├── local_ai_model_manager.dart
        │   └── memory_repository.dart
        ├── model/
        │   ├── ai_summary_models.dart
        │   └── memory_models.dart
        └── ui/
            ├── local_ai_summary_page.dart
            ├── local_ai_summary_panel.dart
            ├── media_preview_page.dart
            └── memory_page.dart
```

## 后续方向

- 在日总结 UI 中直接展示 AI 事件，并按事件只展开对应的真实聊天证据；
- 手动笔记 `notes`；
- 总结任务取消、后台运行与性能统计；
- 继续优化长时间跨度的年总结质量。
