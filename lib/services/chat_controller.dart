import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/agent_server.dart';
import '../models/pending.dart';
import '../utils/session_format.dart';
import 'agent_backend.dart';
import 'dsh_backend.dart';
import 'event_dispatcher.dart';
import 'model_catalog.dart';
import 'opencode_backend.dart';
import 'server_manager.dart';
import 'session_state.dart';
import 'settings_service.dart';

part 'chat_boot.dart';
part 'chat_messaging.dart';

/// 本地乐观气泡与 durable 消息对账用的 id 生成器
const Uuid _uuid = Uuid();

/// 库内共享宿主：声明各分片（mixin）依赖的字段，
/// 本身不对外暴露。[ChatController] 继承它并混入各职责分片。
///
/// 注意：分片用 `mixin X on _ChatControllerCore` 挂载，**不能**写成
/// `on ChatController` —— 那会让 mixin 与宿主类互为超接口，
/// Dart 直接报 recursive_interface_inheritance。
abstract class _ChatControllerCore extends ChangeNotifier {
  final SettingsService settings;
  final ServerManager? manager;

  /// 全局唯一的状态中枢，由上层注入
  final SessionState state;

  /// 统一事件入口（与 state 同一实例生命周期）
  late final EventDispatcher dispatcher;

  /// 当前选中的后端（按 kind 选 DshBackend / OpenCodeBackend）
  AgentBackend? _backend;

  _ChatControllerCore({
    required this.settings,
    required this.state,
    this.manager,
  }) {
    // dispatcher 与 state 共用同一实例，避免状态分裂
    dispatcher = EventDispatcher(
      state: state,
      onSessionStatusExternal: (sessionId, running) {
        // 权威中枢先落状态，再通知 ServerManager 实时刷新列表
        manager?.applySessionStatus(
          settings.activeServerId ?? '',
          sessionId,
          running,
        );
      },
    );
  }
}

/// 聊天业务逻辑门面：按 AgentServer.kind 选后端，页面只跟这个类对话
///
/// 重构后：
/// - 公开 API（boot/switchSession/send/cancel/answerApproval…）与后端无关；
/// - 所有连线、状态迁移、审批应答收在各自 backend 内部
///   （DshBackend / OpenCodeBackend 同级实现 AgentBackend）；
/// - 所有状态都从 SessionState 读取，所有事件都经 EventDispatcher 分发；
/// - 通知/声音钩子挂在 EventDispatcher 上（构造时一次），后端无关。
///
/// 按职责拆分（part 文件，同库共享私有作用域，对外 API 不变）：
/// - chat_boot.dart：初始化/重连 + 会话操作 + 会话列表/标题/已读
/// - chat_messaging.dart：发送/取消 + 审批/提问 + opencode 表单
class ChatController extends _ChatControllerCore
    with ChatBoot, ChatMessaging {
  ChatController({
    required super.settings,
    required super.state,
    super.manager,
  });

  /// 模型目录 / 切换（未连接或后端不支持时为 null）
  ModelCatalogService? get models => _backend?.models;

  @override
  void dispose() {
    _backend?.dispose();
    dispatcher.dispose();
    super.dispose();
  }
}
