import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/agent_server.dart';
import '../screens/qr_scan_screen.dart';
import '../services/opencode/opencode_api.dart';
import '../services/opencode/opencode_target.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';
import '../theme/ios_theme.dart';
import 'opencode_server_form.dart';

/// 添加 opencode 后端（两种接入方式）
///
/// 1. 授权链接：`opencode pair --remote` 生成的
///    `https://<隧道域名>/auth/connect/<code>`（码 300s 有效），
///    贴入后自动换取令牌，之后的 API 全部走 `opencode:<token>`；
/// 2. 手动连接：局域网直连 `http://<IP>:4096` + 服务密码
///    （PC 端需 `opencode serve --hostname 0.0.0.0`）。
///
/// [existingServerId] 非空 = 重新授权（保留条目，只更新凭据）。
class AddOpenCodeDialog extends StatefulWidget {
  final String? existingServerId;
  const AddOpenCodeDialog({super.key, this.existingServerId});

  @override
  State<AddOpenCodeDialog> createState() => _AddOpenCodeDialogState();
}

class _AddOpenCodeDialogState extends State<AddOpenCodeDialog> {
  final _link = TextEditingController();
  final _url = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  bool _linkMode = true;
  bool _busy = false;
  String? _error;

  AgentServer? get _existing {
    final id = widget.existingServerId;
    if (id == null) return null;
    final settings = context.read<SettingsService>();
    for (final s in settings.servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final e = _existing;
    if (e != null) {
      _linkMode = false;
      _url.text = e.httpUrl;
      _name.text = e.name;
    }
  }

  @override
  void dispose() {
    _link.dispose();
    _url.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  /// 按模式取令牌：授权链接换码 / 手动连接先验再存。
  /// 失败时写 _error 并返回 null。
  Future<String?> _acquireToken(OpenCodeTarget target) async {
    if (_linkMode) {
      final code = target.pairCode;
      if (code == null) {
        setState(() => _error = '链接里没有授权码：请粘贴 opencode pair --remote 输出的完整链接');
        return null;
      }
      return OpenCodeApi(baseUrl: target.baseUrl).exchangePairCode(code);
    }
    final password = _password.text.trim();
    if (password.isEmpty) {
      setState(() => _error = '请填服务密码（PC 端 opencode serve 的 OPENCODE_SERVER_PASSWORD）');
      return null;
    }
    // 先验再存：密码错当场说，别存一个连不上的条目
    final ok = await OpenCodeApi(baseUrl: target.baseUrl, password: password)
        .testConnection();
    if (!ok) {
      setState(() => _error = '连不上 $target.baseUrl：PC 上 opencode serve 起了吗？');
      return null;
    }
    return password;
  }

  /// 扫码填入：授权二维码（含 /auth/connect/<code>）→ 链接模式；
  /// 局域网地址二维码 → 手动模式。识别不出给错误提示。
  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            const QrScanScreen(expect: QrScanExpect.opencodeLink),
      ),
    );
    if (raw == null || !mounted) return;
    final target = parseOpenCodeTarget(raw);
    if (target == null) {
      setState(() => _error = '扫到的内容不是有效的 opencode 地址');
      return;
    }
    if (target.pairCode != null) {
      _link.text = raw.trim();
      setState(() {
        _linkMode = true;
        _error = null;
      });
    } else {
      _url.text = target.baseUrl;
      setState(() {
        _linkMode = false;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = parseOpenCodeTarget(_linkMode ? _link.text : _url.text);
      if (target == null) {
        setState(() => _error = '无法识别地址：请粘贴完整授权链接，或填 http://IP:4096');
        return;
      }

      final token = await _acquireToken(target);
      if (token == null) return;

      final settings = context.read<SettingsService>();
      final existing = _existing;
      final id = existing?.id ?? const Uuid().v4();
      final name = _name.text.trim().isNotEmpty
          ? _name.text.trim()
          : (existing?.name ?? target.host);
      await settings.upsertServer(AgentServer(
        id: id,
        name: name,
        kind: AgentKind.opencode,
        host: target.host,
        port: target.port,
        url: target.baseUrl,
        token: token,
        lastSessionId: existing?.lastSessionId,
        unpaired: false,
      ));
      await settings.setActiveServer(id);
      await context.read<ServerManager>().refreshAll();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on OpenCodeAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '添加失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existingServerId == null ? '添加 opencode' : '重新授权 opencode'),
      content: OpenCodeServerForm(
        link: _link,
        url: _url,
        password: _password,
        name: _name,
        linkMode: _linkMode,
        busy: _busy,
        error: _error,
        onModeChanged: (v) => setState(() => _linkMode = v),
        onScan: _scan,
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        IosButton(
          label: '测试并保存',
          onPressed: _busy ? null : _save,
        ),
      ],
    );
  }
}
