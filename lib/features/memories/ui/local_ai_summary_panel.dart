import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/ai_summary_repository.dart';
import '../data/hierarchical_summary_service.dart';
import '../data/local_ai_model_manager.dart';
import '../model/ai_summary_models.dart';

class LocalAiSummaryPanel extends StatefulWidget {
  const LocalAiSummaryPanel({
    super.key,
    required this.onSummariesChanged,
    this.repository = const AiSummaryRepository(),
    this.modelManager = const LocalAiModelManager(),
    this.summaryService,
  });

  final VoidCallback onSummariesChanged;
  final AiSummaryRepository repository;
  final LocalAiModelManager modelManager;
  final HierarchicalSummaryService? summaryService;

  @override
  State<LocalAiSummaryPanel> createState() => _LocalAiSummaryPanelState();
}

class _LocalAiSummaryPanelState extends State<LocalAiSummaryPanel> {
  late final HierarchicalSummaryService _summaryService;
  SummaryPeriod _period = SummaryPeriod.day;
  LocalAiModelInfo? _model;
  List<SummaryRange> _ranges = const <SummaryRange>[];
  Map<String, StoredAiSummary> _summaries = const <String, StoredAiSummary>{};
  String? _busyKey;
  String? _status;
  String? _error;
  double? _modelCopyProgress;
  bool _loading = true;
  bool _showAllRanges = false;

  @override
  void initState() {
    super.initState();
    _summaryService = widget.summaryService ?? HierarchicalSummaryService();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final model = await widget.modelManager.currentModel();
      final ranges = await widget.repository.loadRanges(_period);
      final summaries = await widget.repository.loadSummaries(_period);
      if (!mounted) return;
      setState(() {
        _model = model;
        _ranges = ranges;
        _summaries = summaries;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '读取本地 AI 状态失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectModel() async {
    if (_busyKey != null) return;
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['gguf'],
    );
    final sourcePath = selected?.path;
    if (sourcePath == null || sourcePath.isEmpty) return;

    setState(() {
      _busyKey = 'model';
      _modelCopyProgress = 0;
      _error = null;
      _status = '正在导入自定义 GGUF…';
    });
    try {
      final model = await widget.modelManager.importModel(
        sourcePath,
        onProgress: (progress) {
          if (mounted) setState(() => _modelCopyProgress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _model = model;
        _status = '已切换到 ${model.name}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '导入自定义模型失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busyKey = null;
          _modelCopyProgress = null;
        });
      }
    }
  }

  Future<void> _useBundledModel() async {
    if (_busyKey != null) return;
    setState(() {
      _busyKey = 'model';
      _error = null;
      _status = '正在恢复内置轻量模型…';
    });
    try {
      final model = await widget.modelManager.useBundledModel();
      if (!mounted) return;
      setState(() {
        _model = model;
        _status = '已使用内置模型';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '启用内置模型失败：$error');
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _generateRange(SummaryRange range) async {
    if (_busyKey != null) return;
    setState(() {
      _busyKey = range.key;
      _error = null;
      _status = '准备 ${range.label}…';
    });
    try {
      await _summaryService.generate(
        range,
        onProgress: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      widget.onSummariesChanged();
      setState(() => _status = '${range.label} 已整理完成');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '生成 ${range.label} 总结失败：$error');
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _generateAll() async {
    if (_busyKey != null || _ranges.isEmpty) return;
    setState(() {
      _busyKey = '__all__';
      _error = null;
    });
    try {
      for (var index = _ranges.length - 1; index >= 0; index -= 1) {
        if (!mounted) return;
        final range = _ranges[index];
        setState(() {
          _status = '整理 ${range.label}（${_ranges.length - index}/${_ranges.length}）';
        });
        await _summaryService.generate(
          range,
          onProgress: (status) {
            if (mounted) setState(() => _status = status);
          },
        );
      }
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      widget.onSummariesChanged();
      setState(() => _status = '当前${_period.label}总结已全部更新');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '批量生成失败：$error');
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _changePeriod(SummaryPeriod period) async {
    if (_busyKey != null || _period == period) return;
    setState(() {
      _period = period;
      _showAllRanges = false;
      _status = null;
      _error = null;
    });
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final model = _model;
    final generated = _ranges.where((range) => _summaries.containsKey(range.key)).length;
    final pending = _ranges.length - generated;
    final progress = _ranges.isEmpty ? 0.0 : generated / _ranges.length;
    final visibleRanges = _showAllRanges
        ? _ranges
        : _ranges.take(12).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModelCard(
          model: model,
          loading: _loading,
          busy: _busyKey != null,
          copyProgress: _modelCopyProgress,
          onSelectModel: _selectModel,
          onUseBundledModel: _useBundledModel,
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<SummaryPeriod>(
            showSelectedIcon: false,
            segments: SummaryPeriod.values
                .map(
                  (period) => ButtonSegment<SummaryPeriod>(
                    value: period,
                    label: Text(period.label),
                  ),
                )
                .toList(growable: false),
            selected: <SummaryPeriod>{_period},
            onSelectionChanged: _busyKey == null
                ? (selection) => _changePeriod(selection.single)
                : null,
          ),
        ),
        const SizedBox(height: 14),
        _ProgressCard(
          period: _period,
          total: _ranges.length,
          generated: generated,
          progress: progress,
          busy: _busyKey != null,
          status: _status,
          modelReady: model != null,
          onGenerateAll: _generateAll,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
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
                    _error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_loading) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
        ] else if (_ranges.isEmpty) ...[
          const SizedBox(height: 14),
          const _NoRangeCard(),
        ] else ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                _period == SummaryPeriod.day ? '每天的回忆' : '${_period.label}回忆',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                pending == 0 ? '已全部整理' : '还差 $pending 个',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: pending == 0 ? scheme.primary : scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final range in visibleRanges) ...[
            _SummaryRangeCard(
              range: range,
              summary: _summaries[range.key],
              busy: _busyKey == range.key || _busyKey == '__all__',
              onGenerate: () => _generateRange(range),
            ),
            const SizedBox(height: 10),
          ],
          if (_ranges.length > 12)
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: _busyKey == null
                    ? () => setState(() => _showAllRanges = !_showAllRanges)
                    : null,
                icon: Icon(_showAllRanges ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: Text(
                  _showAllRanges
                      ? '收起'
                      : '查看其余 ${_ranges.length - visibleRanges.length} 个',
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.loading,
    required this.busy,
    required this.copyProgress,
    required this.onSelectModel,
    required this.onUseBundledModel,
  });

  final LocalAiModelInfo? model;
  final bool loading;
  final bool busy;
  final double? copyProgress;
  final VoidCallback onSelectModel;
  final VoidCallback onUseBundledModel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final description = loading && model == null
        ? '正在准备 App 内置轻量模型…'
        : model == null
            ? '内置模型暂未就绪，可以选择自己的 GGUF。'
            : '${model!.name} · ${_formatBytes(model!.byteSize)} · 完全本地运行';

    return Card.filled(
      color: scheme.surfaceContainerLow,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.memory_rounded, color: scheme.primary),
        ),
        title: Row(
          children: [
            const Expanded(child: Text('本地模型')),
            if (model != null) _ModelTag(label: model!.isBundled ? '内置' : '自定义'),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '普通使用不需要设置。只有想更换模型时再打开这里。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onSelectModel,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('选择自定义 GGUF'),
              ),
              if (model != null && !model!.isBundled)
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onUseBundledModel,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('恢复内置模型'),
                ),
            ],
          ),
          if (copyProgress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: copyProgress),
          ],
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.period,
    required this.total,
    required this.generated,
    required this.progress,
    required this.busy,
    required this.status,
    required this.modelReady,
    required this.onGenerateAll,
  });

