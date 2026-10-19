import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 提示音服务：approval（需确认）/ question（需回答）/ done（本轮完成）
/// 音源解析顺序：设置里的自定义本地路径 > 内置 asset。
/// 后期自定义只需在设置页调 SettingsService.setCustomSound，无需改这里。
///
/// 设计原则：提示音是「尽力而为」的非关键副作用。任何平台调用失败
/// （无声卡 / 测试环境 / 插件未就绪）都必须静默降级，绝不把异常抛给事件
/// 处理链（否则一个响铃失败会连带打断审批/提问/对账）。
class SoundService {
  static AudioPlayer? _player;
  static bool _contextReady = false;
  static bool _disabled = false;

  /// 惰性、防御式地取播放器：构造失败（无音频插件的测试环境）即永久禁用。
  static AudioPlayer? get _safePlayer {
    if (_disabled) return null;
    try {
      _player ??= AudioPlayer();
      return _player;
    } catch (_) {
      _disabled = true;
      return null;
    }
  }

  /// 测试开关：彻底禁用提示音。插件内部会 fire-and-forget 地发起平台通道
  /// 调用（AudioPlayer 构造后的异步 init），异常无法从外部捕获，测试环境
  /// 必须在构造前禁用。
  @visibleForTesting
  static void debugDisable() => _disabled = true;

  /// 按通知用途播放：走通知音量，屏幕熄灭时也能出声。
  /// 默认 media 用途会被系统在后台/息屏时静音，这是「只有前台有声音」的原因。
  static Future<void> _ensureContext() async {
    if (_contextReady) return;
    final p = _safePlayer;
    if (p == null) return;
    try {
      await p.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notificationEvent,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
      _contextReady = true;
    } catch (_) {
      // 平台音频上下文不可用：提示音降级为静默
    }
  }

  static Future<void> play(String name, {String? customPath}) async {
    final p = _safePlayer;
    if (p == null) return;
    await _ensureContext();
    try {
      if (customPath != null && customPath.isNotEmpty) {
        await p.play(DeviceFileSource(customPath));
      } else {
        await p.play(AssetSource('sounds/$name.wav'));
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
