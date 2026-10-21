/// 控制台「最近 3 小时」混排规则测试
///
/// 锁住三件事：跨机器、过滤空/归档/超窗、按最近活动倒序。
library;

import 'package:dsh_tablet_client/models/agent_server.dart';
import 'package:dsh_tablet_client/services/server_manager.dart';
import 'package:dsh_tablet_client/services/session_monitor.dart';
import 'package:dsh_tablet_client/services/session_source.dart';
import 'package:dsh_tablet_client/services/settings_service.dart';
import 'package:dsh_tablet_client/utils/console_sessions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptySource implements SessionListSource {
  @override
  Future<List<Map<String, dynamic>>> fetchSessions({Duration? timeout}) async =>
      [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
  });

  tearDown(() {
    settings.dispose();
  });

  ServerGroup group({
    required String id,
    required String name,
    required String host,
    required List<Map<String, dynamic>> sessions,
    Set<String> archived = const {},
  }) {
    final server = AgentServer(id: id, name: name, host: host);
    final monitor = SessionMonitor(
      settings: settings,
      server: server,
      source: _EmptySource(),
    );
    monitor.sessions = sessions;
    monitor.archivedIds = {...archived};
    return ServerGroup(
      server: server,
      monitor: monitor,
      running: const [],
      unviewed: const [],
      recent: const [],
    );
  }

  Map<String, dynamic> session(
    String id,
    DateTime at, {
    String? title,
    bool blank = false,
  }) =>
      {
        'sessionId': id,
        'updatedAt': at.millisecondsSinceEpoch,
        'blank': blank,
        'running': false,
        if (title != null)
          'projections': {
            'values': {'title': title},
          },
      };

  test('跨机器混排：过滤空/归档/超窗，按时间倒序', () {
    final now = DateTime(2026, 10, 21, 12);
    final groups = [
      group(
        id: 'a',
        name: '工作台',
        host: 'a.local',
        sessions: [
          session('a-old', now.subtract(const Duration(hours: 4)),
              title: '旧任务'),
          session('a-new', now.subtract(const Duration(minutes: 2)),
              title: '新任务'),
          session('a-arch', now.subtract(const Duration(minutes: 1)),
              title: '归档任务'),
          session('a-blank', now.subtract(const Duration(minutes: 1)),
              blank: true),
        ],
        archived: {'a-arch'},
      ),
      group(
        id: 'b',
        name: '',
        host: 'b.local',
        sessions: [
          session('b-1', now.subtract(const Duration(minutes: 5)),
              title: 'B 任务'),
        ],
      ),
    ];

    final entries = collectRecentSessions(
      groups,
      window: const Duration(hours: 3),
      now: now,
    );

    expect(entries.map((e) => e.session['sessionId']), ['a-new', 'b-1']);
    expect(entries.first.serverName, '工作台');
    expect(entries.last.serverName, 'b.local', reason: '别名为空时退回地址');
  });

  test('同一台机器里重复的会话只保留一条', () {
    final now = DateTime(2026, 10, 21, 12);
    final dup = session(
      'dup-1',
      now.subtract(const Duration(minutes: 1)),
      title: '重复任务',
    );
    final entries = collectRecentSessions(
      [
        group(
          id: 'a',
          name: '工作台',
          host: 'a.local',
          sessions: [dup, dup],
        ),
      ],
      window: const Duration(hours: 3),
      now: now,
    );

    expect(entries, hasLength(1));
  });
}