  final SummaryPeriod period;
  final int total;
  final int generated;
  final double progress;
  final bool busy;
  final String? status;
  final bool modelReady;
  final VoidCallback onGenerateAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = total - generated;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  total == 0
                      ? '暂无可整理内容'
                      : remaining == 0
                          ? '${period.label}总结已整理完成'
                          : '还有 $remaining 个${period.label}总结待整理',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text('$generated / $total', style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : progress,
              minHeight: 7,
              backgroundColor: scheme.surface.withValues(alpha: 0.68),
            ),
          ),
          if (status != null) ...[
            const SizedBox(height: 9),
            Text(
              status!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: modelReady && !busy && total > 0 ? onGenerateAll : null,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(
                busy
                    ? '正在整理…'
                    : remaining > 0
                        ? '继续整理'
                        : '检查并更新',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRangeCard extends StatelessWidget {
  const _SummaryRangeCard({
    required this.range,
    required this.summary,
    required this.busy,
    required this.onGenerate,
  });

  final SummaryRange range;
  final StoredAiSummary? summary;
  final bool busy;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        range.label,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${range.dayCount} 天 · ${range.messageCount} 条聊天',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StateBadge(done: summary != null),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              summary?.summaryText ?? '还没有总结。可以单独生成这一段，不需要重新跑全部。',
              maxLines: summary == null ? 2 : 5,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: summary == null ? scheme.onSurfaceVariant : scheme.onSurface,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : onGenerate,
                icon: Icon(summary == null ? Icons.auto_awesome_rounded : Icons.refresh_rounded),
                label: Text(summary == null ? '生成' : '重新整理'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelTag extends StatelessWidget {
  const _ModelTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: done ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        done ? '已整理' : '待整理',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: done ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _NoRangeCard extends StatelessWidget {
  const _NoRangeCard();

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '当前没有可整理的聊天。先导入聊天档案，再回来生成回忆总结。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
  return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
}
