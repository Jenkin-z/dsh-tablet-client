/// opencode 表单弹窗测试（Widget 层）
///
/// 锁死的语义：
/// - 按字段 type 原生渲染：string+options → chips、boolean → Switch、
///   integer/number → 数字键盘；
/// - 答案形状 {key: value} 与 reply API 1:1（不做 DSH 的 selected/custom 转换）；
/// - 只有 required 空缺才拦截提交（optional 可空——DSH 无 optional 概念）；
/// - 服务端 default 预填，不改也能直接提交；
/// - 放弃回答 → pop(false)，调用方据此取消。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/models/pending.dart';
import 'package:dsh_tablet_client/widgets/open_code_form_sheet.dart';

PendingForm _form(List<Map<String, dynamic>> fields) => PendingForm(
      formId: 'frm_1',
      sessionId: 's1',
      title: '部署确认',
      fields: fields,
    );

/// 开弹窗 →（可选交互）→ 点提交，返回 onSubmit 收到的答案
///
/// 提交必须收在辅助里：弹窗是异步关的，提前 return 会定格 null。
Future<Map<String, dynamic>?> _run(
  WidgetTester tester,
  PendingForm form, {
  Future<void> Function()? interact,
}) async {
  Map<String, dynamic>? submitted;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => OpenCodeFormSheet(
            form: form,
            onSubmit: (answer) async {
              submitted = answer;
              return true;
            },
          ),
        ),
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (interact != null) await interact();
  await tester.tap(find.text('提交'));
  await tester.pumpAndSettle();
  return submitted;
}

void main() {
  testWidgets('必填空缺 → 拦截提交（不调 onSubmit）', (tester) async {
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => OpenCodeFormSheet(
              form: _form([
                {'key': 'env', 'type': 'string', 'title': '环境', 'required': true},
              ]),
              onSubmit: (a) async {
                submitted = a;
                return true;
              },
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(submitted, isNull);
    expect(find.text('有必填项未填写'), findsOneWidget);
  });

  testWidgets('string+options → chips 单选，提交形状 {key: value}', (tester) async {
    final submitted = await _run(
      tester,
      _form([
        {
          'key': 'env',
          'type': 'string',
          'title': '环境',
          'required': true,
          'options': [
            {'value': 'dev', 'label': '开发'},
            {'value': 'prod', 'label': '生产'},
          ],
        },
      ]),
      interact: () async {
        await tester.tap(find.text('生产'));
        await tester.pumpAndSettle();
      },
    );
    expect(submitted, {'env': 'prod'});
  });

  testWidgets('boolean → Switch，提交形状为 bool', (tester) async {
    final submitted = await _run(
      tester,
      _form([
        {'key': 'force', 'type': 'boolean', 'title': '强制'},
      ]),
      interact: () async {
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
      },
    );
    expect(submitted, {'force': true});
  });

  testWidgets('integer → 数字键盘，提交形状为 int', (tester) async {
    final submitted = await _run(
      tester,
      _form([
        {'key': 'count', 'type': 'integer', 'title': '副本数'},
      ]),
      interact: () async {
        await tester.enterText(find.byType(TextField), '3');
        await tester.pumpAndSettle();
      },
    );
    expect(submitted, {'count': 3});
  });

  testWidgets('服务端 default 预填，不改直接提交', (tester) async {
    final submitted = await _run(
      tester,
      _form([
        {'key': 'env', 'type': 'string', 'title': '环境', 'default': 'dev'},
      ]),
    );
    expect(submitted, {'env': 'dev'});
  });

  testWidgets('optional 字段留空 → 整个键省略（不能是空串）', (tester) async {
    final submitted = await _run(
      tester,
      _form([
        {'key': 'note', 'type': 'string', 'title': '备注'},
      ]),
    );
    expect(submitted, isEmpty);
  });

  testWidgets('multiselect → 多选 chips，提交形状为 List<String>', (tester) async {
    final submitted = await _run(
      tester,
      _form([
        {
          'key': 'tags',
          'type': 'multiselect',
          'title': '标签',
          'options': [
            {'value': 'a', 'label': 'A'},
            {'value': 'b', 'label': 'B'},
          ],
        },
      ]),
      interact: () async {
        await tester.tap(find.text('A'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('B'));
        await tester.pumpAndSettle();
      },
    );
    expect(submitted, {'tags': ['a', 'b']});
  });

  testWidgets('onSubmit 抛错 → 弹窗内显示错误且不关闭', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => OpenCodeFormSheet(
              form: _form([
                {'key': 'env', 'type': 'string', 'title': '环境', 'default': 'dev'},
              ]),
              onSubmit: (a) async =>
                  throw Exception('Missing required form field: env'),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Missing required form field: env'),
        findsOneWidget);
    // 弹窗仍在
    expect(find.text('提交'), findsOneWidget);
  });

  testWidgets('放弃回答 → pop(false)，调用方据此取消', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showDialog<bool>(
              context: context,
              builder: (_) => OpenCodeFormSheet(
                form: _form([
                  {'key': 'env', 'type': 'string', 'title': '环境'},
                ]),
                onSubmit: (a) async => true,
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃回答'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('hidden 字段不渲染、不提交', (tester) async {
    final submitted = await _run(
      tester,
      _form([
        {'key': 'visible', 'type': 'string', 'title': '可见', 'default': 'x'},
        {'key': 'secret', 'type': 'string', 'title': '隐藏', 'hidden': true},
      ]),
      interact: () async {
        // 提交前断言渲染（提交后弹窗已关，找不到控件）
        expect(find.text('可见'), findsOneWidget);
        expect(find.text('隐藏'), findsNothing);
      },
    );
    expect(submitted, {'visible': 'x'});
  });
}
