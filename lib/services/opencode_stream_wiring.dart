import 'agent_backend.dart';
import 'opencode/opencode_mapper.dart';
import 'opencode/opencode_stream.dart';

/// SSE 事件 → OpenCodeEventSink 的装配（从 OpenCodeBackend 拆出）
///
/// backend 只提供几个判断/动作回调（是否当前会话 / 是否自己的回显 /
/// turn 边沿 / 流就绪 / 流断开），这里负责把流回调与 mapper 的每个动作
/// 接到 dispatcher 与对账通道上。
class OpenCodeWiring {
  final BackendContext ctx;

  /// 事件是否属于当前绑定会话
  final bool Function(String sessionId) isCurrent;

  /// inbox 回显是否是自己刚发的（免重拉历史）
  final bool Function(String inboxId) isOwnEcho;

  /// turn 开始/结束的边沿动作（触发表单对账）
  final void Function() onTurnEdge;

  /// permission.asked 到达：再拉一次列表对账（事件载荷与列表同构）
  final void Function() onApprovalEvent;

  /// 别的客户端发来用户消息：重拉历史（reconciler 提供）
  final Future<void> Function() onForeignEcho;

  /// SSE 流就绪：置连接态 + 全量对账（backend 提供 reconciler 动作）
  final void Function() onStreamConnected;

  /// SSE 流断开（尚未进入重试）
  final void Function() onStreamDisconnected;

  /// SSE 传输级错误（含授权失败，401 时流不再重试）
  final void Function(String message) onStreamError;

  OpenCodeWiring({
    required this.ctx,
    required this.isCurrent,
    required this.isOwnEcho,
    required this.onTurnEdge,
    required this.onApprovalEvent,
    required this.onForeignEcho,
    required this.onStreamConnected,
    required this.onStreamDisconnected,
    required this.onStreamError,
  });

  void attach(OpenCodeStream stream) {
    stream.onEvent = _onEvent;
    stream.onConnected = onStreamConnected;
    stream.onDisconnected = onStreamDisconnected;
    stream.onError = onStreamError;
  }

  void _onEvent(String type, Map<String, dynamic> data) {
    OpenCodeMapper.mapEvent(
      type: type,
      data: data,
      // 全局事件流带着别的会话的内容，按会话过滤掉
      isCurrent: isCurrent,
      sink: OpenCodeEventSink(
        onTextDelta: ctx.dispatcher.onTextDelta,
        onAssistantFinal: (text) => ctx.dispatcher.onAssistantFinal(text, false),
        onTurnStart: (sid) {
          if (isCurrent(sid)) ctx.dispatcher.onTurnStart();
          ctx.dispatcher.onSessionStatus(sid, true);
          // Agent 开跑：可能紧接着用 form 工具提问，立即对账一次
          onTurnEdge();
        },
        onTurnEnd: (sid) {
          if (isCurrent(sid)) ctx.dispatcher.onTurnEnd();
          ctx.dispatcher.onSessionStatus(sid, false);
          // 回合收尾再对账一次：拦住「最后一刻建的表单」
          onTurnEdge();
          ctx.onRefreshSessions();
        },
        onToolCall: (name, args) => ctx.dispatcher.onToolCall(name, args),
        onToolResult: ctx.dispatcher.onToolResult,
        onApproval: ({
          required String sessionId,
          required String approvalId,
          required String action,
          required List<String> resources,
          String? message,
        }) {
          ctx.dispatcher.onApproval(
            rpcId: approvalId,
            sessionId: sessionId,
            approvalId: approvalId,
            toolName: action,
            reason: OpenCodeMapper.approvalReason(resources, message),
          );
          // 事件载荷与 GET /api/permission/request 同构，再拉一次列表对账
          onApprovalEvent();
        },
        onApprovalResolved: ctx.dispatcher.onApprovalResolved,
        onUserEcho: (inboxId) async {
          // 自己刚发的消息已有乐观气泡，不重拉
          if (isOwnEcho(inboxId)) return;
          await onForeignEcho();
          await ctx.onRefreshSessions();
        },
        onSessionCreated: (_) => ctx.onRefreshSessions(),
        onSessionRenamed: (sid, title) {
          if (isCurrent(sid)) ctx.state.setSessionTitle(title);
          ctx.onRefreshSessions();
        },
        onFormResolved: ctx.dispatcher.onFormResolved,
      ),
    );
  }
}
