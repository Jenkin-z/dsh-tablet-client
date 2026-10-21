import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../theme/ios_theme.dart';
import '../widgets/settings_entry.dart';
import '../widgets/update_dialog.dart';

/// 设置 › 应用更新
///
/// 当前版本、手动检查更新、启动时自动检查。
class SettingsUpdatePage extends StatelessWidget {
  const SettingsUpdatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    return SettingsSubPage(
      title: '应用更新',
      children: [
        SettingsGroup(
          children: [
            FutureBuilder<String>(
              future: UpdateService.currentVersion(),
              builder: (context, snap) => ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: IosTheme.iosGray,
                  size: 22,
                ),
                title: const Text('当前版本'),
                subtitle: Text(
                  snap.data ?? '…',
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: IosButton(
                  label: '检查更新',
                  filled: false,
                  onPressed: () => UpdateFlow.checkAndPrompt(
                    context,
                    s.servers
                        .where((e) => e.host.isNotEmpty)
                        .map((e) => e.host)
                        .followedBy([s.serverHost]),
                  ),
                ),
              ),
            ),
            SwitchListTile(
              secondary: Icon(
                Icons.system_update_outlined,
                color: IosTheme.iosBlue,
                size: 22,
              ),
              title: const Text('启动时自动检查'),
              subtitle: const Text(
                '局域网小文件请求，无更新不打扰',
                style: TextStyle(fontSize: 13),
              ),
              value: s.updateAutoCheck,
              onChanged: (v) => s.setUpdateAutoCheck(v),
              activeThumbColor: IosTheme.iosGreen,
            ),
          ],
        ),
      ],
    );
  }
}
