/// 会话可见性回归测试
///
/// 用户报告：「对话列表里有一些不是我创建的 DSH 自动生成的对话」。
/// 那些是任务执行过程中自动拉起的**子 Agent 会话**。
///
/// Web 端的过滤规则（`ui-workspace/src/client/tree.ts` 的 `sessionVisible()`）：
/// ```ts
/// session.origin !== 'subagent'
///   && !archived.has(session.id)
///   && (!session.blank || session.id === current)
/// ```
/// App 端此前只实现了 blank 一项，`origin` 从未使用，所以子 Agent 泄漏进列表。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/utils/session_format.dart';

Map<String, dynamic> _s(
  String id, {
  String? origin,
  bool blank = false,
  bool running = false,
  String? parent,
}) =>
    {
      'sessionId': id,
      'updatedAt': 1000,
      if (origin != null) 'origin': origin,
      if (parent != null) 'parentSessionId': parent,
      'blank': blank,
      'running': running,
    };

void main() {
  group('isUserFacingSession：子 Agent 会话必须被隐藏', () {
    test('origin == subagent 的会话不可见', () {
      expect(isUserFacingSession(_s('sub-1', origin: 'subagent')), isFalse);
      expect(isSubagentSession(_s('sub-1', origin: 'subagent')), isTrue);
    });

    test('子 Agent 即使带 parentSessionId 也照样隐藏', () {
      final child = _s('sub-2', origin: 'subagent', parent: 'root-1');
      expect(isUserFacingSession(child), isFalse);
    });

    test('子 Agent 即使正在运行也不显示', () {
      // 用户不该看到「某个子 Agent 在跑」，那是父会话的内部进展
      expect(
        isUserFacingSession(_s('sub-3', origin: 'subagent', running: true)),
        isFalse,
      );
    });

    test('普通用户会话可见', () {
      expect(isUserFacingSession(_s('root-1')), isTrue);
      expect(isUserFacingSession(_s('root-2', running: true)), isTrue);
    });

    test('origin 缺失按普通会话处理（向后兼容旧服务端）', () {
      expect(isUserFacingSession(_s('legacy')), isTrue);
    });

    test('其它 origin 值不误伤', () {
      expect(isUserFacingSession(_s('x', origin: 'user')), isTrue);
    });
  });

  group('isUserFacingSession：空会话只保留当前那一个', () {
    test('非当前的空会话隐藏（否则列表堆满「新会话」）', () {
      expect(isUserFacingSession(_s('blank-1', blank: true)), isFalse);
      expect(
        isUserFacingSession(_s('blank-1', blank: true),
            currentSessionId: 'other'),
        isFalse,
      );
    });

    test('当前的空会话保留（它是「新建对话」的落点）', () {
      expect(
        isUserFacingSession(_s('blank-1', blank: true),
            currentSessionId: 'blank-1'),
        isTrue,
      );
    });

    test('子 Agent 优先于 blank：即使它是当前会话也不显示', () {
      expect(
        isUserFacingSession(_s('sub-9', origin: 'subagent', blank: true),
            currentSessionId: 'sub-9'),
        isFalse,
      );
    });
  });

  group('过滤发生在数据入口，而不是只在 UI 挡', () {
    test('SessionMonitor 在计数/通知前剔除子 Agent', () {
      final src = File('lib/services/session_monitor.dart').readAsStringSync();
      expect(src.contains('isUserFacingSession'), isTrue,
          reason: '必须过滤，否则子 Agent 跑完会弹「会话已完成」通知');
      // 过滤必须出现在 refresh() 里、且用于 sessions 赋值
      expect(src.contains('sessions = items'), isTrue);
      final idx = src.indexOf('Future<void> refresh()');
      expect(idx >= 0, isTrue);
      final body = src.substring(idx, (idx + 1800).clamp(0, src.length));
      expect(body.contains('isUserFacingSession'), isTrue,
          reason: 'refresh() 内部必须过滤');
      expect(body.contains('_markFinished'), isTrue,
          reason: '通知在 refresh() 里触发，过滤必须早于它');
    });

    test('ChatController 的会话列表同样过滤', () {
      final src = File('lib/services/chat_controller.dart').readAsStringSync();
      expect(src.contains('isUserFacingSession'), isTrue,
          reason: '对话页侧栏用 state.sessions，不过滤会漏出子 Agent');
    });
  });
}
