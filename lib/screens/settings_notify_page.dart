import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../widgets/settings_entry.dart';
import '../widgets/sound_settings.dart';

/// 设置 › 通知与声音
///
/// 提示音开关/试听/自定义铃声 + 系统通知自测。
class SettingsNotifyPage extends StatelessWidget {
  const SettingsNotifyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    return SettingsSubPage(
      title: '通知与声音',
      children: [
        SettingsGroup(
          title: '提示音',
          children: [SoundTogglesSection(settings: s)],
        ),
        SettingsGroup(
          title: '自定义铃声',
          children: [CustomSoundsSection(settings: s)],
        ),
        SettingsGroup(
          title: '通知测试',
          children: [
            ListTile(
              leading: Icon(
                Icons.notifications_active_outlined,
                color: IosTheme.iosBlue,
              ),
              title: const Text('发送测试通知'),
              subtitle: const Text(
                '验证系统通知是否正常弹出（含声音+震动）',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                size: 20,
                color: IosTheme.iosGray3,
              ),
              onTap: () async {
                await NotificationService.show(
                  title: 'DSH Agent 测试通知',
                  body: '如果你听到声音+看到弹窗，说明通知功能正常！',
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已发送，请检查状态栏')),
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
