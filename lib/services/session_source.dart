import '../models/agent_server.dart';
import '../utils/session_format.dart';
import 'dsh/dsh_api.dart';
import 'dsh/mux_history.dart';
import 'opencode/opencode_api.dart';
import 'opencode/opencode_mapper.dart';

/// 会话列表数据源（SessionMonitor 用）：DSH 与 opencode 各一份实现
///
/// 产出统一的归一化 map（sessionId/projections/updatedAt/running/blank），
/// SessionMonitor 的边沿检测、未读、通知逻辑对后端无感。
abstract class SessionListSource {
  Future<List<Map<String, dynamic>>> fetchSessions({Duration? timeout});
}

/// 可选能力：完成通知正文需要拉最近历史提炼摘要。
///
/// 单独拆一个接口，测试/第三方数据源只实现列表即可，不必被迫写空方法。
abstract class SessionSummarySource implements SessionListSource {
  Future<String?> fetchSummary(String sessionId, {Duration? timeout});
}

/// 安全调用摘要能力；数据源不支持时返回 null。
Future<String?> fetchSessionSummary(
  SessionListSource source,
  String sessionId, {
  Duration? timeout,
}) {
  if (source is SessionSummarySource) {
    return source.fetchSummary(sessionId, timeout: timeout);
  }
  return Future<String?>.value();
}

/// DSH：Host RPC 原样返回（origin/blank/running 字段本就在线）
class DshSessionSource implements SessionListSource, SessionSummarySource {
  final DshApi api;
  const DshSessionSource(this.api);

  @override
  Future<List<Map<String, dynamic>>> fetchSessions({Duration? timeout}) =>
      api.listSessions(timeout: timeout);

  @override
  Future<String?> fetchSummary(String sessionId, {Duration? timeout}) async {
    final page = await api.getHistory(
      sessionId,
      maxMessages: 20,
      timeout: timeout,
    );
    final events = page['events'];
    if (events is! List) return null;
    return summarizeConversation(
      parseHistory(events).map((m) => (role: m.role, text: m.text)),
    );
  }
}

/// opencode：列表 + active 合并成归一化 map（parentID=null 已服务端过滤子会话）
class OpenCodeSessionSource implements SessionListSource, SessionSummarySource {
  final OpenCodeApi api;
  const OpenCodeSessionSource(this.api);

  @override
  Future<List<Map<String, dynamic>>> fetchSessions({Duration? timeout}) async {
    // 列表与 active 互不依赖，并行拉，别把一次轮询拖成两段串行往返。
    final results = await Future.wait<Object>([
      api.listSessions(timeout: timeout),
      api.activeSessions(timeout: timeout),
    ]);
    final items = results[0] as List<Map<String, dynamic>>;
    final active = results[1] as Set<String>;
    return items
        .map((i) => OpenCodeMapper.normalizeSession(i, activeIds: active))
        .toList();
  }

  @override
  Future<String?> fetchSummary(String sessionId, {Duration? timeout}) async {
    // order=desc 才是「最新 20 条」；拿 asc 会取到会话开头，摘要就错了。
    final raw = await api.messages(
      sessionId,
      limit: 20,
      order: 'desc',
      timeout: timeout,
    );
    return summarizeConversation(
      OpenCodeMapper.messagesToChat(raw.reversed.toList())
          .map((m) => (role: m.role, text: m.content)),
    );
  }
}

/// 按 kind 造数据源
SessionListSource sessionSourceFor(AgentServer server) {
  switch (server.kind) {
    case AgentKind.dsh:
      return DshSessionSource(
        DshApi(baseUrl: server.httpUrl, cookie: server.cookie),
      );
    case AgentKind.opencode:
      return OpenCodeSessionSource(
        OpenCodeApi(baseUrl: server.httpUrl, password: server.token),
      );
  }
}
