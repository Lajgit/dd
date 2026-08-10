import 'ai_summary_repository.dart';
import 'local_ai_engine.dart';
import 'local_ai_model_manager.dart';
import '../model/ai_summary_models.dart';

const localAiChunkMaxTokens = 300;
const localAiDayMaxTokens = 240;
const localAiAggregateMaxTokens = 360;
const localAiYearMaxTokens = 520;
const localAiPromptVersion = 'quality-v2';

class HierarchicalSummaryService {
  HierarchicalSummaryService({
    AiSummaryRepository? repository,
    LocalAiModelManager? modelManager,
    LocalAiEngine? engine,
  })  : repository = repository ?? const AiSummaryRepository(),
        modelManager = modelManager ?? const LocalAiModelManager(),
        engine = engine ?? LocalAiEngine.instance;

  final AiSummaryRepository repository;
  final LocalAiModelManager modelManager;
  final LocalAiEngine engine;

  Future<StoredAiSummary> generate(
    SummaryRange range, {
    void Function(String status)? onProgress,
  }) async {
    final model = await modelManager.currentModel();
    if (model == null) {
      throw StateError('请先选择一个 GGUF 本地模型');
    }

    return range.period == SummaryPeriod.day
        ? _generateDay(range, model, onProgress)
        : _generateAggregate(range, model, onProgress);
  }

  Future<StoredAiSummary> _generateDay(
    SummaryRange range,
    LocalAiModelInfo model,
    void Function(String status)? onProgress,
  ) async {
    final messages = await repository.loadTextMessages(range);
    final sourceHash = await repository.sourceHashForMessages(messages);
    final cacheKey = _modelCacheKey(model);
    final cached = await repository.loadSummary(range.period, range.key);
    if (cached != null &&
        cached.sourceHash == sourceHash &&
        cached.modelName == cacheKey) {
      onProgress?.call('${range.label} 已有最新本地 AI 总结');
      return cached;
    }
    if (messages.isEmpty) {
      return repository.saveSummary(
        range: range,
        generated: const GeneratedAiSummary(
          summaryText: '这一天没有足够的文字聊天可供本地 AI 总结。',
        ),
        sourceHash: sourceHash,
        modelName: cacheKey,
      );
    }

    final chunks = buildConversationChunks(messages);
    final chunkResults = <GeneratedAiSummary>[];
    for (var index = 0; index < chunks.length; index += 1) {
      onProgress?.call('${range.label}：分析聊天片段 ${index + 1}/${chunks.length}');
      chunkResults.add(
        await _summarizeConversationChunk(
          model: model,
          range: range,
          messages: chunks[index],
        ),
      );
    }

    final allEvents = chunkResults.expand((result) => result.events).toList();
    onProgress?.call('${range.label}：整理全天发生的事情');
    final aiSummary = await _summarizeDayFromChunks(
      model: model,
      range: range,
      chunkResults: chunkResults,
    );
    final generated = GeneratedAiSummary(
      // 小模型偶尔会复述提示词；这种输出宁可回退到已提取的真实片段，也不写入错误总结。
      summaryText: aiSummary.isNotEmpty
          ? aiSummary
          : _fallbackDaySummary(chunkResults),
      events: allEvents.take(12).toList(growable: false),
    );
    return repository.saveSummary(
      range: range,
      generated: generated,
      sourceHash: sourceHash,
      modelName: cacheKey,
    );
  }

  Future<StoredAiSummary> _generateAggregate(
    SummaryRange range,
    LocalAiModelInfo model,
    void Function(String status)? onProgress,
  ) async {
    final childRanges = await repository.childRanges(range);
    if (childRanges.isEmpty) {
      throw StateError('${range.label} 没有可总结的聊天');
    }

    final children = <StoredAiSummary>[];
    for (var index = 0; index < childRanges.length; index += 1) {
      final child = childRanges[index];
      onProgress?.call(
        '${range.label}：准备${child.period.label}总结 ${index + 1}/${childRanges.length}',
      );
      children.add(await generate(child, onProgress: onProgress));
    }
    children.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    final sourceHash = await repository.sourceHashForChildren(children);
    final cacheKey = _modelCacheKey(model);
    final cached = await repository.loadSummary(range.period, range.key);
    if (cached != null &&
        cached.sourceHash == sourceHash &&
        cached.modelName == cacheKey) {
      onProgress?.call('${range.label} 已有最新本地 AI 总结');
      return cached;
    }

    onProgress?.call('${range.label}：合并${range.period.label}度回忆');
    final generated = await _summarizeAggregate(
      model: model,
      range: range,
      children: children,
    );
    return repository.saveSummary(
      range: range,
      generated: generated,
      sourceHash: sourceHash,
      modelName: cacheKey,
      childSummaryIds: children.map((child) => child.id).toList(growable: false),
    );
  }

