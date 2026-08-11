import 'package:flutter/services.dart';

import '../model/ai_summary_models.dart';

class BundledLocalAiModel {
  const BundledLocalAiModel();

  static const _channel = MethodChannel(
    'com.lajgit.diandi_memory/local_ai_assets',
  );

  static const assetPath = 'models/qwen3-4b-q5_k_m-aca59686.gguf';
  static const fileName = 'qwen3-4b-q5_k_m-aca59686.gguf';
  static const displayName = 'Qwen3-4B-Q5_K_M';
  static const sha256 =
      'aca596860e8cb40af6539e3f2ea40df305f42515deac56d49c08d39a02e6533f';

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
