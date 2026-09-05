import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dsh_api.dart';
import 'settings_service.dart';
import 'sound_service.dart';

/// 会话监控：常驻轮询 session.list + workspace.list，
/// 检测“运行→完成”的跃迁（后台完成的会话标为未读 + 完成提示音）。
/// 与聊天页的侧栏刷新相互独立，互不干扰。
class SessionMonitor extends ChangeNotifier {
  final SettingsService settings;

  SessionMonitor(this.settings);

  static const pollInterval = Duration(seconds: 8);

  List<Map<String, dynamic>> sessions = [];
  List<Map<String, dynamic>> workspaces = [];
  Set<String> archivedIds = {};
  bool loading = false;
  String? error;
  DateTime? lastRefresh;

  Timer? _timer;
  bool _started = false;
  // 上一轮的 running 状态，用于跃迁检测
  final Map<String, bool> _prevRunning = {};

  void start() {
    if (_started) return;
    _started = true;
    refresh();
    _timer = Timer.periodic(pollInterval, (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<void> refresh() async {
    if (!_started) return;
    loading = sessions.isEmpty;
    try {
      final api = DshApi(baseUrl: settings.serverUrl);
      final items = await api.listSessions();
      Map<String, dynamic>? ws;
      try {
        ws = await api.listWorkspaces();
      } catch (_) {
        ws = null;
      }

      final current = settings.sessionId;

      // 首次成功拉取：以当前快照为已读基线，避免历史会话一次性全标未读
      if (!settings.seenSeeded) {
        final seed = <String, int>{};
        for (final s in items) {
          final id = s['sessionId'] as String? ?? '';
          if (id.isEmpty) continue;
          seed[id] = (s['updatedAt'] as int?) ?? 0;
        }
        await settings.seedSeen(seed);
      }

      for (final s in items) {
        final id = s['sessionId'] as String? ?? '';
        if (id.isEmpty) continue;
        final running = s['running'] == true;
        final was = _prevRunning[id];

        // 跃迁：运行 → 完成（且不是正在看的会话）→ 标未读 + 提示音
        if (was == true && !running && id != current) {
          s['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
          await settings.addUnviewed(id);
          if (settings.soundEnabled && settings.completionSound) {
            SoundService.done(
                customPath: settings.customSoundPath('done'));
          }
        }
        // 非运行、非空、有新活动（PC 端等他端产生）→ 标未读
        else if (!running &&
            s['blank'] != true &&
            id != current &&
            ((s['updatedAt'] as int?) ?? 0) > settings.lastSeen(id)) {
          await settings.addUnviewed(id);
        }
        _prevRunning[id] = running;
      }

      sessions = items;
      if (ws != null) {
        final rawItems = ws['items'] as List<dynamic>? ?? [];
        workspaces = rawItems.whereType<Map<String, dynamic>>().toList();
        final rawArchived = ws['archivedSessionIds'] as List<dynamic>? ?? [];
        archivedIds = rawArchived.whereType<String>().toSet();
      }
      error = null;
      lastRefresh = DateTime.now();
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ---------- 控制台派生视图 ----------

  /// 进行中的会话（活跃倒序）
  List<Map<String, dynamic>> get runningSessions {
    final list = sessions.where((s) => s['running'] == true).toList();
    list.sort((a, b) => _activity(b).compareTo(_activity(a)));
    return list;
  }

  /// 完成后未查看的会话（活跃倒序，已过滤运行中/空会话/归档）
  List<Map<String, dynamic>> get unviewedSessions {
    final unviewed = settings.unviewedIds;
    final list = sessions.where((s) {
      final id = s['sessionId'] as String? ?? '';
      return id.isNotEmpty &&
          unviewed.contains(id) &&
          s['running'] != true &&
          s['blank'] != true &&
          !archivedIds.contains(id);
    }).toList();
    list.sort((a, b) => _activity(b).compareTo(_activity(a)));
    return list;
  }

  /// 最近活跃（排除运行中/未读/空会话，取前 8）
  List<Map<String, dynamic>> get recentSessions {
    final unviewed = settings.unviewedIds;
    final list = sessions.where((s) {
      final id = s['sessionId'] as String? ?? '';
      return id.isNotEmpty &&
          s['running'] != true &&
          !unviewed.contains(id) &&
          s['blank'] != true &&
          !archivedIds.contains(id);
    }).toList();
    list.sort((a, b) => _activity(b).compareTo(_activity(a)));
    return list.take(8).toList();
  }

  static int _activity(Map<String, dynamic> s) =>
      (s['updatedAt'] as int?) ?? 0;
}
