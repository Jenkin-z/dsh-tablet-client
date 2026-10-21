/// 设置页二级菜单回归测试
///
/// 锁死的语义：
/// - 根页只列「去哪」的入口，不再直接摆开关（页面太长）；
/// - 每个入口能进对应二级页，二级页里内容齐全。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dsh_tablet_client/screens/settings_appearance_page.dart';
import 'package:dsh_tablet_client/screens/settings_screen.dart';
import 'package:dsh_tablet_client/screens/settings_servers_page.dart';
import 'package:dsh_tablet_client/services/server_manager.dart';
import 'package:dsh_tablet_client/services/settings_service.dart';

Future<void> _pumpSettings(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues({});
  final settings = SettingsService();
  await settings.init();
  final manager = ServerManager(settings);
  addTearDown(() {
    manager.dispose();
    settings.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<ServerManager>.value(value: manager),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('根页只列二级入口，不再直接摆开关', (tester) async {
    await _pumpSettings(tester);

    expect(find.text('设备管理'), findsOne);
    expect(find.text('平板常驻'), findsOne);
    expect(find.text('通知与声音'), findsOne);
    expect(find.text('外观'), findsOne);
    expect(find.text('会话'), findsOne);
    expect(find.text('应用更新'), findsOne);

    // 这些内容搬到了二级页
    expect(find.text('屏幕常亮'), findsNothing);
    expect(find.text('提示音'), findsNothing);
    expect(find.text('当前版本'), findsNothing);
  });

  testWidgets('点「外观」进二级页：主题分段齐全', (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsAppearancePage), findsOne);
    expect(find.text('主题'), findsOne);
    expect(find.text('自动'), findsOne);
    expect(find.text('浅色'), findsOne);
    expect(find.text('深色'), findsOne);
  });

  testWidgets('点「设备管理」进二级页：后端与授权入口都在', (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('设备管理'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsServersPage), findsOne);
    expect(find.text('添加 / 授权 PC'), findsOne);
    expect(find.text('添加 opencode'), findsOne);
    expect(find.text('测试'), findsOne);
  });
}
