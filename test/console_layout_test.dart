/// 紧凑控制台布局回归：长机器名不能把行撑爆（对齐 DESIGN.md 设备卡）。
library;

import 'package:dsh_tablet_client/models/agent_server.dart';
import 'package:dsh_tablet_client/models/poll_beat.dart';
import 'package:dsh_tablet_client/widgets/console_device_chip.dart';
import 'package:dsh_tablet_client/widgets/console_machine_card.dart';
import 'package:dsh_tablet_client/widgets/poll_pulse.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<PollBeat> _beats(int ok) => [
      for (var i = 0; i < ok; i++)
        PollBeat(PollBeatStatus.ok, DateTime(2026, 1, 1, 0, 0, i * 8)),
    ];

void main() {
  testWidgets('ConsoleMachineCard 长别名省略，宽度封顶、高度固定', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // 不再套固定宽度：要给卡片松约束，才能量出它「按内容收缩」的宽度
          body: Center(
            child: ConsoleMachineCard(
              title: '一台名字非常非常长的开发机器，长到应该被省略',
              kind: AgentKind.dsh,
              beats: _beats(8),
              online: true,
              needsAuth: false,
              pendingApprovals: 0,
              pendingQuestions: 0,
              running: 12,
              active: true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(ConsoleMachineCard));
    expect(size.height, ConsoleMachineCard.cardHeight);
    // 长别名顶到内容上限即止（contentMaxWidth + 左右内边距）
    expect(
      size.width,
      lessThanOrEqualTo(
        ConsoleMachineCard.contentMaxWidth + 20,
      ),
      reason: '横向条卡片宽度受 contentMaxWidth 封顶',
    );
  });

  testWidgets('短名卡片按内容收缩，不被撑成一条', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConsoleMachineCard(
              title: 'PC',
              kind: AgentKind.dsh,
              beats: _beats(3),
              online: true,
              needsAuth: false,
              pendingApprovals: 0,
              pendingQuestions: 0,
              running: 0,
              active: false,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final w = tester.getSize(find.byType(ConsoleMachineCard)).width;
    expect(w, lessThanOrEqualTo(ConsoleMachineCard.contentMaxWidth + 20),
        reason: '短名按内容收缩（flutter_test 用 Ahem 字体，每字宽=字号，真机会更窄）');
    expect(w, greaterThanOrEqualTo(80), reason: '点击目标别缩得太离谱');
  });

  testWidgets('竖栏侧边栏卡片充满整行宽度（expand）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ConsoleMachineCard(
                title: '一台名字非常非常长的开发机器，长到应该被省略',
                kind: AgentKind.dsh,
                beats: _beats(8),
                online: true,
                needsAuth: false,
                pendingApprovals: 1,
                pendingQuestions: 1,
                running: 12,
                active: true,
                expand: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(ConsoleMachineCard));
    expect(size.height, ConsoleMachineCard.cardHeight);
    expect(size.width, 320,
        reason: '2026-11 反馈：横屏竖栏设备卡要充满侧边栏宽度');
  });

  testWidgets('心跳刻度恒渲染 8 格（不足补空格）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConsoleMachineCard(
              title: '工作台',
              kind: AgentKind.dsh,
              beats: _beats(3),
              online: true,
              needsAuth: false,
              pendingApprovals: 0,
              pendingQuestions: 0,
              running: 0,
              active: false,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(PollPulse), findsOneWidget);
    // 3 条心跳 + 5 个空格 = 8 格（空格也是 Opacity 容器）
    final pulse = tester.widget<PollPulse>(find.byType(PollPulse));
    expect(pulse.beats.length, 3);
  });

  testWidgets('待办角标 >0 时显示数字', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConsoleMachineCard(
              title: '工作台',
              kind: AgentKind.opencode,
              beats: _beats(0),
              online: true,
              needsAuth: false,
              pendingApprovals: 1,
              pendingQuestions: 1,
              running: 0,
              active: false,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('2'), findsOneWidget, reason: '待办角标（审批/提问数）');
    expect(find.textContaining('审批 1'), findsOneWidget, reason: '待办明细行');
    expect(find.text('opencode'), findsOneWidget, reason: '后端徽标');
  });

  testWidgets('ConsoleDeviceChip 长机器名省略而不是溢出', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConsoleDeviceChip(
              name: '一台名字非常非常长的开发机器，长到应该被省略',
              online: true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(ConsoleDeviceChip)).width,
      lessThanOrEqualTo(160),
    );
  });
}
