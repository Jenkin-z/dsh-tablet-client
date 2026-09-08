import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/dsh_server.dart';
import '../services/dsh_auth.dart';
import '../services/server_manager.dart';
import '../services/settings_service.dart';

/// 扫码或粘贴 /pair-accept?pair= 链接。RK3288 只有单摄，默认后摄。
class PairScreen extends StatefulWidget {
  final String? existingServerId;
  const PairScreen({super.key, this.existingServerId});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final _paste = TextEditingController(text: '192.168.10.171:3080');
  late final MobileScannerController _scanner;
  bool _busy = false;
  String? _error;
  bool _handled = false;
  CameraFacing _facing = CameraFacing.back;
  int _startAttempts = 0;

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(
      facing: CameraFacing.back,
      autoStart: false,
    );
    _scanner.addListener(_onScannerState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCam(CameraFacing.back));
  }

  void _onScannerState() {
    final s = _scanner.value;
    if (!s.isInitialized && s.error != null && mounted) {
      final code = s.error!.errorCode;
      final details = s.error?.errorDetails;
      final message = details?.message ?? '';
      final platformCode = details?.code ?? '';
      final cam = s.availableCameras ?? -1;
      String hint = '请用下面输入框粘贴配对链接。';
      if (code.toString().contains('permissionDenied')) {
        hint = '请在系统设置里允许相机权限，或直接粘贴链接。';
      } else if (code.toString().contains('unsupported')) {
        hint = '当前设备不支持扫码，请直接粘贴配对链接。';
      } else if (code.toString().contains('genericError')) {
        hint = '摄像头初始化失败（常见于低端板）。请直接粘贴配对链接。';
      }
      setState(() {
        _error = '摄像头打不开（$code；cameras=$cam；$platformCode）。\n$hint\n$message';
      });
    }
  }

  Future<void> _startCam(CameraFacing facing) async {
    if (_startAttempts >= 2) return;
    _startAttempts += 1;
    try {
      await _scanner.stop();
    } catch (_) {}
    try {
      await _scanner.start(cameraDirection: facing);
      if (mounted) setState(() => _facing = facing);
    } catch (_) {
      if (facing == CameraFacing.back) {
        await _startCam(CameraFacing.front);
      }
    }
  }

  Future<void> _flipCam() async {
    if (_startAttempts >= 2) return;
    final next = _facing == CameraFacing.front
        ? CameraFacing.back
        : CameraFacing.front;
    await _startCam(next);
  }

  Future<void> _openPairPage() async {
    final target = PairingClient.parse(_paste.text);
    final host = target?.host ?? '192.168.10.171';
    final port = target?.port ?? 3080;
    final uri = Uri.parse('http://$host:$port/pair-accept');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      setState(() => _error = '无法打开浏览器，请手动访问 http://$host:$port/pair-accept');
    }
  }

  Future<void> _autoReadTokenAndPair() async {
    if (_busy) return;
    final target = PairingClient.parse(_paste.text);
    final host = target?.host ?? '192.168.10.171';
    final port = target?.port ?? 3080;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await PairingClient.fetchTokenFromPairPage(host, port);
      if (token == null || !mounted) {
        setState(() => _error = '未在配对页读到令牌，请手动复制令牌粘贴后点“粘贴链接配对”');
        return;
      }
      await _submit('http://$host:$port/pair-accept?pair=$token');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '自动读取失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit(String raw, {bool skipPair = false}) async {
    if (_busy) return;
    final target = PairingClient.parse(raw);
    if (target == null) {
      setState(() => _error = '无法识别，请输入 IP 或完整链接');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? deviceId;
      if (!skipPair && target.token != null && target.token!.isNotEmpty) {
        try {
          deviceId = await PairingClient.accept(target);
        } on DshAuthException catch (e) {
          if (e.status == 404) {
            deviceId = null;
          } else {
            rethrow;
          }
        }
      }
      if (!mounted) return;
      final settings = context.read<SettingsService>();
      final existingId = widget.existingServerId;
      final same = settings.servers.where((s) =>
          s.host == target.host &&
          s.port == target.port &&
          (existingId == null || s.id == existingId));
      final id = existingId ?? (same.isEmpty ? const Uuid().v4() : same.first.id);
      final prev = settings.servers.where((s) => s.id == id);
      await settings.upsertServer(DshServer(
        id: id,
        name: prev.isEmpty ? target.host : prev.first.name,
        host: target.host,
        port: target.port,
        deviceId: deviceId,
        lastSessionId: prev.isEmpty ? null : prev.first.lastSessionId,
        unpaired: false,
      ));
      await settings.setActiveServer(id);
      await context.read<ServerManager>().refreshAll();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _handled = false;
        _error = '$e';
      });
    }
  }

  @override
  void dispose() {
    _scanner.removeListener(_onScannerState);
    _paste.dispose();
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加 / 配对 PC'),
        actions: [
          IconButton(
            tooltip: _facing == CameraFacing.front ? '切换后置' : '切换前置',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: _busy ? null : _flipCam,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scanner,
                  errorBuilder: (context, error, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '摄像头打不开（${error.errorCode}）。\n请用下面输入框粘贴配对链接。',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  onDetect: (barcodes) {
                    if (_handled || _busy) return;
                    final v = barcodes.barcodes
                        .map((b) => b.rawValue)
                        .whereType<String>()
                        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
                    if (v.isEmpty) return;
                    _handled = true;
                    _submit(v);
                  },
                ),
                if (_scanner.value.isRunning && _scanner.value.availableCameras == 1)
                  const Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      '检测到单个摄像头，请把屏幕朝向 PC 上的二维码；也可直接粘贴链接',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, shadows: [
                        Shadow(blurRadius: 6, color: Colors.black),
                      ]),
                    ),
                  ),
                if (_busy)
                  const ColoredBox(
                    color: Color(0x88000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _paste,
                  decoration: const InputDecoration(
                    labelText: '配对链接或令牌',
                    hintText: '完整链接，或仅粘贴 32 位令牌',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : () => _submit(_paste.text),
                        child: const Text('粘贴链接配对'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _busy ? null : () => _submit(_paste.text, skipPair: true),
                        child: const Text('直接连接'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _autoReadTokenAndPair,
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: const Text('自动读取令牌并配对'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '在浏览器中打开配对页',
                      onPressed: _busy ? null : _openPairPage,
                      icon: const Icon(Icons.public_outlined),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
