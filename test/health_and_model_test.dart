/// 健康度判定 + 模型目录/投影解析回归测试
///
/// 锁定的两个「会骗人」的点：
/// 1. 状态点只代表 socket 通 → 列表失败时仍显绿（历史 bug）
/// 2. 模型选择投影解析错 → 重连后模型显示回默认值
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/models/connection_health.dart';
import 'package:dsh_tablet_client/services/dsh_session_state.dart';
import 'package:dsh_tablet_client/services/model_service.dart';

void main() {
  group('连接健康度四态', () {
    late DshSessionState state;

    setUp(() => state = DshSessionState());

    test('初始：未连接 → offline', () {
      expect(state.health, ConnectionHealth.offline);
    });

    test('连接中 → connecting（优先于其它）', () {
      state.setConnecting(true);
      expect(state.health, ConnectionHealth.connecting);
    });

    test('连上且列表成功 → healthy', () {
      state.setConnected(true);
      state.setSessionsHealth(ok: true);
      expect(state.health, ConnectionHealth.healthy);
      expect(state.degraded, isFalse);
    });

    test('连上但列表失败 → degraded，绝不再是绿色', () {
      state.setConnected(true);
      state.setSessionsHealth(ok: false, error: '会话列表读取失败');
      expect(state.health, ConnectionHealth.degraded);
      expect(state.degraded, isTrue);
      expect(state.sessionsError, '会话列表读取失败');
    });

    test('还没拉过列表时不算降级（不能一上线就报警）', () {
      state.setConnected(true);
      expect(state.sessionsOk, isNull);
      // 「没验证过」= 连接中（橙），不是 degraded（也不是 healthy）。
      // 这条曾经断言 healthy，那正是「状态点一直绿」这个 bug 的一部分：
      // socket 一连上、第一次列表还没回来就报绿。
      expect(state.health, ConnectionHealth.connecting);
      expect(state.degraded, isFalse, reason: '没验证过 ≠ 降级，不该报警');
    });

    test('断线优先于降级 → offline', () {
      state.setConnected(true);
      state.setSessionsHealth(ok: false, error: 'x');
      state.setConnected(false);
      expect(state.health, ConnectionHealth.offline);
    });

    test('恢复成功会清掉错误原因', () {
      state.setConnected(true);
      state.setSessionsHealth(ok: false, error: 'x');
      state.setSessionsHealth(ok: true);
      expect(state.sessionsError, isNull);
      expect(state.health, ConnectionHealth.healthy);
    });

    test('reset 清空健康度', () {
      state.setConnected(true);
      state.setSessionsHealth(ok: false, error: 'x');
      state.reset();
      expect(state.sessionsOk, isNull);
      expect(state.sessionsError, isNull);
      expect(state.health, ConnectionHealth.offline);
    });
  });

  group('ModelSelection 解析与比较', () {
    test('从投影读 next 优先于 lastUsed', () {
      final sel = ModelService.selectionFromProjection({
        'lastUsed': {'provider': 'a', 'model': 'old'},
        'next': {'provider': 'b', 'model': 'new', 'reasoningEffort': 'high'},
      });
      expect(sel!.provider, 'b');
      expect(sel.model, 'new');
      expect(sel.reasoningEffort, 'high');
    });

    test('next 为空时回落到 lastUsed', () {
      final sel = ModelService.selectionFromProjection({
        'lastUsed': {'provider': 'a', 'model': 'used'},
        'next': null,
      });
      expect(sel!.model, 'used');
      expect(sel.reasoningEffort, isNull);
    });

    test('两个都空 → null', () {
      expect(
        ModelService.selectionFromProjection({'lastUsed': null, 'next': null}),
        isNull,
      );
      expect(ModelService.selectionFromProjection(null), isNull);
      expect(ModelService.selectionFromProjection('nonsense'), isNull);
    });

    test('sameAs 比较三个字段', () {
      const a = ModelSelection(provider: 'p', model: 'm', reasoningEffort: 'h');
      expect(a.sameAs(const ModelSelection(provider: 'p', model: 'm', reasoningEffort: 'h')), isTrue);
      expect(a.sameAs(const ModelSelection(provider: 'p', model: 'm')), isFalse);
      expect(a.sameAs(const ModelSelection(provider: 'p', model: 'x', reasoningEffort: 'h')), isFalse);
      expect(a.sameAs(null), isFalse);
    });

    test('payload 会带上 reasoningEffort，缺省则整个键省略', () {
      const withEffort =
          ModelSelection(provider: 'p', model: 'm', reasoningEffort: 'low');
      expect(withEffort.toJson()['reasoningEffort'], 'low');
      const without = ModelSelection(provider: 'p', model: 'm');
      expect(without.toJson().containsKey('reasoningEffort'), isFalse);
    });
  });

  group('CatalogModel 解析推理档位', () {
    test('解析 efforts 与 defaultEffort', () {
      final m = CatalogModel.fromJson({
        'id': 'gpt-x',
        'name': 'GPT-X',
        'description': '示例',
        'reasoning': {
          'defaultEffort': 'medium',
          'efforts': [
            {'id': 'low', 'name': '低'},
            {'id': 'medium', 'name': '中'},
          ],
        },
      });
      expect(m.id, 'gpt-x');
      expect(m.hasEfforts, isTrue);
      expect(m.efforts.length, 2);
      expect(m.defaultEffort, 'medium');
      expect(m.efforts[0].name, '低');
    });

    test('没有 reasoning 字段时不崩、hasEfforts 为 false', () {
      final m = CatalogModel.fromJson({'id': 'plain', 'name': 'Plain'});
      expect(m.hasEfforts, isFalse);
      expect(m.defaultEffort, isNull);
    });

    test('缺 name 时退回 id', () {
      expect(CatalogModel.fromJson({'id': 'only-id'}).name, 'only-id');
    });
  });
}
