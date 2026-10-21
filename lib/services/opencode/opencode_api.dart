import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/constants.dart';

/// opencode 授权失败（401/403：密码或配对令牌无效）
class OpenCodeAuthException implements Exception {
  final int status;
  final String message;

  const OpenCodeAuthException({required this.status, required this.message});

  @override
  String toString() => message;
}

/// opencode 业务错误（非 2xx）
class OpenCodeException implements Exception {
  final String message;
  const OpenCodeException(this.message);

  @override
  String toString() => message;
}

/// opencode v2 REST 客户端（HTTP Basic，用户名固定 `opencode`）
///
/// 协议事实以真机实测为准（docs/opencode-openapi-v2.json + sse-capture*.txt）：
/// - 全部端点在 `/api/*`（v1 文档的 `/global/*` 已废弃）；
/// - 密码 = 服务密码（OPENCODE_SERVER_PASSWORD）或配对令牌；
/// - 响应信封统一 `{data: ...}`；审批应答为 204 空响应。
class OpenCodeApi {
  final String baseUrl;

  /// Basic 密码（配对令牌或服务密码）
  final String? password;

  /// 可注入的 HTTP 客户端（单测用；不传就走 http 顶层函数）
  final http.Client? client;

  const OpenCodeApi({required this.baseUrl, this.password, this.client});

