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
    final p = IosPalette.of(context);
    return AlertDialog(
      backgroundColor: p.elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IosTheme.radiusM),
      ),
      title: Text(
        '发现新版本 ${info.versionName}',
        style: const TextStyle(
          fontSize: IosType.title3,
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
                  color: p.surface2,
                  borderRadius: BorderRadius.circular(IosTheme.radiusXS),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 18,
                      color: p.label,
                    ),
                    const SizedBox(width: IosTheme.spaceS),
                    Text(
                      '大小：${info.sizeText}',
                      style: TextStyle(
                        fontSize: 14,
                        color: p.label,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: IosTheme.spaceM),
              if (info.sha256 != null) ...[
                // 发布完整性可见化（借鉴 dsh-go marketplace 的 security 行）：
                // 指纹先亮出来，校验在下载完成后做 —— 声明 ≠ 已验证
                Row(
                  children: [
                    Icon(
                      Icons.fingerprint,
                      size: 16,
                      color: p.label,
                    ),
                    const SizedBox(width: IosTheme.spaceS),
                    Text(
                      '发布指纹 ${info.fingerprintShort}',
                      style: TextStyle(
                        fontSize: IosType.footnotePlus,
                        color: p.label,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: IosTheme.spaceXS),
                Text(
                  '下载完成后将逐字节校验 SHA-256，不匹配拒绝安装',
                  style: TextStyle(
                    fontSize: IosType.caption,
                    color: p.label2,
                  ),
                ),
                const SizedBox(height: IosTheme.spaceM),
              ],
              Text(
                info.changelog,
                style: const TextStyle(fontSize: IosType.body, height: 1.5),
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
                color: p.accent,
                fontSize: IosType.title3,
              ),
            ),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
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
