import '../models/message.dart';

/// 会话空闲启发式（与后端无关）：依据消息流尾部判定「服务端其实已经收尾」
///
/// 背景（借鉴 opencode-mobile 对同类 bug 的修复）：运行态是事件驱动的，
/// 断线期间 busy→idle 事件丢失后，SSE/WebSocket 重连只从「现在」续传、
/// 不重放历史 —— 本地就会永久卡在进行中。
///
/// 规则（方向性单向，勿破坏）：
/// - 只有「最后一条是 assistant 且已定稿（非流式、非乐观）」才判空闲；
/// - 最后一条是 user（还在等回复）或 assistant 仍在流式 → 可能还在跑，
///   一律返回 false；
/// - **只允许调用方据此清除 stale busy，绝不允许反向据它把会话置 busy** ——
///   真在跑的会话永远不会被这条启发式误伤成「进行中」。
bool isSessionActuallyIdle(List<ChatMessage> messages) {
  if (messages.isEmpty) return false;
  final last = messages.last;
  if (last.role != 'assistant') return false;
  return !last.isStreaming && !last.pending;
}
