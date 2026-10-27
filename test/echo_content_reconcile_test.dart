/// 乐观回显「内容兜底对账」回归测试（与后端无关，opencode 是主要受益者）
///
/// 锁定 ghosting bug：连发两条消息时，durable 消息不带 rpcId，
/// 按内容只能对账**最老一条**本地回显 —— 不能把第二条还没回显的
/// 乐观气泡一并吞掉，也不能在列表尾部多出重复气泡。
library;

import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:dsh_tablet_client/models/message.dart';
import 'package:dsh_tablet_client/services/event_dispatcher.dart';
import 'package:dsh_tablet_client/services/session_state.dart';

void main() {
  late SessionState state;
  late EventDispatcher dispatcher;

  setUp(() {
    state = SessionState();
    dispatcher = EventDispatcher(state: state);
    state.setSessionId('s1');
  });

  tearDown(() {
    dispatcher.dispose();
    state.dispose();
  });

  group('内容兜底对账（无 rpcId 的 durable 回显）', () {
    test('单条：durable 到达时把乐观气泡就地转正，不多不少', () {
      dispatcher.addLocalUserMessage('修一下登录页', 'r1');
      dispatcher.confirmLocalUserMessage('r1');

      dispatcher.onUserMessage('修一下登录页', null, '1', 'srv-1');

      final users = dispatcher.messages.where((m) => m.role == 'user').toList();
      expect(users.length, 1, reason: '本地气泡应被对账掉，不新增重复');
      expect(users.single.content, '修一下登录页');
      expect(users.single.pending, isFalse);
    });

    test('连发两条：先到的 durable 只对账最老一条', () {
      dispatcher.addLocalUserMessage('第一条', 'r1');
      dispatcher.confirmLocalUserMessage('r1');
      dispatcher.addLocalUserMessage('第二条', 'r2');
      dispatcher.confirmLocalUserMessage('r2');

      // 服务端按序回显，第一条先到
      dispatcher.onUserMessage('第一条', null, '1', 'srv-1');

      var users = dispatcher.messages.where((m) => m.role == 'user').toList();
      expect(users.length, 2, reason: '第一条被对账、第二条乐观气泡必须保留');
      expect(users[0].content, '第一条');
      expect(users[1].content, '第二条');

      dispatcher.onUserMessage('第二条', null, '2', 'srv-2');
      users = dispatcher.messages.where((m) => m.role == 'user').toList();
      expect(users.length, 2, reason: '第二条 durable 到达同样只对账自己那条');
      expect(users.map((m) => m.content).toList(), ['第一条', '第二条']);
    });

    test('对账后的气泡带 durable id，重复回显被 messageId 去重挡住', () {
      dispatcher.addLocalUserMessage('同一句', 'r1');
      dispatcher.onUserMessage('同一句', null, '1', 'srv-1');
      // 同一 durable 消息的 replacement 副本
      dispatcher.onUserMessage('同一句', null, '2', 'srv-1');

      final users = dispatcher.messages.where((m) => m.role == 'user').toList();
      expect(users.length, 1);
    });

    test('历史装载：已落库的回显不再补回，未落库的保留乐观态', () {
      dispatcher.addLocalUserMessage('已落库', 'r1');
      dispatcher.confirmLocalUserMessage('r1');
      dispatcher.addLocalUserMessage('未落库', 'r2');

      dispatcher.onHistoryLoaded(const []);

      // 快照里没有任何消息时，两条都要补回
      var users = dispatcher.messages.where((m) => m.role == 'user').toList();
      expect(users.length, 2);
      expect(users[0].pending, isFalse, reason: '已确认的回显不再显示 pending 态');
      expect(users[1].pending, isTrue);

      // 快照里已出现同内容 durable 消息：只补回未落库那条
      dispatcher.onHistoryLoaded([
        ChatMessage(id: 'srv-a', role: 'user', content: '已落库'),
      ]);
      users = dispatcher.messages.where((m) => m.role == 'user').toList();
      expect(users.map((m) => m.content).toList(), ['已落库', '未落库'],
          reason: '已落库的回显不能重复补回');
    });
  });
}
