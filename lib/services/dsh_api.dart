import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'dsh_auth.dart';

/// DSH 原生 Host API 客户端
///
/// POST /api/<method> + Cookie: dsh-auth-*=...（browser-session，约 30 天）
/// 信封：{type:'client-request',rpcId,method:'session/list',payload:{args:{...}}}
/// args 按形参名传参：list 用 {_request:...}，其余用 {request:...}
class DshApi {
  final String baseUrl;

  /// "dsh-auth-xxx=value"；为空时请求会得到 401
  final String? cookie;
  final _uuid = const Uuid();

  DshApi({required this.baseUrl, this.cookie});

  String get _rpcPrefix => '$baseUrl/api';

  Map<String, String> get _headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (cookie != null && cookie!.isNotEmpty) {
      h['Cookie'] = cookie!;
    }
    return h;
  }

  void _throwIfAuthFailed(http.Response resp) {
    if (resp.statusCode != 401 && resp.statusCode != 403) return;
    final unpaired = resp.statusCode == 401;
    throw DshAuthException(
      status: resp.statusCode,
      unpaired: unpaired,
      message: unpaired
          ? '授权已过期或缺失（约 30 天有效），请重新用启动令牌换取'
          : '请求被拒绝（HTTP 403）',
    );
  }

  Future<Map<String, dynamic>> _rpc(
      String method, Map<String, dynamic> args) async {
    final resp = await http
        .post(
          Uri.parse('$_rpcPrefix/$method'),
          headers: _headers,
          body: jsonEncode({
            'type': 'client-request',
            'rpcId': _uuid.v4(),
            'method': method,
            'payload': {'args': args},
          }),
        )
        .timeout(const Duration(seconds: 30));
    _throwIfAuthFailed(resp);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = data['result'] as Map<String, dynamic>;
    if (result['ok'] == true) {
      return (result['value'] ?? <String, dynamic>{}) as Map<String, dynamic>;
    }
    final error = result['error'] as Map<String, dynamic>;
    throw Exception('RPC Error [${error['code']}]: ${error['message']}');
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    final value = await _rpc('session/list', {'_request': {}});
    final items = value['items'] as List<dynamic>? ?? [];
    return items.whereType<Map<String, dynamic>>().toList();
  }

  Future<String> createSession(
      {String? cwd, String? agentPreset, String? workspaceId}) async {
    final request = <String, dynamic>{};
    if (cwd != null) request['cwd'] = cwd;
    if (agentPreset != null) request['agentPreset'] = agentPreset;
    if (workspaceId != null) request['workspaceId'] = workspaceId;
    final value = await _rpc('session/create', {'request': request});
    return value['sessionId'] as String;
  }

  /// 发送提示；返回客户端自生成的 requestId（与 durable user/message 源对账）
  Future<String> sendPrompt(String sessionId, String text) async {
    final requestId = _uuid.v4();
    await _rpc('session/prompt', {
      'request': {
        'requestId': requestId,
        'sessionId': sessionId,
        'mode': 'queue',
        'content': [
          {'type': 'text', 'text': text}
        ],
      },
    });
    return requestId;
  }

  /// 历史分页；throughSeq=null 表示空截断（仅探测会话存在）
  Future<Map<String, dynamic>> getHistory(String sessionId,
      {int? throughSeq, int? beforeSeq, int? maxMessages}) async {
    final request = <String, dynamic>{
      'address': {'kind': 'session', 'sessionId': sessionId},
      'throughSeq': throughSeq ?? -1,
      if (beforeSeq != null) 'beforeSeq': beforeSeq,
      if (maxMessages != null) 'maxMessages': maxMessages,
    };
    final value = await _rpc('session/page', {'request': request});
    return {
      'events': value['records'] ?? [],
      'hasMore': value['hasMore'] == true,
    };
  }

  Future<bool> cancelSession(String sessionId) async {
    final value = await _rpc('session/cancel',
        {'request': {'sessionId': sessionId}});
    return value['accepted'] == true;
  }

  Future<bool> testConnection() async {
    try {
      await listSessions();
      return true;
    } on DshAuthException {
      rethrow;
    } catch (_) {
      return false;
    }
  }
}
