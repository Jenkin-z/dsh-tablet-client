import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent_server.dart';
import '../services/dsh/dsh_api.dart';
import '../services/opencode/opencode_api.dart';
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
      final active = s.active;
      if (active == null) return;
      final id = switch (active.kind) {
        AgentKind.dsh =>
          await DshApi(baseUrl: s.serverUrl, cookie: active.cookie)
              .createSession(),
        AgentKind.opencode =>
          await OpenCodeApi(baseUrl: active.httpUrl, password: active.token)
              .createSession()
              .then((info) => info['id'] as String? ?? ''),
      };
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
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.add_circle_outline,
                color: IosTheme.iosGreen,
                size: 22,
              ),
              title: const Text('新建会话'),
              subtitle: const Text(
                '另起一段对话，旧记录保留在 PC 端',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                size: 20,
                color: IosTheme.iosGray3,
              ),
              onTap: () => _newSession(context),
            ),
          ],
        ),
      ],
    );
  }
}
