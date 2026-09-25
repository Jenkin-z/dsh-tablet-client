import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../models/dsh_server.dart';
import '../utils/session_format.dart';
import 'dsh_api.dart';
import 'dsh_auth.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import 'sound_service.dart';

/// 单台 PC 的会话轮询
///
/// 职责：拉会话列表 + 识别「非当前会话刚跑完」并在此刻触发
/// 未读标记 / 系统通知 / 提示音。
/// 其余状态推断交给 DshSessionState 与 MuxEventDispatcher。
class SessionMonitor {
  final SettingsService settings;
  DshServer server;

  /// 通知 id 递增，避免同一条通知互相覆盖
  int _notifySeq = 0;

  /// 上一次轮询时各会话是否在跑，用于识别「刚跑完」的边沿
  final Map<String, bool> _prevRunning = {};

  SessionMonitor({required this.settings, required this.server})
      : _api = DshApi(baseUrl: server.httpUrl, cookie: server.cookie);

  List<Map<String, dynamic>> sessions = [];
  List<Map<String, dynamic>> workspaces = [];
  Set<String> archivedIds = {};
  bool loading = false;
  bool online = false;
  String? error;
  DateTime? lastRefresh;

  final DshApi _api;

  String _key(String sessionId) => settings.seenKey(server.id, sessionId);

  Future<void> refresh() async {
    loading = sessions.isEmpty;
    try {
      final items = await _api.listSessions();
      final current = server.lastSessionId;
      // 先剔除子 Agent 与多余的空会话：前者是任务的中间产物，
      // 后者是「新建对话」的占位。必须在计数和通知之前剔除，
      // 否则「子 Agent 跑完」会弹出「会话已完成」通知，打扰用户。
      for (final s in items.where((s) => isUserFacingSession(s, currentSessionId: current))) {
        final id = s['sessionId'] as String? ?? '';
        if (id.isEmpty) continue;
        final key = _key(id);
        await settings.rememberBaseline(key, (s['updatedAt'] as int?) ?? 0);
        final running = s['running'] == true;
        final was = _prevRunning[id];
        if (was == true && !running && id != current) {
          // 非当前会话刚跑完：把时间顶到现在，让它浮到「最近」列表顶部
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
      // 存储的列表也要过滤，否则 _filter()/groups 仍会把子 Agent 数进
      // 「运行中」「最近」计数，控制台上就会出现莫名其妙的条目。
      sessions = items
          .where((s) => isUserFacingSession(s, currentSessionId: current))
          .toList();
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
    // 实时推送也要走完成检测，否则只有轮询到的完成才会通知
    if (was == true && !running && sessionId != server.lastSessionId) {
      target['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
      _markFinished(_key(sessionId));
    }
    return true;
  }

  /// 会话完成：标记未读 + 双通道通知 + 提示音
  ///
  /// 只对**非当前会话**触发 —— 你正看着的会话不需要通知你。
  Future<void> _markFinished(String key) async {
    await settings.addUnviewed(key);
    try {
      await NotificationService.show(
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
    // DshApi 是 final 的，host/port/cookie 变了需要重建整个 Monitor，
    // 由 ServerManager._syncMonitors 负责替换；这里只更新数据。
    server = newServer;
  }

  static int activityOf(Map<String, dynamic> s) =>
      (s['updatedAt'] as int?) ?? 0;
}
