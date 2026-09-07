import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dsh_server.dart';
import '../screens/pair_screen.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';

/// 设置页：已配对 PC 列表 + 扫码添加
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
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('扫码添加 PC'),
                subtitle: const Text('扫描 DSH 网页上的配对二维码'),
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
        ? '需重新配对'
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
          if (s.unpaired || s.deviceId == null)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: '配对',
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
