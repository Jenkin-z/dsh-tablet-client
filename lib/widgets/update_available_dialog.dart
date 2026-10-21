import 'package:flutter/material.dart';
import '../services/update_service.dart';
import '../theme/ios_theme.dart';

/// 发现新版弹窗 —— iOS 风格
///
/// 从 update_dialog.dart 拆出来是为了守住 200 行上限。
class UpdateAvailableDialog extends StatelessWidget {
  final UpdateInfo info;

  const UpdateAvailableDialog({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IosTheme.radiusM),
      ),
      title: Text(
        '发现新版本 ${info.versionName}',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(IosTheme.spaceM),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A3A3C)
                      : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(IosTheme.radiusXS),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 18,
                      color: IosTheme.iosGray,
                    ),
                    const SizedBox(width: IosTheme.spaceS),
                    Text(
                      '大小：${info.sizeText}',
                      style: TextStyle(
                        fontSize: 14,
                        color: IosTheme.iosGray,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: IosTheme.spaceM),
              Text(
                info.changelog,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!info.force)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '稍后',
              style: TextStyle(
                color: IosTheme.iosBlue,
                fontSize: 17,
              ),
            ),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: IosTheme.iosBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(IosTheme.radiusButton),
            ),
          ),
          child: const Text('立即更新'),
        ),
      ],
    );
  }
}
