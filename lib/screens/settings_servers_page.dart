import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/backend_ops.dart';
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
      // 连接测试也走转接层（BackendOps 临时装配 backend，不直连具体 API 类）
      final ok = await BackendOps(s).testConnection();
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
    final p = IosPalette.of(context);
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
                color: p.accent,
                size: 22,
              ),
              title: Text(
                '当前: ${Provider.of<SettingsService>(context).serverUrl}',
              ),
              subtitle: _testResult != null
                  ? Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testResult!.contains('✓') ? p.ok : p.bad,
                      ),
                    )
                  : null,
              trailing: _testing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: p.accent,
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
