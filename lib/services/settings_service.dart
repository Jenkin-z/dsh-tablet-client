import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/dsh_server.dart';
import 'seen_store.dart';

/// 持久化：多 PC 列表、主题、声音、未读水位
class SettingsService extends ChangeNotifier {
  late SharedPreferences _prefs;
  final _uuid = const Uuid();
  final SeenStore _seen = SeenStore();

  List<DshServer> _servers = [];
  String? _activeServerId;
  bool _keepScreenOn = true;
  bool _autoReconnect = true;
  bool _soundEnabled = true;
  bool _approvalSound = true;
  bool _completionSound = true;
  Map<String, String> _customSounds = {};
  Set<String> _expandedWs = {};
  bool _updateAutoCheck = true;
  String _themeModeKey = 'system';

  List<DshServer> get servers => List.unmodifiable(_servers);
  String? get activeServerId => _activeServerId;
  DshServer? get active {
    if (_servers.isEmpty) return null;
    for (final s in _servers) {
      if (s.id == _activeServerId) return s;
    }
    return _servers.first;
  }

  String get serverHost => active?.host ?? '192.168.10.171';
  int get serverPort => active?.port ?? 3080;
  String get serverUrl => active?.httpUrl ?? 'http://192.168.10.171:3080';
  String get wsUrl => active?.wsUrl ?? 'ws://192.168.10.171:3080';
  String? get sessionId => active?.lastSessionId;
  bool get keepScreenOn => _keepScreenOn;
  bool get autoReconnect => _autoReconnect;
  bool get soundEnabled => _soundEnabled;
  bool get approvalSound => _approvalSound;
  bool get completionSound => _completionSound;
  Map<String, String> get customSounds => Map.unmodifiable(_customSounds);
  Set<String> get expandedWs => Set.unmodifiable(_expandedWs);
  bool get updateAutoCheck => _updateAutoCheck;
  String get themeModeKey => _themeModeKey;
  Set<String> get unviewedIds => Set.unmodifiable(_seen.unviewed);
  int lastSeen(String id) => _seen.lastSeen(id);
  String? customSoundPath(String name) => _customSounds[name];
  String seenKey(String serverId, String sessionId) =>
      DshServer.sessionKey(serverId, sessionId);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _keepScreenOn = _prefs.getBool('keepScreenOn') ?? true;
    _autoReconnect = _prefs.getBool('autoReconnect') ?? true;
    _soundEnabled = _prefs.getBool('soundEnabled') ?? true;
    _approvalSound = _prefs.getBool('approvalSound') ?? true;
    _completionSound = _prefs.getBool('completionSound') ?? true;
    _loadCustomSounds();
    _expandedWs = (_prefs.getStringList('expandedWs') ?? []).toSet();
    _updateAutoCheck = _prefs.getBool('updateAutoCheck') ?? true;
    _themeModeKey = _prefs.getString('themeMode') ?? 'system';
    _seen.load(_prefs);
    _loadServers();
    notifyListeners();
  }

  void _loadServers() {
    final raw = _prefs.getString('serversJson');
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _servers = list
            .whereType<Map<String, dynamic>>()
            .map(DshServer.fromJson)
            .where((s) => s.id.isNotEmpty && s.host.isNotEmpty)
            .toList();
      } catch (_) {
        _servers = [];
      }
    }
    _activeServerId = _prefs.getString('activeServerId');
    if (_servers.isEmpty) {
      final host = _prefs.getString('serverHost') ?? '192.168.10.171';
      final port = _prefs.getInt('serverPort') ?? 3080;
      final sid = _prefs.getString('sessionId');
      final id = _uuid.v4();
      _servers = [
        DshServer(
            id: id, name: host, host: host, port: port, lastSessionId: sid),
      ];
      _activeServerId = id;
      _seen.rekeyBareIds(id);
      _seen.save(_prefs);
      _saveServers();
      return;
    }
    if (_activeServerId == null ||
        !_servers.any((s) => s.id == _activeServerId)) {
      _activeServerId = _servers.first.id;
    }
  }

  Future<void> _saveServers() async {
    await _prefs.setString(
        'serversJson', jsonEncode(_servers.map((s) => s.toJson()).toList()));
    if (_activeServerId != null) {
      await _prefs.setString('activeServerId', _activeServerId!);
    }
    final a = active;
    if (a == null) return;
    await _prefs.setString('serverHost', a.host);
    await _prefs.setInt('serverPort', a.port);
    if (a.lastSessionId != null) {
      await _prefs.setString('sessionId', a.lastSessionId!);
    }
  }

  Future<void> upsertServer(DshServer server) async {
    final i = _servers.indexWhere((s) => s.id == server.id);
    if (i >= 0) {
      _servers[i] = server;
    } else {
      _servers.add(server);
    }
    _activeServerId ??= server.id;
    await _saveServers();
    notifyListeners();
  }

  Future<void> removeServer(String id) async {
    _servers.removeWhere((s) => s.id == id);
    if (_activeServerId == id) {
      _activeServerId = _servers.isEmpty ? null : _servers.first.id;
    }
    await _saveServers();
    notifyListeners();
  }

  Future<void> setActiveServer(String id) async {
    if (!_servers.any((s) => s.id == id)) return;
    _activeServerId = id;
    await _saveServers();
    notifyListeners();
  }

  Future<void> patchServer(String id, DshServer Function(DshServer) fn) async {
    final i = _servers.indexWhere((s) => s.id == id);
    if (i < 0) return;
    _servers[i] = fn(_servers[i]);
    await _saveServers();
    notifyListeners();
  }

  Future<void> setServer(String host, int port) async {
    final a = active;
    if (a == null) {
      final id = _uuid.v4();
      await upsertServer(
          DshServer(id: id, name: host, host: host, port: port));
      await setActiveServer(id);
      return;
    }
    await patchServer(
        a.id, (s) => s.copyWith(host: host, port: port, name: s.name));
  }

  Future<void> setSessionId(String? id) async {
    final a = active;
    if (a == null) return;
    await patchServer(
      a.id,
      (s) => s.copyWith(lastSessionId: id, clearSessionId: id == null),
    );
  }

  Future<void> setKeepScreenOn(bool value) async {
    _keepScreenOn = value;
    await _prefs.setBool('keepScreenOn', value);
    notifyListeners();
  }

  Future<void> setAutoReconnect(bool value) async {
    _autoReconnect = value;
    await _prefs.setBool('autoReconnect', value);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    await _prefs.setBool('soundEnabled', value);
    notifyListeners();
  }

  Future<void> setApprovalSound(bool value) async {
    _approvalSound = value;
    await _prefs.setBool('approvalSound', value);
    notifyListeners();
  }

  Future<void> setCompletionSound(bool value) async {
    _completionSound = value;
    await _prefs.setBool('completionSound', value);
    notifyListeners();
  }

  Future<void> setCustomSound(String name, String? path) async {
    if (path == null || path.isEmpty) {
      _customSounds.remove(name);
      await _prefs.remove('customSound.$name');
    } else {
      _customSounds[name] = path;
      await _prefs.setString('customSound.$name', path);
    }
    notifyListeners();
  }

  void _loadCustomSounds() {
    for (final name in ['approval', 'question', 'done']) {
      final p = _prefs.getString('customSound.$name');
      if (p != null && p.isNotEmpty) _customSounds[name] = p;
    }
  }

  Future<void> setWsExpanded(String id, bool expanded) async {
    if (expanded) {
      _expandedWs.add(id);
    } else {
      _expandedWs.remove(id);
    }
    await _prefs.setStringList('expandedWs', _expandedWs.toList());
    notifyListeners();
  }

  Future<void> setUpdateAutoCheck(bool value) async {
    _updateAutoCheck = value;
    await _prefs.setBool('updateAutoCheck', value);
    notifyListeners();
  }

  Future<void> setThemeMode(String key) async {
    if (key != 'system' && key != 'light' && key != 'dark') return;
    _themeModeKey = key;
    await _prefs.setString('themeMode', key);
    notifyListeners();
  }

  Future<void> rememberBaseline(String id, int at) async {
    await _seen.rememberBaseline(_prefs, id, at);
  }

  Future<void> markSeen(String id) async {
    final changed = await _seen.markSeen(_prefs, id);
    if (changed) notifyListeners();
  }

  Future<void> markAllSeen(Iterable<String> ids) async {
    final changed = await _seen.markAllSeen(_prefs, ids);
    if (changed) notifyListeners();
  }

  Future<void> addUnviewed(String id) async {
    if (await _seen.addUnviewed(_prefs, id)) notifyListeners();
  }
}
