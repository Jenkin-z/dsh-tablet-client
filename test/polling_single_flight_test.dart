/// 轮询单飞与超时回归测试
///
/// 定时器 8 秒一次，但一次 HTTP 请求可能挂到 30 秒；没有单飞时，
/// 每 8 秒就会再叠一层请求。这里锁住两条约束：
/// - 上一次 refresh 没回来，下一次直接跳过；
/// - 请求超时后 loading/单飞标记必须复位，不能把轮询永久卡死。
library;

import 'dart:async';

import 'package:dsh_tablet_client/models/agent_server.dart';
import 'package:dsh_tablet_client/services/session_monitor.dart';
import 'package:dsh_tablet_client/services/session_source.dart';
import 'package:dsh_tablet_client/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BlockingSource implements SessionListSource {
  final _completer = Completer<List<Map<String, dynamic>>>();
  int calls = 0;
  Duration? timeout;

  @override
  Future<List<Map<String, dynamic>>> fetchSessions({Duration? timeout}) {
    calls++;
    this.timeout = timeout;
    return _completer.future;
  }

  void complete() => _completer.complete([]);
}

class _NeverSource implements SessionListSource {
  Duration? timeout;

  @override
  Future<List<Map<String, dynamic>>> fetchSessions({Duration? timeout}) {
    this.timeout = timeout;
    return Completer<List<Map<String, dynamic>>>().future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;
  const server = AgentServer(id: 'pc-1', name: '测试机', host: '127.0.0.1');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
  });

  tearDown(() {
    settings.dispose();
  });

  test('refresh 单飞：上一次没回来时不会叠第二次请求', () async {
    final source = _BlockingSource();
    final monitor = SessionMonitor(
      settings: settings,
      server: server,
      source: source,
    );

    final first = monitor.refresh();
    final second = monitor.refresh();

    expect(source.calls, 1, reason: '第二次 refresh 应直接跳过');
    expect(source.timeout, isNotNull);

    source.complete();
    await first;
    await second;

    expect(monitor.loading, isFalse);
    expect(monitor.online, isTrue);
  });

  test('请求超时会收敛并复位 loading，不阻塞后续轮询', () async {
    final source = _NeverSource();
    const timeout = Duration(milliseconds: 30);
    final monitor = SessionMonitor(
      settings: settings,
      server: server,
      source: source,
      requestTimeout: timeout,
    );

    await monitor.refresh();

    expect(source.timeout, timeout);
    expect(monitor.loading, isFalse);
    expect(monitor.online, isFalse);
    expect(monitor.error, contains('TimeoutException'));
  });
}
