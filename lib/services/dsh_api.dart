import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../utils/constants.dart';
import 'dsh_auth.dart';

/// DSH RPC 业务错误（与 DshAuthException 区分：401/403 走 Auth，其余走此）
class DshRpcException implements Exception {
  final String code;
  final String message;
  final int httpStatus;

  const DshRpcException({
    required this.code,
    required this.message,
    this.httpStatus = 0,
  });

  @override
  String toString() => 'RPC [$code]: $message';
}

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

  /// 发一次 RPC 并解包 `result`。
  ///
  /// 公开是刻意的：ModelService 等分文件的服务复用它，
  /// 避免第二套 RPC 实现跟这里漂移（信封/鉴权/错误解包只有一份）。
  Future<Map<String, dynamic>> rpc(
    String method,
    Map<String, dynamic> args, {
    Duration? timeout,
  }) async {
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
        .timeout(timeout ?? httpTimeout);
    _throwIfAuthFailed(resp);
    if (resp.statusCode != 200) {
      throw DshRpcException(
        code: 'http/${resp.statusCode}',
        message: 'HTTP ${resp.statusCode}: ${resp.body}',
        httpStatus: resp.statusCode,
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = data['result'] as Map<String, dynamic>;
    if (result['ok'] == true) {
      return (result['value'] ?? <String, dynamic>{}) as Map<String, dynamic>;
    }
    final error = result['error'] as Map<String, dynamic>;
    throw DshRpcException(
      code: error['code'] as String? ?? 'unknown',
      message: error['message'] as String? ?? '未知错误',
      httpStatus: resp.statusCode,
    );
  }

  // ── 会话操作 ────────────────────────────────────

  Future<List<Map<String, dynamic>>> listSessions() async {
    // Host 形参名是 `_request: SessionListRequest`（下划线只是表示"保留不用"），
    // 生成客户端规则是「线上字段名 = 形参名」，所以这里**必须**是 `_request`。
    // 传 `{}` 会让 Host 参数解析失败 → 列表永远为空。
    // 依据：apps/web/tests/smoke-real.e2e.ts:755-766 的真实调用。
    final value = await rpc('session/list', {
      '_request': <String, dynamic>{},
    });
    final items = value['items'] as List<dynamic>? ?? [];
    return items.whereType<Map<String, dynamic>>().toList();
  }

  Future<String> createSession(
      {String? cwd, String? agentPreset, String? workspaceId}) async {
    final request = <String, dynamic>{};
    if (cwd != null) request['cwd'] = cwd;
    if (agentPreset != null) request['agentPreset'] = agentPreset;
    if (workspaceId != null) request['workspaceId'] = workspaceId;
    final value = await rpc('session/create', {'request': request});
    return value['sessionId'] as String;
  }

  /// 发送提示；返回用于对账的 requestId
  ///
  /// [requestId] 由调用方预先给出，这样本地乐观气泡与 durable 消息
  /// 用的是同一个 id，回显才能精确对账（而不是靠内容去重）。
  Future<String> sendPrompt(String sessionId, String text,
      {String? requestId}) async {
    final rid = requestId ?? _uuid.v4();
    await rpc('session/prompt', {
      'request': {
        'requestId': rid,
        'sessionId': sessionId,
        'mode': 'queue',
        'content': [
          {'type': 'text', 'text': text}
        ],
      },
    });
    return rid;
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
    final value = await rpc('session/page', {'request': request});
    return {
      'events': value['records'] ?? [],
      'hasMore': value['hasMore'] == true,
    };
  }

  Future<bool> cancelSession(String sessionId) async {
    final resp = await http
        .post(
          Uri.parse('$_rpcPrefix/session/cancel'),
          headers: _headers,
          body: jsonEncode({
            'type': 'client-request',
            'rpcId': _uuid.v4(),
            'method': 'session/cancel',
            'payload': {
              'args': {
                'request': {'sessionId': sessionId}
              }
            },
          }),
        )
        .timeout(cancelTimeout);
    _throwIfAuthFailed(resp);
    if (resp.statusCode != 200) {
      throw DshRpcException(
        code: 'http/${resp.statusCode}',
        message: 'HTTP ${resp.statusCode}: ${resp.body}',
        httpStatus: resp.statusCode,
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = data['result'] as Map<String, dynamic>;
    if (result['ok'] != true) {
      final error = result['error'] as Map<String, dynamic>;
      throw DshRpcException(
        code: error['code'] as String? ?? 'unknown',
        message: error['message'] as String? ?? '未知错误',
      );
    }
    final value =
        (result['value'] ?? <String, dynamic>{}) as Map<String, dynamic>;
    return value['accepted'] == true;
  }

  /// 诊断用：返回 cancel 的原始响应文本（截断）。
  Future<String> cancelSessionRaw(String sessionId) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_rpcPrefix/session/cancel'),
            headers: _headers,
            body: jsonEncode({
              'type': 'client-request',
              'rpcId': _uuid.v4(),
              'method': 'session/cancel',
              'payload': {
                'args': {
                  'request': {'sessionId': sessionId}
                }
              },
            }),
          )
          .timeout(const Duration(seconds: 8));
      return 'HTTP ${resp.statusCode} ${resp.body}';
    } catch (e) {
      return 'ERR $e';
    }
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

  // ── 新增接口（对齐 DSH 官方 Web 端） ────────────

  /// 会话搜索（全文检索历史消息内容）
  ///
  /// 返回 `{ items: [{ sessionId, snippet }], hasMore: bool }`
  Future<Map<String, dynamic>> searchSessions(String query) async {
    // 端点是 session/search，不是 session/list
    final value = await rpc('session/search', {
      'request': {'query': query},
    });
    return {
      'items': value['items'] ?? [],
      'hasMore': value['hasMore'] == true,
    };
  }

  /// 重命名会话
  ///
  /// 返回 `{ title: String, seq: int }`
  Future<Map<String, dynamic>> renameSession(
      String sessionId, String title) async {
    final value = await rpc('session/rename', {
      'request': {'sessionId': sessionId, 'title': title},
    });
    return {'title': value['title'], 'seq': value['seq']};
  }

  /// 队列管理：编辑/删除待处理消息
  ///
  /// action: { kind: 'edit', content: [...] } | { kind: 'remove' }
  Future<bool> updateQueue(
    String sessionId,
    String itemId,
    Map<String, dynamic> action,
  ) async {
    final value = await rpc('session/updateQueue', {
      'request': {
        'sessionId': sessionId,
        'itemId': itemId,
        'action': action,
      },
    });
    return value['accepted'] == true;
  }
}
