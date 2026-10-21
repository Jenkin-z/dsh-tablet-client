/// 会话展示格式化：标题提取 + 相对时间（聊天侧栏与控制台共用）
library;

/// 这个会话是否该出现在用户面前
///
/// DSH 在执行任务时会自动拉起**子 Agent 会话**，它们带着
/// `origin == 'subagent'` 和 `parentSessionId` 出现在 `session/list` 里。
/// 这些是任务的中间产物，不是用户创建的对话，**不应该出现在任何会话列表**。
///
/// Web 端的等价规则在 `ui-workspace/src/client/tree.ts` 的 `sessionVisible()`：
///
/// ```ts
/// session.origin !== 'subagent'
///   && !archived.has(session.id)
///   && (!session.blank || session.id === current)
/// ```
///
/// 本函数承担 `origin` 与 `blank` 两项；归档由调用方各自的 archivedIds 处理。
///
/// **过滤必须发生在数据入口**：只挡 UI 的话，子 Agent 跑完仍会弹出
/// 「会话已完成」通知——那是用户最不该被打扰的时刻。
///
/// [currentSessionId] 是「当前选中的会话」。空会话只是「新建对话」的占位行，
/// 和 Web 端一样只保留当前那一个，否则列表会堆满「新会话」。
bool isUserFacingSession(
  Map<String, dynamic> s, {
  String? currentSessionId,
}) {
  if (s['origin'] == 'subagent') return false;
  if (s['blank'] == true && s['sessionId'] != currentSessionId) return false;
  return true;
}

/// 子 Agent 会话判定（单独暴露，供测试与诊断使用）
bool isSubagentSession(Map<String, dynamic> s) => s['origin'] == 'subagent';

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

/// 从历史消息提炼一条通知摘要。
///
/// 完成通知的标题来自会话投影里的任务名；正文没有现成字段，
/// 只能从最近历史里取最后一条有效消息：通常是 assistant 的结果，
/// 如果用户刚发了新任务还没回复，就取这条 user 文本。
/// 这里只做纯文本归一化，网络请求由数据源负责。
String? summarizeConversation(
  Iterable<({String role, String text})> messages, {
  int maxChars = 100,
}) {
  String? assistant;
  String? user;
  var assistantAt = -1;
  var userAt = -1;
  var index = 0;
  for (final m in messages) {
    final text = _cleanSummary(m.text);
    if (text.isNotEmpty) {
      if (m.role == 'assistant') {
        assistant = text;
        assistantAt = index;
      } else if (m.role == 'user') {
        user = text;
        userAt = index;
      }
    }
    index++;
  }
  // 最后一条是 assistant 就用结果；如果用户刚发了新任务还没回复，
  // 用这条新任务，别拿上一轮的旧结果冒充本次概要。
  final pick = assistantAt >= userAt ? assistant : user;
  if (pick == null) return null;
  return pick.length > maxChars ? '${pick.substring(0, maxChars)}…' : pick;
}

String _cleanSummary(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 完成通知文案：标题是任务名，正文是机器 + 概要。
///
/// 摘要缺失或与标题重复时退回可点击的通用文案，避免通知只有
/// 「会话已完成」这种没有信息量的句子。
({String title, String body}) completionNotice({
  required Map<String, dynamic> session,
  required String serverName,
  String? summary,
}) {
  final title = sessionTitleOf(session);
  final machine = serverName.trim().isEmpty ? 'PC' : serverName.trim();
  final clean = summary == null ? '' : _cleanSummary(summary);
  final body = clean.isEmpty || clean == title
      ? '在$machine上完成，点击查看结果'
      : '$machine · $clean';
  return (title: title, body: body);
}

/// 会话活跃时间（ms）；缺失按 0 处理沉底
int activityOf(Map<String, dynamic> s) =>
    (s['updatedAt'] as num?)?.toInt() ?? 0;

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
