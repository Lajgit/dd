import 'ai_summary_repository.dart';
import 'local_ai_engine.dart';
import 'local_ai_model_manager.dart';
import '../model/ai_summary_models.dart';

const localAiChunkMaxTokens = 300;
const localAiDayMaxTokens = 240;
const localAiAggregateMaxTokens = 360;
const localAiYearMaxTokens = 520;

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
    final generated = GeneratedAiSummary(
      summaryText: await _summarizeDayFromChunks(
        model: model,
        range: range,
        chunkResults: chunkResults,
      ),
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
请整理 ${range.label} 的这一段情侣聊天。只依据输入，不要补充没有说过的事实。
提取 0-4 个真正发生、计划或值得记住的事情，忽略“哈哈”“嗯嗯”等闲聊。
消息编号只能使用输入中出现的 id。

不要输出 JSON。严格使用下面的逐行格式：
总结：这一段发生了什么，1-3句
事件：短标题｜发生了什么｜1,2
事件：短标题｜发生了什么｜3,4

没有值得记录的事件时只输出“总结：...”。不要输出 Markdown、思考过程或额外解释。

聊天：
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
根据下面已经从真实聊天中提取的片段，写一段 ${range.label} 的情侣回忆总结。
重点回答“今天做了什么、商量了什么、有什么值得记住的互动”。
不要编造，不要写聊天条数，不要逐句复述，使用自然温暖的中文，80-180字。
不要输出 JSON。只输出一行：
总结：你的总结正文

$material

/no_think
''',
    );
    final summary = parseSingleSummaryOutput(raw);
    if (summary.isEmpty) {
      throw const FormatException('本地模型没有返回有效的日总结');
    }
    return summary;
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
把下面更小时间单位的真实 AI 总结，合并成 ${range.label} 的回忆总结。
重点概括：$target。
只依据提供内容，不增加事实；不要逐条罗列；写成温暖但克制的中文叙述。
${range.period == SummaryPeriod.year ? '建议 220-450 字。' : '建议 120-260 字。'}
不要输出 JSON。只输出一行：
总结：你的总结正文

$material

/no_think
''',
    );
    final summary = parseSingleSummaryOutput(raw);
    if (summary.isEmpty) {
      throw FormatException('本地模型没有返回有效的${range.period.label}总结');
    }
    return GeneratedAiSummary(summaryText: summary);
  }
}

const _systemPrompt = '''
你是“点滴记忆”的本地回忆整理器。所有输入都来自一对伴侣的真实聊天。
你的任务是忠实归纳，不推测身份，不编造地点、关系、情绪或事件。
如果证据不足就少写。严格遵守用户指定的逐行输出格式，不要自行改成 JSON，不要输出思考过程、Markdown 或额外解释。
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
    if (summaryValue != null && summaryValue.isNotEmpty) {
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
    if (title.isEmpty || description.isEmpty || ids.isEmpty) continue;
    events.add(
      GeneratedAiEvent(
        title: title,
        description: description,
        messageIds: ids,
      ),
    );
  }

  summary ??= lines
      .where((line) => _valueAfterLabel(line, const <String>['事件']) == null)
      .cast<String?>()
      .firstWhere((line) => line != null && line.isNotEmpty, orElse: () => null);

  return GeneratedAiSummary(
    summaryText: summary?.trim().isNotEmpty == true
        ? summary!.trim()
        : '这一段主要是日常交流。',
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
    if (value != null && value.isNotEmpty) return value;
  }
  return lines.join(' ').trim();
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

String _modelCacheKey(LocalAiModelInfo model) => '${model.name}|${model.byteSize}';

String _limit(String value, int maxLength) {
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength - 1)}…';
}