/// 设备行布局契约测试
///
/// 用户要求：一行一台机器，左侧图标、中间 IP（**不带端口**）、
/// 右侧其它信息，在线/离线**只用图标**表达（离线是红色带斜线的图标）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
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

  group('地址只显示 IP，不带端口', () {
    test('ConsoleDevices 传的是 host，不再拼 :port', () {
      expect(devices.contains('hostLabel: groups[i].server.host'), isTrue);
      // 直接看那一行里有没有出现 port，避免字符串转义的坑
      final idx = devices.indexOf('hostLabel:');
      expect(idx >= 0, isTrue);
      final line = devices.substring(idx, devices.indexOf('\n', idx));
      expect(line.contains('port'), isFalse,
          reason: '地址行不该再拼端口：$line');
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
      expect(devices.contains('stateText'), isFalse,
          reason: '状态不再用文字行，交给图标');
    });
  });

  group('单行布局', () {
    test('字段只剩一行信息，运行/未读退化为图标+数字', () {
      // 旧布局是「运行 N」「未读 N」两个带文字的胶囊
      expect(devices.contains('运行 '), isFalse);
      expect(devices.contains('未读 '), isFalse);
      expect(devices.contains('DeviceMiniStat'), isTrue);
    });

    test('设备行不再接收 name 参数（地址就是唯一标识）', () {
      // ConsoleDeviceChip（会话里的设备徽章）仍需要 name，所以只检查
      // ConsoleDeviceCard 这一段里没有 name 字段。
      final start = devices.indexOf('class ConsoleDeviceCard');
      final end = devices.indexOf('class ConsoleDeviceChip');
      expect(start >= 0 && end > start, isTrue);
      final card = devices.substring(start, end);
      expect(card.contains('this.name'), isFalse);
      expect(card.contains('String name'), isFalse);
    });

    test('小件已拆到 device_row_parts.dart，避免文件超限', () {
      expect(parts.contains('class DeviceStatusIcon'), isTrue);
      expect(parts.contains('class DeviceMiniStat'), isTrue);
      expect(parts.contains('class DeviceActiveBadge'), isTrue);
      final lines = devices.split('\n').length;
      expect(lines, lessThanOrEqualTo(220),
          reason: 'widget 文件上限 200，留一点余量');
    });
  });
}
