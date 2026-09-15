import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

/// 控制台已读水位（sessionKey = serverId::sessionId）
/// 使用防抖写入：高频操作（markSeen/addUnviewed）延迟 500ms 批量持久化
class SeenStore {
  Map<String, int> seenAt = {};
  Set<String> unviewed = {};
  Timer? _debounce;
  bool _dirty = false;

  void load(SharedPreferences prefs) {
    try {
      final raw = prefs.getString('seenAtMap');
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        seenAt = {
          for (final e in m.entries)
            if (e.value is num) e.key: (e.value as num).toInt()
        };
      }
    } catch (_) {
      seenAt = {};
    }
    unviewed = (prefs.getStringList('unviewedIds') ?? []).toSet();
  }

  /// 立即持久化（用于关键路径，如页面销毁）
  Future<void> save(SharedPreferences prefs) async {
    _debounce?.cancel();
    _debounce = null;
    _dirty = false;
    await _doSave(prefs);
  }

  /// 防抖写入：500ms 内多次调用只写最后一次
  void _scheduleSave(SharedPreferences prefs) {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(seenStoreDebounce, () {
      _debounce = null;
      _dirty = false;
      _doSave(prefs);
    });
  }

  Future<void> _doSave(SharedPreferences prefs) async {
    if (seenAt.length > seenStoreMaxEntries) {
      final sorted = seenAt.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      seenAt = {for (final e in sorted.take(seenStoreMaxEntries)) e.key: e.value};
    }
    await prefs.setString('seenAtMap', jsonEncode(seenAt));
    await prefs.setStringList('unviewedIds', unviewed.toList());
  }

  /// 销毁前调用，确保数据落盘
  Future<void> flush(SharedPreferences prefs) async {
    if (_dirty) await save(prefs);
  }

  int lastSeen(String id) => seenAt[id] ?? 0;

  Future<void> rememberBaseline(
      SharedPreferences prefs, String id, int at) async {
    if (seenAt.containsKey(id)) return;
    seenAt[id] = at;
    _scheduleSave(prefs);
  }

  Future<bool> markSeen(SharedPreferences prefs, String id) async {
    seenAt[id] = DateTime.now().millisecondsSinceEpoch;
    final changed = unviewed.remove(id);
    _scheduleSave(prefs);
    return changed;
  }

  Future<bool> markAllSeen(
      SharedPreferences prefs, Iterable<String> ids) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final id in ids) {
      seenAt[id] = now;
      if (unviewed.remove(id)) changed = true;
    }
    _scheduleSave(prefs);
    return changed;
  }

  Future<bool> addUnviewed(SharedPreferences prefs, String id) async {
    if (!unviewed.add(id)) return false;
    _scheduleSave(prefs);
    return true;
  }

  void rekeyBareIds(String serverId) {
    String k(String id) => id.contains('::') ? id : '$serverId::$id';
    seenAt = {for (final e in seenAt.entries) k(e.key): e.value};
    unviewed = {for (final id in unviewed) k(id)};
  }
}
