import 'package:flutter/foundation.dart';

/// 切换「当前机器 / 当前会话」的唯一入口
///
/// 背景：ChatScreen 的 key 是 `ValueKey(activeServerId)`，
/// 所以改 activeServerId 本身就会重建对话页并重新 boot()。
/// 如果在改完 activeServerId 之后**再**去请求一次会话切换，
/// 同一件事就做了两遍，必然产生竞态（表现为「有时进对话有时不进」）。
///
/// 因此这里把两者合并成一次原子请求：
/// 调用方说明「目标机器 + 目标会话」，由 ChatScreen 在重建后消费一次。
class SessionRouter extends ChangeNotifier {
  String? _serverId;
  String? _sessionId;
  int _token = 0;
  int _consumed = 0;

  String? get serverId => _serverId;
  String? get sessionId => _sessionId;
  int get token => _token;

  /// 请求切到 [serverId] 的 [sessionId]。
  ///
  /// [sessionId] 为 null 表示「只切机器，会话沿用该机器上次用的」。
  void request(String serverId, String? sessionId) {
    _serverId = serverId;
    _sessionId = sessionId;
    _token++;
    notifyListeners();
  }

  /// 取走本次请求（每个 token 只消费一次）
  bool consume(int token) {
    if (token != _token || token == _consumed) return false;
    _consumed = token;
    return true;
  }
}
