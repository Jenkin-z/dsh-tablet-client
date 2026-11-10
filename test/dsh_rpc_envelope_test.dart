/// DSH RPC 响应信封契约测试
///
/// 锁定 fail-closed 解包：任何形状异常（非法 JSON、缺 result、
/// value/error 类型不对）都必须转成带明确 code 的 DshRpcException，
/// 绝不让 TypeError / FormatException 裸穿到业务层。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/services/dsh/dsh_api.dart';

void main() {
  group('unwrapRpcEnvelope 契约', () {
    test('ok=true 带 value → 返回 value', () {
      final v = unwrapRpcEnvelope(
        '{"result":{"ok":true,"value":{"id":"s1","n":2}}}',
        httpStatus: 200,
      );
      expect(v, {'id': 's1', 'n': 2});
    });

    test('ok=true 无 value → 空 Map', () {
      final v = unwrapRpcEnvelope('{"result":{"ok":true}}', httpStatus: 200);
      expect(v, isEmpty);
    });

    test('ok=false + error → 抛 DshRpcException，携带 code/message/httpStatus', () {
      expect(
        () => unwrapRpcEnvelope(
          '{"result":{"ok":false,"error":{"code":"session/not-found","message":"没有这个会话"}}}',
          httpStatus: 200,
        ),
        throwsA(isA<DshRpcException>()
            .having((e) => e.code, 'code', 'session/not-found')
            .having((e) => e.message, 'message', '没有这个会话')
            .having((e) => e.httpStatus, 'httpStatus', 200)),
      );
    });

    test('非法 JSON → malformed/json，不是 FormatException', () {
      expect(
        () => unwrapRpcEnvelope('{oops', httpStatus: 200),
        throwsA(isA<DshRpcException>()
            .having((e) => e.code, 'code', 'malformed/json')),
      );
    });

    test('信封不是对象（数组/字符串）→ malformed/envelope', () {
      expect(
        () => unwrapRpcEnvelope('[1,2,3]', httpStatus: 200),
        throwsA(isA<DshRpcException>()
            .having((e) => e.code, 'code', 'malformed/envelope')),
      );
      expect(
        () => unwrapRpcEnvelope('"hello"', httpStatus: 200),
        throwsA(isA<DshRpcException>()
            .having((e) => e.code, 'code', 'malformed/envelope')),
      );
    });

    test('缺 result / result 非对象 → malformed/result', () {
      expect(
        () => unwrapRpcEnvelope('{"other":1}', httpStatus: 200),
        throwsA(isA<DshRpcException>()
            .having((e) => e.code, 'code', 'malformed/result')),
      );
      expect(
        () => unwrapRpcEnvelope('{"result":"ok"}', httpStatus: 200),
        throwsA(isA<DshRpcException>()
            .having((e) => e.code, 'code', 'malformed/result')),
      );
    });

    test('ok=true 但 value 不是对象 → malformed/value', () {
      expect(
        () => unwrapRpcEnvelope(
          '{"result":{"ok":true,"value":[1,2]}}',
          httpStatus: 200,
        ),
        throwsA(isA<DshRpcException>()
            .having((e) => e.code, 'code', 'malformed/value')),
      );
    });

    test('ok=false 但缺 error → malformed/error', () {
      expect(
        () => unwrapRpcEnvelope('{"result":{"ok":false}}', httpStatus: 200),
        throwsA(isA<DshRpcException>()
            .having((e) => e.code, 'code', 'malformed/error')),
      );
    });

    test('error 字段类型异常 → code 降级 unknown，不抛 TypeError', () {
      expect(
        () => unwrapRpcEnvelope(
          '{"result":{"ok":false,"error":{"code":123,"message":true}}}',
          httpStatus: 502,
        ),
        throwsA(isA<DshRpcException>()
            .having((e) => e.code, 'code', 'unknown')
            .having((e) => e.message, 'message', '未知错误')
            .having((e) => e.httpStatus, 'httpStatus', 502)),
      );
    });
  });
}
