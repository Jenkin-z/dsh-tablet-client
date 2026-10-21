import 'package:flutter/material.dart';

import '../services/keep_alive_service.dart';
import '../theme/ios_theme.dart';

/// 前台服务开关（保活）：开启后在通知栏常驻通知，系统不会杀进程
class ForegroundServiceTile extends StatefulWidget {
  const ForegroundServiceTile({super.key});

  @override
  State<ForegroundServiceTile> createState() => _ForegroundServiceTileState();
}

class _ForegroundServiceTileState extends State<ForegroundServiceTile> {
  bool _running = false;
  bool _batteryOk = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final running = await KeepAliveService.isRunning;
    final battery = await KeepAliveService.ignoringBatteryOptimizations;
    if (mounted) {
      setState(() {
        _running = running;
        _batteryOk = battery;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    final running =
        value ? await KeepAliveService.start() : await KeepAliveService.stop();
    if (!mounted) return;
    setState(() => _running = running);
    if (value && !running) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('前台保活没有启动，请检查通知权限')),
      );
    }
  }

  Future<void> _requestBattery() async {
    await KeepAliveService.requestIgnoreBatteryOptimization();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          secondary: Icon(Icons.shield_outlined,
              color: IosTheme.iosGreen, size: 22),
          title: const Text('前台保活服务'),
          subtitle: const Text('启动时自动开启；关掉后切到后台将收不到通知',
              style: TextStyle(fontSize: 13)),
          value: _running,
          onChanged: _toggle,
          activeThumbColor: IosTheme.iosGreen,
        ),
        if (!_batteryOk)
          ListTile(
            leading: Icon(Icons.battery_alert_outlined,
                color: IosTheme.iosOrange, size: 22),
            title: const Text('忽略电池优化'),
            subtitle: const Text('未加入白名单，熄屏后可能被系统冻结',
                style: TextStyle(fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: _requestBattery,
          ),
      ],
    );
  }
}
