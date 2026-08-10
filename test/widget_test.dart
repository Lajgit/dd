import 'package:diandi_memory/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('启动后显示微信档案导入入口和回忆导航', (tester) async {
    await tester.pumpWidget(const DiandiMemoryApp());

    expect(find.text('导入微信聊天档案'), findsOneWidget);
    expect(find.text('选择 ZIP 文件'), findsOneWidget);
    expect(find.text('回忆'), findsOneWidget);
    expect(find.text('AI总结'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
  });

  testWidgets('全局 FilledButton 只限制高度，不强制无限宽度', (tester) async {
    await tester.pumpWidget(const DiandiMemoryApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final minimumSize = app.theme?.filledButtonTheme.style?.minimumSize
        ?.resolve(const <WidgetState>{});

    expect(minimumSize, const Size(0, 50));
  });
}
