import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../utils/constants.dart';
import 'dsh_auth.dart';

part 'dsh_api_sessions.dart';
part 'dsh_api_cancel.dart';
part 'dsh_api_extras.dart';

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

/// 库内共享宿主：声明 API 客户端各分片（mixin）依赖的字段与方法，
/// 本身不对外暴露。[DshApi] 继承它并混入各职责分片。
///
/// 注意：分片用 `mixin X on _DshApiCore` 挂载，**不能**写成
/// `on DshApi` —— 那会让 mixin 与宿主类互为超接口，
/// Dart 直接报 recursive_interface_inheritance。
abstract class _DshApiCore {
  final String baseUrl;

  /// "dsh-auth-xxx=value"；为空时请求会得到 401
  final String? cookie;
  final _uuid = const Uuid();

  _DshApiCore({required this.baseUrl, this.cookie});

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
}

/// DSH 原生 Host API 客户端
///
/// POST /api/<method> + Cookie: dsh-auth-*=...（browser-session，约 30 天）
/// 信封：{type:'client-request',rpcId,method:'session/list',payload:{args:{...}}}
/// args 按形参名传参：list 用 {_request:...}，其余用 {request:...}
///
/// 按职责拆分（part 文件，同库共享私有作用域，对外 API 不变）：
/// - dsh_api_sessions.dart：会话列表/创建/发送/历史分页
/// - dsh_api_cancel.dart：取消会话 + 连通性探测
/// - dsh_api_extras.dart：搜索/重命名/队列管理
class DshApi extends _DshApiCore
    with DshApiSessions, DshApiCancel, DshApiExtras {
  DshApi({required super.baseUrl, super.cookie});
}
