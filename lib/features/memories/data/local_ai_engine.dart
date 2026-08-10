import 'package:llama_flutter_android/llama_flutter_android.dart';

class LocalAiEngine {
  LocalAiEngine._();

  static final LocalAiEngine instance = LocalAiEngine._();

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
  }) async {
    await ensureLoaded(modelPath);
    final controller = _controller!;
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
