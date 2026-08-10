import 'dart:io';

import 'package:flutter/material.dart';

import '../data/memory_repository.dart';
import '../model/memory_models.dart';
import 'media_preview_page.dart';

class MemoryOverviewPage extends StatefulWidget {
  const MemoryOverviewPage({
    super.key,
    this.refreshToken = 0,
    this.onOpenImport,
    this.onOpenAi,
    this.repository = const MemoryRepository(),
  });

  final int refreshToken;
  final VoidCallback? onOpenImport;
  final VoidCallback? onOpenAi;
  final MemoryRepository repository;

  @override
  State<MemoryOverviewPage> createState() => _MemoryOverviewPageState();
}

class _MemoryOverviewPageState extends State<MemoryOverviewPage> {
  late Future<List<MemoryDaySummary>> _future;
  String? _selectedMonth;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant MemoryOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  void _reload() {
    _future = widget.repository.loadDailySummaries();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我们的点滴'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: FutureBuilder<List<MemoryDaySummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingState();
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: '读取本地回忆失败：${snapshot.error}',
              onRetry: () => setState(_reload),
            );
          }

          final summaries = snapshot.data ?? const <MemoryDaySummary>[];
          if (summaries.isEmpty) {
            return _EmptyState(onOpenImport: widget.onOpenImport);
          }

          final months = _monthsOf(summaries);
          if (_selectedMonth != null && !months.contains(_selectedMonth)) {
            _selectedMonth = null;
          }
          final visible = _selectedMonth == null
              ? summaries
              : summaries
                  .where((summary) => summary.dateKey.startsWith(_selectedMonth!))
                  .toList(growable: false);
          final messageCount = summaries.fold<int>(
            0,
            (total, item) => total + item.messageCount,
          );
          final mediaCount = summaries.fold<int>(
            0,
            (total, item) => total + item.mediaMessageCount,
          );

          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  sliver: SliverToBoxAdapter(
                    child: _MemoryDashboard(
                      dayCount: summaries.length,
                      messageCount: messageCount,
                      mediaCount: mediaCount,
                      onOpenAi: widget.onOpenAi,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  sliver: SliverToBoxAdapter(
                    child: _MonthFilter(
                      months: months,
                      selected: _selectedMonth,
                      onSelected: (month) => setState(() => _selectedMonth = month),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Text(
                          _selectedMonth == null ? '时间线' : _formatMonthLabel(_selectedMonth!),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          '${visible.length} 天',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final summary = visible[index];
                      return _MemoryDayTile(
                        summary: summary,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _MemoryDayDetailPage(
                                summary: summary,
                                repository: widget.repository,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MemoryDashboard extends StatelessWidget {
  const _MemoryDashboard({
    required this.dayCount,
    required this.messageCount,
    required this.mediaCount,
    this.onOpenAi,
  });

  final int dayCount;
  final int messageCount;
  final int mediaCount;
  final VoidCallback? onOpenAi;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.10)),
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
                  color: scheme.surface.withValues(alpha: 0.84),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.favorite_rounded, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '把日子留在这里',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '聊天、照片与本地 AI 总结都只属于你们。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _Stat(value: '$dayCount', label: '有记录的日子')),
              const SizedBox(width: 8),
              Expanded(child: _Stat(value: _compactNumber(messageCount), label: '聊天')),
              const SizedBox(width: 8),
              Expanded(child: _Stat(value: _compactNumber(mediaCount), label: '媒体')),
            ],
          ),
          if (onOpenAi != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: onOpenAi,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('整理新的 AI 回忆'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.fade,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _MonthFilter extends StatelessWidget {
  const _MonthFilter({required this.months, required this.selected, required this.onSelected});
  final List<String> months;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChip(label: '全部', selected: selected == null, onTap: () => onSelected(null)),
          const SizedBox(width: 8),
          for (var index = 0; index < months.length; index += 1) ...[
            _FilterChip(
              label: _formatMonthLabel(months[index]),
              selected: selected == months[index],
              onTap: () => onSelected(months[index]),
            ),
            if (index != months.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}

class _MemoryDayTile extends StatelessWidget {
  const _MemoryDayTile({required this.summary, required this.onTap});
  final MemoryDaySummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = DateTime.fromMillisecondsSinceEpoch(summary.dayStartSeconds * 1000);
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.62)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateBadge(date: date),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _weekdayLabel(date),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      summary.summaryText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _Meta(icon: Icons.chat_bubble_outline_rounded, text: '${summary.messageCount}'),
                        if (summary.mediaMessageCount > 0)
                          _Meta(icon: Icons.photo_library_outlined, text: '${summary.mediaMessageCount}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            '${date.day}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSecondaryContainer,
                ),
          ),
          Text(
            '${date.month}月',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _MemoryDayDetailPage extends StatelessWidget {
  const _MemoryDayDetailPage({required this.summary, required this.repository});
  final MemoryDaySummary summary;
  final MemoryRepository repository;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(summary.dayStartSeconds * 1000);
    return Scaffold(
      appBar: AppBar(title: Text('${date.month}月${date.day}日 · ${_weekdayLabel(date)}')),
      body: FutureBuilder<List<MemoryChatMessage>>(
        future: repository.loadMessagesForDay(summary),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const _LoadingState();
          if (snapshot.hasError) {
            return _ErrorState(
              message: '聊天记录读取失败：${snapshot.error}',
              onRetry: () {},
              showRetry: false,
            );
          }
          final messages = snapshot.data ?? const <MemoryChatMessage>[];
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            itemCount: messages.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _DaySummaryCard(summary: summary),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _ChatBubble(message: messages[index - 1]),
              );
            },
          );
        },
      ),
    );
  }
}

class _DaySummaryCard extends StatelessWidget {
  const _DaySummaryCard({required this.summary});
  final MemoryDaySummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              Text('这一天', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          Text(summary.summaryText, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(text: '${summary.messageCount} 条聊天'),
              _Pill(text: '你 ${summary.selfMessageCount} · 对方 ${summary.otherMessageCount}'),
              if (summary.mediaMessageCount > 0) _Pill(text: '${summary.mediaMessageCount} 条媒体'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final MemoryChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSelf = message.isSender;
    final media = _mediaPreview(context, message);
    final content = _displayContent(message);
    return Align(
      alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
          decoration: BoxDecoration(
            color: isSelf ? scheme.primaryContainer.withValues(alpha: 0.72) : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isSelf ? 20 : 7),
              bottomRight: Radius.circular(isSelf ? 7 : 20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _senderLabel(message),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                  ),
                  if (message.createTime != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      _timeLabel(message.createTime!),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
              if (media != null) ...[
                const SizedBox(height: 8),
                media,
              ],
              if (content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(content, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45)),
                ),
              if (media == null && message.mediaType?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 7),
                _AttachmentChip(message: message),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget? _mediaPreview(BuildContext context, MemoryChatMessage message) {
  final path = message.mediaLocalPath;
  if (path == null || path.trim().isEmpty) return null;
  final file = File(path);
  if (!file.existsSync()) return null;

  if (_isImage(message)) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ImagePreviewPage(file: file, title: message.mediaName),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          file,
          width: 250,
          height: 180,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  if (_isVideo(message)) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => VideoPreviewPage(file: file, title: message.mediaName),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_fill_rounded),
              SizedBox(width: 8),
              Text('播放视频'),
            ],
          ),
        ),
      ),
    );
  }
  return null;
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.message});
  final MemoryChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_file_rounded, size: 16),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              message.mediaName?.trim().isNotEmpty == true
                  ? message.mediaName!.trim()
                  : (message.mediaType ?? '媒体'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onOpenImport});
  final VoidCallback? onOpenImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 28),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.favorite_border_rounded, size: 34, color: scheme.primary),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '从第一段聊天开始',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          '导入 WechatExplorer ZIP 后，会自动按天整理聊天、媒体和本地 AI 回忆。原始内容只保存在设备上。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
        ),
        if (onOpenImport != null) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onOpenImport,
            icon: const Icon(Icons.add_rounded),
            label: const Text('导入聊天档案'),
          ),
        ],
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry, this.showRetry = true});
  final String message;
  final VoidCallback onRetry;
  final bool showRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (showRetry) ...[
              const SizedBox(height: 14),
              FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
            ],
          ],
        ),
      ),
    );
  }
}

