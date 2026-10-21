/// 设备行布局契约测试
///
/// 用户要求：机器列表改成紧凑形式，左侧图标、中间别名（**不带端口**）、
/// 右侧运行/未读，在线/离线**只用图标**表达（离线是红色带斜线的图标）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/theme/ios_theme.dart';
import 'package:dsh_tablet_client/widgets/device_row_parts.dart';

void main() {
  late String devices;
  late String parts;

  setUpAll(() {
    devices = File('lib/widgets/console_devices.dart').readAsStringSync();
    parts = File('lib/widgets/device_row_parts.dart').readAsStringSync();
  });

  group('地址不带端口', () {
    test('ConsoleDevices 从不拼 :port', () {
      // 后来的改动把主标题从 host 换成了别名（opencode 隧道条目显示
      // host 会像一串 id），但「不拼端口」这条一直成立。
      final start = devices.indexOf('ConsoleMachineChip(');
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

    test('不再有「在线 / 离线」文字行', () {
      // 旧布局用整行文字表达状态，已删除
      expect(devices.contains("online ? '在线' : '离线'"), isFalse);
      expect(devices.contains('stateText'), isFalse, reason: '状态不再用文字行，交给图标');
    });
  });

  group('紧凑布局', () {
    test('字段只剩一行信息，运行/未读退化为图标+数字', () {
      // 旧布局是「运行 N」「未读 N」两个带文字的胶囊
      expect(devices.contains('运行 '), isFalse);
      expect(devices.contains('未读 '), isFalse);
      expect(devices.contains('DeviceMiniStat'), isTrue);
    });

    test('机器条横向滚动，不再一台机器一张全宽卡', () {
      expect(devices.contains('scrollDirection: Axis.horizontal'), isTrue);
      expect(devices.contains('class ConsoleMachineChip'), isTrue);
      expect(devices.contains('class ConsoleDeviceCard'), isFalse,
          reason: '纵向大卡片已替换为紧凑胶囊');
      expect(devices.contains('height: 44'), isTrue,
          reason: '胶囊高度固定在 44，避免回到多行');
    });

    test('主标题是别名，缺别名时退回地址', () {
      // ConsoleDeviceChip（会话里的设备徽章）已拆到独立文件，不再有
      // name 字段冲突；设备条用的是 title = name 或 host。
      final start = devices.indexOf('class ConsoleMachineChip');
      expect(start >= 0, isTrue);
      final card = devices.substring(start);
      expect(card.contains('this.title'), isTrue);
      expect(devices.contains('final name = group.server.name'), isTrue);
      expect(devices.contains("host.isNotEmpty ? host : 'PC'"), isTrue,
          reason: '防御旧数据：空名退回地址');
    });

    test('小件已拆到 device_row_parts.dart，避免文件超限', () {
      expect(parts.contains('class DeviceStatusIcon'), isTrue);
      expect(parts.contains('class DeviceMiniStat'), isTrue);
      expect(parts.contains('class DeviceActiveBadge'), isTrue);
      final lines = devices.split('\n').length;
      expect(lines, lessThanOrEqualTo(220), reason: 'widget 文件上限 200，留一点余量');
    });
  });
}
