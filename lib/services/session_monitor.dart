import '../models/dsh_server.dart';
import 'dsh_api.dart';
import 'dsh_auth.dart';
import 'settings_service.dart';
import 'sound_service.dart';

/// 单台 PC 的会话轮询
class SessionMonitor {
  final SettingsService settings;
  DshServer server;

  SessionMonitor({required this.settings, required this.server});

  static const pollInterval = Duration(seconds: 8);

  List<Map<String, dynamic>> sessions = [];
  List<Map<String, dynamic>> workspaces = [];
  Set<String> archivedIds = {};
  bool loading = false;
  bool online = false;
  String? error;
  DateTime? lastRefresh;
  final Map<String, bool> _prevRunning = {};

  DshApi get _api =>
      DshApi(baseUrl: server.httpUrl, deviceId: server.deviceId);

  String _key(String sessionId) => settings.seenKey(server.id, sessionId);

  Future<void> refresh() async {
    loading = sessions.isEmpty;
    try {
      if (server.deviceId != null && server.deviceId!.isNotEmpty) {
        await PairingClient.heartbeat(
            server.host, server.port, server.deviceId!);
      }
      final items = await _api.listSessions();
      Map<String, dynamic>? ws;
      try {
        ws = await _api.listWorkspaces();
      } catch (_) {
        ws = null;
      }
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
          await settings.addUnviewed(key);
          if (settings.soundEnabled && settings.completionSound) {
            SoundService.done(customPath: settings.customSoundPath('done'));
          }
        } else if (!running &&
            s['blank'] != true &&
            id != current &&
            ((s['updatedAt'] as int?) ?? 0) > settings.lastSeen(key)) {
          await settings.addUnviewed(key);
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
      if (e.unpaired || (e.status == 401 && server.deviceId == null)) {
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

  static int activityOf(Map<String, dynamic> s) =>
      (s['updatedAt'] as int?) ?? 0;
}
