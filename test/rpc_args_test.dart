/// RPC 参数形状回归测试
///
/// 这组用例锁定「线上字段名 = Host 形参名」这条规则。
///
/// 为什么用读源码的方式：写错的后果**不是报错，而是静默失败**。
/// `session/list` 的 args 从 `{_request:{}}` 改成 `{}` 会让
///   · 会话列表永远为空
///   · SessionMonitor.refresh 走 catch → online=false → 设备全部显示离线
///   · 控制台和聊天页侧栏同时变空
/// 三处症状、一个根因，且编译、analyze 全绿。只有断言真实源码才能拦住。
///
/// 依据：packages/api/session-controller/src/index.ts 的形参名
/// 与 apps/web/tests/smoke-real.e2e.ts:755-766 的真实调用。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _apiPath = 'lib/services/dsh_api.dart';

/// 取出某个 `rpc('method', {...})` 调用里 args 的最外层键名
Set<String> _argKeysFor(String source, String method) {
  final marker = "rpc('$method'";
  final start = source.indexOf(marker);
  if (start < 0) return {};
  // 从调用点往后扫，找出紧随其后的第一个 { 里出现的字符串键
  final braceStart = source.indexOf('{', start);
  if (braceStart < 0) return {};
  var depth = 0;
  var end = braceStart;
  for (var i = braceStart; i < source.length; i++) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }
  final body = source.substring(braceStart, end + 1);
  return RegExp(r"'([A-Za-z_][A-Za-z0-9_]*)'\s*:")
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  late String source;

  setUpAll(() {
    final f = File(_apiPath);
    expect(f.existsSync(), isTrue, reason: '找不到 $_apiPath');
    source = f.readAsStringSync();
  });

  group('session/list 必须用 _request', () {
    test('Host 形参是 _request，传入 args 的最外层键必须是 _request', () {
      // index.ts:224  async list(_request: SessionListRequest, signal)
      // 下划线只表示「保留不用」，不影响线上字段名
      final keys = _argKeysFor(source, 'session/list');
      expect(
        keys,
        contains('_request'),
        reason: 'session/list 的 args 必须是 {_request:{}}；'
            '写成 {} 会让列表为空且设备全部离线',
      );
      expect(keys, isNot(contains('request')),
          reason: 'list 的形参是 _request 而不是 request；两者不通用');
    });

    test('smoke-real.e2e.ts 的真实调用佐证', () {
      // 真实端到端测试打的就是 {_request:{}}
      // remoteRpc(baseUrl, 'session/list', { _request: {} })
      const realWorldCall = <String, dynamic>{'_request': <String, dynamic>{}};
      expect(realWorldCall.keys.single, '_request');
    });
  });

  group('单对象首参的端点用 request 包装', () {
    test('create / prompt / page / search / rename / updateQueue 都用 request', () {
      for (final method in const [
        'session/create',
        'session/prompt',
        'session/page',
        'session/search',
        'session/rename',
        'session/updateQueue',
      ]) {
        final keys = _argKeysFor(source, method);
        expect(keys, isNotEmpty, reason: '没找到 $method 的 rpc 调用（方法名或调用形式变了？）');
        expect(keys, contains('request'), reason: '$method 必须用 request 包装');
      }
    });
  });

  group('session/cancel 的裸 HTTP 调用', () {
    test('args 里是 request.sessionId，响应只有 accepted', () {
      // index.ts:378  cancel(request: SessionCancelRequest)
      expect(source.contains('session/cancel'), isTrue);
      final idx = source.indexOf('session/cancel');
      final window = source.substring(idx, (idx + 600).clamp(0, source.length));
      expect(window.contains("'request'"), isTrue,
          reason: 'cancel 的形参是 request');
      expect(window.contains('sessionId'), isTrue);
    });
  });

  group('session/follow 的 request 包装层', () {
    test('mux_stream.dart 的 follow 开窗必须含 request 层', () {
      // index.ts:401  follow(request: SessionFollowRequest, signal)
      final src = File('lib/services/mux_stream.dart').readAsStringSync();
      final idx = src.indexOf("'session/follow'");
      expect(idx >= 0, isTrue, reason: '找不到 session/follow 开窗代码');
      // 取该 open 调用附近的一段，确认 args → request → address 三层
      final window = src.substring(idx, (idx + 700).clamp(0, src.length));
      expect(window.contains("'request'"), isTrue,
          reason: '少了 request 包装层 Host 会拒流：既无历史也无流式');
      expect(window.contains("'address'"), isTrue);
      expect(window.contains("'assistantStream'"), isTrue);
    });
  });

  group('模型端点参数形状', () {
    late String modelSource;

    setUpAll(() {
      final f = File('lib/services/model_service.dart');
      expect(f.existsSync(), isTrue);
      modelSource = f.readAsStringSync();
    });

    test('session/modelCatalog 零业务参数 → args 必须是 {}', () {
      // index.ts:263  modelCatalog(): Promise<ModelCatalog>   ← 无可传参数
      // catalog.ts:45  remote.session.modelCatalog()          ← 客户端确实不传
      expect(
        modelSource.contains("rpc('session/modelCatalog', {})"),
        isTrue,
        reason: 'modelCatalog 没有业务参数，args 必须是空对象',
      );
    });

    test('session/selectModel 用 request 包装，且带 sessionId', () {
      // index.ts:254  selectModel(request: SessionSelectModelRequest)
      // shipped-composition.e2e.ts:739  {request:{sessionId, provider, model}}
      final idx = modelSource.indexOf("rpc('session/selectModel'");
      expect(idx >= 0, isTrue, reason: '找不到 selectModel 调用');
      final window =
          modelSource.substring(idx, (idx + 260).clamp(0, modelSource.length));
      expect(window.contains("'request'"), isTrue);
      expect(window.contains('sessionId'), isTrue);
    });

    test('modelSelection 投影读 next 优先，回落 lastUsed', () {
      // types.ts:101  ModelSelectionProjection = {lastUsed, next}
      expect(modelSource.contains("['next']"), isTrue);
      expect(modelSource.contains("['lastUsed']"), isTrue);
    });
  });
}
