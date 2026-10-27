import '../agent_mode.dart';
import 'opencode_api.dart';

/// opencode 模式目录（AgentModeService 实现）
///
/// `GET /api/agent` 返回全部 agent（含 subagent 专用条目）；
/// `mode` 字段为 `subagent | primary | all`，只有 primary/all 能作为
/// 会话模式切换（subagent 不可选，直接在数据入口过滤）。
/// 当前模式读 `GET /api/session/{id}` 顶层的 `agent` 字段。
class OpenCodeModeService implements AgentModeService {
  final OpenCodeApi _api;

  const OpenCodeModeService(this._api);

  @override
  Future<List<AgentMode>> fetchModes() async {
    final items = await _api.agentCatalog();
    return [
      for (final m in items)
        if (m['mode'] != 'subagent' && (m['id'] as String? ?? '').isNotEmpty)
          AgentMode.fromJson(m),
    ];
  }

  @override
  Future<String> currentMode(String sessionId) async {
    final info = await _api.sessionInfo(sessionId);
    return info['agent'] as String? ?? '';
  }

  @override
  Future<void> select(String sessionId, String modeId) {
    return _api.switchAgent(sessionId, modeId);
  }
}
