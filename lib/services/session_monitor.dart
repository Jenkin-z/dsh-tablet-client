import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../models/dsh_server.dart';
import 'dsh_api.dart';
import 'dsh_auth.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import 'sound_service.dart';

/// 单台 PC 的会话轮询
class SessionMonitor {
  final SettingsService settings;
  DshServer server;
  int _notifySeq = 0;

  SessionMonitor({required this.settings, required this.server})
      : _api = DshApi(baseUrl: server.httpUrl, cookie: server.cookie);

  List<Map<String, dynamic>> sessions = [];
  List<Map<String, dynamic>> workspaces = [];
  Set<String> archivedIds = {};
  bool loading = false;
  bool online = false;
  String? error;
  DateTime? lastRefresh;
  final Map<String, bool> _prevRunning = {};

  final DshApi _api;

  String _key(String sessionId) => settings.seenKey(server.id, sessionId);

  Future<void> refresh() async {
    loading = sessions.isEmpty;
    try {
      final items = await _api.listSessions();
      final current = server.lastSessionId;
      for (final s in items) {
        final id = s['sessionId'] as String? ?? '';
        if (id.isEmpty) continue;
        final key = _key(id);
        await settings.rememberBaseline(key, (s['updatedAt'] as int?) ?? 0);
        final running = s['running'] == true;
        final was = _prevRunning[id];
        if (was == true && !running && id != current) {
          s['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
          await _markFinished(key);
        } else if (!running &&
            s['blank'] != true &&
            id != current &&
            ((s['updatedAt'] as int?) ?? 0) > settings.lastSeen(key)) {
          await settings.addUnviewed(key);
        }
        _prevRunning[id] = running;
      }
      sessions = items;
      error = null;
      online = true;
      lastRefresh = DateTime.now();
      if (server.unpaired || server.lastError != null) {
        await settings.patchServer(
          server.id,
          (s) => s.copyWith(unpaired: false, clearError: true),
        );
      }
    } on DshAuthException catch (e) {
      online = false;
      error = e.message;
      if (e.unpaired) {
        await settings.patchServer(
          server.id,
          (s) => s.copyWith(unpaired: true, lastError: e.message),
        );
      }
    } catch (e) {
      online = false;
      error = '$e';
    } finally {
      loading = false;
    }
  }

  /// 实时状态推送（api-session/status）：立即更新会话 running 标记
  ///
  /// 返回是否有变化，供上层决定是否需要刷新界面。
  bool applyStatus(String sessionId, bool running) {
    Map<String, dynamic>? target;
    for (final s in sessions) {
      if (s['sessionId'] == sessionId) {
        target = s;
        break;
      }
    }
    if (target == null || target['running'] == running) return false;
    final was = _prevRunning[sessionId];
    target['running'] = running;
    _prevRunning[sessionId] = running;
    if (was == true && !running && sessionId != server.lastSessionId) {
      target['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
      _markFinished(_key(sessionId));
    }
    return true;
  }

  /// 会话完成：标记未读 + 双通道通知 + 提示音
  Future<void> _markFinished(String key) async {
    await settings.addUnviewed(key);
    try {
      NotificationService.show(
        id: 10000 + _notifySeq++,
        title: '会话已完成',
        body: '非当前会话有新结果',
      );
    } catch (_) {}
    try {
      FlutterForegroundTask.updateService(
        notificationText: '会话已完成: 非当前会话有新结果',
      );
    } catch (_) {}
    if (settings.soundEnabled && settings.completionSound) {
      SoundService.done(customPath: settings.customSoundPath('done'));
    }
  }

  /// 当 server 信息变更时，刷新内部 DshApi
  void updateServer(DshServer newServer) {
    if (newServer.host != server.host ||
        newServer.port != server.port ||
        newServer.cookie != server.cookie) {
      server = newServer;
      // DshApi 是 final 的，需要重建整个 Monitor；
      // 由 ServerManager._syncMonitors 负责替换
    } else {
      server = newServer;
    }
  }

  static int activityOf(Map<String, dynamic> s) =>
      (s['updatedAt'] as int?) ?? 0;
}