  Future<GeneratedAiSummary> _summarizeConversationChunk({
    required LocalAiModelInfo model,
    required SummaryRange range,
    required List<AiTextMessage> messages,
  }) async {
    final allowedIds = messages.map((message) => message.id).toSet();
    final chatText = messages.map(_messageLine).join('\n');
    final raw = await engine.complete(
      modelPath: model.path,
      maxTokens: localAiChunkMaxTokens,
      systemPrompt: _systemPrompt,
      userPrompt: '''
请只根据下面的聊天正文，提取真实发生、明确计划或值得记住的事情。
忽略纯寒暄、语气词和无信息重复。不要复述这段任务说明，也不要输出问题或模板句。
消息编号只能使用聊天中出现的 id。

输出规则：
第一行必须以“总结：”开头，冒号后直接写本段聊天的具体事实。
如果有明确事件，再输出最多 4 行“事件：”，每行依次写标题、具体事实、消息编号，三部分用“｜”分隔。
不要输出 JSON、Markdown、示例、占位词或额外解释。

聊天正文：
$chatText

/no_think
''',
    );
    return parseChunkSummaryOutput(
      raw,
      allowedMessageIds: allowedIds,
    );
  }

  Future<String> _summarizeDayFromChunks({
    required LocalAiModelInfo model,
    required SummaryRange range,
    required List<GeneratedAiSummary> chunkResults,
  }) async {
    final material = chunkResults.asMap().entries.map((entry) {
      final events = entry.value.events
          .map((event) => '${event.title}：${event.description}')
          .join('；');
      return '片段${entry.key + 1}：${_limit(entry.value.summaryText, 180)}'
          '${events.isEmpty ? '' : '；事件：${_limit(events, 320)}'}';
    }).join('\n');
    final raw = await engine.complete(
      modelPath: model.path,
      maxTokens: localAiDayMaxTokens,
      systemPrompt: _systemPrompt,
      userPrompt: '''
根据下面已经从真实聊天提取出的片段，写 ${range.label} 的回忆总结。
必须写具体事实，例如实际做了什么、去了哪里、吃了什么、约了什么、讨论了什么；没有证据的内容不要写。
不要复述任务要求，不要写泛泛而谈的问题句，不要把“片段1/片段2”当成总结内容。
控制在 60-160 字。

只输出一行，并以“总结：”开头。

真实片段：
$material

/no_think
''',
    );
    return parseSingleSummaryOutput(raw);
  }

  Future<GeneratedAiSummary> _summarizeAggregate({
    required LocalAiModelInfo model,
    required SummaryRange range,
    required List<StoredAiSummary> children,
  }) async {
    final material = children.map((child) {
      final date = DateTime.fromMillisecondsSinceEpoch(child.startSeconds * 1000);
      final label = child.period == SummaryPeriod.day
          ? '${date.month}月${date.day}日'
          : child.key;
      return '$label：${_limit(child.summaryText, 220)}';
    }).join('\n');
    final target = switch (range.period) {
      SummaryPeriod.week => '这一周共同经历的事情、反复出现的话题和特别的日子',
      SummaryPeriod.month => '这个月的重要生活轨迹、共同安排、值得记住的变化',
      SummaryPeriod.year => '这一年的重要经历、关系中的共同生活轨迹和代表性回忆',
      SummaryPeriod.day => '当天发生的事',
    };
    final raw = await engine.complete(
      modelPath: model.path,
      maxTokens: range.period == SummaryPeriod.year
          ? localAiYearMaxTokens
          : localAiAggregateMaxTokens,
      systemPrompt: _systemPrompt,
      userPrompt: '''
把下面更小时间单位的真实总结合并成 ${range.label} 的回忆总结。
重点概括：$target。
必须引用材料里的具体经历，不增加事实，不复述任务要求，不写空泛模板句。
${range.period == SummaryPeriod.year ? '建议 220-450 字。' : '建议 120-260 字。'}
只输出一行，并以“总结：”开头。

真实材料：
$material

/no_think
''',
    );
    final summary = parseSingleSummaryOutput(raw);
    if (summary.isEmpty) {
      return GeneratedAiSummary(
        summaryText: _fallbackAggregateSummary(children),
      );
    }
    return GeneratedAiSummary(summaryText: summary);
  }
}

