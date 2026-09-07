import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 控制台已读水位（sessionKey = serverId::sessionId）
class SeenStore {
  Map<String, int> seenAt = {};
  Set<String> unviewed = {};

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

  Future<void> save(SharedPreferences prefs) async {
    if (seenAt.length > 300) {
      final sorted = seenAt.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      seenAt = {for (final e in sorted.take(300)) e.key: e.value};
    }
    await prefs.setString('seenAtMap', jsonEncode(seenAt));
    await prefs.setStringList('unviewedIds', unviewed.toList());
  }

  int lastSeen(String id) => seenAt[id] ?? 0;

  Future<void> rememberBaseline(
      SharedPreferences prefs, String id, int at) async {
    if (seenAt.containsKey(id)) return;
    seenAt[id] = at;
    await save(prefs);
  }

  Future<bool> markSeen(SharedPreferences prefs, String id) async {
    seenAt[id] = DateTime.now().millisecondsSinceEpoch;
    final changed = unviewed.remove(id);
    await save(prefs);
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
    await save(prefs);
    return changed;
  }

  Future<bool> addUnviewed(SharedPreferences prefs, String id) async {
    if (!unviewed.add(id)) return false;
    await prefs.setStringList('unviewedIds', unviewed.toList());
    return true;
  }

  void rekeyBareIds(String serverId) {
    String k(String id) => id.contains('::') ? id : '$serverId::$id';
    seenAt = {for (final e in seenAt.entries) k(e.key): e.value};
    unviewed = {for (final id in unviewed) k(id)};
  }
}
