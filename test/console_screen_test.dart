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
import 'package:dsh_tablet_client/widgets/console_recent_list.dart';
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
    final h = await _pumpConsole(tester, const Size(800, 600));

    expect(find.byType(ConsoleMachineChip), findsOneWidget);
    expect(find.byType(ConsoleSessionTile), findsOneWidget);
    expect(find.text('修复登录页'), findsOneWidget);
    expect(find.text('工作台'), findsNWidgets(2));

    await tester.tap(find.byType(ConsoleSessionTile));
    expect(h.openedServer, 'srv-a');
    expect(h.openedSession, 'sess-1');

    await tester.tap(find.byType(ConsoleMachineChip));
    expect(h.switchedServer, 'srv-a');

    h.dispose();
  });

  testWidgets('横屏设备栏在左侧，竖屏回到顶部', (tester) async {
    final h = await _pumpConsole(tester, const Size(1280, 800));

    final chip = find.byType(ConsoleMachineChip);
    final recent = find.byType(ConsoleRecentList);
    expect(tester.getCenter(chip).dx, lessThan(tester.getCenter(recent).dx));
    expect(find.text('设备'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(800, 1280));
    await tester.pumpAndSettle();

    expect(tester.getCenter(chip).dy, lessThan(tester.getCenter(recent).dy));
    expect(find.text('设备'), findsNothing);

    h.dispose();
  });
}

class _Harness {
  final _FakeManager manager;
  final SettingsService settings;
  final SessionState state;
  String? openedServer;
  String? openedSession;
  String? switchedServer;

  _Harness(this.manager, this.settings, this.state);

  void dispose() {
    manager.dispose();
    settings.dispose();
    state.dispose();
  }
}

Future<_Harness> _pumpConsole(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues({});
  final settings = SettingsService();
  await settings.init();

  const server = AgentServer(
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
  final h = _Harness(manager, settings, state);

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
            h.openedServer = serverId;
            h.openedSession = sessionId;
          },
          onSwitchServer: (serverId) => h.switchedServer = serverId,
        ),
      ),
    ),
  );
  await tester.pump();
  return h;
}