List<String> _monthsOf(List<MemoryDaySummary> summaries) {
  final months = <String>[];
  for (final summary in summaries) {
    if (summary.dateKey.length < 7) continue;
    final month = summary.dateKey.substring(0, 7);
    if (!months.contains(month)) months.add(month);
  }
  return months;
}

String _formatMonthLabel(String value) {
  final parts = value.split('-');
  if (parts.length != 2) return value;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null) return value;
  return '$year年$month月';
}

String _weekdayLabel(DateTime date) {
  const labels = <String>['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  return labels[date.weekday - 1];
}

String _senderLabel(MemoryChatMessage message) {
  final name = message.senderName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return message.isSender ? '我' : '对方';
}

String _timeLabel(int seconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _displayContent(MemoryChatMessage message) {
  final content = message.content?.trim() ?? '';
  if (content.isEmpty) return '';
  if (content.startsWith('<') && content.endsWith('>')) return '结构化微信消息';
  return content;
}

bool _isImage(MemoryChatMessage message) {
  final type = '${message.mediaType ?? ''} ${message.messageType ?? ''}'.toLowerCase();
  return type.contains('image') || type.contains('sticker') || type.contains('img');
}

bool _isVideo(MemoryChatMessage message) {
  final type = '${message.mediaType ?? ''} ${message.messageType ?? ''}'.toLowerCase();
  return type.contains('video');
}

String _compactNumber(int value) {
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(value >= 100000 ? 0 : 1)}万';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}
