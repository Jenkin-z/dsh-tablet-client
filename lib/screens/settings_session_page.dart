import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/backend_ops.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../widgets/settings_entry.dart';

/// 设置 › 会话
///
/// 当前会话 id + 新建会话（另起一段对话，旧记录留在 PC 端）。
class SettingsSessionPage extends StatelessWidget {
  const SettingsSessionPage({super.key});

  Future<void> _newSession(BuildContext context) async {
    try {
      final s = Provider.of<SettingsService>(context, listen: false);
      // 新建会话走转接层（BackendOps 临时装配 backend，不直连具体 API 类）
      final id = await BackendOps(s).createSession();
      if (id.isEmpty) throw Exception('响应里没有会话 id');
      await s.setSessionId(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已创建新会话，返回对话页重连生效')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final p = IosPalette.of(context);
    return SettingsSubPage(
      title: '会话',
      children: [
        SettingsGroup(
          children: [
            ListTile(
              leading: Icon(
                Icons.tag,
                color: IosTheme.iosPurple,
                size: 22,
              ),
              title: const Text('当前会话'),
              subtitle: Text(
                s.sessionId ?? '无',
                style: const TextStyle(
                  fontFamily: IosType.mono,
                  fontSize: IosType.footnotePlus,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.add_circle_outline,
                color: p.ok,
                size: 22,
              ),
              title: const Text('新建会话'),
              subtitle: const Text(
                '另起一段对话，旧记录保留在 PC 端',
                style: TextStyle(fontSize: IosType.footnotePlus),
              ),
              trailing: Icon(
                Icons.chevron_right,
                size: 20,
                color: p.label3,
              ),
              onTap: () => _newSession(context),
            ),
          ],
        ),
      ],
    );
  }
}
