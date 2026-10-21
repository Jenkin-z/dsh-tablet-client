/// 双后端切换无残留回归测试（源码守卫）
///
/// 锁死的语义：
/// - 换 PC/换后端 = 重建 ChatController：必须先清状态中枢（SessionState）
///   与事件入口（EventDispatcher）、 dispose 旧 backend，否则控制台/
///   侧栏会读到上一台的残留（会话、未读、审批）；
/// - 后端按 AgentServer.kind 分派：DSH 与 opencode 是同级的
///   AgentBackend 实现，页面逻辑不走 if(kind) 分支。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_reader.dart';

void main() {
  late String src;

  setUpAll(() {
    src = readSourceWithParts('lib/services/chat_controller.dart');
  });

  group('boot 换后端前清残留', () {
    test('reset 状态中枢 + 事件入口 + dispose 旧 backend', () {
      final idx = src.indexOf('Future<void> boot()');
      expect(idx >= 0, isTrue, reason: '找不到 boot()');
      final body = src.substring(idx, (idx + 600).clamp(0, src.length));
      expect(body.contains('dispatcher.reset()'), isTrue,
          reason: '不清事件入口，上一台的审批/声音钩子会串台');
      expect(body.contains('state.reset()'), isTrue,
          reason: '不清状态中枢，控制台读到上一台的会话与未读');
      // dispose 旧 backend 在 open 之前（连接段）
      final openIdx = src.indexOf('_backend!.open(');
      expect(openIdx >= 0, isTrue);
      final window = src.substring(idx, openIdx);
      expect(window.contains('_backend?.dispose()'), isTrue,
          reason: '不 dispose 旧 backend，旧 SSE/轮询定时器泄漏');
    });
  });

  group('按 kind 分派后端', () {
    test('DSH / opencode 各走各的 AgentBackend 实现', () {
      expect(src.contains('AgentKind.dsh => DshBackend(ctx)'), isTrue);
      expect(src.contains('AgentKind.opencode => OpenCodeBackend(ctx)'), isTrue);
    });

    test('提问应答只转给 DshBackend（opencode 表单 v1 不在范围）', () {
      expect(src.contains('_backend is DshBackend ? _backend as DshBackend : null'),
          isTrue);
    });
  });

  group('opencode 连接态接线守卫', () {
    late String wiringSrc;
    late String backendSrc;

    setUpAll(() {
      wiringSrc =
          File('lib/services/opencode_stream_wiring.dart').readAsStringSync();
      backendSrc = File('lib/services/opencode_backend.dart').readAsStringSync();
    });

    test('Wiring.attach 必须接上 onConnected/onDisconnected/onError', () {
      final idx = wiringSrc.indexOf('void attach(');
      expect(idx >= 0, isTrue);
      final body = wiringSrc.substring(idx);
      expect(body.contains('stream.onConnected'), isTrue,
          reason: '不接 onConnected，connected 永远 false（线上 bug）');
      expect(body.contains('stream.onDisconnected'), isTrue);
      expect(body.contains('stream.onError'), isTrue);
    });

    test('backend 连上时落连接态并做全量对账', () {
      expect(backendSrc.contains('setConnected(true)'), isTrue,
          reason: 'opencode 全链路没有任何 setConnected(true) 就是永远连不上');
      expect(backendSrc.contains('reconcileAll()'), isTrue,
          reason: '连上后必须全量对账兜漏事件');
    });
  });
}
