import 'package:flutter/services.dart';

import '../model/ai_summary_models.dart';

class BundledLocalAiModel {
  const BundledLocalAiModel();

  static const _channel = MethodChannel(
    'com.lajgit.diandi_memory/local_ai_assets',
  );

  static const assetPath = 'models/qwen3-0.6b-q4_k_m-b0638f08.gguf';
  static const fileName = 'qwen3-0.6b-q4_k_m-b0638f08.gguf';
  static const displayName = 'Qwen3-0.6B-Q4_K_M';
  static const sha256 =
      'b0638f08417a2d3c8652760462eb5407c6e30173cf9608ad0820757a281eea0e';

  Future<LocalAiModelInfo> ensureAvailable() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'ensureBundledModel',
      const <String, Object?>{
        'assetPath': assetPath,
        'targetFileName': fileName,
        'expectedSha256': sha256,
      },
    );
    final modelPath = result?['path'] as String?;
    final byteSize = result?['byteSize'] as int?;
    if (modelPath == null || modelPath.isEmpty || byteSize == null) {
      throw PlatformException(
        code: 'bundled_model_missing',
        message: '内置 GGUF 模型没有正确安装到 App 私有目录',
      );
    }
    return LocalAiModelInfo(
      path: modelPath,
      name: displayName,
      byteSize: byteSize,
      isBundled: true,
    );
  }
}
