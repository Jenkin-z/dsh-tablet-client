import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/constants.dart';
import 'opencode_api.dart';

/// opencode 表单 REST 客户端（Agent form 工具提问；DSH question 的对应物）
///
/// 协议事实以真机实测为准（v2.0.32，与 openapi 有出入）：
/// - 列表 GET /api/session/{sid}/form 只回 Form.Info，**不含 state**——
///   pending/answered/cancelled 要逐个 GET detail 才知道；
/// - SSE 只推 form.cancelled；创建/应答**无事件**——发现 pending 只能靠
///   轮询对账（OpenCodeReconciler.reconcileForms）；
/// - 重复应答：Agent 建的 form 回 409 FormAlreadySettledError，API 客户端
///   建的幂等回 204——两者都算「已解决」；
/// - 缺必填字段回 400 FormInvalidAnswerError（message 可直显）；
/// - formID 不存在回 404——同样按「已消失」处理。
class OpenCodeFormApi {
  final String baseUrl;
  final String? password;

  const OpenCodeFormApi({required this.baseUrl, this.password});

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

  void _checkAuth(http.Response resp) {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const OpenCodeAuthException(
        status: 401,
        message: 'opencode 授权失败：密码/令牌无效，请重新添加',
      );
    }
  }

  /// 会话表单列表（Form.Info：id/sessionID/title/metadata/fields，无 state）
  Future<List<Map<String, dynamic>>> listForms(String sessionId) async {
    final resp = await http
        .get(_u('/api/session/$sessionId/form'), headers: _headers)
        .timeout(httpTimeout);
    _checkAuth(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw OpenCodeException('HTTP ${resp.statusCode}: ${resp.body}');
    }
    if (resp.body.isEmpty) return const [];
    final data = jsonDecode(resp.body);
    final items = data is Map ? data['data'] : null;
    return items is List ? items.whereType<Map<String, dynamic>>().toList() : [];
  }

  /// 表单详情（Form.Detail，含 `state:{status: pending|answered|cancelled}`）
  Future<Map<String, dynamic>> formDetail(
    String sessionId,
    String formId,
  ) async {
    final resp = await http
        .get(_u('/api/session/$sessionId/form/$formId'), headers: _headers)
        .timeout(httpTimeout);
    _checkAuth(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw OpenCodeException('HTTP ${resp.statusCode}: ${resp.body}');
    }
    if (resp.body.isEmpty) return const {};
    final data = jsonDecode(resp.body);
    final info = data is Map ? data['data'] : null;
    return info is Map<String, dynamic> ? info : const {};
  }

  /// 应答表单。返回 true = 已提交；false = 已被解决（409/404，本地移除即可）。
  /// 答案不合法（400）上抛 [OpenCodeException]，message 来自服务端。
  Future<bool> replyForm(
    String sessionId,
    String formId,
    Map<String, dynamic> answer,
  ) async {
    final resp = await http
        .post(
          _u('/api/session/$sessionId/form/$formId/reply'),
          headers: _headers,
          body: jsonEncode({'answer': answer}),
        )
        .timeout(httpTimeout);
    _checkAuth(resp);
    if (resp.statusCode == 409 || resp.statusCode == 404) {
      // 别人已应答 / 表单已消失：都按已解决处理
      return false;
    }
    if (resp.statusCode == 400) {
      throw OpenCodeException(
          _errorMessage(resp.body, '答案不完整或有字段不合法'));
    }
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  /// 取消表单（放弃回答），`message` 告诉 Agent 为什么没答
  Future<bool> cancelForm(
    String sessionId,
    String formId, {
    String? message,
  }) async {
    final resp = await http
        .delete(
          _u('/api/session/$sessionId/form/$formId', {
            if (message != null && message.isNotEmpty) 'message': message,
          }),
          headers: _headers,
        )
        .timeout(httpTimeout);
    _checkAuth(resp);
    // 404：表单已自己消失；409：已 settled——都无需再管
    return resp.statusCode >= 200 && resp.statusCode < 300 ||
        resp.statusCode == 404 ||
        resp.statusCode == 409;
  }

  /// 从错误响应体里提取服务端 message（opencode 错误信封 `{_tag, message}`）
  String _errorMessage(String body, String fallback) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
    } catch (_) {
      // 非 JSON 错误体，用兜底文案
    }
    return fallback;
  }
}
