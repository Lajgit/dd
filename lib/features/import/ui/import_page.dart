import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/wechat_archive_scanner.dart';
import '../model/wechat_archive_models.dart';

class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final WechatArchiveScanner _scanner = const WechatArchiveScanner();

  WechatArchiveSummary? _summary;
  String? _selectedFileName;
  String? _error;
  bool _isScanning = false;

  Future<void> _pickArchive() async {
    if (_isScanning) return;

    const zipTypeGroup = XTypeGroup(
      label: 'ZIP archive',
      extensions: <String>['zip'],
    );
    final selected = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[zipTypeGroup],
    );
    if (selected == null) return;

    final path = selected.path.trim();
    if (path.isEmpty) {
      setState(() {
        _error = '无法获取该 ZIP 的本地路径，请先将档案保存到手机后再选择。';
        _summary = null;
        _selectedFileName = selected.name;
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _error = null;
      _summary = null;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入微信聊天档案')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'WechatExplorer ZIP',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              '直接选择 WechatExplorer 的完整 HTML 档案 ZIP。App 会查找 data/messages.js，并核对图片、视频、语音和文件资源是否存在。',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isScanning ? null : _pickArchive,
              icon: const Icon(Icons.folder_zip_outlined),
              label: Text(_isScanning ? '正在扫描…' : '选择 ZIP 文件'),
            ),
            if (_selectedFileName != null) ...[
              const SizedBox(height: 12),
              Text(
                _selectedFileName!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_isScanning) ...[
              const SizedBox(height: 24),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                '大型档案会在后台解析，不会一次性把全部媒体读入内存。',
                textAlign: TextAlign.center,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 24),
              _ErrorCard(message: _error!),
            ],
            if (_summary != null) ...[
              const SizedBox(height: 24),
              _SummaryCard(summary: _summary!),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final WechatArchiveSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '档案识别成功',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow(label: '聊天', value: summary.archiveName),
            if (summary.archiveVersion != null)
              _DetailRow(label: '档案版本', value: '${summary.archiveVersion}'),
            _DetailRow(label: '消息', value: '${summary.messageCount} 条'),
            _DetailRow(label: '图片', value: '${summary.imageCount} 张'),
            _DetailRow(label: '视频', value: '${summary.videoCount} 个'),
            _DetailRow(label: '语音', value: '${summary.voiceCount} 条'),
            _DetailRow(label: '表情', value: '${summary.stickerCount} 个'),
            _DetailRow(label: '文件', value: '${summary.fileCount} 个'),
            _DetailRow(
              label: '媒体引用',
              value: '${summary.availableMediaCount}/${summary.mediaReferenceCount} 可用',
            ),
            if (summary.missingMediaCount > 0)
              _DetailRow(
                label: '缺失资源',
                value: '${summary.missingMediaCount} 个',
                warning: true,
              ),
            if (summary.startTime != null && summary.endTime != null)
              _DetailRow(
                label: '时间范围',
                value: '${_formatDate(summary.startTime!)} ～ ${_formatDate(summary.endTime!)}',
              ),
            const Divider(height: 28),
            Text(
              summary.messagesJsPath,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
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
          SizedBox(width: 76, child: Text(label)),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
