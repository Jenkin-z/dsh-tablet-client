import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../theme/ios_theme.dart';

/// 自定义铃声行（内置默认 / 自定义文件名 + 选择 / 恢复内置）
///
/// 从 sound_settings.dart 拆出来，让那个文件守住 200 行上限。
class CustomSoundTile extends StatelessWidget {
  final SettingsService settings;

  /// 铃声标识：`approval` / `question` / `done`
  final String name;

  /// 展示标题（如「确认音」）
  final String label;

  /// 用途说明（如「审批 / 问题请求到达」）
  final String desc;

  final VoidCallback onPick;
  final VoidCallback onReset;

  const CustomSoundTile({
    super.key,
    required this.settings,
    required this.name,
    required this.label,
    required this.desc,
    required this.onPick,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final custom = settings.customSoundPath(name);
    final fileName =
        custom == null ? null : custom.split('/').last.split('\\').last;
    return ListTile(
      leading: Icon(
        Icons.music_note_outlined,
        color: IosTheme.iosPink,
        size: 22,
      ),
      title: Text(label),
      subtitle: Text(
        custom == null
            ? '$desc · 内置默认'
            : '$desc · 自定义：$fileName',
        style: const TextStyle(fontSize: 13),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: onPick,
            style: TextButton.styleFrom(
              foregroundColor: IosTheme.iosBlue,
              padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceS),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('选择'),
          ),
          if (custom != null)
            IconButton(
              icon: const Icon(Icons.restore, size: 18),
              color: IosTheme.iosGray,
              tooltip: '恢复内置',
              onPressed: onReset,
            ),
        ],
      ),
    );
  }
}
