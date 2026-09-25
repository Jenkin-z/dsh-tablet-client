/// 会话展示格式化：标题提取 + 相对时间（聊天侧栏与控制台共用）
library;

/// 安全访问 projections.values.title（兼容嵌套结构）
String sessionTitleOf(Map<String, dynamic> s) {
  final t = _safeProjectionTitle(s);
  if (t != null && t.isNotEmpty) return t;
  if (s['blank'] == true) return '新会话';
  final id = s['sessionId'] as String? ?? '';
  return id.length > 8 ? '会话 …${id.substring(id.length - 6)}' : '未命名会话';
}

/// 安全提取 projections.values.title（兼容 string 和 {title: string} 两种格式）
String? _safeProjectionTitle(Map<String, dynamic> s) {
  try {
    final proj = s['projections'];
    if (proj is! Map) return null;
    final values = proj['values'];
    if (values is! Map) return null;
    final t = values['title'];
    if (t is String && t.isNotEmpty) return t;
    if (t is Map) {
      final inner = t['title'];
      if (inner is String && inner.isNotEmpty) return inner;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 从 session/control 的 projection 帧更新标题缓存
String? projectionTitleFrom(Map<String, dynamic> value) {
  try {
    if (value['key'] != 'title') return null;
    final v = value['value'];
    if (v is String && v.isNotEmpty) return v;
    if (v is Map) {
      final inner = v['title'];
      if (inner is String && inner.isNotEmpty) return inner;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 从 session/follow 开窗快照的 `projections` 提取标题
///
/// 结构：`{ asOfSeq, values: { title: string|null, ... } }`
/// （session-title/src/types.ts 把 `title` 合并进 SessionProjectionMap）
String? extractProjectionTitle(Map<String, dynamic> projections) {
  final values = projections['values'];
  if (values is! Map) return null;
  final t = values['title'];
  if (t is String && t.isNotEmpty) return t;
  return null;
}

String timeAgoOf(int? ms) {
  if (ms == null) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return '${dt.month}/${dt.day}';
}

/// 会话活跃时间（ms）；缺失按 0 处理沉底
int activityOf(Map<String, dynamic> s) => (s['updatedAt'] as int?) ?? 0;

/// 会话的工作区标题（未分组返回 null）
String? workspaceOf(
  Map<String, dynamic> s,
  List<Map<String, dynamic>> workspaces,
) {
  final id = s['sessionId'] as String? ?? '';
  for (final w in workspaces) {
    final ids = (w['sessionIds'] as List<dynamic>? ?? []).whereType<String>();
    if (ids.contains(id)) {
      final title = (w['title'] as String?)?.trim();
      if (title != null && title.isNotEmpty) return title;
      return w['path'] as String?;
    }
  }
  return null;
}