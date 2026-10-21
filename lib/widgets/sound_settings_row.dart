import 'package:flutter/material.dart';

import '../theme/ios_theme.dart';

/// 声音设置卡片内的分隔线
///
/// 从 sound_settings.dart 拆出来，让那个文件守住 200 行上限。
class SoundSettingsDivider extends StatelessWidget {
  const SoundSettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 56),
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06),
    );
  }
}

/// 「试听」行里的小按钮（确认 / 提问 / 完成）
///
/// 从 sound_settings.dart 拆出来，让那个文件守住 200 行上限。
class SoundPreviewButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const SoundPreviewButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: IosTheme.iosBlue,
        padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceS),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}
