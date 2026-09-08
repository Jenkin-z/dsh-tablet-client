import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dsh_server.dart';
import '../screens/pair_screen.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';

/// 设置页：PC 列表 + 添加/授权入口
class ServerListCard extends StatelessWidget {
  const ServerListCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsService, ServerManager>(
      builder: (context, settings, manager, _) {
        return Card(
          child: Column(
            children: [
              for (final s in settings.servers)
                _tile(context, settings, manager, s),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('添加 / 授权 PC'),
                subtitle: const Text('用 DSH 启动令牌换取 30 天授权'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PairScreen()),
                ),
              ),
            ],
          ),
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
    return ListTile(
      leading: Icon(
        Icons.computer,
        color: s.unpaired
            ? Colors.orange
            : (mon?.online == true ? Colors.green : Colors.grey),
      ),
      title: Text(s.name),
      subtitle: Text('${s.host}:${s.port} · $status'),
      selected: active,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.unpaired || s.cookie == null)
            IconButton(
              icon: const Icon(Icons.key_outlined),
              tooltip: '重新授权',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PairScreen(existingServerId: s.id),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
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
