import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 持久化设置：服务器地址、Session ID、亮屏开关等
class SettingsService extends ChangeNotifier {
  late SharedPreferences _prefs;

  String _serverHost = '192.168.10.171';
  int _serverPort = 3080;
  String? _sessionId;
  bool _keepScreenOn = true;
  bool _autoReconnect = true;
  // 提示音：总开关 + 分类开关；customSounds 预留后期自定义（名 -> 本地音频路径）
  bool _soundEnabled = true;
  bool _approvalSound = true;
  bool _completionSound = true;
  Map<String, String> _customSounds = {};
  // 侧栏工作区展开状态（默认全收起，存展开的 id）
  Set<String> _expandedWs = {};
  // 启动时自动检查更新（默认开，局域网小文件请求）
  bool _updateAutoCheck = true;
  // 主题：system 跟随系统 / light 浅色 / dark 深色
  String _themeModeKey = 'system';
  // 控制台已读水位：sessionId -> 最后查看时间；未读集合；基线是否已播种
  Map<String, int> _seenAt = {};
  Set<String> _unviewed = {};
  bool _seenSeeded = false;

  String get serverHost => _serverHost;
  int get serverPort => _serverPort;
  String get serverUrl => 'http://$_serverHost:$_serverPort';
  String get wsUrl => 'ws://$_serverHost:$_serverPort';
  String? get sessionId => _sessionId;
  bool get keepScreenOn => _keepScreenOn;
  bool get autoReconnect => _autoReconnect;
  bool get soundEnabled => _soundEnabled;
  bool get approvalSound => _approvalSound;
  bool get completionSound => _completionSound;
  Map<String, String> get customSounds => Map.unmodifiable(_customSounds);
  Set<String> get expandedWs => Set.unmodifiable(_expandedWs);
  bool get updateAutoCheck => _updateAutoCheck;
  String get themeModeKey => _themeModeKey;
  bool get seenSeeded => _seenSeeded;
  Set<String> get unviewedIds => Set.unmodifiable(_unviewed);
  int lastSeen(String id) => _seenAt[id] ?? 0;
  // 后期自定义提示音时调用：name = approval/question/done，path = 本地音频文件
  String? customSoundPath(String name) => _customSounds[name];

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _serverHost = _prefs.getString('serverHost') ?? '192.168.10.171';
    _serverPort = _prefs.getInt('serverPort') ?? 3080;
    _sessionId = _prefs.getString('sessionId');
    _keepScreenOn = _prefs.getBool('keepScreenOn') ?? true;
    _autoReconnect = _prefs.getBool('autoReconnect') ?? true;
    _soundEnabled = _prefs.getBool('soundEnabled') ?? true;
    _approvalSound = _prefs.getBool('approvalSound') ?? true;
    _completionSound = _prefs.getBool('completionSound') ?? true;
    _loadCustomSounds();
    _expandedWs = (_prefs.getStringList('expandedWs') ?? []).toSet();
    _updateAutoCheck = _prefs.getBool('updateAutoCheck') ?? true;
    _themeModeKey = _prefs.getString('themeMode') ?? 'system';
    _loadSeen();
    notifyListeners();
  }

  Future<void> setServer(String host, int port) async {
    _serverHost = host;
    _serverPort = port;
    await _prefs.setString('serverHost', host);
    await _prefs.setInt('serverPort', port);
    notifyListeners();
  }

  Future<void> setSessionId(String? id) async {
    _sessionId = id;
    if (id != null) {
      await _prefs.setString('sessionId', id);
    } else {
      await _prefs.remove('sessionId');
    }
    notifyListeners();
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

  /// 后期自定义提示音预留：存 name -> 本地音频路径
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

  /// 工作区展开/收起持久化
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

  /// 主题：system / light / dark
  Future<void> setThemeMode(String key) async {
    if (key != 'system' && key != 'light' && key != 'dark') return;
    _themeModeKey = key;
    await _prefs.setString('themeMode', key);
    notifyListeners();
  }

  // ---------- 控制台已读/未读 ----------

  void _loadSeen() {
    try {
      final raw = _prefs.getString('seenAtMap');
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _seenAt = {
          for (final e in m.entries)
            if (e.value is num) e.key: (e.value as num).toInt()
        };
      }
    } catch (_) {
      _seenAt = {};
    }
    _unviewed = (_prefs.getStringList('unviewedIds') ?? []).toSet();
    _seenSeeded = _prefs.getBool('seenSeeded') ?? false;
  }

  Future<void> _saveSeen() async {
    // 上限保护：只保留最近 300 条水位
    if (_seenAt.length > 300) {
      final sorted = _seenAt.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _seenAt = {for (final e in sorted.take(300)) e.key: e.value};
    }
    await _prefs.setString('seenAtMap', jsonEncode(_seenAt));
    await _prefs.setStringList('unviewedIds', _unviewed.toList());
    await _prefs.setBool('seenSeeded', _seenSeeded);
  }

  /// 首次成功拉取时以当前快照为已读基线（避免历史会话一次性全标未读）
  Future<void> seedSeen(Map<String, int> snapshot) async {
    if (_seenSeeded) return;
    _seenAt = Map.of(snapshot);
    _seenSeeded = true;
    await _saveSeen();
    notifyListeners();
  }

  /// 标为已读
  Future<void> markSeen(String id) async {
    _seenAt[id] = DateTime.now().millisecondsSinceEpoch;
    if (_unviewed.remove(id)) {
      await _saveSeen();
      notifyListeners();
    } else {
      await _saveSeen();
    }
  }

  /// 批量标为已读
  Future<void> markAllSeen(Iterable<String> ids) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final id in ids) {
      _seenAt[id] = now;
      if (_unviewed.remove(id)) changed = true;
    }
    await _saveSeen();
    if (changed) notifyListeners();
  }

  /// 标为未读（后台完成/他端有新活动时）
  Future<void> addUnviewed(String id) async {
    if (_unviewed.add(id)) {
      await _prefs.setStringList('unviewedIds', _unviewed.toList());
      notifyListeners();
    }
  }
}