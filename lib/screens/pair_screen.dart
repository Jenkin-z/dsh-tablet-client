import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/agent_server.dart';
import '../services/dsh/dsh_auth.dart';
import '../services/dsh/lan_pair_auth.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import '../widgets/pair_info_card.dart';
import 'qr_scan_screen.dart';

/// 用 DSH 启动令牌换取 browser-session cookie（约 30 天，DSH 重启仍有效）
///
/// 五条路：
/// 1. 自动：PC 运行 tool/publish_launch_token.ps1 把令牌发到 8099，这里一键拉取
/// 2. 手动：粘贴 dsh web 启动输出的完整链接（http://IP:3080/?token=r_...）
/// 3. 配对页：PC 双击「手机授权.bat」，从 IP:8899 领自签 cookie（桌面端 19387）
/// 4. 扫码：启动令牌链接 / 8899 配对页 / lan-pair 的 /p/<码> 链接
/// 5. 配对码：dsh-lan-pair 闸门（默认 19387），输 PC 上显示的 4 位配对码；
///    已有设备 cookie 时打开本页自动静默续期，不用再要配对码
class PairScreen extends StatefulWidget {
  final String? existingServerId;
  const PairScreen({super.key, this.existingServerId});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final _paste = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 下一拍再跑，避开 initState 里直接 setState
    Future.microtask(_initExistingServer);
  }

  @override
  void dispose() {
    _paste.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  /// 重授权入口的进场动作：把现有别名预填进输入框；
  /// 设备 cookie 还在就静默续期（只换 DSH 会话，成功直接返回），
  /// 失败（设备被吊销等）落回常规界面输配对码
  Future<void> _initExistingServer() async {
    final id = widget.existingServerId;
    if (id == null || !mounted) return;
    final servers = context.read<SettingsService>().servers;
    final matches = servers.where((s) => s.id == id);
    if (matches.isEmpty) return;
    final server = matches.first;
    // 没有别名（name == host）就不填，留 hint；保存时留空按地址处理
    if (server.name != server.host) _name.text = server.name;
    final device = LanPairAuth.deviceCookieOf(server.cookie);
    if (device == null) return; // 旧授权方式，没有设备 cookie 可续
    setState(() => _busy = true);
    try {
      final g = await LanPairAuth.renew(
        host: server.host,
        port: server.port,
        deviceCookie: device,
      );
      await _finish(g.host, g.port, g.cookie);
    } catch (_) {
      // 续期失败不拦人：回常规界面重新授权（多半是要重输配对码）
      if (mounted) setState(() => _busy = false);
    }
  }

  /// dsh-lan-pair 配对码授权（闸门默认 19387）
  Future<void> _lanPairAuthorize() async {
    if (_busy) return;
    final target = LanPairAuth.parseAddress(_paste.text);
    if (target == null) {
      setState(() => _error =
          '无法识别地址。填 PC 的局域网 IP，可带端口：如 192.168.10.217、192.168.10.217:19388');
      return;
    }
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请输入配对码（PC 管理页 /__gate/admin 或 DSH 面板上显示的数字）');
      return;
    }
    await _run(() => LanPairAuth.authorizeWithCode(target, code));
  }

  Future<void> _autoAuthorize() async {
    if (_busy) return;
    final target = NativeAuth.parse(_paste.text);
    if (target == null) {
      setState(() => _error = '无法识别地址。任意 IP/主机名均可，如 192.168.10.171:3080、myhost:3080');
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

  /// 新方案：PC 双击「手机授权.bat」后，从 8899 配对页领 cookie
  Future<void> _pairPageAuthorize() async {
    if (_busy) return;
    final target = NativeAuth.parse(_paste.text);
    if (target == null) {
      setState(() => _error = '无法识别地址。填 PC 的 IP 或主机名即可，如 192.168.10.171、10.0.0.5、myhost');
      return;
    }
    await _run(() => NativeAuth.fetchFromPairServer(target.host));
  }

  Future<void> _authorizeWithToken() async {
    if (_busy) return;
    final target = NativeAuth.parse(_paste.text);
    if (target == null) {
      setState(() => _error = '无法识别，请粘贴完整启动链接（http://IP:3080/?token=...）');
      return;
    }
    if (!target.isPairServer &&
        (target.token == null || target.token!.isEmpty)) {
      setState(() => _error = '链接里没有 token。请复制 dsh web 启动输出的完整网址，或粘贴 8899 配对页地址');
      return;
    }
    await _run(() => NativeAuth.authorize(target));
  }

  Future<void> _run(Future<AuthGrant> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = await job();
      await _finish(g.host, g.port, g.cookie);
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
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (raw == null || !mounted) return;
    // lan-pair 配对二维码（http://IP:19387/p/<码>）：兑换即配对
    if (LanPairAuth.parsePairLink(raw) != null) {
      await _run(() => LanPairAuth.authorizeFromQr(raw));
      return;
    }
    final target = NativeAuth.parse(raw);
    if (target == null ||
        !(target.isPairServer ||
            (target.token != null && target.token!.isNotEmpty))) {
      setState(() => _error = '扫到的内容不是有效的 DSH 启动链接');
      return;
    }
    await _run(() => NativeAuth.authorize(target));
  }

  Future<void> _finish(String host, int port, String cookie) async {
    final settings = context.read<SettingsService>();
    final existingId = widget.existingServerId;
    final same = settings.servers.where((s) =>
        s.host == host && s.port == port &&
        (existingId == null || s.id == existingId));
    final id = existingId ?? (same.isEmpty ? const Uuid().v4() : same.first.id);
    final prev = settings.servers.where((s) => s.id == id);
    // 别名：输入框填了就覆盖；留空沿用旧名（没有旧条目才退回地址），
    // 这样重新配对一次不会把已有别名冲掉
    final alias = _name.text.trim();
    final keepName = prev.isEmpty ? host : prev.first.name;
    await settings.upsertServer(AgentServer(
      id: id,
      name: alias.isEmpty ? keepName : alias,
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

  /// 输入框公共样式（地址 / 配对码 / 名称共用，别复制三份）
  InputDecoration _field(String hint, bool isDark) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: IosTheme.iosGray),
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusInput),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: IosTheme.spaceL,
          vertical: IosTheme.spaceM,
        ),
      );

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
                  decoration:
                      _field('IP 或主机名:端口，如 192.168.10.171:3080', isDark),
                ),
                const SizedBox(height: IosTheme.spaceL),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 16, letterSpacing: 4),
                  decoration: _field('配对码：PC 管理页 / 面板上显示的 4 位数字', isDark),
                ),
                const SizedBox(height: IosTheme.spaceL),
                TextField(
                  controller: _name,
                  style: const TextStyle(fontSize: 16),
                  decoration: _field('名称（可选）：首页显示的别名，留空用地址', isDark),
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
                Row(
                  children: [
                    Expanded(
                      child: IosButton(
                        label: '配对页授权',
                        icon: Icons.phonelink_lock,
                        filled: false,
                        onPressed: _busy ? null : _pairPageAuthorize,
                      ),
                    ),
                    const SizedBox(width: IosTheme.spaceM),
                    Expanded(
                      child: IosButton(
                        label: '扫码授权',
                        icon: Icons.qr_code_scanner,
                        filled: false,
                        onPressed: _busy ? null : _scanAuthorize,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: IosTheme.spaceM),
                SizedBox(
                  width: double.infinity,
                  child: IosButton(
                    label: '配对码授权',
                    icon: Icons.pin,
                    onPressed: _busy ? null : _lanPairAuthorize,
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
          const PairInfoCard(),
        ],
      ),
    );
  }
}
