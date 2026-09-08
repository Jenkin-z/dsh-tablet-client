import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/dsh_server.dart';
import '../services/dsh_auth.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';

/// 用 DSH 启动令牌换取 browser-session cookie（约 30 天，DSH 重启仍有效）
///
/// 两条路：
/// 1. 自动：PC 运行 tool/publish_launch_token.ps1 把令牌发到 8099，这里一键拉取
/// 2. 手动：粘贴 dsh web 启动输出的完整链接（http://IP:3080/?token=r_...）
class PairScreen extends StatefulWidget {
  final String? existingServerId;
  const PairScreen({super.key, this.existingServerId});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final _paste = TextEditingController(text: '192.168.10.171:3080');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _autoAuthorize() async {
    if (_busy) return;
    final target = NativeAuth.parse(_paste.text);
    if (target == null) {
      setState(() => _error = '无法识别，请输入 PC 地址（如 192.168.10.171:3080）');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final relay = await NativeAuth.fetchFromRelay(target.host);
      final cookie = await NativeAuth.exchangeCookie(relay);
      await _finish(target.host, target.port, cookie);
    } on DshAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '自动授权失败: $e';
      });
    }
  }

  Future<void> _authorizeWithToken() async {
    if (_busy) return;
    final target = NativeAuth.parse(_paste.text);
    if (target == null) {
      setState(() => _error = '无法识别，请粘贴完整启动链接（http://IP:3080/?token=...）');
      return;
    }
    if (target.token == null || target.token!.isEmpty) {
      setState(() => _error = '链接里没有 token。请复制 dsh web 启动输出的完整网址，或在 PC 上运行发布脚本后点“自动授权”');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cookie = await NativeAuth.exchangeCookie(target);
      await _finish(target.host, target.port, cookie);
    } on DshAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '授权失败: $e';
      });
    }
  }

  Future<void> _finish(String host, int port, String cookie) async {
    final settings = context.read<SettingsService>();
    final existingId = widget.existingServerId;
    final same = settings.servers.where((s) =>
        s.host == host && s.port == port &&
        (existingId == null || s.id == existingId));
    final id = existingId ?? (same.isEmpty ? const Uuid().v4() : same.first.id);
    final prev = settings.servers.where((s) => s.id == id);
    await settings.upsertServer(DshServer(
      id: id,
      name: prev.isEmpty ? host : prev.first.name,
      host: host,
      port: port,
      cookie: cookie,
      lastSessionId: prev.isEmpty ? null : prev.first.lastSessionId,
      unpaired: false,
    ));
    await settings.setActiveServer(id);
    await context.read<ServerManager>().refreshAll();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加 / 授权 PC')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _paste,
            decoration: const InputDecoration(
              labelText: 'PC 地址或启动令牌链接',
              hintText: '192.168.10.171:3080 或 http://IP:3080/?token=r_...',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _autoAuthorize,
            child: const Text('自动授权（推荐）'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _authorizeWithToken,
            child: const Text('粘贴启动令牌授权'),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 24),
          Text(
            '说明\n'
            '· 启动令牌在 PC 上 dsh web 启动输出的网址里（?token=r_...），'
            '每个 DSH 进程一份，重启后会变\n'
            '· 换到的授权默认 30 天有效，DSH 重启不用重新授权\n'
            '· 自动方式：在 PC 上运行 tool\\publish_launch_token.ps1，'
            '令牌会发到 8099 下载服务，平板一键拉取',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
