import 'package:diandi_memory/features/memories/data/bundled_local_ai_model.dart';
import 'package:diandi_memory/features/memories/model/ai_summary_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('内置轻量模型使用固定 GGUF 文件和 SHA-256', () {
    expect(BundledLocalAiModel.fileName, endsWith('.gguf'));
    expect(BundledLocalAiModel.assetPath, contains(BundledLocalAiModel.fileName));
    expect(BundledLocalAiModel.sha256, hasLength(64));
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
