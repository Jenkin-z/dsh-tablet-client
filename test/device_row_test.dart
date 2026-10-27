/// 设备行布局契约测试
///
/// 用户要求：机器列表改成紧凑两行卡片——第一行名称，第二行运行/未读数，
/// 在线/离线**只用图标**表达（离线是红色带斜线的图标）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/theme/ios_theme.dart';
import 'package:dsh_tablet_client/widgets/device_row_parts.dart';

void main() {
  late String devices;
  late String card;
  late String parts;

  setUpAll(() {
    devices = File('lib/widgets/console_devices.dart').readAsStringSync();
    card = File('lib/widgets/console_machine_card.dart').readAsStringSync();
    parts = File('lib/widgets/device_row_parts.dart').readAsStringSync();
  });

  group('地址不带端口', () {
    test('ConsoleDevices 主标题不拼 :port', () {
      // 主标题是别名（opencode 隧道条目显示 host 会像一串 id），
      // 地址只作为第二行兜底文案。
      final start = devices.indexOf('ConsoleMachineCard(');
      expect(start >= 0, isTrue);
      final call = devices.substring(start);
      expect(call.contains('server.port'), isFalse, reason: '设备行不该再拼端口');
      expect(devices.contains('group.server.host'), isTrue,
          reason: '别名缺失时要退回地址');
    });
  });

  group('在线状态只用图标表达', () {
    test('离线是红色断开图标', () {
      final icon = DeviceStatusIcon(online: false, needsAuth: false);
      expect(icon.color, IosTheme.iosRed);
    });

    test('在线是绿色对勾', () {
      final icon = DeviceStatusIcon(online: true, needsAuth: false);
      expect(icon.color, IosTheme.iosGreen);
    });

    test('需授权是橙色锁', () {
      final icon = DeviceStatusIcon(online: false, needsAuth: true);
      expect(icon.color, IosTheme.iosOrange);
    });
  });

  group('两行卡片布局', () {
    test('卡片类在独立文件，统计用图标+数字', () {
      expect(card.contains('class ConsoleMachineCard'), isTrue);
      expect(card.contains('DeviceMiniStat'), isTrue);
      expect(devices.contains('ConsoleMachineChip'), isFalse,
          reason: '旧单行胶囊已替换为两行卡片');
    });

    test('机器条横向滚动，卡片高度固定 62', () {
      expect(devices.contains('scrollDirection: Axis.horizontal'), isTrue);
      expect(card.contains('height: 62'), isTrue,
          reason: '两行卡片高度固定，避免内容抖动');
    });

    test('第一行是别名，第二行数量为 0 时退回地址', () {
      expect(card.contains('this.title'), isTrue);
      expect(card.contains('this.subtitle'), isTrue);
      expect(devices.contains('final name = group.server.name'), isTrue);
      expect(devices.contains("host.isNotEmpty ? host : 'PC'"), isTrue,
          reason: '防御旧数据：空名退回地址');
      expect(devices.contains('subtitle: host'), isTrue,
          reason: '第二行兜底显示地址');
    });

    test('小件留在 device_row_parts.dart，文件不超限', () {
      expect(parts.contains('class DeviceStatusIcon'), isTrue);
      expect(parts.contains('class DeviceMiniStat'), isTrue);
      expect(parts.contains('class DeviceActiveBadge'), isTrue);
      final lines = card.split('\n').length;
      expect(lines, lessThanOrEqualTo(220), reason: 'widget 文件上限 200，留一点余量');
    });
  });
}