  static const _user = 'opencode';

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$_user:${password ?? ''}'))}',
      };

  Uri _u(String path, [Map<String, String>? query]) {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    return uri;
  }

  Map<String, dynamic> _unwrap(http.Response resp) {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw OpenCodeAuthException(
        status: resp.statusCode,
        message: 'opencode 授权失败：密码/令牌无效，请重新添加',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.length > 200
          ? '${resp.body.substring(0, 200)}…'
          : resp.body;
      throw OpenCodeException('HTTP ${resp.statusCode}: $body');
    }
    if (resp.body.isEmpty) return const {};
    final data = jsonDecode(resp.body);
    return data is Map<String, dynamic> ? data : const {};
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    final uri = _u(path, query);
    final c = client;
    final resp = c != null
        ? await c.get(uri, headers: _headers).timeout(timeout ?? httpTimeout)
        : await http.get(uri, headers: _headers).timeout(timeout ?? httpTimeout);
    return _unwrap(resp);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    final uri = _u(path);
    final encoded = body == null ? null : jsonEncode(body);
    final c = client;
    final resp = c != null
        ? await c
            .post(uri, headers: _headers, body: encoded)
            .timeout(timeout ?? httpTimeout)
        : await http
            .post(uri, headers: _headers, body: encoded)
            .timeout(timeout ?? httpTimeout);
    return _unwrap(resp);
  }

  // ── 会话 ────────────────────────────────────────

  /// 根会话列表（parentID=null 只取根会话；子会话 = DSH subagent 的等价物）
  Future<List<Map<String, dynamic>>> listSessions({
    int limit = 100,
    Duration? timeout,
  }) async {
    final data = await _get('/api/session',
        query: {
          'limit': '$limit',
          'parentID': 'null',
        },
        timeout: timeout);
    final items = data['data'];
    return items is List
        ? items.whereType<Map<String, dynamic>>().toList()
        : [];
  }

  /// 活跃会话 id 集合（`{data: {"ses_xxx": {type:"running"}}}`）
  Future<Set<String>> activeSessions({Duration? timeout}) async {
    final data = await _get('/api/session/active', timeout: timeout);
    final map = data['data'];
    return map is Map ? map.keys.whereType<String>().toSet() : <String>{};
  }

  Future<Map<String, dynamic>> sessionInfo(String sessionId) async {
    final data = await _get('/api/session/$sessionId');
    final info = data['data'];
    return info is Map<String, dynamic> ? info : const {};
  }

  Future<Map<String, dynamic>> createSession({
    String? cwd,
    List<Map<String, dynamic>>? permissions,
  }) async {
    final data = await _post('/api/session', body: {
      // location 决定会话落进哪个工作区；不传 = 服务端默认目录，分组就错了
      if (cwd != null && cwd.isNotEmpty) 'location': {'directory': cwd},
      if (permissions != null) 'permissions': permissions,
    });
    final info = data['data'];
    return info is Map<String, dynamic> ? info : const {};
  }

  /// 历史消息（默认 asc 序；摘要要传 order: 'desc' 取最新一页）
  Future<List<Map<String, dynamic>>> messages(String sessionId,
      {int limit = 200, String order = 'asc', Duration? timeout}) async {
    final data = await _get('/api/session/$sessionId/message',
        query: {
          'limit': '$limit',
          'order': order,
        },
        timeout: timeout);
    final items = data['data'];
    return items is List
        ? items.whereType<Map<String, dynamic>>().toList()
        : [];
  }

  /// **最近**一页消息（按时间升序返回）
  ///
  /// opencode 的 `order=asc` 是从**会话开头**往后取：会话一长（几百条），
  /// 平板就永远显示开头那批旧消息——电脑端明明在聊今天的，平板停在昨天。
  /// （摘要那条路早就踩过这个坑，见 session_source.dart。）
  ///
  /// 这里用 `order=desc` 取最新一页，再翻回升序交给上层渲染。
  Future<List<Map<String, dynamic>>> recentMessages(String sessionId,
      {int limit = 200, Duration? timeout}) async {
    final desc = await messages(sessionId,
        limit: limit, order: 'desc', timeout: timeout);
    return desc.reversed.toList();
  }

  /// 发送提示；返回服务端分配的 inbox 消息 id（回执对账用）
  Future<String> sendPrompt(String sessionId, String text) async {
    final data = await _post('/api/session/$sessionId/prompt', body: {
      'text': text,
    });
    final item = data['data'];
    final id = item is Map<String, dynamic> ? item['id'] as String? : null;
    return id ?? '';
  }

  /// 中断（对应 DSH cancel）；`{interrupted: bool}`
  Future<bool> interrupt(String sessionId) async {
    final data = await _post('/api/session/$sessionId/interrupt');
    return data['interrupted'] == true;
  }

  // ── 模型 ────────────────────────────────────────

  /// 模型目录（`data[]`，每条含 providerID/id/name/variants[]）
  Future<List<Map<String, dynamic>>> modelCatalog() async {
    final data = await _get('/api/model');
    final items = data['data'];
    return items is List
        ? items.whereType<Map<String, dynamic>>().toList()
        : [];
  }

  /// 切换会话模型（语义 = 对后续轮次生效，与 DSH 投影 next 一致）
  Future<void> selectModel(
    String sessionId, {
    required String id,
    required String providerID,
    String? variant,
  }) async {
    await _post('/api/session/$sessionId/model', body: {
      'model': {
        'id': id,
        'providerID': providerID,
        if (variant != null) 'variant': variant,
      },
    });
  }

  // ── 权限审批 ────────────────────────────────────

  /// 待审批列表（与 permission.asked 事件载荷同构）
  Future<List<Map<String, dynamic>>> permissionRequests() async {
    final data = await _get('/api/permission/request');
    final items = data['data'];
    return items is List
        ? items.whereType<Map<String, dynamic>>().toList()
        : [];
  }

  /// 审批应答：once | always | reject（实测 204 后会话恢复执行）
  Future<bool> replyPermission(
    String sessionId,
    String requestId,
    String decision,
  ) async {
    final resp = await http
        .post(
          _u('/api/session/$sessionId/permission/$requestId/reply'),
          headers: _headers,
          body: jsonEncode({'decision': decision}),
        )
        .timeout(httpTimeout);
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const OpenCodeAuthException(
        status: 401,
        message: 'opencode 授权失败：密码/令牌无效，请重新添加',
      );
    }
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  // ── 配对 ────────────────────────────────────────

  /// 授权链接换令牌：`GET {base}/auth/connect/{code}` → `{token}`
  Future<String> exchangePairCode(String code) async {
    final data = await _get('/auth/connect/$code');
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const OpenCodeException('配对响应里没有 token');
    }
    return token;
  }

  /// 连通性测试（授权失败会上抛，其余返回 false）
  Future<bool> testConnection() async {
    try {
      await listSessions(limit: 1);
      return true;
    } on OpenCodeAuthException {
      rethrow;
    } catch (_) {
      return false;
    }
  }
}
