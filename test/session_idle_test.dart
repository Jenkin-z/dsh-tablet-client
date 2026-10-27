/// 会话空闲启发式测试（与后端无关）
///
/// 锁定「只清 busy 不设 busy」的方向性：只有尾部 assistant 定稿才判空闲，
/// user 收尾 / 流式中 / 乐观中一律不算 —— 绝不能把真在跑的会话误伤。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/models/message.dart';
import 'package:dsh_tablet_client/services/session_idle.dart';

ChatMessage msg(String role, {bool streaming = false, bool pending = false}) =>
    ChatMessage(id: 'm-${role}-${streaming ? 's' : 'd'}', role: role,
        content: 'x', isStreaming: streaming, pending: pending);

void main() {
  test('空消息流不算空闲', () {
    expect(isSessionActuallyIdle(const []), isFalse);
  });

  test('最后一条是 user（等回复中）不算空闲', () {
    expect(isSessionActuallyIdle([msg('assistant'), msg('user')]), isFalse);
  });

  test('assistant 仍在流式不算空闲', () {
    expect(isSessionActuallyIdle([msg('user'), msg('assistant', streaming: true)]),
        isFalse);
  });

  test('assistant 乐观中不算空闲', () {
    expect(isSessionActuallyIdle([msg('user'), msg('assistant', pending: true)]),
        isFalse);
  });

  test('assistant 已定稿 = 空闲（stale busy 可清除）', () {
    expect(isSessionActuallyIdle([msg('user'), msg('assistant')]), isTrue);
  });

  test('system 收尾不算空闲（保守）', () {
    expect(isSessionActuallyIdle([msg('user'), msg('system')]), isFalse);
  });
}
