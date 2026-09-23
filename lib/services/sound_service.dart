import 'package:audioplayers/audioplayers.dart';

/// 提示音服务：approval（需确认）/ question（需回答）/ done（本轮完成）
/// 音源解析顺序：设置里的自定义本地路径 > 内置 asset。
/// 后期自定义只需在设置页调 SettingsService.setCustomSound，无需改这里。
class SoundService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _contextReady = false;

  /// 按通知用途播放：走通知音量，屏幕熄灭时也能出声。
  /// 默认 media 用途会被系统在后台/息屏时静音，这是「只有前台有声音」的原因。
  static Future<void> _ensureContext() async {
    if (_contextReady) return;
    await _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notificationEvent,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    ));
    _contextReady = true;
  }

  static Future<void> play(String name, {String? customPath}) async {
    await _ensureContext();
    try {
      if (customPath != null && customPath.isNotEmpty) {
        await _player.play(DeviceFileSource(customPath));
      } else {
        await _player.play(AssetSource('sounds/$name.wav'));
      }
    } catch (_) {
      // 提示音失败不影响主流程
    }
  }

  static Future<void> approval({String? customPath}) =>
      play('approval', customPath: customPath);
  static Future<void> question({String? customPath}) =>
      play('question', customPath: customPath);
  static Future<void> done({String? customPath}) =>
      play('done', customPath: customPath);
}