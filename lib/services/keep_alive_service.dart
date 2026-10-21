import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 前台保活：让进程在后台/锁屏时不被冻结，轮询和 mux 才能继续跑、通知才能发出。
///
/// 之前只有设置页的手动开关，且 manifest 缺少 ForegroundService 声明，
/// 开关打开也起不来；现在 App 启动即自动拉起。
class KeepAliveService {
  static const _title = 'DSH Agent 运行中';
  static const _text = '与 PC 端保持连接';

  static void init() {
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
        // 保活不依赖 onRepeatEvent：每分钟唤醒一次只会白耗电。
        // 网络轮询/mux 有自己的生命周期，不需要前台服务替它们打拍子。
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  /// 已在跑则直接返回 true，否则启动；返回最终是否在运行
  static Future<bool> start() async {
    try {
      if (await FlutterForegroundTask.isRunningService) return true;
      await FlutterForegroundTask.startService(
        notificationTitle: _title,
        notificationText: _text,
        callback: keepAliveCallback,
      );
    } catch (_) {}
    return FlutterForegroundTask.isRunningService;
  }

  static Future<bool> stop() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    return FlutterForegroundTask.isRunningService;
  }

  /// 省电优化会在熄屏后冻结网络与定时器，常驻监控必须加入白名单
  static Future<bool> get ignoringBatteryOptimizations =>
      FlutterForegroundTask.isIgnoringBatteryOptimizations;

  static Future<bool> requestIgnoreBatteryOptimization() =>
      FlutterForegroundTask.requestIgnoreBatteryOptimization();

  static void setStatus(String text) {
    try {
      FlutterForegroundTask.updateService(notificationText: text);
    } catch (_) {}
  }
}

/// 前台服务入口（必须为顶层函数）
@pragma('vm:entry-point')
void keepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}
