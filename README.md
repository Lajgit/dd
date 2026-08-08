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
8. 按天生成本地统计小结，小结展开后直接读取 SQLite 中的真实聊天记录；
9. 已保存的图片/表情可在聊天证据中直接预览。

当前“每日小结”是完全本地的统计型总结，不调用 AI。后续事件提取与 AI 日/周/月/年总结会建立在已验证的本地消息与证据链之上。

## 本地数据库

SQLite schema v1 包含：

- `import_sources`：每次 WechatExplorer 来源、来源指纹、原始 `messages.js` 路径和导入统计；
- `participants`：微信发送者 ID、显示名称和是否本人；
- `messages`：稳定消息键、微信原始 ID、发送者、类型、正文、时间和 `contentData`；
- `media`：按 SHA-256 去重后的 App 私有媒体文件；
- `message_media`：消息、来源与媒体之间的证据关系和本地保存状态。

规范化表不会重复保存头像 Base64；完整原始数据保留在私有 `messages.js` 文件中。

## 数据边界

V1 只在本地处理聊天档案。完整聊天、图片、视频、语音和文件不上传。后续 AI 功能只发送用户主动触发分析时所需的文本片段。

## Windows 首次环境准备

如果 `flutter doctor` 提示找不到 `flutter`，先在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\install_flutter_windows.ps1
```

完成后关闭并重新打开 PowerShell，再进入仓库目录。如果 `flutter doctor` 提示 Android toolchain 缺失，按 doctor 的具体提示补齐 Android SDK / Command-line Tools / licenses。

## 本地构建

仓库暂不提交 Flutter 自动生成的 Android 平台模板。在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\bootstrap_android.ps1
```

脚本依次执行：

```text
flutter clean
flutter create . --platforms=android --project-name=diandi_memory --org=com.lajgit
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Windows 项目和 Pub Cache 位于不同盘符时，脚本会为生成的 Android 工程关闭 Kotlin incremental compilation，规避跨盘符缓存路径问题。

成功后 APK 位于：

```text
build\app\outputs\flutter-apk\app-debug.apk
```

## 目录

```text
lib/
├── app/
│   └── app.dart
├── core/
│   └── database/
│       └── app_database.dart
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
        ├── data/memory_repository.dart
        ├── model/memory_models.dart
        └── ui/memory_page.dart
```

## 下一阶段

在媒体持久化与真实聊天证据链真机验证通过后，再继续：

- 事件 `events / event_messages` 数据层；
- 手动笔记 `notes`；
- AI 日 / 周 / 月 / 年总结；
- 总结与原始消息证据之间的可追溯引用；
- 视频、语音和文件的专用查看体验。
