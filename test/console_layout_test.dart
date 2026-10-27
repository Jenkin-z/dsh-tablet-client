/// 紧凑控制台布局回归：长机器名不能把行撑爆。
library;

import 'package:dsh_tablet_client/widgets/console_device_chip.dart';
import 'package:dsh_tablet_client/widgets/console_machine_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ConsoleMachineCard 长别名省略，宽度封顶、高度固定 62', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // 不再套固定宽度：要给卡片松约束，才能量出它「按内容收缩」的宽度
          body: Center(
            child: ConsoleMachineCard(
              title: '一台名字非常非常长的开发机器，长到应该被省略',
              subtitle: 'a.local',
              online: true,
              needsAuth: false,
              running: 12,
              unviewed: 34,
              active: true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(ConsoleMachineCard));
    expect(size.height, ConsoleMachineCard.cardHeight);
    // 长别名顶到内容上限即止：8+26+6+132+8 = 180，不再像旧版可到 274
    expect(
      size.width,
      lessThanOrEqualTo(180),
      reason: '横向条卡片宽度受 contentMaxWidth 封顶',
    );
  });

  testWidgets('短名卡片按内容收缩，不被撑成一条', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConsoleMachineCard(
              title: 'PC',
              subtitle: 'a.local',
              online: true,
              needsAuth: false,
              running: 0,
              unviewed: 0,
              active: false,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final w = tester.getSize(find.byType(ConsoleMachineCard)).width;
    expect(w, lessThanOrEqualTo(150),
        reason: '短名按内容收缩（flutter_test 用 Ahem 字体，每字宽=字号，真机会更窄）');
    expect(w, greaterThanOrEqualTo(80), reason: '点击目标别缩得太离谱');
  });

  testWidgets('纵向设备条长别名省略，统计不被挤出', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 228,
              child: ConsoleMachineCard(
                title: '一台名字非常非常长的开发机器，长到应该被省略',
                subtitle: 'a.local',
                online: true,
                needsAuth: false,
                running: 12,
                unviewed: 34,
                active: true,
                fillWidth: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ConsoleMachineCard)).height,
        ConsoleMachineCard.cardHeight);
  });

  testWidgets('数量都为 0 时第二行退回显示地址', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConsoleMachineCard(
              title: '工作台',
              subtitle: 'a.local:8090',
              online: true,
              needsAuth: false,
              running: 0,
              unviewed: 0,
              active: false,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('a.local:8090'), findsOneWidget);
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
