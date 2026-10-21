import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/agent_server.dart';
import 'seen_store.dart';

part 'settings_servers.dart';
part 'settings_preferences.dart';

/// 库内共享宿主：声明设置服务各分片（mixin）依赖的字段，
/// 本身不对外暴露。[SettingsService] 继承它并混入各职责分片。
///
/// 注意：分片用 `mixin X on _SettingsCore` 挂载，**不能**写成
/// `on SettingsService` —— 那会让 mixin 与宿主类互为超接口，
/// Dart 直接报 recursive_interface_inheritance。
abstract class _SettingsCore extends ChangeNotifier {
  late SharedPreferences _prefs;
  final _uuid = const Uuid();
  final SeenStore _seen = SeenStore();

  List<AgentServer> _servers = [];
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

  List<AgentServer> get servers => List.unmodifiable(_servers);
  String? get activeServerId => _activeServerId;
  AgentServer? get active {
    if (_servers.isEmpty) return null;
    for (final s in _servers) {
      if (s.id == _activeServerId) return s;
    }
    return _servers.first;
  }

  String get serverHost {
    final a = active;
    if (a == null) return '192.168.10.171';
    // opencode 隧道条目没有 host，退回展示地址
    return a.host.isNotEmpty ? a.host : a.displayAddress;
  }

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
      AgentServer.sessionKey(serverId, sessionId);
}

/// 持久化：多后端列表（DSH / opencode）、主题、声音、未读水位
///
/// 按职责拆分（part 文件，同库共享私有作用域，对外 API 不变）：
/// - settings_servers.dart：多后端列表的读写与当前后端选择
/// - settings_preferences.dart：开关类偏好 + 声音 + 未读水位
class SettingsService extends _SettingsCore
    with SettingsServers, SettingsPreferences {
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
}
