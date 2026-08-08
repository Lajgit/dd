import 'package:diandi_memory/features/import/data/messages_js_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = MessagesJsParser();

  test('解析 WechatExplorer messages.js', () {
    const source = '''
window.__WECHAT_EXPORT__ = {"version":2,"name":"梨宝","messages":[{"localId":1,"type":"普通文本","content":"你好"}]};
''';

    final archive = parser.parse(source);

    expect(archive.version, 2);
    expect(archive.name, '梨宝');
    expect(archive.messages, hasLength(1));
    expect(archive.messages.single['content'], '你好');
  });

  test('没有 name 时使用唯一会话名称', () {
    const source = '''
window.__WECHAT_EXPORT__ = {"version":2,"conversations":[{"name":"测试会话"}],"messages":[]};
''';

    final archive = parser.parse(source);

    expect(archive.name, '测试会话');
  });

  test('缺少 messages 数组时拒绝导入', () {
    const source = 'window.__WECHAT_EXPORT__ = {"version":2};';

    expect(
      () => parser.parse(source),
      throwsA(isA<FormatException>()),
    );
  });
}
