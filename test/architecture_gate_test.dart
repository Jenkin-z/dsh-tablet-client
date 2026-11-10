/// 架构门禁测试（对标 dsh-go 的 architecture conformance gate）
///
/// 静态扫描 lib/ 源码，防止架构回退：
/// 1. 轮次状态写入口唯一：setAgentRunning / setAssistantStreaming /
///    setActiveTool 这些旧 setter 已删除，任何地方不得再出现；
/// 2. SessionState.applyTurnState 只能被 TurnSupervisor 调用
///    （存储侧 CAS 闸门不是公共写接口）；
/// 3. 队列视图写入口唯一：replaceQueue 只在 session_state_queue.dart 声明、
///    event_queue.dart 调用；
/// 4. UI 层禁止直接 import 后端实现（页面只跟 ChatController 对话）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<File> dartFiles;
  late Map<String, String> sources;

  setUpAll(() {
    dartFiles = _dartFilesOf('lib');
    sources = {
      for (final f in dartFiles)
        _posix(f.path): f.readAsStringSync(),
    };
  });

  test('旧运行态 setter 已删除：任何 lib/ 源码不得再调用', () {
    final banned = ['setAgentRunning(', 'setAssistantStreaming(', 'setActiveTool('];
    for (final name in banned) {
      final offenders = sources.entries
          .where((e) => e.value.contains(name))
          .map((e) => e.key)
          .toList();
      expect(offenders, isEmpty,
          reason: '$name 已收敛进 TurnSupervisor（唯一写入口），'
              '发现调用说明有绕层写入：$offenders');
    }
  });

  test('applyTurnState 只出现在 supervisor 与 session_state（存储闸门不是公共接口）', () {
    final whitelist = {
      _posix('lib/services/turn_supervisor.dart'),
      _posix('lib/services/session_state.dart'),
    };
    final offenders = sources.entries
        .where((e) => e.value.contains('applyTurnState('))
        .map((e) => e.key)
        .where((p) => !whitelist.contains(p))
        .toList();
    expect(offenders, isEmpty, reason: '绕过 supervisor 直写轮次状态：$offenders');
  });

  test('replaceQueue 只在队列分片调用（队列写入口唯一）', () {
    final whitelist = {
      _posix('lib/services/session_state_queue.dart'),
      _posix('lib/services/event_queue.dart'),
    };
    final offenders = sources.entries
        .where((e) => e.value.contains('replaceQueue('))
        .map((e) => e.key)
        .where((p) => !whitelist.contains(p))
        .toList();
    expect(offenders, isEmpty, reason: '队列视图只能经 event_queue 分片更新：$offenders');
  });

  test('screens/ 禁止 import API/backend 实现（页面只跟 ChatController 门面对话）', () {
    // 配对引导页（pair/qr_scan）与设置页的免连接操作（backend_ops，
    // 见 commit d6b7e74 的收口）是门面级依赖；业务 API 与后端装配
    // 一律不得进页面。
    final offenders = <String>[];
    final re = RegExp(
      r"""import\s+['"][^'"]*services/(dsh/(dsh_api|model_service|mux_)|opencode/opencode_(api|stream|reconciler|mapper)|(dsh_backend|opencode_backend))""",
    );
    sources.forEach((path, src) {
      if (!path.startsWith(_posix('lib/screens/'))) return;
      if (re.hasMatch(src)) offenders.add(path);
    });
    expect(offenders, isEmpty, reason: '页面绕过门面直连后端实现：$offenders');
  });
}

List<File> _dartFilesOf(String root) {
  final dir = Directory(root);
  final out = <File>[];
  final stack = <Directory>[dir];
  while (stack.isNotEmpty) {
    final d = stack.removeAt(0);
    for (final e in d.listSync()) {
      if (e is Directory) {
        stack.add(e);
      } else if (e is File && e.path.endsWith('.dart')) {
        out.add(e);
      }
    }
  }
  return out;
}

/// 统一成 / 分隔路径，测试在 Windows 上也不受 \ / 混用影响
String _posix(String p) => p.replaceAll('\\', '/');
