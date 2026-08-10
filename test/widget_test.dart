import 'package:diandi_memory/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('导入入口和主导航保持可用', (tester) async {
    // Widget 测试环境没有 sqflite 平台实现，因此从导入页启动；正式 App 默认从「回忆」页进入。
    await tester.pumpWidget(const DiandiMemoryApp(initialIndex: 2));

    expect(find.text('导入微信聊天档案'), findsOneWidget);
    expect(find.text('选择 ZIP 文件'), findsOneWidget);
    expect(find.text('回忆'), findsOneWidget);
    expect(find.text('总结'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
  });

  testWidgets('全局 FilledButton 只限制高度，不强制无限宽度', (tester) async {
    await tester.pumpWidget(const DiandiMemoryApp(initialIndex: 2));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final minimumSize = app.theme?.filledButtonTheme.style?.minimumSize
        ?.resolve(const <WidgetState>{});

    expect(minimumSize, const Size(0, 50));
  });
}
