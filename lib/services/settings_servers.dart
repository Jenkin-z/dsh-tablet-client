part of 'settings_service.dart';

// 多后端列表的读写与当前后端选择（SettingsService 的 part 文件）
//
// 方法用 `mixin X on _SettingsCore` 挂载：mixin 进入宿主类的
// 方法分派（外部调用方才能解析到），而 part 机制保证 mixin 与宿主同一
// library，可访问宿主私有字段。

mixin SettingsServers on _SettingsCore {
  void _loadServers() {
    final raw = _prefs.getString('serversJson');
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _servers = list
            .whereType<Map<String, dynamic>>()
            .map(AgentServer.fromJson)
            // opencode 隧道条目只有 url 没有 host，两者有其一即可
            .where((s) => s.id.isNotEmpty && (s.host.isNotEmpty || (s.url ?? '').isNotEmpty))
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
        AgentServer(
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
    // 旧镜像字段：opencode 隧道条目没有 host，别用空串把旧值盖掉
    if (a.host.isNotEmpty) await _prefs.setString('serverHost', a.host);
    await _prefs.setInt('serverPort', a.port);
    if (a.lastSessionId != null) {
      await _prefs.setString('sessionId', a.lastSessionId!);
    }
  }

  Future<void> upsertServer(AgentServer server) async {
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

  Future<void> patchServer(String id, AgentServer Function(AgentServer) fn) async {
    final i = _servers.indexWhere((s) => s.id == id);
    if (i < 0) return;
    _servers[i] = fn(_servers[i]);
    await _saveServers();
    notifyListeners();
  }

  /// 修改设备显示名（不影响连接指纹，不会触发重连）
  Future<void> renameServer(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await patchServer(id, (s) => s.copyWith(name: trimmed));
  }

  Future<void> setServer(String host, int port) async {
    final a = active;
    if (a == null) {
      final id = _uuid.v4();
      await upsertServer(
          AgentServer(id: id, name: host, host: host, port: port));
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
}
