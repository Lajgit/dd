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
    return buffer.toString().trim();
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
