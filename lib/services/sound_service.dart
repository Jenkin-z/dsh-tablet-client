import 'package:audioplayers/audioplayers.dart';

/// 提示音服务：approval（需确认）/ question（需回答）/ done（本轮完成）
/// 音源解析顺序：设置里的自定义本地路径 > 内置 asset。
/// 后期自定义只需在设置页调 SettingsService.setCustomSound，无需改这里。
class SoundService {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> play(String name, {String? customPath}) async {
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