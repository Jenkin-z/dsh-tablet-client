import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'dsh_auth.dart';

/// DSH Host API 客户端
///
/// 已配对：POST /remote/api/<method> + 头 X-DSH-Remote-Device
/// 未配对老 DSH：POST /api/<method>
class DshApi {
  final String baseUrl;
  final String? deviceId;
  final _uuid = const Uuid();

  DshApi({required this.baseUrl, this.deviceId});

  bool get _remote => deviceId != null && deviceId!.isNotEmpty;

  String get _rpcPrefix => _remote ? '$baseUrl/remote/api' : '$baseUrl/api';

  Map<String, String> get _headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_remote) {
      h['X-DSH-Remote-Device'] = deviceId!;
      h['Cookie'] = '${PairingClient.cookieName}=$deviceId';
    }
    return h;
  }

  void _throwIfAuthFailed(http.Response resp) {
    if (resp.statusCode != 401 && resp.statusCode != 403) return;
    var unpaired = resp.statusCode == 403;
    try {
      final data = jsonDecode(resp.body);
      if (data is Map) {
        final err = data['result'] is Map ? data['result']['error'] : data['error'];
        final code = err is Map ? err['code'] as String? : data['code'] as String?;
        if (code == 'unpaired') unpaired = true;
      }
    } catch (_) {}
    throw DshAuthException(
      status: resp.statusCode,
      unpaired: unpaired,
      message: unpaired ? '配对已失效，需要重新扫码' : '需要鉴权（HTTP ${resp.statusCode}）',
    );
  }

  Future<Map<String, dynamic>> _rpc(
      String method, Map<String, dynamic> payload) {
    return _rpcWithId(method, payload, _uuid.v4());
  }

  Future<Map<String, dynamic>> _rpcWithId(
      String method, Map<String, dynamic> payload, String rpcId) async {
    final body = {
      'type': 'client-request',
      'rpcId': rpcId,
      'method': method,
      'payload': payload,
    };
    final resp = await http
        .post(
          Uri.parse('$_rpcPrefix/$method'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    _throwIfAuthFailed(resp);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = data['result'] as Map<String, dynamic>;
    if (result['ok'] == true) {
      return result['value'] as Map<String, dynamic>;
    }
    final error = result['error'] as Map<String, dynamic>;
    throw Exception('RPC Error [${error['code']}]: ${error['message']}');
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    final value = await _rpc('session.list', {});
    final items = value['items'] as List<dynamic>;
    return items.cast<Map<String, dynamic>>();
  }

  Future<String> createSession(
      {String? cwd, String? agentPreset, String? workspaceId}) async {
    final payload = <String, dynamic>{};
    if (cwd != null) payload['cwd'] = cwd;
    if (agentPreset != null) payload['agentPreset'] = agentPreset;
    if (workspaceId != null) payload['workspaceId'] = workspaceId;
    final value = await _rpc('session.create', payload);
    return value['sessionId'] as String;
  }

  Future<String> sendPrompt(String sessionId, String text) async {
    final rpcId = _uuid.v4();
    final value = await _rpcWithId('session.prompt', {
      'sessionId': sessionId,
      'mode': 'queue',
      'content': [
        {'type': 'text', 'text': text}
      ],
    }, rpcId);
    if (value['accepted'] != true) {
      throw Exception('prompt 未被接受');
    }
    return rpcId;
  }

  Future<Map<String, dynamic>> getHistory(String sessionId,
      {int? beforeSeq, int? maxMessages}) async {
    final payload = <String, dynamic>{'sessionId': sessionId};
    if (beforeSeq != null) payload['beforeSeq'] = beforeSeq;
    if (maxMessages != null) payload['maxMessages'] = maxMessages;
    return await _rpc('session.history', payload);
  }

  Future<bool> cancelSession(String sessionId) async {
    final value = await _rpc('session.cancel', {'sessionId': sessionId});
    return value['accepted'] == true;
  }

  Future<Map<String, dynamic>> describe() async {
    return await _rpc('host.describe', {});
  }

  Future<Map<String, dynamic>> listWorkspaces() async {
    return await _rpc('workspace.list', {});
  }

  Future<bool> respond(String rpcId, Map<String, dynamic> value) async {
    final resp = await http
        .post(
          Uri.parse('$_rpcPrefix/respond'),
          headers: _headers,
          body: jsonEncode({
            'type': 'client-response',
            'rpcId': rpcId,
            'result': {'ok': true, 'value': value},
          }),
        )
        .timeout(const Duration(seconds: 30));
    _throwIfAuthFailed(resp);
    if (resp.statusCode != 200) return false;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['accepted'] == true;
  }

  Future<bool> answerApproval({
    required String rpcId,
    required String sessionId,
    required String approvalId,
    required bool allow,
  }) {
    return respond(rpcId, {
      'sessionId': sessionId,
      'approvalId': approvalId,
      'outcome': allow ? 'allowed-once' : 'rejected',
    });
  }

  Future<bool> answerQuestion({
    required String rpcId,
    required String sessionId,
    required List<Map<String, dynamic>> answers,
  }) {
    return respond(rpcId, {
      'sessionId': sessionId,
      'answer': {'answers': answers},
    });
  }

  Future<bool> testConnection() async {
    try {
      await describe();
      return true;
    } on DshAuthException {
      rethrow;
    } catch (_) {
      return false;
    }
  }
}
