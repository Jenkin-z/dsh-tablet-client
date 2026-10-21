/// 控制台整页回归：机器条 + 跨机器混排 + 会话点击。
library;

import 'package:dsh_tablet_client/models/agent_server.dart';
import 'package:dsh_tablet_client/screens/console_screen.dart';
import 'package:dsh_tablet_client/services/server_manager.dart';
import 'package:dsh_tablet_client/services/session_monitor.dart';
import 'package:dsh_tablet_client/services/session_source.dart';
import 'package:dsh_tablet_client/services/session_state.dart';
import 'package:dsh_tablet_client/services/settings_service.dart';
import 'package:dsh_tablet_client/widgets/console_devices.dart';
import 'package:dsh_tablet_client/widgets/console_session_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSource implements SessionListSource {
  @override
  Future<List<Map<String, dynamic>>> fetchSessions({Duration? timeout}) async {
    return const [];
  }
}

class _FakeManager extends ServerManager {
  _FakeManager(super.settings);

  List<ServerGroup> fakeGroups = const [];

  @override
  List<ServerGroup> get groups => fakeGroups;

  @override
  Future<void> refreshAll() async {}
}

void main() {
  testWidgets('控制台把窗口内会话跨机器混排，并保留两种点击手势', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.init();

    final server = const AgentServer(
      id: 'srv-a',
      name: '工作台',
      host: 'a.local',
      cookie: 'cookie',
    );
    final monitor = SessionMonitor(
      settings: settings,
      server: server,
      source: _FakeSource(),
    )
      ..online = true
      ..sessions = [
        {
          'sessionId': 'sess-1',
          'projections': {
            'values': {'title': '修复登录页'},
          },
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          'running': false,
          'blank': false,
        },
      ];

    final manager = _FakeManager(settings)
      ..fakeGroups = [
        ServerGroup(
          server: server,
          monitor: monitor,
          running: const [],
          unviewed: const [],
          recent: const [],
        ),
      ];
    final state = SessionState();
    String? openedServer;
    String? openedSession;
    String? switchedServer;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerManager>.value(value: manager),
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<SessionState>.value(value: state),
        ],
        child: MaterialApp(
          home: ConsoleScreen(
            onOpenSession: (serverId, sessionId) {
              openedServer = serverId;
              openedSession = sessionId;
            },
            onSwitchServer: (serverId) => switchedServer = serverId,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ConsoleMachineChip), findsOneWidget);
    expect(find.byType(ConsoleSessionTile), findsOneWidget);
    expect(find.text('修复登录页'), findsOneWidget);
    expect(find.text('工作台'), findsNWidgets(2));

    await tester.tap(find.byType(ConsoleSessionTile));
    expect(openedServer, 'srv-a');
    expect(openedSession, 'sess-1');

    await tester.tap(find.byType(ConsoleMachineChip));
    expect(switchedServer, 'srv-a');

    manager.dispose();
    settings.dispose();
    state.dispose();
  });
}
