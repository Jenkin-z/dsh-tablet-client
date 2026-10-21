import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../theme/ios_theme.dart';
import '../widgets/settings_entry.dart';
import 'settings_appearance_page.dart';
import 'settings_notify_page.dart';
import 'settings_resident_page.dart';
import 'settings_servers_page.dart';
import 'settings_session_page.dart';
import 'settings_update_page.dart';

/// 设置根页 —— iOS 风格二级菜单
///
/// 原来把 PC、常驻、外观、声音、通知、更新、会话全堆在一页，
/// 平板上一屏拉到底才找得到。这里改成 iOS 设置的层级：
/// 根页只列「去哪」，具体项各自一个二级页。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _themeLabels = {
    'system': '自动',
    'light': '浅色',
    'dark': '深色',
  };

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final servers = s.servers;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: IosTheme.spaceL,
          vertical: IosTheme.spaceM,
        ),
        children: [
          SettingsGroup(
            title: '设备',
            children: [
              SettingsEntryTile(
                icon: Icons.dns_outlined,
                iconColor: IosTheme.iosBlue,
                title: '设备管理',
                value: servers.isEmpty ? '未添加' : '${servers.length} 台',
                onTap: () => _push(context, const SettingsServersPage()),
              ),
              SettingsEntryTile(
                icon: Icons.lightbulb_outline,
                iconColor: IosTheme.iosOrange,
                title: '平板常驻',
                value: s.keepScreenOn ? '常亮开' : '常亮关',
                onTap: () => _push(context, const SettingsResidentPage()),
              ),
            ],
          ),
          const SizedBox(height: IosTheme.spaceM),
          SettingsGroup(
            title: '通知与显示',
            children: [
              SettingsEntryTile(
                icon: Icons.notifications_outlined,
                iconColor: IosTheme.iosGreen,
                title: '通知与声音',
                value: s.soundEnabled ? '提示音开' : '提示音关',
                onTap: () => _push(context, const SettingsNotifyPage()),
              ),
              SettingsEntryTile(
                icon: Icons.palette_outlined,
                iconColor: IosTheme.iosPurple,
                title: '外观',
                value: _themeLabels[s.themeModeKey] ?? '自动',
                onTap: () => _push(context, const SettingsAppearancePage()),
              ),
            ],
          ),
          const SizedBox(height: IosTheme.spaceM),
          SettingsGroup(
            title: '其他',
            children: [
              SettingsEntryTile(
                icon: Icons.forum_outlined,
                iconColor: IosTheme.iosTeal,
                title: '会话',
                value: s.sessionId == null ? '无' : _short(s.sessionId!),
                onTap: () => _push(context, const SettingsSessionPage()),
              ),
              FutureBuilder<String>(
                future: UpdateService.currentVersion(),
                builder: (context, snap) => SettingsEntryTile(
                  icon: Icons.system_update_outlined,
                  iconColor: IosTheme.iosBlue,
                  title: '应用更新',
                  value: snap.data ?? '…',
                  onTap: () => _push(context, const SettingsUpdatePage()),
                ),
              ),
            ],
          ),
          const SizedBox(height: IosTheme.spaceXXL),
        ],
      ),
    );
  }

  /// 会话 id 太长，右边只显示头尾几段
  static String _short(String id) =>
      id.length <= 12 ? id : '${id.substring(0, 6)}…${id.substring(id.length - 4)}';
}
