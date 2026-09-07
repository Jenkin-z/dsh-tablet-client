import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/dsh_server.dart';
import 'session_monitor.dart';
import 'settings_service.dart';

/// 聚合多台 PC 的轮询结果，按 PC 分组给控制台用
class ServerGroup {
  final DshServer server;
  final SessionMonitor monitor;
  final List<Map<String, dynamic>> running;
  final List<Map<String, dynamic>> unviewed;
  final List<Map<String, dynamic>> recent;

  const ServerGroup({
    required this.server,
    required this.monitor,
    required this.running,
    required this.unviewed,
    required this.recent,
  });
}

class ServerManager extends ChangeNotifier {
  final SettingsService settings;
  final Map<String, SessionMonitor> _monitors = {};
  Timer? _timer;
  bool _started = false;
  DateTime? lastRefresh;

  ServerManager(this.settings);

  void start() {
    if (_started) return;
    _started = true;
    refreshAll();
    _timer = Timer.periodic(SessionMonitor.pollInterval, (_) => refreshAll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  SessionMonitor? monitorOf(String serverId) => _monitors[serverId];

  Future<void> refreshAll() async {
    if (!_started) return;
    _syncMonitors();
    await Future.wait(_monitors.values.map((m) => m.refresh()));
    lastRefresh = DateTime.now();
    notifyListeners();
  }

  void _syncMonitors() {
    final ids = settings.servers.map((s) => s.id).toSet();
    _monitors.removeWhere((id, _) => !ids.contains(id));
    for (final s in settings.servers) {
      final existing = _monitors[s.id];
      if (existing == null) {
        _monitors[s.id] = SessionMonitor(settings: settings, server: s);
      } else {
        existing.server = s;
      }
    }
  }

  List<ServerGroup> get groups {
    final out = <ServerGroup>[];
    for (final s in settings.servers) {
      final m = _monitors[s.id];
      if (m == null) continue;
      out.add(ServerGroup(
        server: s,
        monitor: m,
        running: _filter(m, s, running: true),
        unviewed: _filter(m, s, unviewed: true),
        recent: _filter(m, s, recent: true).take(8).toList(),
      ));
    }
    return out;
  }

  int get runningCount =>
      groups.fold(0, (n, g) => n + g.running.length);
  int get unviewedCount =>
      groups.fold(0, (n, g) => n + g.unviewed.length);
  int get totalCount =>
      groups.fold(0, (n, g) => n + g.monitor.sessions.length);

  List<Map<String, dynamic>> _filter(
    SessionMonitor m,
    DshServer server, {
    bool running = false,
    bool unviewed = false,
    bool recent = false,
  }) {
    final unv = settings.unviewedIds;
    final list = m.sessions.where((s) {
      final id = s['sessionId'] as String? ?? '';
      if (id.isEmpty) return false;
      final key = settings.seenKey(server.id, id);
      final isRun = s['running'] == true;
      if (running) return isRun;
      if (unviewed) {
        return unv.contains(key) &&
            !isRun &&
            s['blank'] != true &&
            !m.archivedIds.contains(id);
      }
      if (recent) {
        return !isRun &&
            !unv.contains(key) &&
            s['blank'] != true &&
            !m.archivedIds.contains(id);
      }
      return false;
    }).toList();
    list.sort(
        (a, b) => SessionMonitor.activityOf(b).compareTo(SessionMonitor.activityOf(a)));
    return list;
  }
}
