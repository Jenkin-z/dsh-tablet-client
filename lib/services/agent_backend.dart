import '../models/agent_server.dart';
import 'event_dispatcher.dart';
import 'model_catalog.dart';
import 'session_state.dart';
import 'settings_service.dart';
import 'server_manager.dart';

/// 统一后端接口：DSH 与 opencode 是同级的两份实现
///
/// 页面（chat_screen / session_drawer / approval_card / model_sheet）只经
/// ChatController 这个门面对话，不直接触碰任何后端；接第三个 agent 客户端
/// = 一个实现类 + [AgentKind] 多一个枚举值，页面零改动。
///
/// 约定：
/// - 所有事件都必须流经 [EventDispatcher]（对账/状态迁移只有一份）；
/// - 会话列表统一产出归一化 map（`sessionId/projections/updatedAt/running`），
///   页面与 SessionMonitor 不感知来源；
/// - `open(null)` 语义 = 断开并清空（切机器/无会话时）。
abstract class AgentBackend {
  /// 当前是否已连上（数据通道就绪，而非仅 socket 通）
  bool get connected;

  /// 模型目录/切换；未实现为 null（界面据此隐藏入口）
  ModelCatalogService? get models;

  /// 当前实际连着的会话（权威值，而非设置里的期望值）
  String? get activeSessionId;

  /// 连接事件流并进入该会话
  Future<void> open(String? sessionId);

  /// 归一化会话 map 列表（子会话已在数据入口过滤）
  Future<List<Map<String, dynamic>>> listSessions();

  /// 新建会话，返回会话 id
  Future<String> createSession({String? cwd});

  /// 发送消息；[requestId] 为本地乐观气泡的 rpcId，用于回执对账
  Future<void> sendPrompt({
    required String sessionId,
    required String text,
    required String requestId,
  });

  /// 中断（对应 DSH cancel）
  Future<void> cancel(String sessionId);

  /// 审批应答；返回是否被服务端接受
  Future<bool> replyApproval({
    required String sessionId,
    required String approvalId,
    required bool allow,
  });

  Future<void> dispose();
}

/// 后端共用的装配上下文
///
/// 每个后端都需要往同一个状态中枢写、经同一个 dispatcher 分发，
/// 并在特定时机（就绪/重连/一轮结束）触发会话列表刷新。
class BackendContext {
  final SettingsService settings;
  final ServerManager? manager;
  final SessionState state;
  final EventDispatcher dispatcher;
  final AgentServer server;

  /// 会话列表刷新（由 ChatController 提供，内部做统一过滤 + 健康度写入）
  final Future<void> Function() onRefreshSessions;

  const BackendContext({
    required this.settings,
    required this.state,
    required this.dispatcher,
    required this.server,
    required this.onRefreshSessions,
    this.manager,
  });
}
