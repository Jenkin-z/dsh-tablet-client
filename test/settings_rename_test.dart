/// 设备改名回归测试
///
/// 改名只影响展示名，不能改连接指纹（否则 UI 会把 ChatScreen 重建，
/// 当前会话被无谓重连）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dsh_tablet_client/models/agent_server.dart';
import 'package:dsh_tablet_client/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renameServer 去空格、持久化，且连接指纹不变', () async {
    final server = AgentServer(
      id: 'pc1',
      name: '旧名字',
      host: '192.168.1.10',
      cookie: 'dsh-auth-x=v',
    );
    SharedPreferences.setMockInitialValues({
      'serversJson': jsonEncode([server.toJson()]),
      'activeServerId': 'pc1',
    });

    final settings = SettingsService();
    await settings.init();
    final revision = settings.servers.single.connectionRevision;

    await settings.renameServer('pc1', '  工作 PC  ');

    expect(settings.servers.single.name, '工作 PC');
    expect(settings.servers.single.connectionRevision, revision);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('serversJson'), contains('工作 PC'));
  });

  test('空名称被忽略', () async {
    final server = AgentServer(id: 'pc1', name: '旧名字', host: '1.2.3.4');
    SharedPreferences.setMockInitialValues({
      'serversJson': jsonEncode([server.toJson()]),
      'activeServerId': 'pc1',
    });

    final settings = SettingsService();
    await settings.init();
    await settings.renameServer('pc1', '   ');

    expect(settings.servers.single.name, '旧名字');
  });
}
