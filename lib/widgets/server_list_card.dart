import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/agent_server.dart';
import '../screens/pair_screen.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import 'add_opencode_dialog.dart';

/// 设置页：后端列表（DSH PC + opencode）+ 添加/授权入口 —— iOS 风格
///
/// 不再包裹 Card，由父级 IosGroupedList 提供分组容器。
class ServerListCard extends StatelessWidget {
  const ServerListCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsService, ServerManager>(
      builder: (context, settings, manager, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in settings.servers)
              _tile(context, settings, manager, s),
            ListTile(
              leading: Icon(
                Icons.key_outlined,
                color: IosTheme.iosBlue,
                size: 22,
              ),
              title: const Text('添加 / 授权 PC'),
              subtitle: const Text(
                '用 DSH 启动令牌换取 30 天授权',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                size: 20,
                color: IosTheme.iosGray3,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PairScreen()),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.terminal,
                color: IosTheme.iosPurple,
                size: 22,
              ),
              title: const Text('添加 opencode'),
              subtitle: const Text(
                '粘贴授权链接，或填局域网地址 + 服务密码',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                size: 20,
                color: IosTheme.iosGray3,
              ),
              onTap: () => _addOpenCode(context),
            ),
          ],
        );
      },
    );
  }

  /// 打开添加/重新授权对话框，返回 true 表示刚保存过
  Future<bool?> _addOpenCode(BuildContext context, {String? existingServerId}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AddOpenCodeDialog(existingServerId: existingServerId),
    );
  }

  Widget _tile(
    BuildContext context,
    SettingsService settings,
    ServerManager manager,
    AgentServer s,
  ) {
    final mon = manager.monitorOf(s.id);
    final active = settings.activeServerId == s.id;
    final status = s.unpaired
        ? '需重新授权'
        : (mon?.online == true ? '在线' : (mon?.error ?? '离线'));
    final statusColor = s.unpaired
        ? IosTheme.iosOrange
        : (mon?.online == true ? IosTheme.iosGreen : IosTheme.iosGray);
    final isOpenCode = s.kind == AgentKind.opencode;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(IosTheme.radiusXS),
        ),
        child: Icon(
          isOpenCode ? Icons.terminal : Icons.computer,
          color: statusColor,
          size: 20,
        ),
      ),
      title: Text(
        s.name,
        style: TextStyle(
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        '${s.displayAddress} · $status',
        style: const TextStyle(fontSize: 13),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // DSH 条目走配对页换 cookie；opencode 条目走授权链接/密码，
          // 不显示 DSH 的钥匙按钮（两种授权体系不互通）
          if (isOpenCode
              ? s.unpaired
              : (s.unpaired || s.cookie == null))
            IconButton(
              icon: Icon(
                Icons.key_outlined,
                color: IosTheme.iosOrange,
                size: 20,
              ),
              tooltip: '重新授权',
              onPressed: () async {
                if (isOpenCode) {
                  await _addOpenCode(context, existingServerId: s.id);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PairScreen(existingServerId: s.id),
                    ),
                  );
                }
              },
            ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: IosTheme.iosRed.withValues(alpha: 0.7),
              size: 20,
            ),
            tooltip: '删除',
            onPressed: () async {
              await settings.removeServer(s.id);
              await manager.refreshAll();
            },
          ),
        ],
      ),
      onTap: () async {
        await settings.setActiveServer(s.id);
        await manager.refreshAll();
      },
    );
  }
}