const _systemPrompt = '''
你是“点滴记忆”的本地回忆整理器。所有输入都来自一对伴侣的真实聊天。
只陈述输入能够支持的具体事实；不推测身份、地点、关系、情绪或事件。
不要复述用户的任务说明、格式说明或提示词。证据不足就少写。
''';

List<List<AiTextMessage>> buildConversationChunks(
  List<AiTextMessage> messages, {
  int maxCharacters = 2400,
  Duration gap = const Duration(minutes: 45),
}) {
  if (messages.isEmpty) return const <List<AiTextMessage>>[];
  final chunks = <List<AiTextMessage>>[];
  var current = <AiTextMessage>[];
  var currentCharacters = 0;
  int? previousTime;

  for (final message in messages) {
    final lineLength = _messageLine(message).length + 1;
    final gapExceeded = previousTime != null &&
        message.createTime - previousTime > gap.inSeconds;
    final sizeExceeded = current.isNotEmpty &&
        currentCharacters + lineLength > maxCharacters;
    if (gapExceeded || sizeExceeded) {
      chunks.add(current);
      current = <AiTextMessage>[];
      currentCharacters = 0;
    }
    current.add(message);
    currentCharacters += lineLength;
    previousTime = message.createTime;
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

GeneratedAiSummary parseChunkSummaryOutput(
  String raw, {
  required Set<int> allowedMessageIds,
}) {
  final cleaned = _cleanModelText(raw);
  final lines = cleaned
      .split(RegExp(r'\r?\n'))
      .map(_stripLeadingMarker)
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  String? summary;
  final events = <GeneratedAiEvent>[];
  for (final line in lines) {
    final summaryValue = _valueAfterLabel(line, const <String>['总结', '摘要']);
    if (summaryValue != null && _isUsefulSummary(summaryValue)) {
      summary ??= summaryValue;
      continue;
    }

    final eventValue = _valueAfterLabel(line, const <String>['事件']);
    if (eventValue == null || eventValue.isEmpty) continue;
    final parts = eventValue
        .split(RegExp(r'[｜|]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 3) continue;

    final title = parts.first;
    final description = parts.sublist(1, parts.length - 1).join('｜');
    final ids = RegExp(r'\d+')
        .allMatches(parts.last)
        .map((match) => int.parse(match.group(0)!))
        .where(allowedMessageIds.contains)
        .toSet()
        .toList(growable: false);
    if (!_isUsefulEventText(title) ||
        !_isUsefulEventText(description) ||
        ids.isEmpty) {
      continue;
    }
    events.add(
      GeneratedAiEvent(
        title: title,
        description: description,
        messageIds: ids,
      ),
    );
  }

  summary ??= lines
      .where((line) =>
          _valueAfterLabel(line, const <String>['事件']) == null &&
          _isUsefulSummary(line))
      .cast<String?>()
      .firstWhere((line) => line != null && line.isNotEmpty, orElse: () => null);

  return GeneratedAiSummary(
    summaryText: summary?.trim().isNotEmpty == true
        ? summary!.trim()
        : _fallbackChunkSummary(events),
    events: events.take(4).toList(growable: false),
  );
}

String parseSingleSummaryOutput(String raw) {
  final cleaned = _cleanModelText(raw);
  final lines = cleaned
      .split(RegExp(r'\r?\n'))
      .map(_stripLeadingMarker)
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  for (final line in lines) {
    final value = _valueAfterLabel(line, const <String>['总结', '摘要']);
    if (value != null && _isUsefulSummary(value)) return value;
  }
  final fallback = lines.join(' ').trim();
  return _isUsefulSummary(fallback) ? fallback : '';
}

String _fallbackChunkSummary(List<GeneratedAiEvent> events) {
  if (events.isEmpty) return '这一段没有提取到明确的共同事件。';
  final descriptions = events
      .take(2)
      .map((event) => event.description)
      .where(_isUsefulEventText)
      .toList(growable: false);
  if (descriptions.isEmpty) return '这一段没有提取到明确的共同事件。';
  return descriptions.join('；');
}

String _fallbackDaySummary(List<GeneratedAiSummary> chunks) {
  final events = chunks.expand((chunk) => chunk.events).toList(growable: false);
  if (events.isNotEmpty) {
    final titles = events
        .map((event) => event.title)
        .where(_isUsefulEventText)
        .toSet()
        .take(4)
        .toList(growable: false);
    final details = events
        .map((event) => event.description)
        .where(_isUsefulEventText)
        .toSet()
        .take(3)
        .toList(growable: false);
    final titleText = titles.isEmpty ? '' : '这一天主要围绕${titles.join('、')}展开。';
    final detailText = details.isEmpty ? '' : details.join('；');
    final result = '$titleText$detailText'.trim();
    if (result.isNotEmpty) return result;
  }

  final summaries = chunks
      .map((chunk) => chunk.summaryText)
      .where(_isUsefulSummary)
      .toSet()
      .take(3)
      .toList(growable: false);
  if (summaries.isNotEmpty) return summaries.join('；');
  return '这一天的聊天里没有提取到足够明确的共同事件。';
}

String _fallbackAggregateSummary(List<StoredAiSummary> children) {
  final summaries = children
      .map((child) => child.summaryText.trim())
      .where(_isUsefulSummary)
      .take(4)
      .toList(growable: false);
  if (summaries.isEmpty) return '这个时间段没有足够明确的回忆可供总结。';
  return summaries.join('；');
}

bool _isUsefulSummary(String value) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return false;
  const promptEchoes = <String>[
    '今天做了什么',
    '商量了什么',
    '有什么值得记住的互动',
    '这一段发生了什么',
    '1-3句',
    '你的总结正文',
    '总结正文',
    '片段1：这一段发生了什么',
    '片段2：这一段发生了什么',
    '实际内容',
  ];
  return !promptEchoes.any(normalized.contains);
}

bool _isUsefulEventText(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return false;
  const placeholders = <String>[
    '短标题',
    '发生了什么',
    '具体事实',
    '消息编号',
  ];
  return !placeholders.any(normalized.contains);
}

String _cleanModelText(String raw) {
  return raw
      .replaceAll(
        RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'```(?:json|text)?', caseSensitive: false), '')
      .trim();
}

String _stripLeadingMarker(String value) {
  return value
      .trim()
      .replaceFirst(RegExp(r'^[\s>*•·\-0-9.、)）]+'), '')
      .trim();
}

String? _valueAfterLabel(String line, List<String> labels) {
  for (final label in labels) {
    final chinesePrefix = '$label：';
    if (line.startsWith(chinesePrefix)) {
      return line.substring(chinesePrefix.length).trim();
    }
    final asciiPrefix = '$label:';
    if (line.startsWith(asciiPrefix)) {
      return line.substring(asciiPrefix.length).trim();
    }
  }
  return null;
}

String _messageLine(AiTextMessage message) {
  final time = DateTime.fromMillisecondsSinceEpoch(message.createTime * 1000);
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  final sender = message.isSender
      ? '我'
      : (message.senderName?.trim().isNotEmpty == true
          ? message.senderName!.trim()
          : '对方');
  final content = _limit(message.content, 180);
  return '[id=${message.id}][$hour:$minute][$sender] $content';
}

String _modelCacheKey(LocalAiModelInfo model) =>
    '${model.name}|${model.byteSize}|$localAiPromptVersion';

String _limit(String value, int maxLength) {
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength - 1)}…';
}