# 点滴记忆

Flutter Android V1。当前第一阶段直接读取 WechatExplorer 导出的完整 HTML 档案 ZIP，不经过额外 PC 转换器。

## 当前目标

选择一个 WechatExplorer ZIP 后，App 会：

1. 在 ZIP 任意顶层目录中查找 `data/messages.js`；
2. 解析 `window.__WECHAT_EXPORT__ = {...};`；
3. 统计消息、图片、视频、语音、表情和文件数量；
4. 根据 `exportMediaUrl` / `voiceDataUrl` 核对 ZIP 内实际媒体资源；
5. 在 UI 中显示档案名称、时间范围和资源缺失情况。

当前阶段**不会解压或复制全部媒体，也不会写 SQLite**。这两部分放到下一阶段，避免在数据协议尚未稳定前扩大改动范围。

## 数据边界

V1 只在本地处理聊天档案。完整聊天、图片、视频、语音和文件不上传。后续 AI 功能只发送用户主动触发分析时所需的文本片段。

## 本地启动

仓库暂不提交 Flutter 自动生成的 Android 平台模板。首次克隆后，在 Windows PowerShell 执行：

```powershell
.\tool\bootstrap_android.ps1
```

脚本等价于：

```powershell
flutter create . `
  --platforms=android `
  --project-name=diandi_memory `
  --org=com.lajgit

flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

GitHub Actions 也会使用同一流程生成 Android 平台文件并执行 analyze、test 和 debug APK 构建。

## 目录

```text
lib/
├── app/
│   └── app.dart
├── features/
│   └── import/
│       ├── data/
│       │   ├── messages_js_parser.dart
│       │   └── wechat_archive_scanner.dart
│       ├── model/
│       │   └── wechat_archive_models.dart
│       └── ui/
│           └── import_page.dart
└── main.dart
```

## 下一阶段

扫描结果确认稳定后再实现：

- SQLite `import_sources / participants / messages / media / message_media`；
- ZIP 中媒体按需复制到 App 私有目录；
- 基于微信消息 ID 的增量导入和重复检测；
- SHA-256 媒体去重。
