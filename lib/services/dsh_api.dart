import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// DSH Host API 客户端
///
/// 通信协议：
///   POST /api/<method>  body: { type: "client-request", rpcId, method, payload }
///   响应: { type: "server-response", rpcId, result: { ok: true/false, value/error } }
///
/// 主要方法：
///   session.list    - 列出会话
///   session.create  - 创建会话
///   session.prompt  - 发送消息
///   session.history - 读取历史
class DshApi {
  final String baseUrl;
  final _uuid = const Uuid();

  DshApi({required this.baseUrl});

  /// 发送 RPC 请求并返回 result.value（自动生成 rpcId）
  Future<Map<String, dynamic>> _rpc(String method, Map<String, dynamic> payload) {
    return _rpcWithId(method, payload, _uuid.v4());
  }

  /// 发送 RPC 请求并返回 result.value（调用方指定 rpcId，便于事件回声匹配）
  Future<Map<String, dynamic>> _rpcWithId(
      String method, Map<String, dynamic> payload, String rpcId) async {
    final body = {
      'type': 'client-request',
      'rpcId': rpcId,
      'method': method,
      'payload': payload,
    };
    final resp = await http.post(
      Uri.parse('$baseUrl/api/$method'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = data['result'] as Map<String, dynamic>;
    if (result['ok'] == true) {
      return result['value'] as Map<String, dynamic>;
    } else {
      final error = result['error'] as Map<String, dynamic>;
      throw Exception('RPC Error [${error['code']}]: ${error['message']}');
    }
  }

  /// 列出已有会话
  Future<List<Map<String, dynamic>>> listSessions() async {
    final value = await _rpc('session.list', {});
    final items = value['items'] as List<dynamic>;
    return items.cast<Map<String, dynamic>>();
  }

  /// 创建新会话，返回 sessionId；可指定归属工作区
  Future<String> createSession({String? cwd, String? agentPreset, String? workspaceId}) async {
    final payload = <String, dynamic>{};
    if (cwd != null) payload['cwd'] = cwd;
    if (agentPreset != null) payload['agentPreset'] = agentPreset;
    if (workspaceId != null) payload['workspaceId'] = workspaceId;
    final value = await _rpc('session.create', payload);
    return value['sessionId'] as String;
  }

  /// 发送 prompt，返回本次请求的 rpcId（mux 回声的 user/message 会带回它，用于去重）
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

  /// 读取历史消息，返回事件列表
  Future<Map<String, dynamic>> getHistory(String sessionId, {int? beforeSeq, int? maxMessages}) async {
    final payload = <String, dynamic>{'sessionId': sessionId};
    if (beforeSeq != null) payload['beforeSeq'] = beforeSeq;
    if (maxMessages != null) payload['maxMessages'] = maxMessages;
    return await _rpc('session.history', payload);
  }

  /// 取消当前运行的会话
  Future<bool> cancelSession(String sessionId) async {
    final value = await _rpc('session.cancel', {'sessionId': sessionId});
    return value['accepted'] == true;
  }

  /// host.describe — 用于连接检测
  Future<Map<String, dynamic>> describe() async {
    return await _rpc('host.describe', {});
  }

  /// 列出工作区：{ items: WorkspaceView[], archivedSessionIds: string[] }
  /// WorkspaceView = { workspaceId, path, title, sessionIds[], createdAt, updatedAt }
  Future<Map<String, dynamic>> listWorkspaces() async {
    return await _rpc('workspace.list', {});
  }

  /// 回答 server-request（审批/问题）：POST /api/respond
  /// body: { type: 'client-response', rpcId: 原帧rpcId, result: { ok: true, value } }
  /// 返回 accepted
  Future<bool> respond(String rpcId, Map<String, dynamic> value) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/respond'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'type': 'client-response',
        'rpcId': rpcId,
        'result': {'ok': true, 'value': value},
      }),
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) return false;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['accepted'] == true;
  }

  /// 回答审批：outcome = allowed-once（允许一次）/ rejected（拒绝）
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

  /// 回答问题：answers = [{ id, selected: [label...], custom? }]
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

  /// 测试连接是否可用
  Future<bool> testConnection() async {
    try {
      await describe();
      return true;
    } catch (_) {
      return false;
    }
  }
}