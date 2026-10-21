import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../widgets/settings_entry.dart';

/// 设置 › 外观
///
/// 主题：自动 / 浅色 / 深色。
class SettingsAppearancePage extends StatelessWidget {
  const SettingsAppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    return SettingsSubPage(
      title: '外观',
      children: [
        SettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.all(IosTheme.spaceL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('主题', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: IosTheme.spaceM),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'system',
                        label: Text('自动'),
                        icon: Icon(Icons.settings_suggest_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: 'light',
                        label: Text('浅色'),
                        icon: Icon(Icons.light_mode_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: 'dark',
                        label: Text('深色'),
                        icon: Icon(Icons.dark_mode_outlined, size: 18),
                      ),
                    ],
                    selected: {s.themeModeKey},
                    onSelectionChanged: (v) => s.setThemeMode(v.first),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
