import 'dart:io';

import 'package:flutter/material.dart';

import '../data/memory_repository.dart';
import '../model/memory_models.dart';

class MemoryPage extends StatefulWidget {
  const MemoryPage({
    super.key,
    this.refreshToken = 0,
    this.repository = const MemoryRepository(),
  });

  final int refreshToken;
  final MemoryRepository repository;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  late Future<List<MemoryDaySummary>> _summariesFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant MemoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _reload();
    }
  }

  void _reload() {
    _summariesFuture = widget.repository.loadDailySummaries();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _summariesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我们的点滴'),
        centerTitle: false,
      ),
      body: FutureBuilder<List<MemoryDaySummary>>(
        future: _summariesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _LoadError(
              message: '读取本地回忆失败：${snapshot.error}',
              onRetry: () => setState(_reload),
            );
          }

          final summaries = snapshot.data ?? const <MemoryDaySummary>[];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                const _MemoryHero(),
                const SizedBox(height: 18),
                if (summaries.isEmpty)
                  const _EmptyMemoryCard()
                else ...[
                  Row(
                    children: [
                      Text(
                        '每日小结',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      _SoftTag(label: '${summaries.length} 天'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '当前小结来自本地消息统计；展开后会直接读取 SQLite 中的真实聊天记录。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  for (final summary in summaries) ...[
                    _MemoryDayCard(
                      summary: summary,
                      repository: widget.repository,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MemoryHero extends StatelessWidget {
  const _MemoryHero();

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
            scheme.primaryContainer,
            const Color(0xFFFFEDE7),
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
              color: Colors.white.withValues(alpha: 0.72),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.favorite_rounded, color: scheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '把平凡的日子，慢慢收进回忆里',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '所有聊天与媒体都保存在本机，想念的时候再打开看看。',
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

class _EmptyMemoryCard extends StatelessWidget {
  const _EmptyMemoryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1DAD7)),
      ),
      child: Column(
        children: [
          const Icon(Icons.favorite_border_rounded, size: 42),
          const SizedBox(height: 14),
          Text(
            '还没有回忆小结',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            '去「导入」页加入一份 WechatExplorer 聊天档案，完成后这里会按天整理。',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MemoryDayCard extends StatefulWidget {
  const _MemoryDayCard({
    required this.summary,
    required this.repository,
  });

  final MemoryDaySummary summary;
  final MemoryRepository repository;

  @override
  State<_MemoryDayCard> createState() => _MemoryDayCardState();
}

class _MemoryDayCardState extends State<_MemoryDayCard> {
  Future<List<MemoryChatMessage>>? _messagesFuture;

  void _handleExpansion(bool expanded) {
    if (expanded && _messagesFuture == null) {
      setState(() {
        _messagesFuture = widget.repository.loadMessagesForDay(widget.summary);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0DDD9)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 7),
            color: Color(0x12000000),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        onExpansionChanged: _handleExpansion,
        tilePadding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(Icons.auto_awesome_rounded, color: scheme.secondary),
        ),
        title: Text(
          _formatDayTitle(widget.summary.dateKey),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            widget.summary.summaryText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
        ),
        children: [
          const Divider(height: 18),
          Row(
            children: [
              _SoftTag(label: '${widget.summary.messageCount} 条聊天'),
              const SizedBox(width: 8),
              if (widget.summary.mediaMessageCount > 0)
                _SoftTag(label: '${widget.summary.mediaMessageCount} 条媒体'),
              const Spacer(),
              Text(
                '真实聊天',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MessageEvidenceList(future: _messagesFuture),
        ],
      ),
    );
  }
}

class _MessageEvidenceList extends StatelessWidget {
  const _MessageEvidenceList({required this.future});

  final Future<List<MemoryChatMessage>>? future;

  @override
  Widget build(BuildContext context) {
    final messagesFuture = future;
    if (messagesFuture == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<MemoryChatMessage>>(
      future: messagesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text('聊天记录读取失败：${snapshot.error}'),
          );
        }

        final messages = snapshot.data ?? const <MemoryChatMessage>[];
        if (messages.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text('这一天没有可展示的聊天记录。'),
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _ChatBubble(message: messages[index]),
          ),
        );
      },
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
    final background = isSelf
        ? scheme.primaryContainer.withValues(alpha: 0.72)
        : const Color(0xFFFFF8F4);
    final mediaFile = message.mediaLocalPath == null
        ? null
        : File(message.mediaLocalPath!);
    final showImage = mediaFile != null &&
        mediaFile.existsSync() &&
        _isImageMedia(message.mediaType);

    return Align(
      alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isSelf ? 18 : 5),
              bottomRight: Radius.circular(isSelf ? 5 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.senderName?.trim().isNotEmpty == true
                        ? message.senderName!.trim()
                        : isSelf
                            ? '我'
                            : '对方',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatMessageTime(message.createTime),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              if (showImage) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    mediaFile,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                _displayMessageContent(message),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
              if (message.mediaType != null && !showImage) ...[
                const SizedBox(height: 7),
                _MediaChip(
                  type: message.mediaType!,
                  name: message.mediaName,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaChip extends StatelessWidget {
  const _MediaChip({required this.type, this.name});

  final String type;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_file_rounded, size: 16),
          const SizedBox(width: 4),
          Flexible(child: Text(name?.trim().isNotEmpty == true ? name! : type)),
        ],
      ),
    );
  }
}

class _SoftTag extends StatelessWidget {
  const _SoftTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECE9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 38),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重新读取')),
          ],
        ),
      ),
    );
  }
}

String _formatDayTitle(String dateKey) {
  final parts = dateKey.split('-').map(int.parse).toList();
  final date = DateTime(parts[0], parts[1], parts[2]);
  const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
  return '${date.month}月${date.day}日 · 星期${weekdays[date.weekday - 1]}';
}

String _formatMessageTime(int? timestamp) {
  if (timestamp == null) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

bool _isImageMedia(String? type) {
  final normalized = type?.toLowerCase() ?? '';
  return normalized.contains('image') ||
      normalized.contains('sticker') ||
      normalized.contains('图片') ||
      normalized.contains('表情');
}

String _displayMessageContent(MemoryChatMessage message) {
  final content = message.content?.trim();
  if (content == null || content.isEmpty) {
    return '[${message.messageType ?? message.mediaType ?? '消息'}]';
  }
  if (content.startsWith('<') && content.length > 240) {
    return '[${message.messageType ?? '结构化消息'}]';
  }
  return content;
}
