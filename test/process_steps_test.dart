/// 过程步骤卡（当前轮执行过程）回归测试
///
/// 锁死的语义：
/// - 工具调用前的过程文本固化为 text 条目，不再凭空消失（对齐 Web 端过程区）；
/// - 工具条目 running → done/failed 随 tool/result 收尾；
/// - turn/end 收起、新一轮开始清空；turn 进行中的排队用户消息不清；
/// - turn 收尾后迟到的 tool 事件（重连重放）不进条目。
library;

import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:dsh_tablet_client/models/message.dart';
import 'package:dsh_tablet_client/models/process_step.dart';
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

  Future<void> flush() =>
      Future<void>.delayed(const Duration(milliseconds: 250));

  test('流式文本（含未 flush 尾巴）在工具调用时固化，工具条目 running', () async {
    dispatcher.onTurnStart();
    dispatcher.onTextDelta('先看一下文件');
    // 不等 flush，直接来工具调用：缓冲里的尾巴固化为文本条目
    dispatcher.onToolCall('read', '{"file_path":"/a/b.txt"}');
    await flush();

    expect(dispatcher.processEntries, hasLength(2));
    expect(dispatcher.processEntries.first.text, '先看一下文件');
    expect(dispatcher.processEntries.last.kind, ProcessEntryKind.tool);
    expect(dispatcher.processEntries.last.toolName, 'read');
    expect(dispatcher.processEntries.last.toolDetail, '/a/b.txt');
    expect(dispatcher.processEntries.last.isRunning, isTrue);
    // 气泡被撤掉，只剩哨兵
    expect(dispatcher.messages.map((m) => m.role), ['steps']);
  });

  test('tool/result 收尾最后一个 running 条目（成功/失败）', () {
    dispatcher.onTurnStart();
    dispatcher.onToolCall('read');
    dispatcher.onToolResult(false);
    expect(dispatcher.processEntries.single.status, ProcessEntryStatus.done);

    dispatcher.onToolCall('edit', '{"path":"x"}');
    expect(
        dispatcher.processEntries.last.status, ProcessEntryStatus.running);
    dispatcher.onToolResult(true);
    expect(dispatcher.processEntries.last.status, ProcessEntryStatus.failed);
  });

  test('turn/end 收起；新一轮开始（turn/start）清空', () {
    dispatcher.onTurnStart();
    dispatcher.onToolCall('bash', '{"command":"ls"}');
    dispatcher.onToolResult(false);
    dispatcher.onTurnEnd();

    expect(dispatcher.processCollapsed, isTrue);
    expect(dispatcher.processEntries, hasLength(1));

    dispatcher.onTurnStart();
    expect(dispatcher.processEntries, isEmpty);
    expect(dispatcher.processCollapsed, isFalse);
    // 哨兵随条目清空退场
    expect(dispatcher.messages.where((m) => m.role == 'steps'), isEmpty);
  });

  test('用户消息开启新一轮时清空上一轮步骤；排队消息（进行中）不清', () {
    dispatcher.onTurnStart();
    dispatcher.onToolCall('bash');
    dispatcher.onToolResult(false);
    dispatcher.onTurnEnd();

    // 上一轮已收尾：新用户消息清空
    dispatcher.onUserMessage('下一题', null, '10', 'm10');
    expect(dispatcher.processEntries, isEmpty);

    // 本轮进行中：排队消息不清
    dispatcher.onToolCall('read');
    dispatcher.onUserMessage('排队消息', null, '11', 'm11');
    expect(dispatcher.processEntries, hasLength(1));
  });

  test('turn 收尾后迟到的 tool 事件（重连重放）不进条目', () {
    dispatcher.onTurnStart();
    dispatcher.onToolCall('bash');
    dispatcher.onToolResult(false);
    dispatcher.onTurnEnd();

    dispatcher.onToolCall('late-tool');
    dispatcher.onToolResult(true);

    expect(dispatcher.processEntries, hasLength(1));
    expect(dispatcher.processEntries.single.toolName, 'bash');
  });

  test('历史装载清空过程条目（旧轮次不回填）', () {
    dispatcher.onTurnStart();
    dispatcher.onToolCall('bash');
    dispatcher.onTurnEnd();
    expect(dispatcher.processEntries, isNotEmpty);

    dispatcher.onHistoryLoaded([
      ChatMessage(id: 'u1', role: 'user', content: '你好'),
      ChatMessage(id: 'a1', role: 'assistant', content: '回答'),
    ]);

    expect(dispatcher.processEntries, isEmpty);
    expect(dispatcher.processCollapsed, isFalse);
    expect(dispatcher.messages.where((m) => m.role == 'steps'), isEmpty);
  });

  test('纯文本流式被后续步骤固化（流式气泡未定稿就来了工具调用）', () async {
    dispatcher.onTurnStart();
    dispatcher.onTextDelta('我来检查一下配置');
    await flush();
    dispatcher.onToolCall('read', '{"file_path":"cfg.yaml"}');

    expect(dispatcher.processEntries, hasLength(2));
    expect(dispatcher.processEntries.first.text, '我来检查一下配置');
    expect(dispatcher.processEntries.last.toolName, 'read');
    // 气泡被撤掉，流里只剩哨兵；后续增量会重新建气泡
    final roles = dispatcher.messages.map((m) => m.role).toList();
    expect(roles, ['steps']);
  });
}
