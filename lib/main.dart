import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/main_shell.dart';
import 'services/notification_service.dart';
import 'services/server_manager.dart';
import 'services/session_router.dart';
import 'services/settings_service.dart';
import 'theme/ios_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsService();
  await settings.init();

  await WakelockPlus.toggle(enable: settings.keepScreenOn);

  // Android 13+ 需要运行时请求通知权限
  await ForegroundStarter.requestPermissions();

  // 初始化本地通知（审批/提问/完成时弹出 heads-up 通知）
  await NotificationService.init();

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'dshm_foreground',
      channelName: 'DSHM 后台保活',
      channelDescription: '保持与 PC 端连接的常驻通知',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      playSound: false,
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
        ChangeNotifierProvider(create: (_) => ServerManager(settings)),
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
      theme: ThemeData(
        colorSchemeSeed: IosTheme.iosBlue,
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: IosTheme.iosGroupedBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: IosTheme.iosGroupedBg,
          foregroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 56,
          backgroundColor: Colors.white.withValues(alpha: 0.94),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          indicatorColor: IosTheme.iosBlue.withValues(alpha: 0.12),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: IosTheme.iosBlue,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              );
            }
            return TextStyle(
              color: IosTheme.iosGray,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: IosTheme.iosBlue, size: 22);
            }
            return const IconThemeData(color: IosTheme.iosGray, size: 22);
          }),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusCard),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return Colors.white;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IosTheme.iosGreen;
            }
            return IosTheme.iosGray3;
          }),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
        ),
        dividerTheme: const DividerThemeData(
          thickness: 0.5,
          color: Color(0xFFC6C6C8),
          space: 0.5,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1C1C1E),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusS),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          elevation: 20,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusM),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: IosTheme.iosBlue,
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: IosTheme.iosDarkGroupedBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: IosTheme.iosDarkGroupedBg,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 56,
          backgroundColor: const Color(0xFF1C1C1E).withValues(alpha: 0.94),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          indicatorColor: IosTheme.iosBlue.withValues(alpha: 0.24),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: IosTheme.iosBlue,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              );
            }
            return TextStyle(
              color: IosTheme.iosGray2,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: IosTheme.iosBlue, size: 22);
            }
            return const IconThemeData(color: IosTheme.iosGray2, size: 22);
          }),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1C1C1E),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusCard),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return Colors.white;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IosTheme.iosGreen;
            }
            return IosTheme.iosGray;
          }),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
        ),
        dividerTheme: const DividerThemeData(
          thickness: 0.5,
          color: Color(0xFF38383A),
          space: 0.5,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2C2C2E),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusS),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF2C2C2E),
          elevation: 20,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusM),
          ),
        ),
      ),
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
