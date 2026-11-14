import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../widgets/settings_entry.dart';
import '../widgets/sound_settings.dart';

/// 设置 › 通知与声音
///
/// 通知分类开关 + 提示音开关/试听/自定义铃声 + 系统通知自测。
class SettingsNotifyPage extends StatelessWidget {
  const SettingsNotifyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final p = IosPalette.of(context);
    return SettingsSubPage(
      title: '通知与声音',
      children: [
        SettingsGroup(
          title: '通知类型',
          children: [
            _NotifySwitch(
              icon: Icons.approval_outlined,
              color: p.warnTint,
              title: '审批提醒',
              subtitle: '工具调用需要确认时',
              value: s.notifyApproval,
              onChanged: s.setNotifyApproval,
            ),
            _NotifySwitch(
              icon: Icons.help_outline,
              color: p.accent,
              title: '提问提醒',
              subtitle: 'Agent 向你提问时',
              value: s.notifyQuestion,
              onChanged: s.setNotifyQuestion,
            ),
            _NotifySwitch(
              icon: Icons.edit_note_outlined,
              color: IosTheme.iosPurple,
              title: '表单提醒',
              subtitle: 'opencode 表单待填写时',
              value: s.notifyForm,
              onChanged: s.setNotifyForm,
            ),
            _NotifySwitch(
              icon: Icons.check_circle_outline,
              color: p.ok,
              title: '完成提醒',
              subtitle: '会话一轮跑完时',
              value: s.notifyCompletion,
              onChanged: s.setNotifyCompletion,
            ),
          ],
        ),
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
                color: p.accent,
              ),
              title: const Text('发送测试通知'),
              subtitle: const Text(
                '验证系统通知是否正常弹出（含声音+震动）',
                style: TextStyle(fontSize: IosType.footnotePlus),
              ),
              trailing: Icon(
                Icons.chevron_right,
                size: 20,
                color: p.label3,
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

/// 通知分类开关行（iOS 风格：彩色图标 + 标题/副标题 + Switch）
class _NotifySwitch extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotifySwitch({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontSize: IosType.body)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: IosType.footnote)),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}
