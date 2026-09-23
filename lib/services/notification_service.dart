import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 系统本地通知：弹出 heads-up 通知（有声音、震动、状态栏图标）
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static int _autoId = 0;

  /// 事件通知通道 ID（v2：通道声音一旦创建无法修改，换 ID 强制重建）
  static const _channelId = 'dshm_events_v2';
  static const _channelName = 'DSHM 事件通知';
  static const _channelDesc = '审批、提问、会话完成等重要通知';

  /// res/raw/dshm_alert 的原始资源名（不含扩展名）
  static const _sound = RawResourceAndroidNotificationSound('dshm_alert');

  /// 初始化通知插件 + 显式创建通道
  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);

    // 显式创建通道
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      // 旧通道没有自定义声音且创建后不可改，删掉避免设置里留两条
      await androidPlugin.deleteNotificationChannel('dshm_events');
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        enableVibration: true,
        enableLights: true,
        playSound: true,
        sound: _sound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );
      await androidPlugin.createNotificationChannel(channel);
    }

    _initialized = true;
  }

  /// 弹出一条 heads-up 通知（后台也能弹出+响铃）
  static Future<void> show({
    int? id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    final nid = id ?? _autoId++;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/ic_launcher',
        ticker: 'DSHM',
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 300, 150, 300]),
        playSound: true,
        sound: _sound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,
        styleInformation: const DefaultStyleInformation(true, true),
      ),
    );
    await _plugin.show(nid, title, body, details);
  }
}
