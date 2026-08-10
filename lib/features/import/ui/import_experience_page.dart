import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/wechat_archive_importer.dart';
import '../data/wechat_archive_scanner.dart';
import '../model/wechat_archive_models.dart';

class ImportExperiencePage extends StatefulWidget {
  const ImportExperiencePage({
    super.key,
    this.onImported,
    this.onOpenMemories,
  });

  final VoidCallback? onImported;
  final VoidCallback? onOpenMemories;

  @override
  State<ImportExperiencePage> createState() => _ImportExperiencePageState();
}

class _ImportExperiencePageState extends State<ImportExperiencePage> {
  final WechatArchiveScanner _scanner = const WechatArchiveScanner();
  final WechatArchiveImporter _importer = const WechatArchiveImporter();

  WechatArchiveSummary? _summary;
  WechatArchiveImportResult? _result;
  String? _selectedFileName;
  String? _selectedZipPath;
  String? _error;
  bool _isScanning = false;
  bool _isImporting = false;

  int get _step {
    if (_result != null) return 2;
    if (_summary != null) return 1;
    return 0;
  }

  Future<void> _pickArchive() async {
    if (_isScanning || _isImporting) return;
    // 只取路径，避免大型 ZIP 通过平台通道一次性进入内存。
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    if (selected == null) return;

    final path = selected.path;
    if (path == null || path.trim().isEmpty) {
      setState(() {
        _error = '无法获取这个 ZIP 的本地路径，请先把档案保存到手机后再选择。';
        _summary = null;
        _result = null;
        _selectedZipPath = null;
        _selectedFileName = selected.name;
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _error = null;
      _summary = null;
      _result = null;
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
    final path = _selectedZipPath;
    if (path == null || _summary == null || _isImporting) return;
    setState(() {
      _isImporting = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _importer.importZip(path);
      if (!mounted) return;
      setState(() => _result = result);
      widget.onImported?.call();
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '保存聊天档案失败：$error');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _startAnotherImport() {
    setState(() {
      _summary = null;
      _result = null;
      _selectedFileName = null;
      _selectedZipPath = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('导入微信聊天档案')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            _ImportIntro(step: _step),
            const SizedBox(height: 16),
            if (_result == null) ...[
              _PickerCard(
                selectedFileName: _selectedFileName,
                scanning: _isScanning,
                importing: _isImporting,
                onPick: _pickArchive,
              ),
              if (_isScanning) ...[
                const SizedBox(height: 12),
                const _WorkingCard(
                  title: '正在检查档案',
                  description: '只读取必要的索引信息，不会把整个 ZIP 一次加载进内存。',
                ),
              ],
              if (_summary != null) ...[
                const SizedBox(height: 14),
                _ArchivePreview(summary: _summary!),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isImporting ? null : _importArchive,
                    icon: _isImporting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.favorite_rounded),
                    label: Text(_isImporting ? '正在保存…' : '确认保存到点滴记忆'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '保存后会写入本地 SQLite，并把可用媒体流式复制到 App 私有目录；相同内容只保留一份。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (_isImporting) ...[
                const SizedBox(height: 12),
                const _WorkingCard(
                  title: '正在收藏这段回忆',
                  description: '正在写入聊天、保存媒体并计算 SHA-256 去重。请保持 App 在前台。',
                ),
              ],
            ] else ...[
              _ImportSuccess(
                result: _result!,
                onOpenMemories: widget.onOpenMemories,
                onImportAnother: _startAnotherImport,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              _ErrorCard(message: _error!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportIntro extends StatelessWidget {
  const _ImportIntro({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.archive_outlined, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '把旧聊天，变成可以继续翻看的回忆',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '选择 WechatExplorer 导出的完整 ZIP。扫描、保存和后续 AI 总结都在设备上完成。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 18),
          _StepIndicator(current: step),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StepItem(index: 0, current: current, label: '选择档案')),
        const SizedBox(width: 6),
        Expanded(child: _StepItem(index: 1, current: current, label: '确认内容')),
        const SizedBox(width: 6),
        Expanded(child: _StepItem(index: 2, current: current, label: '保存完成')),
      ],
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({required this.index, required this.current, required this.label});

  final int index;
  final int current;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = index <= current;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: active ? scheme.surface.withValues(alpha: 0.86) : scheme.surface.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            index < current ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 15,
            color: active ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({
    required this.selectedFileName,
    required this.scanning,
    required this.importing,
    required this.onPick,
  });

  final String? selectedFileName;
  final bool scanning;
  final bool importing;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择聊天档案',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              '支持 WechatExplorer 完整 HTML 档案 ZIP。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: scanning || importing ? null : onPick,
                icon: const Icon(Icons.folder_zip_rounded),
                label: Text(scanning ? '正在扫描…' : '选择 ZIP 文件'),
              ),
            ),
            if (selectedFileName != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.description_outlined, size: 17, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      selectedFileName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkingCard extends StatelessWidget {
  const _WorkingCard({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 9),
              Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ArchivePreview extends StatelessWidget {
  const _ArchivePreview({required this.summary});

  final WechatArchiveSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.check_rounded, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('档案识别成功', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text(summary.archiveName, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Metric(icon: Icons.chat_bubble_outline_rounded, label: '${summary.messageCount} 条消息'),
                _Metric(icon: Icons.image_outlined, label: '${summary.imageCount} 张图片'),
                _Metric(icon: Icons.videocam_outlined, label: '${summary.videoCount} 个视频'),
                if (summary.voiceCount > 0)
                  _Metric(icon: Icons.mic_none_rounded, label: '${summary.voiceCount} 条语音'),
                _Metric(icon: Icons.emoji_emotions_outlined, label: '${summary.stickerCount} 个表情'),
                if (summary.fileCount > 0)
                  _Metric(icon: Icons.insert_drive_file_outlined, label: '${summary.fileCount} 个文件'),
              ],
            ),
            const SizedBox(height: 14),
            _InfoRow(label: '媒体资源', value: '${summary.availableMediaCount}/${summary.mediaReferenceCount} 可用'),
            if (summary.startTime != null && summary.endTime != null)
              _InfoRow(label: '时间范围', value: '${_formatDate(summary.startTime!)} ～ ${_formatDate(summary.endTime!)}'),
            if (summary.missingMediaCount > 0)
              _InfoRow(label: '缺失资源', value: '${summary.missingMediaCount} 个', warning: true),
          ],
        ),
      ),
    );
  }
}

class _ImportSuccess extends StatelessWidget {
  const _ImportSuccess({
    required this.result,
    required this.onOpenMemories,
    required this.onImportAnother,
  });

  final WechatArchiveImportResult result;
  final VoidCallback? onOpenMemories;
  final VoidCallback onImportAnother;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.favorite_rounded, color: scheme.primary),
          ),
          const SizedBox(height: 14),
          Text(
            result.isDuplicateSource ? '这段回忆已经在这里了' : '这段回忆保存好了',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(result.archiveName, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _SuccessStat(value: '${result.insertedMessageCount}', label: '新增消息')),
              const SizedBox(width: 8),
              Expanded(child: _SuccessStat(value: '${result.uniqueMediaCount}', label: '唯一媒体')),
              const SizedBox(width: 8),
              Expanded(child: _SuccessStat(value: '${result.missingMediaCount}', label: '缺失资源')),
            ],
          ),
          const SizedBox(height: 14),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 10),
            title: const Text('查看导入详情'),
            children: [
              _InfoRow(label: '档案消息', value: '${result.archiveMessageCount} 条'),
              _InfoRow(label: '已存在', value: '${result.existingMessageCount} 条'),
              _InfoRow(label: '参与者', value: '${result.participantCount} 个'),
              _InfoRow(label: '媒体保存', value: '${result.storedMediaReferenceCount}/${result.mediaReferenceCount} 个引用'),
              _InfoRow(label: '本次新存', value: '${result.newlyStoredMediaCount} 个文件'),
            ],
          ),
          if (onOpenMemories != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenMemories,
                icon: const Icon(Icons.favorite_rounded),
                label: const Text('去看回忆'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onImportAnother,
              icon: const Icon(Icons.add_rounded),
              label: const Text('继续导入另一份档案'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessStat extends StatelessWidget {
  const _SuccessStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.warning = false});

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: warning ? scheme.error : scheme.onSurface),
            ),
          ),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
