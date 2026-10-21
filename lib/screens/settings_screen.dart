import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/agent_server.dart';
import '../services/dsh/dsh_api.dart';
import '../services/notification_service.dart';
import '../services/opencode/opencode_api.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../theme/ios_theme.dart';
import '../widgets/foreground_service_tile.dart';
import '../widgets/server_list_card.dart';
import '../widgets/sound_settings.dart';
import '../widgets/update_dialog.dart';

/// 设置界面 —— iOS 风格分组列表
///
/// 使用单层 ListView，每个分节用 IosCard 包裹，避免嵌套滚动冲突。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  Future<void> _newSession() async {
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已创建新会话，返回对话页重连生效')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, s, _) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('设置')),
        body: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: IosTheme.spaceL,
            vertical: IosTheme.spaceM,
          ),
          children: [
            // ── PC ──
            const IosSectionHeader(title: 'PC'),
            IosCard(
              child: Column(
                children: [
                  const ServerListCard(),
                  _testConnectionTile(),
                ],
              ),
            ),
            const SizedBox(height: IosTheme.spaceL),

            // ── 平板常驻 ──
            const IosSectionHeader(title: '平板常驻'),
            IosCard(
              child: Column(
                children: [
                  _switchTile(
                    icon: Icons.lightbulb_outline,
                    iconColor: IosTheme.iosOrange,
                    title: '屏幕常亮',
                    subtitle: '防止平板自动锁屏熄屏',
                    value: s.keepScreenOn,
                    onChanged: (v) async {
                      await s.setKeepScreenOn(v);
                      await WakelockPlus.toggle(enable: v);
                    },
                  ),
                  _divider(),
                  const ForegroundServiceTile(),
                  _divider(),
                  _switchTile(
                    icon: Icons.autorenew,
                    iconColor: IosTheme.iosGreen,
                    title: '断线自动重连',
                    subtitle: '网络恢复后自动连回 DSH',
                    value: s.autoReconnect,
                    onChanged: (v) => s.setAutoReconnect(v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: IosTheme.spaceL),

            // ── 外观 ──
            const IosSectionHeader(title: '外观'),
            IosCard(
              child: _themeSegmentTile(s),
            ),
            const SizedBox(height: IosTheme.spaceL),

            // ── 提示音 + 自定义铃声 ──
            SoundSettingsSection(settings: s),
            const SizedBox(height: IosTheme.spaceL),

            // ── 通知测试 ──
            const IosSectionHeader(title: '通知测试'),
            IosCard(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.notifications_active_outlined,
                      color: IosTheme.iosBlue,
                    ),
                    title: const Text('发送测试通知'),
                    subtitle: const Text('验证系统通知是否正常弹出（含声音+震动）'),
                    trailing: const Icon(Icons.chevron_right, size: 20),
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
            ),
            const SizedBox(height: IosTheme.spaceL),

            // ── 应用更新 ──
            const IosSectionHeader(title: '应用更新'),
            IosCard(
              child: Column(
                children: [
                  _updateVersionTile(s),
                  _divider(),
                  _switchTile(
                    icon: Icons.system_update_outlined,
                    iconColor: IosTheme.iosBlue,
                    title: '启动时自动检查',
                    subtitle: '局域网小文件请求，无更新不打扰',
                    value: s.updateAutoCheck,
                    onChanged: (v) => s.setUpdateAutoCheck(v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: IosTheme.spaceL),

            // ── 会话 ──
            const IosSectionHeader(title: '会话'),
            IosCard(
              child: Column(
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
                  _divider(),
                  ListTile(
                    leading: Icon(
                      Icons.add_circle_outline,
                      color: IosTheme.iosGreen,
                      size: 22,
                    ),
                    title: const Text('新建会话'),
                    subtitle: const Text('另起一段对话，旧记录保留在 PC 端'),
                    trailing: const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: IosTheme.iosGray3,
                    ),
                    onTap: _newSession,
                  ),
                ],
              ),
            ),
            const SizedBox(height: IosTheme.spaceXXXL),
          ],
        ),
      ),
    );
  }

  /// iOS 风格分隔线
  Widget _divider() {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 56),
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06),
    );
  }

  Widget _testConnectionTile() {
    return ListTile(
      leading: Icon(
        Icons.wifi,
        color: IosTheme.iosBlue,
        size: 22,
      ),
      title: Text('当前: ${Provider.of<SettingsService>(context).serverUrl}'),
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
    );
  }

  Widget _switchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: iconColor, size: 22),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: IosTheme.iosGreen,
    );
  }

  Widget _themeSegmentTile(SettingsService s) {
    return Padding(
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
    );
  }

  Widget _updateVersionTile(SettingsService s) {
    return FutureBuilder<String>(
      future: UpdateService.currentVersion(),
      builder: (context, snap) => ListTile(
        leading: Icon(
          Icons.info_outline,
          color: IosTheme.iosGray,
          size: 22,
        ),
        title: const Text('当前版本'),
        subtitle: Text(snap.data ?? '…', style: const TextStyle(fontSize: 13)),
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
    );
  }
}
