import 'package:diandi_memory/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('启动后显示微信档案导入入口和回忆导航', (tester) async {
    await tester.pumpWidget(const DiandiMemoryApp());

    expect(find.text('导入微信聊天档案'), findsOneWidget);
    expect(find.text('选择 ZIP 文件'), findsOneWidget);
    expect(find.text('回忆'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
  });
}
