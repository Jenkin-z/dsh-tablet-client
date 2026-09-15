import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/dsh_server.dart';
import '../services/dsh_auth.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import 'qr_scan_screen.dart';

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

  Future<void> _scanAuthorize() async {
    if (_busy) return;
    final result = await Navigator.of(context).push<PairResult>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || !mounted) return;
    await _finish(result.host, result.port, result.cookie);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : IosTheme.iosGroupedBg,
      appBar: AppBar(
        title: const Text(
          '添加 / 授权 PC',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(IosTheme.spaceL),
        children: [
          // 输入区域
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(IosTheme.radiusCard),
              boxShadow: IosTheme.shadowS,
            ),
            padding: const EdgeInsets.all(IosTheme.spaceL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PC 地址',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: IosTheme.spaceS),
                TextField(
                  controller: _paste,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: '192.168.10.171:3080',
                    hintStyle: TextStyle(color: IosTheme.iosGray),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFF2F2F7),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(IosTheme.radiusInput),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: IosTheme.spaceL,
                      vertical: IosTheme.spaceM,
                    ),
                  ),
                ),
                const SizedBox(height: IosTheme.spaceL),
                // 按钮区域
                Row(
                  children: [
                    Expanded(
                      child: IosButton(
                        label: '自动授权',
                        icon: Icons.touch_app,
                        onPressed: _busy ? null : _autoAuthorize,
                      ),
                    ),
                    const SizedBox(width: IosTheme.spaceM),
                    Expanded(
                      child: IosButton(
                        label: '令牌授权',
                        icon: Icons.vpn_key,
                        filled: false,
                        onPressed: _busy ? null : _authorizeWithToken,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: IosTheme.spaceM),
                // 扫码按钮
                SizedBox(
                  width: double.infinity,
                  child: IosButton(
                    label: '扫码授权',
                    icon: Icons.qr_code_scanner,
                    filled: false,
                    onPressed: _busy ? null : _scanAuthorize,
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: IosTheme.spaceL),
                  const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: IosTheme.iosBlue,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 错误信息
          if (_error != null) ...[
            const SizedBox(height: IosTheme.spaceM),
            Container(
              padding: const EdgeInsets.all(IosTheme.spaceM),
              decoration: BoxDecoration(
                color: IosTheme.iosRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(IosTheme.radiusS),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: IosTheme.iosRed,
                    size: 20,
                  ),
                  const SizedBox(width: IosTheme.spaceS),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: IosTheme.iosRed,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 说明区域
          const SizedBox(height: IosTheme.spaceXXL),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(IosTheme.radiusCard),
              boxShadow: IosTheme.shadowS,
            ),
            padding: const EdgeInsets.all(IosTheme.spaceL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '说明',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: IosTheme.spaceM),
                _infoRow(
                  icon: Icons.link,
                  text: '启动令牌在 PC 上 dsh web 启动输出的网址里（?token=r_...），每个 DSH 进程一份，重启后会变',
                ),
                const SizedBox(height: IosTheme.spaceS),
                _infoRow(
                  icon: Icons.schedule,
                  text: '换到的授权默认 30 天有效，DSH 重启不用重新授权',
                ),
                const SizedBox(height: IosTheme.spaceS),
                _infoRow(
                  icon: Icons.auto_fix_high,
                  text: '自动方式：在 PC 上运行 tool\\publish_launch_token.ps1，令牌会发到 8099 下载服务，平板一键拉取',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: IosTheme.iosGray),
        const SizedBox(width: IosTheme.spaceS),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: IosTheme.iosGray,
            ),
          ),
        ),
      ],
    );
  }
}
