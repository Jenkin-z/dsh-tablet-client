/// DSH 消息模型
class DshMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final DateTime timestamp;
  final bool isStreaming;

  /// 本地乐观气泡：已发出但还没被 Host 的 durable user/message 确认。
  /// 收到带同一 rpcId 的 durable 消息后，本地这条会被撤掉。
  final bool pending;

  DshMessage({
    required this.id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isStreaming = false,
    this.pending = false,
  }) : timestamp = timestamp ?? DateTime.now();

  DshMessage copyWith({
    String? id,
    String? content,
    bool? isStreaming,
    bool? pending,
  }) {
    return DshMessage(
      id: id ?? this.id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      pending: pending ?? this.pending,
    );
  }
}
