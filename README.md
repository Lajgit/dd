# 点滴记忆

Flutter Android V1。当前直接读取 WechatExplorer 导出的完整 HTML 档案 ZIP，不经过额外 PC 转换器。

## 当前能力

选择一个 WechatExplorer ZIP 后，App 会：

1. 在 ZIP 任意顶层目录中查找 `data/messages.js`；
2. 解析 `window.__WECHAT_EXPORT__ = {...};`；
3. 统计消息、图片、视频、语音、表情和文件数量；
4. 根据 `exportMediaUrl` / `voiceDataUrl` 核对 ZIP 内实际媒体资源；
5. 在 UI 中显示档案名称、时间范围和资源缺失情况；
6. 用户确认后将导入来源、参与者、消息和媒体引用元数据写入本地 SQLite；
7. 将原始 `messages.js` 保存在 App 私有目录，保留重新构建规范化数据的依据；
8. 使用 `sessionId + serverId`，其次 `localId / id / 稳定哈希` 生成消息唯一键，避免重复导入同一消息。

当前阶段**还不会复制全部媒体文件**。媒体私有化复制和 SHA-256 内容去重放到下一小阶段，避免一次扩大改动范围。

## 本地数据库

SQLite schema v1 包含：

- `import_sources`：每次 WechatExplorer 来源、来源指纹、原始 `messages.js` 路径和导入统计；
- `participants`：微信发送者 ID、显示名称和是否本人；
- `messages`：稳定消息键、微信原始 ID、发送者、类型、正文、时间和 `contentData`；
- `media`：预留 SHA-256 内容对象，下一阶段复制媒体后写入；
- `message_media`：消息与 ZIP 内媒体引用的关系以及资源存在状态。

规范化表不会重复保存头像 Base64；完整原始数据保留在私有 `messages.js` 文件中。

## 数据边界

V1 只在本地处理聊天档案。完整聊天、图片、视频、语音和文件不上传。后续 AI 功能只发送用户主动触发分析时所需的文本片段。

## Windows 首次环境准备

如果 `flutter doctor` 提示找不到 `flutter`，先在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\install_flutter_windows.ps1
```

该脚本会：

- 使用现有 Git 安装 Flutter stable 到 `%LOCALAPPDATA%\Programs\flutter`；
- 将 Flutter `bin` 加入当前用户 PATH；
- 执行 `flutter --version` 和 `flutter doctor`。

完成后关闭并重新打开 PowerShell，再进入仓库目录。

如果 `flutter doctor` 提示 Android toolchain 缺失，再安装 Android Studio / Android SDK，并按 `flutter doctor` 的具体提示补齐环境；不要跳过 doctor 的错误项。

## 本地构建

仓库暂不提交 Flutter 自动生成的 Android 平台模板。环境准备完成后，在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\bootstrap_android.ps1
```

脚本会依次执行：

```powershell
flutter --version
flutter clean
flutter create . --platforms=android --project-name=diandi_memory --org=com.lajgit
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

成功后 APK 位于：

```text
build\app\outputs\flutter-apk\app-debug.apk
```

GitHub Actions 也会使用同一流程生成 Android 平台文件并执行 analyze、test 和 debug APK 构建。

## 目录

```text
lib/
├── app/
│   └── app.dart
├── core/
│   └── database/
│       └── app_database.dart
├── features/
│   └── import/
│       ├── data/
│       │   ├── messages_js_parser.dart
│       │   ├── wechat_archive_importer.dart
│       │   └── wechat_archive_scanner.dart
│       ├── model/
│       │   └── wechat_archive_models.dart
│       └── ui/
│           └── import_page.dart
└── main.dart
```

## 下一小阶段

SQLite 消息持久化真机验证通过后再实现：

- ZIP 中媒体流式复制到 App 私有目录；
- SHA-256 内容去重；
- 回填 `media / message_media.media_id`；
- App 重启后直接从 SQLite 浏览聊天，不再重复扫描 ZIP。
