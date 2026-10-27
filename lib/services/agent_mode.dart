/// 模式（agent）目录抽象：数据类 + 后端无关的目录/切换接口
///
/// 与 [ModelCatalogService] 同型的可选能力：后端有「模式」概念才实现
/// （opencode v2 的 agent：build/plan/general…，见
/// docs/opencode-openapi-v2.json 的 `GET /api/agent` +
/// `POST /api/session/{id}/agent`）；DSH 无对应概念，[AgentBackend.modes]
/// 返回 null，界面据此隐藏入口。接第三个后端时同理：要么实现，要么 null。
library;

/// 一个可切换的模式
class AgentMode {
  final String id;
  final String name;
  final String? description;

  const AgentMode({required this.id, required this.name, this.description});

  factory AgentMode.fromJson(Map<String, dynamic> j) => AgentMode(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? (j['id'] as String? ?? ''),
        description: j['description'] as String?,
      );
}

/// 模式目录 + 切换（后端无关抽象）
///
/// 页面（model_sheet）只依赖这个接口；语义 = 对后续轮次生效，
/// 与模型切换（ModelCatalogService.select）一致。
abstract class AgentModeService {
  /// 拉取可切换的模式列表（实现方负责过滤不可选条目）
  Future<List<AgentMode>> fetchModes();

  /// 当前会话生效的模式 id（读不到返回空串）
  Future<String> currentMode(String sessionId);

  /// 切换会话模式
  Future<void> select(String sessionId, String modeId);
}
