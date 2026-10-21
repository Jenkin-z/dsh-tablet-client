import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../widgets/foreground_service_tile.dart';
import '../widgets/settings_entry.dart';

/// 设置 › 平板常驻
///
/// 屏幕常亮、前台保活、断线自动重连——都是「让平板一直盯着」相关的开关，
/// 放一起方便一次配好。
class SettingsResidentPage extends StatelessWidget {
  const SettingsResidentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    return SettingsSubPage(
      title: '平板常驻',
      children: [
        SettingsGroup(
          title: '常驻',
          children: [
            SwitchListTile(
              secondary: Icon(
                Icons.lightbulb_outline,
                color: IosTheme.iosOrange,
                size: 22,
              ),
              title: const Text('屏幕常亮'),
              subtitle: const Text(
                '防止平板自动锁屏熄屏',
                style: TextStyle(fontSize: 13),
              ),
              value: s.keepScreenOn,
              onChanged: (v) async {
                await s.setKeepScreenOn(v);
                await WakelockPlus.toggle(enable: v);
              },
              activeThumbColor: IosTheme.iosGreen,
            ),
            const ForegroundServiceTile(),
            SwitchListTile(
              secondary: Icon(
                Icons.autorenew,
                color: IosTheme.iosGreen,
                size: 22,
              ),
              title: const Text('断线自动重连'),
              subtitle: const Text(
                '网络恢复后自动连回 DSH',
                style: TextStyle(fontSize: 13),
              ),
              value: s.autoReconnect,
              onChanged: (v) => s.setAutoReconnect(v),
              activeThumbColor: IosTheme.iosGreen,
            ),
          ],
        ),
      ],
    );
  }
}
