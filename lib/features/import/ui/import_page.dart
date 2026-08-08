import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/wechat_archive_importer.dart';
import '../data/wechat_archive_scanner.dart';
import '../model/wechat_archive_models.dart';

class ImportPage extends StatefulWidget {
  const ImportPage({
    super.key,
    this.onImported,
    this.onOpenMemories,
  });

  final VoidCallback? onImported;
  final VoidCallback? onOpenMemories;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final WechatArchiveScanner _scanner = const WechatArchiveScanner();
  final WechatArchiveImporter _importer = const WechatArchiveImporter();

  WechatArchiveSummary? _summary;
  WechatArchiveImportResult? _importResult;
  String? _selectedFileName;
  String? _selectedZipPath;
  String? _error;
  bool _isScanning = false;
  bool _isImporting = false;

  Future<void> _pickArchive() async {
    if (_isScanning || _isImporting) return;

    // 只获取文件路径，不把大型 ZIP 的全部字节加载到 Android 平台通道内存中。
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (selected == null) return;

    final path = selected.path;
    if (path == null || path.trim().isEmpty) {
      setState(() {
        _error = '无法获取该 ZIP 的本地路径，请先将档案保存到手机后再选择。';
        _summary = null;
        _importResult = null;
        _selectedZipPath = null;
        _selectedFileName = selected.name;
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _error = null;
      _summary = null;
      _importResult = null;
      _selectedZipPath = path;
      _selectedFileName = selected.name;
    });

    try {
      final summary = await _scanner.scanZip(path);
      if (!mounted) return;
      setState(() => _summary = summary);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '读取聊天档案失败：$error');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _importArchive() async {
    final zipPath = _selectedZipPath;
    if (zipPath == null || _summary == null || _isImporting) return;

    setState(() {
      _isImporting = true;
      _error = null;
      _importResult = null;
    });

    try {
      final result = await _importer.importZip(zipPath);
      if (!mounted) return;
      setState(() => _importResult = result);
      widget.onImported?.call();
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '写入本地数据库失败：$error');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入微信聊天档案')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            const _ImportHero(),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _isScanning || _isImporting ? null : _pickArchive,
              icon: const Icon(Icons.folder_zip_rounded),
              label: Text(_isScanning ? '正在扫描…' : '选择 ZIP 文件'),
            ),
            if (_selectedFileName != null) ...[
              const SizedBox(height: 10),
              Text(
                _selectedFileName!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_isScanning || _isImporting) ...[
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(minHeight: 7),
              ),
              const SizedBox(height: 10),
              Text(
                _isImporting
                    ? '正在写入消息，并把媒体流式保存到本机、计算 SHA-256 去重…'
                    : '正在后台核对 messages.js 与媒体资源，不会把整个 ZIP 一次性读入内存。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 20),
              _ErrorCard(message: _error!),
            ],
            if (_summary != null) ...[
              const SizedBox(height: 20),
              _ArchivePreviewCard(summary: _summary!),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _isImporting ? null : _importArchive,
                icon: const Icon(Icons.favorite_rounded),
                label: Text(_isImporting ? '正在收藏这段回忆…' : '保存到点滴记忆'),
              ),
              const SizedBox(height: 8),
              Text(
                '消息、参与者、原始 messages.js 与可用媒体都会留在 App 私有目录；相同媒体内容只保存一份。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_importResult != null) ...[
              const SizedBox(height: 20),
              _ImportResultCard(result: _importResult!),
              if (widget.onOpenMemories != null) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: widget.onOpenMemories,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('查看回忆总结'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportHero extends StatelessWidget {
  const _ImportHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFE9E7),
            scheme.primaryContainer.withValues(alpha: 0.78),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.76),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.volunteer_activism_rounded, color: scheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '把聊天，变成可以回看的日子',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '选择 WechatExplorer 完整 HTML 档案 ZIP。完整聊天与媒体只在本机处理，不上传。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchivePreviewCard extends StatelessWidget {
  const _ArchivePreviewCard({required this.summary});

  final WechatArchiveSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0DDD9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '档案识别成功 · ${summary.archiveName}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricPill(icon: Icons.chat_bubble_outline, label: '${summary.messageCount} 条消息'),
              _MetricPill(icon: Icons.photo_outlined, label: '${summary.imageCount} 张图片'),
              _MetricPill(icon: Icons.videocam_outlined, label: '${summary.videoCount} 个视频'),
              if (summary.voiceCount > 0)
                _MetricPill(icon: Icons.mic_none_rounded, label: '${summary.voiceCount} 条语音'),
              _MetricPill(icon: Icons.emoji_emotions_outlined, label: '${summary.stickerCount} 个表情'),
              if (summary.fileCount > 0)
                _MetricPill(icon: Icons.insert_drive_file_outlined, label: '${summary.fileCount} 个文件'),
            ],
          ),
          const SizedBox(height: 14),
          _DetailRow(
            label: '媒体资源',
            value: '${summary.availableMediaCount}/${summary.mediaReferenceCount} 可用',
          ),
          if (summary.startTime != null && summary.endTime != null)
            _DetailRow(
              label: '时间范围',
              value: '${_formatDate(summary.startTime!)} ～ ${_formatDate(summary.endTime!)}',
            ),
          if (summary.missingMediaCount > 0)
            _DetailRow(
              label: '缺失资源',
              value: '${summary.missingMediaCount} 个',
              warning: true,
            ),
          const Divider(height: 24),
          Text(
            _friendlyMessagesPath(summary.messagesJsPath),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ImportResultCard extends StatelessWidget {
  const _ImportResultCard({required this.result});

  final WechatArchiveImportResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6F1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0D8D1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.favorite_rounded, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.isDuplicateSource ? '这段回忆已经收藏过' : '这段回忆收藏好了',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      result.archiveName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DetailRow(label: '档案消息', value: '${result.archiveMessageCount} 条'),
          _DetailRow(label: '新增消息', value: '${result.insertedMessageCount} 条'),
          _DetailRow(label: '已存在', value: '${result.existingMessageCount} 条'),
          _DetailRow(label: '参与者', value: '${result.participantCount} 个'),
          _DetailRow(
            label: '媒体保存',
            value: '${result.storedMediaReferenceCount}/${result.mediaReferenceCount} 个引用',
          ),
          _DetailRow(label: '唯一媒体', value: '${result.uniqueMediaCount} 个 SHA-256 内容'),
          _DetailRow(label: '本次新存', value: '${result.newlyStoredMediaCount} 个文件'),
          if (result.missingMediaCount > 0)
            _DetailRow(
              label: '缺失资源',
              value: '${result.missingMediaCount} 个',
              warning: true,
            ),
          const SizedBox(height: 10),
          Text(
            result.isDuplicateSource
                ? '消息没有重复写入；媒体仍会重新核对，缺少的本地副本会按 SHA-256 自动补齐。'
                : '原始 messages.js、消息与媒体都已保存到 App 私有目录；相同内容只保留一个媒体文件。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final valueStyle = warning
        ? TextStyle(color: Theme.of(context).colorScheme.error)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 84, child: Text(label)),
          Expanded(child: Text(value, style: valueStyle)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

String _formatDate(int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _friendlyMessagesPath(String sourcePath) {
  final normalized = sourcePath.replaceAll('\\', '/');
  final index = normalized.toLowerCase().lastIndexOf('data/messages.js');
  return index >= 0 ? normalized.substring(index) : normalized;
}
