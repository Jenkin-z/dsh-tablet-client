import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent_server.dart';
import '../services/dsh/dsh_api.dart';
import '../services/opencode/opencode_api.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../widgets/server_list_card.dart';
import '../widgets/settings_entry.dart';

/// 设置 › 设备管理
///
/// 后端列表（DSH PC + opencode）、添加/授权入口、当前连接测试。
class SettingsServersPage extends StatefulWidget {
  const SettingsServersPage({super.key});

  @override
  State<SettingsServersPage> createState() => _SettingsServersPageState();
}

class _SettingsServersPageState extends State<SettingsServersPage> {
  bool _testing = false;
  String? _testResult;

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final s = Provider.of<SettingsService>(context, listen: false);
      final active = s.active;
      final ok = active == null
          ? false
          : switch (active.kind) {
              AgentKind.dsh => await DshApi(
                  baseUrl: s.serverUrl,
                  cookie: active.cookie,
                ).testConnection(),
              AgentKind.opencode => await OpenCodeApi(
                  baseUrl: active.httpUrl,
                  password: active.token,
                ).testConnection(),
            };
      if (!mounted) return;
      setState(() => _testResult = ok ? '连接正常 ✓' : '连接失败 ✗');
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = '连接失败: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSubPage(
      title: '设备管理',
      children: [
        SettingsGroup(
          title: '后端',
          children: [
            const ServerListCard(),
            ListTile(
              leading: Icon(
                Icons.wifi,
                color: IosTheme.iosBlue,
                size: 22,
              ),
              title: Text(
                '当前: ${Provider.of<SettingsService>(context).serverUrl}',
              ),
              subtitle: _testResult != null
                  ? Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testResult!.contains('✓')
                            ? IosTheme.iosGreen
                            : IosTheme.iosRed,
                      ),
                    )
                  : null,
              trailing: _testing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: IosTheme.iosBlue,
                      ),
                    )
                  : IosButton(
                      label: '测试',
                      filled: false,
                      onPressed: _testConnection,
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
