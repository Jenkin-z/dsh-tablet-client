import 'dart:convert';

import '../../models/message.dart';
import '../model_catalog.dart';

/// opencode SSE 事件 → 统一动作的接收口
///
/// 由 OpenCodeBackend 提供实现（转到 EventDispatcher / 触发重拉），
/// mapper 本身不碰任何状态，保持纯函数可单测。
class OpenCodeEventSink {
  const OpenCodeEventSink({
    required this.onTextDelta,
    required this.onAssistantFinal,
    required this.onTurnStart,
    required this.onTurnEnd,
    required this.onToolCall,
    required this.onToolResult,
    required this.onApproval,
    required this.onApprovalResolved,
    required this.onUserEcho,
    required this.onSessionCreated,
    required this.onSessionRenamed,
    required this.onFormResolved,
  });

  final void Function(String delta) onTextDelta;
  final void Function(String text) onAssistantFinal;

  /// 执行开始/结束（等价 DSH turn/start、turn/end + api-session/status）
  final void Function(String sessionId) onTurnStart;
  final void Function(String sessionId) onTurnEnd;
  final void Function(String name, String? argsJson) onToolCall;
  final void Function() onToolResult;

  /// 待审批（permission.asked / GET /api/permission/request 同构）
  final void Function({
    required String sessionId,
    required String approvalId,
    required String action,
    required List<String> resources,
    String? message,
  }) onApproval;
  final void Function(String approvalId) onApprovalResolved;

  /// 别的客户端（TUI/Web）发来的用户消息 → 需要重拉历史
  final void Function(String inboxId) onUserEcho;
  final void Function(String sessionId) onSessionCreated;
  final void Function(String sessionId, String title) onSessionRenamed;

  /// 表单被取消（`form.cancelled`，data 形如 `{id, sessionID}`）。
  ///
  /// 创建/应答经 REST 无 SSE 事件（实测），pending 的发现由
  /// OpenCodeBackend 轮询对账负责——这里只处理取消这一条推送。
  final void Function(String formId) onFormResolved;
}

/// opencode 协议 → 统一动作（纯函数）
///
/// 事件词表以真机实测为准（docs/sse-capture*.txt），帧形：
/// `{id, created?, type, location?, data, durable?}`，心跳为 `: heartbeat`。
class OpenCodeMapper {
  const OpenCodeMapper._();

  /// SSE 事件分发。未列举的事件类型（usage/step/project/model…）安全忽略。
  static void mapEvent({
    required String type,
    required Map<String, dynamic> data,
    required OpenCodeEventSink sink,
  }) {
    final sid = data['sessionID'] as String? ?? '';
    switch (type) {
      // ── 文本流（打字机） ──
      case 'session.text.delta':
        final delta = data['delta'] as String?;
        if (delta != null && delta.isNotEmpty) sink.onTextDelta(delta);
        break;
      case 'session.text.ended':
        sink.onAssistantFinal(data['text'] as String? ?? '');
        break;

      // ── 执行态（等价 DSH turn/start + api-session/status + turn/end） ──
      case 'session.execution.started':
        if (sid.isNotEmpty) sink.onTurnStart(sid);
        break;
      case 'session.execution.succeeded':
      case 'session.execution.interrupted':
      case 'session.execution.failed':
        if (sid.isNotEmpty) sink.onTurnEnd(sid);
        break;

      // ── 工具 ──
      case 'session.tool.input.started':
        sink.onToolCall(data['name'] as String? ?? 'tool', null);
        break;
      case 'session.tool.called':
        final input = data['input'];
        sink.onToolCall(
          data['name'] as String? ?? 'tool',
          input is Map ? jsonEncode(input) : null,
        );
        break;
      case 'session.tool.success':
      case 'session.tool.failed':
        sink.onToolResult();
        break;

      // ── 权限审批 ──
      case 'permission.asked':
        final id = data['id'] as String? ?? '';
        if (id.isNotEmpty) {
          sink.onApproval(
            sessionId: data['sessionID'] as String? ?? sid,
            approvalId: id,
            action: data['action'] as String? ?? 'tool',
            resources: (data['resources'] as List?)?.whereType<String>().toList() ??
                const [],
            message: data['message'] as String?,
          );
        }
        break;
      case 'permission.replied':
      case 'permission.rejected':
        final rid = data['requestID'] as String?;
        if (rid != null && rid.isNotEmpty) sink.onApprovalResolved(rid);
        break;

      // ── 用户消息（别的客户端发的） ──
      case 'session.inbox.enqueued':
        final inboxId = data['inboxID'] as String?;
        if (inboxId != null && inboxId.isNotEmpty) sink.onUserEcho(inboxId);
        break;

      // ── 会话元数据 ──
      case 'session.created':
        final id = data['sessionID'] as String?;
        if (id != null && id.isNotEmpty) sink.onSessionCreated(id);
        break;
      case 'session.renamed':
        final id = data['sessionID'] as String? ?? '';
        final title = data['title'] as String?;
        if (id.isNotEmpty && title != null && title.isNotEmpty) {
          sink.onSessionRenamed(id, title);
        }
        break;

      // ── 表单（只推取消；创建/应答无事件，靠轮询对账） ──
      case 'form.cancelled':
        final formId = data['id'] as String?;
        if (formId != null && formId.isNotEmpty) sink.onFormResolved(formId);
        break;
    }
  }

