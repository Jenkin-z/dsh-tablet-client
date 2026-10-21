/// 控制台「最近 3 小时」的跨机器扁平列表
///
/// 旧版按机器分组，每台机器一段标题；现在把所有机器的会话混在一起，
/// 只保留窗口期内的条目，按最近活动倒序，每行用设备徽章标明归属。
library;

import '../services/server_manager.dart';
import 'session_format.dart';

/// 混排列表里的一条会话：会话数据 + 它所属的机器
class ConsoleSessionEntry {
  final ServerGroup group;
  final Map<String, dynamic> session;

  const ConsoleSessionEntry({required this.group, required this.session});

  String get serverId => group.server.id;

  /// 别名优先，空名退回地址（与设备条一致）
  String get serverName {
    if (group.server.name.isNotEmpty) return group.server.name;
    if (group.server.host.isNotEmpty) return group.server.host;
    return 'PC';
  }

  bool get online => group.monitor.online;
}

/// 汇总所有机器的窗口期会话：过滤空会话/归档/超窗，按 updatedAt 倒序。
///
/// 直接读 `monitor.sessions` 而不是 `group.recent`：后者每台机器只取
/// 最近 8 条，混排后会把窗口内更早的会话漏掉。
List<ConsoleSessionEntry> collectRecentSessions(
  List<ServerGroup> groups, {
  required Duration window,
  DateTime? now,
}) {
  final cutoff =
      (now ?? DateTime.now()).millisecondsSinceEpoch - window.inMilliseconds;
  final seen = <String>{};
  final out = <ConsoleSessionEntry>[];

  for (final group in groups) {
    for (final session in group.monitor.sessions) {
      final id = session['sessionId'] as String? ?? '';
      if (id.isEmpty) continue;
      if (!seen.add('${group.server.id}::$id')) continue;
      if (session['blank'] == true) continue;
      if (group.monitor.archivedIds.contains(id)) continue;
      if (activityOf(session) < cutoff) continue;
      out.add(ConsoleSessionEntry(group: group, session: session));
    }
  }

  out.sort((a, b) {
    final byTime = activityOf(b.session).compareTo(activityOf(a.session));
    if (byTime != 0) return byTime;
    return sessionTitleOf(a.session).compareTo(sessionTitleOf(b.session));
  });
  return out;
}
