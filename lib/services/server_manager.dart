import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/agent_server.dart';
import '../utils/constants.dart';
import 'session_monitor.dart';
import 'settings_service.dart';

/// 聚合多台后端（DSH / opencode）的轮询结果，按机器分组给控制台用
///
/// 重构后：只做服务器管理和会话列表刷新，不做状态推断。
class ServerGroup {
  final AgentServer server;
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
  bool _refreshing = false;
  bool _disposed = false;
  DateTime? lastRefresh;
  List<ServerGroup>? _cachedGroups;

  ServerManager(this.settings) {
    settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    // 改名等元数据变化要立刻同步给已有 monitor，否则下一次完成通知
    // 还会用旧设备名（_syncMonitors 只在轮询时跑）。
    for (final s in settings.servers) {
      _monitors[s.id]?.updateServer(s);
    }
    notifyListeners();
  }

  void start() {
    if (_started) return;
    _started = true;
    refreshAll();
    _timer = Timer.periodic(pollInterval, (_) => refreshAll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettingsChanged);
    _timer?.cancel();
    super.dispose();
  }

  SessionMonitor? monitorOf(String serverId) => _monitors[serverId];

  /// 当前机器轮询结果的对外广播口。
  ///
  /// **不要接到 SessionState.setSessionsHealth 上。** 那个字段代表
  /// 对话页 mux 的数据健康，轮询是另一条通道；接上去会让状态点恒绿。
  /// 保留这个口子是给需要轮询视图的消费者（例如控制台自身）用的。
  void Function(bool ok, String? error)? onActiveHealth;

  void _reportActiveHealth() {
    // 曾经这里把活跃机器的轮询结果推给 SessionState，用来给顶部状态点
    // 上色。那是错的：状态点属于**对话页那条 WebSocket**，而轮询是另一条
    // 独立的 HTTP 通道 —— 轮询一直成功，点就永远绿，与对话页是否真连上无关。
    //
    // 现在 `_sessionsOk` 只由 ChatController 写入，这里不再对外广播。
    // 每台机器的健康度由设备卡各读各的 monitor（groups / _buildGroups）。
    _cachedGroups = null;
  }

  /// 实时状态推送：立即更新某台 PC 的会话运行标记（无需等下一次轮询）
  void applySessionStatus(String serverId, String sessionId, bool running) {
    final m = _monitors[serverId];
    if (m == null) return;
    if (m.applyStatus(sessionId, running)) notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    _cachedGroups = null;
    super.notifyListeners();
  }

  Future<void> refreshAll() async {
    if (!_started || _disposed || _refreshing) return;
    _refreshing = true;
    try {
      _syncMonitors();
      await Future.wait(_monitors.values.map((m) => m.refresh()));
      // 刷新期间可能已经 stop/dispose，别在销毁后再通知。
      if (!_started || _disposed) return;
      lastRefresh = DateTime.now();
      // 设备卡的结论同样要体现在顶部的状态点上
      _reportActiveHealth();
      notifyListeners();
    } catch (_) {
      // 各 monitor 已把失败写进自己的 online/error；这里只保证
      // 定时器不会因为某一次意外异常而中断。
    } finally {
      _refreshing = false;
    }
  }

  void _syncMonitors() {
    final ids = settings.servers.map((s) => s.id).toSet();
    _monitors.removeWhere((id, _) => !ids.contains(id));
    for (final s in settings.servers) {
      final existing = _monitors[s.id];
      if (existing == null) {
        _monitors[s.id] = SessionMonitor(settings: settings, server: s);
      } else if (existing.server.connectionRevision !=
          s.connectionRevision) {
        _monitors[s.id] = SessionMonitor(settings: settings, server: s);
      } else {
        existing.updateServer(s);
      }
    }
  }

  List<ServerGroup> get groups {
    return _cachedGroups ??= _buildGroups();
  }

  List<ServerGroup> _buildGroups() {
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
    AgentServer server, {
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
        return !isRun && s['blank'] != true && !m.archivedIds.contains(id);
      }
      return false;
    }).toList();

    if (recent) {
      list.sort((a, b) {
        final aTime = a['updatedAt'] as int? ?? 0;
        final bTime = b['updatedAt'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });
    }

    return list;
  }
}