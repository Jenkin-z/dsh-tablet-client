import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_visibility.dart';

/// 系统本地通知：弹出 heads-up 通知（有声音、震动、状态栏图标）
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static int _nextNotificationId = 0;

  /// 点击通知后的跳转回调（MainShell 注册）。
  ///
  /// [serverId]/[sessionId] 由 show() 的调用方随 payload 带上；
  /// 旧通知/测试通知没有 payload，回调不触发（由 [onTap] 判空跳过）。
  static void Function(String serverId, String sessionId)? onTap;

  /// 冷启动（点通知把 App 拉起来）的待消费 payload
  static (String, String)? _launchPayload;

  /// payload 分隔符：单元分隔符，serverId/sessionId 内容里不会出现
  static const _sep = '\u001F';

  static String? _encodePayload(String? serverId, String? sessionId) {
    if (serverId == null || serverId.isEmpty) return null;
    if (sessionId == null || sessionId.isEmpty) return null;
    return '$serverId$_sep$sessionId';
  }

  static (String, String)? _parsePayload(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(_sep);
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return (parts[0], parts[1]);
  }

  /// 取走冷启动 payload（点通知拉起 App 的那次跳转，只消费一次）
  static (String, String)? consumeLaunch() {
    final p = _launchPayload;
    _launchPayload = null;
    return p;
  }

  /// 进程内唯一的通知 id。
  ///
  /// 审批、提问、表单、会话完成都可能同时到达；如果各自用固定 id，
  /// 后来的通知会把前一条直接覆盖掉。统一从这里分配，互不干扰。
  static int nextId() => _nextNotificationId++;

  /// 事件通知通道 ID（v2：通道声音一旦创建无法修改，换 ID 强制重建）
  static const _channelId = 'dshm_events_v2';
  static const _channelName = 'DSHM 事件通知';
  static const _channelDesc = '审批、提问、会话完成等重要通知';

  /// res/raw/dshm_alert 的原始资源名（不含扩展名）
  static const _sound = RawResourceAndroidNotificationSound('dshm_alert');

  /// 初始化通知插件 + 显式创建通道 + 注册点击回调
  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 冷启动：App 进程被通知点击拉起时，launch details 里带着 payload。
    // 此时 MainShell 还没建，先存起来，由 MainShell 首帧后 consumeLaunch()。
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp) {
        _launchPayload = _parsePayload(launch.notificationResponse?.payload);
      }
    } catch (_) {
      // 个别机型 launch details 拿不到：只损失冷启动跳转，不影响通知
    }

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

  /// 点击通知：解析 payload 转给跳转回调
  static void _onNotificationTap(NotificationResponse response) {
    final target = _parsePayload(response.payload);
    if (target == null) return;
    onTap?.call(target.$1, target.$2);
  }

  /// 弹出一条 heads-up 通知（后台也能弹出+响铃）
  ///
  /// [serverId]/[sessionId] 写进点击 payload：用户点通知后由 MainShell
  /// 路由到对应机器的对应会话。任一为空则不带 payload（点击只打开 App）。
  /// [skipInForeground]：前台时不弹（应用内已有对应展示）。是否跳过由
  /// **调用方**判断——规则统一为「事件属于当前正查看的会话才跳过」，
  /// 非当前会话的事件即使在前台也要弹（否则用户根本无从得知）。
  static Future<void> show({
    int? id,
    required String title,
    required String body,
    String? serverId,
    String? sessionId,
    bool skipInForeground = false,
  }) async {
    if (!_initialized) return;
    if (skipInForeground && AppVisibility.foreground) return;
    final nid = id ?? nextId();
    final payload = _encodePayload(serverId, sessionId);
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
    try {
      await _plugin.show(nid, title, body, details, payload: payload);
    } catch (_) {
      // 自定义声音资源不可用（例如资源被压缩掉）时，整个 show 会抛错，
      // 通知发不出去。兜底：去掉自定义声音再发一次，保证通知至少能弹出来。
      final fallback = NotificationDetails(
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
          playSound: false,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          fullScreenIntent: true,
          styleInformation: const DefaultStyleInformation(true, true),
        ),
      );
      await _plugin.show(nid, title, body, fallback, payload: payload);
    }
  }
}
