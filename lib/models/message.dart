/// 聊天消息模型（与后端无关：DSH 与 opencode 产出同一种气泡）
class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final DateTime timestamp;
  final bool isStreaming;

  /// 本地乐观气泡：已发出但还没被后端确认。
  /// 收到确认后，本地这条会被撤掉或转为确认态。
  final bool pending;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isStreaming = false,
    this.pending = false,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? id,
    String? content,
    bool? isStreaming,
    bool? pending,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      pending: pending ?? this.pending,
    );
  }
}
