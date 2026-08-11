import 'package:diandi_memory/features/memories/data/bundled_local_ai_model.dart';
import 'package:diandi_memory/features/memories/model/ai_summary_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('内置默认模型固定为 Qwen3 4B Q5 GGUF 和 SHA-256', () {
    expect(BundledLocalAiModel.fileName, 'qwen3-4b-q5_k_m-aca59686.gguf');
    expect(BundledLocalAiModel.assetPath, contains(BundledLocalAiModel.fileName));
    expect(BundledLocalAiModel.displayName, 'Qwen3-4B-Q5_K_M');
    expect(
      BundledLocalAiModel.sha256,
      'aca596860e8cb40af6539e3f2ea40df305f42515deac56d49c08d39a02e6533f',
    );
  });

  test('LocalAiModelInfo 可区分内置与自定义模型', () {
    const bundled = LocalAiModelInfo(
      path: '/models/bundled.gguf',
      name: 'bundled',
      byteSize: 1,
      isBundled: true,
    );
    const custom = LocalAiModelInfo(
      path: '/models/custom.gguf',
      name: 'custom',
      byteSize: 1,
    );

    expect(bundled.isBundled, isTrue);
    expect(custom.isBundled, isFalse);
  });
}
