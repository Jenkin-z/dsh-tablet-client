/// 设备卡布局契约测试（对齐 DESIGN.md §6 设备卡）
///
/// DESIGN.md：设备卡 = 机器名 + 后端徽标（DSH / opencode）+ 状态点 +
/// 心跳刻度 + 待办角标。心跳刻度是签名动作（§2）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String devices;
  late String card;
  late String pulse;

  setUpAll(() {
    devices = File('lib/widgets/console_devices.dart').readAsStringSync();
    card = File('lib/widgets/console_machine_card.dart').readAsStringSync();
    pulse = File('lib/widgets/poll_pulse.dart').readAsStringSync();
  });

  group('地址不带端口', () {
    test('ConsoleDevices 主标题不拼 :port', () {
      // 主标题是别名（opencode 隧道条目显示 host 会像一串 id），
      // 地址只作为兜底文案。
      final start = devices.indexOf('ConsoleMachineCard(');
      expect(start >= 0, isTrue);
      final call = devices.substring(start);
      expect(call.contains('server.port'), isFalse, reason: '设备行不该再拼端口');
      expect(devices.contains('group.server.host'), isTrue,
          reason: '别名缺失时要退回地址');
    });
  });

  group('设备卡构成（DESIGN.md §6）', () {
    test('卡片类在独立文件，带心跳刻度与后端徽标', () {
      expect(card.contains('class ConsoleMachineCard'), isTrue);
      expect(card.contains('PollPulse'), isTrue,
          reason: '心跳刻度是签名动作，设备卡必须携带');
      expect(card.contains('AgentKind'), isTrue,
          reason: '后端徽标（DSH / opencode）');
      expect(card.contains('pendingApprovals'), isTrue,
          reason: '待办角标（审批/提问数）');
      expect(card.contains('IosStatusDot'), isTrue,
          reason: '状态点表达机器在线语义');
    });

    test('心跳刻度固定 8 格，与 8 秒轮询对齐', () {
      expect(pulse.contains('PollBeat.capacity'), isTrue);
      expect(pulse.contains('PollBeatStatus.missed'), isTrue,
          reason: '红=missed');
      expect(pulse.contains('PollBeatStatus.warn'), isTrue,
          reason: '橙=数据异常');
    });

    test('机器条横向滚动，卡片高度固定（心跳行需要空间）', () {
      expect(devices.contains('scrollDirection: Axis.horizontal'), isTrue);
      expect(card.contains('static const double cardHeight'), isTrue,
          reason: '设备卡高度固定，避免内容抖动');
    });

    test('卡片宽度只封顶不设下限，短名不撑长', () {
      expect(card.contains('contentMaxWidth'), isTrue,
          reason: '内容宽度用常量封顶');
      expect(card.contains('minWidth: 132'), isFalse,
          reason: '旧版 minWidth 132 会把短名也撑长（回归防线）');
    });

    test('第一行是别名，空名退回地址', () {
      expect(card.contains('this.title'), isTrue);
      expect(card.contains('this.subtitle'), isTrue);
      expect(devices.contains('final name = group.server.name'), isTrue);
      expect(devices.contains("host.isNotEmpty ? host : 'PC'"), isTrue,
          reason: '防御旧数据：空名退回地址');
    });
  });
}
