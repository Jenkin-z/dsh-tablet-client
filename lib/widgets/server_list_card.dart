import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dsh_server.dart';
import '../screens/pair_screen.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';

/// 设置页：PC 列表 + 添加/授权入口 —— iOS 风格
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
          ],
        );
      },
    );
  }

  Widget _tile(
    BuildContext context,
    SettingsService settings,
    ServerManager manager,
    DshServer s,
  ) {
    final mon = manager.monitorOf(s.id);
    final active = settings.activeServerId == s.id;
    final status = s.unpaired
        ? '需重新授权'
        : (mon?.online == true ? '在线' : (mon?.error ?? '离线'));
    final statusColor = s.unpaired
        ? IosTheme.iosOrange
        : (mon?.online == true ? IosTheme.iosGreen : IosTheme.iosGray);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(IosTheme.radiusXS),
        ),
        child: Icon(
          Icons.computer,
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
        '${s.host}:${s.port} · $status',
        style: const TextStyle(fontSize: 13),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.unpaired || s.cookie == null)
            IconButton(
              icon: Icon(
                Icons.key_outlined,
                color: IosTheme.iosOrange,
                size: 20,
              ),
              tooltip: '重新授权',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PairScreen(existingServerId: s.id),
                ),
              ),
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
