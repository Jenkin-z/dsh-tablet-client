import 'package:flutter/foundation.dart';

/// 跨 tab 的“打开会话”意图：控制台点某会话 → 聊天页实际切换
/// 用 token 避免重复消费同一意图。
class SessionRouter extends ChangeNotifier {
  String? _target;
  int _token = 0;
  int _consumed = 0;

  String? get target => _target;
  int get token => _token;

  void request(String sessionId) {
    _target = sessionId;
    _token++;
    notifyListeners();
  }

  /// 聊天页消费意图（幂等：同一 token 只消费一次）
  bool consume(int token) {
    if (token != _token || token == _consumed) return false;
    _consumed = token;
    return true;
  }
}