  /// `GET /api/session/{id}/message` 的 data[] → ChatMessage（调用方传 asc 序）
  ///
  /// 只产 user / assistant 两种气泡：
  /// - user：顶层 `text` 字段；
  /// - assistant：`content[]` 里 `type:text` 拼接，reasoning/tool 块跳过
  ///   （与 DSH extractContentBlocks 同一语义）；
  /// - idle / model-switched / system / skill / shell / compaction 不产气泡。
  static List<ChatMessage> messagesToChat(List<dynamic> raw) {
    final out = <ChatMessage>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final type = m['type'] as String?;
      final id = m['id'] as String? ?? '';
      if (type == 'user') {
        final text = m['text'] as String? ?? '';
        if (text.isNotEmpty) {
          out.add(ChatMessage(id: 'u-$id', role: 'user', content: text));
        }
      } else if (type == 'assistant') {
        final text = _concatText(m['content']);
        if (text.isNotEmpty) {
          out.add(ChatMessage(id: 'a-$id', role: 'assistant', content: text));
        }
      }
    }
    return out;
  }

  /// assistant content 块拼纯文本（跳过 reasoning / tool）
  static String _concatText(dynamic content) {
    if (content is! List) return '';
    final buf = StringBuffer();
    for (final part in content) {
      if (part is Map && part['type'] == 'text') {
        final t = part['text'] as String? ?? '';
        if (t.isNotEmpty) buf.write(t);
      }
    }
    return buf.toString();
  }

  /// Session.Info → 归一化会话 map（侧栏/控制台/SessionMonitor 共用）：
  /// `projections.values.title` 与 DSH 形状一致，sessionTitleOf 直接可用；
  /// `cwd` = opencode v2 的 `location.directory`（顶层没有 `directory`，
  /// 那是 v1 SDK 字段，读错会全落「未分组」）——与 DSH 会话 cwd 同义，
  /// 侧栏按它分组、列表按它显示目录名；`running` 来自 /api/session/active；
  /// `blank` = created==updated 的空会话（等价 DSH blank，见
  /// isUserFacingSession 的保留规则）。
  static Map<String, dynamic> normalizeSession(
    Map<String, dynamic> info, {
    Set<String> activeIds = const {},
  }) {
    final id = info['id'] as String? ?? '';
    final time = info['time'];
    final created = time is Map ? (time['created'] as num?)?.toInt() ?? 0 : 0;
    final updated = time is Map ? (time['updated'] as num?)?.toInt() ?? created : created;
    final title = info['title'] as String?;
    final location = info['location'];
    return {
      'sessionId': id,
      'cwd': location is Map ? location['directory'] as String? ?? '' : '',
      'projections': {
        'values': {if (title != null) 'title': title},
      },
      'updatedAt': updated,
      'running': activeIds.contains(id),
      'blank': updated <= created,
    };
  }

  /// Session.Info.model（Model.Ref）→ ModelSelection
  ///
  /// variant=default 视为「未指定档位」（reasoningEffort 传 null）。
  static ModelSelection? modelSelectionOf(dynamic modelRef) {
    if (modelRef is! Map) return null;
    final id = modelRef['id'] as String?;
    final provider = modelRef['providerID'] as String?;
    if (id == null || id.isEmpty || provider == null || provider.isEmpty) {
      return null;
    }
    final variant = modelRef['variant'] as String?;
    return ModelSelection(
      provider: provider,
      model: id,
      reasoningEffort: (variant == null || variant.isEmpty || variant == 'default')
          ? null
          : variant,
    );
  }

  /// 待审批的人类可读原因：message 优先，否则资源列表
  static String? approvalReason(List<String> resources, String? message) {
    if (message != null && message.isNotEmpty) return message;
    if (resources.isEmpty) return null;
    return resources.join('、');
  }
}
