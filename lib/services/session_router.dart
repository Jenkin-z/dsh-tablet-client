import 'package:flutter/foundation.dart';

/// 跨 tab 打开会话：控制台 → 对话页。主键是 (serverId, sessionId)。
class SessionRouter extends ChangeNotifier {
  String? _serverId;
  String? _sessionId;
  int _token = 0;
  int _consumed = 0;

  String? get serverId => _serverId;
  String? get sessionId => _sessionId;
  int get token => _token;

  void request(String serverId, String sessionId) {
    _serverId = serverId;
    _sessionId = sessionId;
    _token++;
    notifyListeners();
  }

  bool consume(int token) {
    if (token != _token || token == _consumed) return false;
    _consumed = token;
    return true;
  }
}
