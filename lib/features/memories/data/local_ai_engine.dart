import 'dart:convert';

import 'package:llama_flutter_android/llama_flutter_android.dart';

import '../../../core/async/serial_task_queue.dart';

class LocalAiEngine {
  LocalAiEngine._();

  static final LocalAiEngine instance = LocalAiEngine._();

  final SerialTaskQueue _generationQueue = SerialTaskQueue();
  LlamaController? _controller;
  String? _loadedModelPath;

  Future<void> ensureLoaded(String modelPath) async {
    final existing = _controller;
    if (_loadedModelPath == modelPath && existing != null) {
      if (await existing.isModelLoaded()) return;
    }

    await dispose();
    final controller = LlamaController();
    var gpuLayers = 0;
    try {
      final gpu = await controller.detectGpu();
      gpuLayers = gpu.recommendedGpuLayers;
    } catch (_) {
      // GPU 探测失败时回退 CPU，不能因为设备 Vulkan 差异阻断本地总结。
      gpuLayers = 0;
    }

    await controller.loadModel(
      modelPath: modelPath,
      threads: 4,
      contextSize: 4096,
      gpuLayers: gpuLayers,
    );
    _controller = controller;
    _loadedModelPath = modelPath;
  }

  Future<String> complete({
    required String modelPath,
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 700,
  }) {
    // llama.cpp 同一个 controller 同时只能有一个生成任务；统一排队，避免页面重建、
    // 批量总结或前一次任务尚未完全收尾时触发 "Already generating"。
    return _generationQueue.run(
      () => _completeOnce(
        modelPath: modelPath,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        maxTokens: maxTokens,
      ),
    );
  }

  Future<String> _completeOnce({
    required String modelPath,
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) async {
    await ensureLoaded(modelPath);
    final controller = _controller!;
    await _recoverIdleController(controller);
    await controller.clearContext();

    final buffer = StringBuffer();
    await for (final token in controller.generateChat(
      messages: <ChatMessage>[
        ChatMessage(role: 'system', content: systemPrompt),
        ChatMessage(role: 'user', content: userPrompt),
      ],
      template: 'chatml',
      maxTokens: maxTokens,
      temperature: 0.2,
      topP: 0.85,
      topK: 30,
      repeatPenalty: 1.08,
    )) {
      buffer.write(token);
    }

    // 0.6B 级小模型偶尔会在正确 JSON 后多输出一个 ]/}，或留下尾随逗号。
    // 这里仅修复结构性噪声，不改写 summary/events 的语义内容。
    return normalizeLocalAiJsonOutput(buffer.toString());
  }

  Future<void> _recoverIdleController(LlamaController controller) async {
    if (!controller.isGenerating) return;

    // 正常串行路径不会走到这里；如果 native/Dart 上一次生成状态仍残留，先等待
    // 一个很短的收尾窗口，再通过插件 stop() 恢复为可生成状态，而不是直接失败。
    for (var attempt = 0; attempt < 10 && controller.isGenerating; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!controller.isGenerating) return;

    await controller.stop();
    if (controller.isGenerating) {
      throw StateError('本地 AI 上一次生成任务尚未结束，请稍后重试');
    }
  }

  Future<void> stop() async {
    await _controller?.stop();
  }

  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    _loadedModelPath = null;
    await controller?.dispose();
  }
}

String normalizeLocalAiJsonOutput(String raw) {
  final cleaned = raw
      .replaceAll(
        RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '')
      .trim();
  final start = cleaned.indexOf('{');
  if (start < 0) return cleaned;

  final balanced = _firstBalancedJsonObject(cleaned, start);
  final lastBrace = cleaned.lastIndexOf('}');
  final candidates = <String>{
    if (balanced != null) balanced,
    if (lastBrace > start) cleaned.substring(start, lastBrace + 1),
  };

  for (final candidate in candidates) {
    final normalized = _removeTrailingJsonCommas(candidate);
    if (_isJsonObject(normalized)) return normalized;

    final repaired = _removeTrailingJsonCommas(
      _repairJsonDelimiters(normalized),
    );
    if (_isJsonObject(repaired)) return repaired;
  }

  return cleaned;
}

String? _firstBalancedJsonObject(String text, int start) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = start; index < text.length; index += 1) {
    final char = text[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }

    if (char == '"') {
      inString = true;
    } else if (char == '{') {
      depth += 1;
    } else if (char == '}') {
      depth -= 1;
      if (depth == 0) return text.substring(start, index + 1);
      if (depth < 0) return null;
    }
  }
  return null;
}

String _removeTrailingJsonCommas(String value) {
  return value.replaceAllMapped(
    RegExp(r',\s*([}\]])'),
    (match) => match.group(1)!,
  );
}

String _repairJsonDelimiters(String value) {
  final output = StringBuffer();
  final stack = <String>[];
  var inString = false;
  var escaped = false;

  for (var index = 0; index < value.length; index += 1) {
    final char = value[index];
    if (inString) {
      output.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }

    if (char == '"') {
      inString = true;
      output.write(char);
      continue;
    }
    if (char == '{' || char == '[') {
      stack.add(char);
      output.write(char);
      continue;
    }
    if (char == '}' || char == ']') {
      final expected = char == '}' ? '{' : '[';
      if (stack.isNotEmpty && stack.last == expected) {
        stack.removeLast();
        output.write(char);
      }
      continue;
    }
    output.write(char);
  }

  while (stack.isNotEmpty) {
    output.write(stack.removeLast() == '{' ? '}' : ']');
  }
  return output.toString();
}

bool _isJsonObject(String value) {
  try {
    return jsonDecode(value) is Map;
  } catch (_) {
    return false;
  }
}
