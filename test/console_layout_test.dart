/// 紧凑控制台布局回归：长机器名不能把行撑爆。
library;

import 'package:dsh_tablet_client/widgets/console_device_chip.dart';
import 'package:dsh_tablet_client/widgets/console_devices.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ConsoleMachineChip 长别名省略，整条仍只有 44 高', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ConsoleMachineChip(
                title: '一台名字非常非常长的开发机器，长到应该被省略',
                online: true,
                needsAuth: false,
                running: 12,
                unviewed: 34,
                active: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ConsoleMachineChip)).height, 44);
  });

  testWidgets('纵向设备条长别名省略，统计不被挤出', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 228,
              child: ConsoleMachineChip(
                title: '一台名字非常非常长的开发机器，长到应该被省略',
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
    expect(tester.getSize(find.byType(ConsoleMachineChip)).height, 44);
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
