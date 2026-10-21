part of 'settings_service.dart';

// 开关类偏好 + 声音 + 未读水位（SettingsService 的 part 文件）
//
// 方法用 `mixin X on _SettingsCore` 挂载：mixin 进入宿主类的
// 方法分派（外部调用方才能解析到），而 part 机制保证 mixin 与宿主同一
// library，可访问宿主私有字段。

mixin SettingsPreferences on _SettingsCore {
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
