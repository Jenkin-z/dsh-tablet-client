import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'services/session_monitor.dart';
import 'services/session_router.dart';
import 'services/settings_service.dart';
import 'screens/chat_screen.dart';
import 'screens/console_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/update_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsService();
  await settings.init();

  // 屏幕常亮（按设置）
  await WakelockPlus.toggle(enable: settings.keepScreenOn);

  // 前台服务初始化（通知渠道等）
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'dsh_tablet_client',
      channelName: 'DSH Agent 保活',
      channelDescription: '保持 DSH Agent 在前台运行',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(60000),
      autoRunOnBoot: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => SessionRouter()),
        ChangeNotifierProvider(
          create: (_) => SessionMonitor(settings),
        ),
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
    // 只绑定一次，避免重复 addListener
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
    // 监听主题设置（跟随系统/浅色/深色）
    final settings = Provider.of<SettingsService>(context);
    final mode = switch (settings.themeModeKey) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp(
      title: 'DSH Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blueGrey,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueGrey,
        useMaterial3: true,
      ),
      themeMode: mode,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _updateChecked = false;
  SessionMonitor? _monitor;

  @override
  void initState() {
    super.initState();
    // 启动后自动检查一次更新（有更新才弹窗）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_updateChecked || !mounted) return;
      _updateChecked = true;
      final s = Provider.of<SettingsService>(context, listen: false);
      if (s.updateAutoCheck) {
        UpdateFlow.checkAndPrompt(context, s.serverHost, auto: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 会话监控常驻轮询（App 存活期间一直跑，控制台与提示音都靠它）
    if (_monitor == null) {
      _monitor = Provider.of<SessionMonitor>(context, listen: false);
      _monitor!.start();
    }
  }

  @override
  void dispose() {
    _monitor?.stop();
    super.dispose();
  }

  /// 控制台点某会话：发路由意图 + 切到对话页（聊天页实际执行切换）
  void _openSession(String sessionId) {
    Provider.of<SessionRouter>(context, listen: false).request(sessionId);
    setState(() => _currentIndex = 1);
  }

  @override
  Widget build(BuildContext context) {
    // 监听设置页返回：如果服务器地址变了，聊天页重建以重连
    final settings = Provider.of<SettingsService>(context);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ConsoleScreen(onOpenSession: _openSession),
          // key 绑定 serverUrl，地址变更时自动重建并重连
          ChatScreen(key: ValueKey(settings.serverUrl)),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '控制台',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: '对话',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

/// 前台服务权限申请包装（Android 13+ 需要 POST_NOTIFICATIONS）
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
