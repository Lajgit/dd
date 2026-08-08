import 'package:diandi_memory/features/import/data/wechat_archive_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const normalizer = WechatMessageNormalizer();

  test('优先使用 sessionId 和 serverId 生成稳定消息键', () {
    final key = normalizer.sourceMessageKey(<String, dynamic>{
      'sessionId': 'wxid_contact',
      'serverId': '123456789',
      'localId': 42,
    });

    expect(key, 'wechat:wxid_contact:server:123456789');
  });

  test('没有 serverId 时回退到 localId', () {
    final key = normalizer.sourceMessageKey(<String, dynamic>{
      'sessionId': 'wxid_contact',
      'localId': 42,
    });

    expect(key, 'wechat:wxid_contact:local:42');
  });

  test('哈希回退不受头像 Base64 字段变化影响', () {
    final first = normalizer.sourceMessageKey(<String, dynamic>{
      'sessionId': 'wxid_contact',
      'createTime': 1735630867,
      'senderId': 'wxid_sender',
      'type': '系统消息',
      'content': '测试',
      'img': 'data:image/jpeg;base64,AAAA',
      'exportAvatarUrl': 'data:image/jpeg;base64,BBBB',
    });
    final second = normalizer.sourceMessageKey(<String, dynamic>{
      'sessionId': 'wxid_contact',
      'createTime': 1735630867,
      'senderId': 'wxid_sender',
      'type': '系统消息',
      'content': '测试',
      'img': 'data:image/jpeg;base64,CCCC',
      'exportAvatarUrl': 'data:image/jpeg;base64,DDDD',
    });

    expect(first, second);
    expect(first, startsWith('wechat:wxid_contact:hash:'));
  });
}
