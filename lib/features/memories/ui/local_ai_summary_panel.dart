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
      _status = '正在把自定义 GGUF 复制到 App 私有目录…';
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
        _status = '已切换到自定义模型：${model.name}';
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
      _status = '正在切回 App 内置轻量模型…';
    });
    try {
      final model = await widget.modelManager.useBundledModel();
      if (!mounted) return;
      setState(() {
        _model = model;
        _status = '已使用内置模型：${model.name}';
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
      _status = '准备 ${range.label} 的本地 AI 总结…';
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
      setState(() => _status = '${range.label} 总结完成');
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
          _status = '生成 ${range.label}（${_ranges.length - index}/${_ranges.length}）';
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
      _status = null;
      _error = null;
    });
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final model = _model;
    final modelDescription = _loading && model == null
        ? '首次打开会把 APK 内置的 Qwen3 0.6B 轻量模型复制到 App 私有目录，之后可完全离线使用。'
        : model == null
            ? '内置模型暂未就绪；仍可通过高级选项选择自己的 GGUF。'
            : '${model.isBundled ? '内置轻量模型' : '自定义 GGUF'} · ${model.name} · ${_formatBytes(model.byteSize)} · 完全本地运行';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFFFFF1EF), Color(0xFFFFE5EB)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF0D6D8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.memory_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '本地 AI 回忆总结',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (model?.isBundled == true)
                    const _ModelTag(label: '内置')
                  else if (model != null)
                    const _ModelTag(label: '自定义'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                modelDescription,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busyKey == null ? _selectModel : null,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('高级：选择自定义 GGUF'),
                  ),
                  if (model != null && !model.isBundled)
                    FilledButton.tonalIcon(
                      onPressed: _busyKey == null ? _useBundledModel : null,
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('恢复内置模型'),
                    ),
                ],
              ),
              if (_modelCopyProgress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _modelCopyProgress),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<SummaryPeriod>(
                  segments: SummaryPeriod.values
                      .map(
                        (period) => ButtonSegment<SummaryPeriod>(
                          value: period,
                          label: Text('${period.label}总结'),
                        ),
                      )
                      .toList(growable: false),
                  selected: <SummaryPeriod>{_period},
                  onSelectionChanged: _busyKey == null
                      ? (selection) => _changePeriod(selection.single)
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      _period == SummaryPeriod.day
                          ? '日总结从当天真实聊天分段提取事件；周/月/年总结会复用更小周期的 AI 总结逐级合并。'
                          : '${_period.label}总结只读取已经生成的下一级总结；缺少时会自动先补齐，结果会缓存到 SQLite。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: model != null && _busyKey == null && _ranges.isNotEmpty
                        ? _generateAll
                        : null,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(_busyKey == '__all__' ? '生成中…' : '生成全部'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_status != null) ...[
          const SizedBox(height: 10),
          Text(_status!, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        if (_loading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ] else if (_period == SummaryPeriod.day) ...[
          const SizedBox(height: 12),
          _DayAiStatus(total: _ranges.length, generated: _summaries.length),
        ] else ...[
          const SizedBox(height: 12),
          for (final range in _ranges) ...[
            _AggregateSummaryCard(
              range: range,
              summary: _summaries[range.key],
              busy: _busyKey == range.key || _busyKey == '__all__',
              onGenerate: () => _generateRange(range),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
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
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _DayAiStatus extends StatelessWidget {
  const _DayAiStatus({required this.total, required this.generated});

  final int total;
  final int generated;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0DDDA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.today_rounded, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '已生成 $generated / $total 天。生成完成后，「回忆」页的当天摘要会自动优先使用本地 AI 结果。',
            ),
          ),
        ],
      ),
    );
  }
}

class _AggregateSummaryCard extends StatelessWidget {
  const _AggregateSummaryCard({
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    range.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${range.dayCount} 天 · ${range.messageCount} 条聊天',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              summary?.summaryText ?? '尚未生成本地 AI 总结。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : onGenerate,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(summary == null ? '生成总结' : '重新总结'),
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
