import '../models/agent_server.dart';
import 'dsh/dsh_api.dart';
import 'opencode/opencode_api.dart';
import 'opencode/opencode_mapper.dart';

/// 会话列表数据源（SessionMonitor 用）：DSH 与 opencode 各一份实现
///
/// 产出统一的归一化 map（sessionId/projections/updatedAt/running/blank），
/// SessionMonitor 的边沿检测、未读、通知逻辑对后端无感。
abstract class SessionListSource {
  Future<List<Map<String, dynamic>>> fetchSessions();
}

/// DSH：Host RPC 原样返回（origin/blank/running 字段本就在线）
class DshSessionSource implements SessionListSource {
  final DshApi api;
  const DshSessionSource(this.api);

  @override
  Future<List<Map<String, dynamic>>> fetchSessions() => api.listSessions();
}

/// opencode：列表 + active 合并成归一化 map（parentID=null 已服务端过滤子会话）
class OpenCodeSessionSource implements SessionListSource {
  final OpenCodeApi api;
  const OpenCodeSessionSource(this.api);

  @override
  Future<List<Map<String, dynamic>>> fetchSessions() async {
    final items = await api.listSessions();
    final active = await api.activeSessions();
    return items
        .map((i) => OpenCodeMapper.normalizeSession(i, activeIds: active))
        .toList();
  }
}

/// 按 kind 造数据源
SessionListSource sessionSourceFor(AgentServer server) => switch (server.kind) {
      AgentKind.dsh => DshSessionSource(DshApi(
          baseUrl: server.httpUrl, cookie: server.cookie)),
      AgentKind.opencode => OpenCodeSessionSource(OpenCodeApi(
          baseUrl: server.httpUrl, password: server.token)),
    };
