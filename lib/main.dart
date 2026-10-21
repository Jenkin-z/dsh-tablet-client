import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/main_shell.dart';
import 'services/session_state.dart';
import 'services/keep_alive_service.dart';
import 'services/notification_service.dart';
import 'services/server_manager.dart';
import 'services/session_router.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsService();
  await settings.init();

  await WakelockPlus.toggle(enable: settings.keepScreenOn);

  // Android 13+ 需要运行时请求通知权限
  await ForegroundStarter.requestPermissions();

  // 初始化本地通知（审批/提问/完成时弹出 heads-up 通知）
  await NotificationService.init();

  // 前台保活：启动即拉起，否则切到后台后进程被冻结，轮询停了就不会有通知
  KeepAliveService.init();
  await KeepAliveService.start();

  // 注意：这里**不再**把 ServerManager 的轮询结果接进 SessionState。
  //
  // 曾经是 `onActiveHealth = (ok, e) => sessionState.setSessionsHealth(...)`，
  // 于是每 8 秒的 HTTP 轮询成功就把状态点刷成绿色 —— 对话页那个点反映的
  // 其实是「轮询能拉到列表」，与对话页那条 WebSocket 毫无关系，
  // 所以它一直绿、永远不会变。
  //
  // 现在 `_sessionsOk` 只由 ChatController 自己写入（boot 与重连时各拉一次
  // 会话列表），点代表的就是「对话页这台机器连上了吗、数据新鲜吗」。
  // 设备卡各自读自己的 monitor，不受影响。
  final sessionState = SessionState();
  final serverManager = ServerManager(settings);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => SessionRouter()),
        ChangeNotifierProvider.value(value: serverManager),
        // 单一权威状态源：全局唯一，ChatScreen 驱动、其余页面只读
        ChangeNotifierProvider.value(value: sessionState),
      ],
      child: const DshTabletApp(),
    ),
  );
}

class DshTabletApp extends StatefulWidget {
  const DshTabletApp({super.key});

  @override
  State<DshTabletApp> createState() => _DshTabletAppState();
}

class _DshTabletAppState extends State<DshTabletApp> {
  SettingsService? _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settings == null) {
      _settings = Provider.of<SettingsService>(context, listen: false);
      _settings!.addListener(_syncWakelock);
    }
  }

  void _syncWakelock() {
    WakelockPlus.toggle(enable: _settings?.keepScreenOn ?? true);
  }

  @override
  void dispose() {
    _settings?.removeListener(_syncWakelock);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final mode = switch (settings.themeModeKey) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp(
      title: 'DSH Agent',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: const MainShell(),
    );
  }
}

class ForegroundStarter {
  static Future<bool> requestPermissions() async {
    final status = await FlutterForegroundTask.checkNotificationPermission();
    if (status != NotificationPermission.granted) {
      final result = await FlutterForegroundTask.requestNotificationPermission();
      return result == NotificationPermission.granted;
    }
    return true;
  }
}
