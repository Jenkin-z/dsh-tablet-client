/// 添加 opencode 对话框 widget 测试
///
/// 只覆盖不联网的错误路径（解析失败 / 缺密码 / 链接无授权码），
/// 保存动作编排本身由 opencode_target_test + 协议实测覆盖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/widgets/add_opencode_dialog.dart';

Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: AddOpenCodeDialog(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('默认渲染：标题 + 两种接入模式', (tester) async {
    await _pumpDialog(tester);
    expect(find.text('添加 opencode'), findsOne);
    expect(find.text('授权链接'), findsWidgets); // 段标题 + 输入框标签
    expect(find.text('手动连接'), findsOne);
    // 默认授权链接模式：提示语可见
    expect(find.text('PC 上运行 opencode pair --remote 生成，300 秒内有效'),
        findsOne);
  });

  testWidgets('切到手动连接：出现地址与密码框', (tester) async {
    await _pumpDialog(tester);
    await tester.tap(find.text('手动连接'));
    await tester.pump();
    expect(find.text('密码'), findsOne);
    expect(find.text('局域网直连需 PC 端 opencode serve --hostname 0.0.0.0'),
        findsOne);
    // 授权链接模式的提示语应消失
    expect(find.text('PC 上运行 opencode pair --remote 生成，300 秒内有效'),
        findsNothing);
  });

  testWidgets('授权链接模式贴垃圾输入 → 报无法识别', (tester) async {
    await _pumpDialog(tester);
    await tester.enterText(
        find.byType(TextField).first, '这不是一个链接');
    await tester.tap(find.text('测试并保存'));
    await tester.pump();
    expect(find.textContaining('无法识别地址'), findsOne);
  });

  testWidgets('授权链接是无授权码的普通 URL → 报缺授权码', (tester) async {
    await _pumpDialog(tester);
    await tester.enterText(
        find.byType(TextField).first, 'http://192.168.10.5:4096');
    await tester.tap(find.text('测试并保存'));
    await tester.pump();
    expect(find.textContaining('链接里没有授权码'), findsOne);
  });

  testWidgets('手动连接 URL 合法但密码为空 → 报请填服务密码', (tester) async {
    await _pumpDialog(tester);
    await tester.tap(find.text('手动连接'));
    await tester.pump();
    // 地址框预填 http://192.168.10.，补成合法地址
    await tester.enterText(find.byType(TextField).first, 'http://192.168.10.5:4096');
    await tester.tap(find.text('测试并保存'));
    await tester.pump();
    expect(find.textContaining('请填服务密码'), findsOne);
  });
}
