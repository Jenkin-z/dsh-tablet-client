import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/dsh_auth.dart';
import '../theme/ios_theme.dart';

/// 扫码授权页面：扫描 DSH 启动链接二维码（含 token）
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  MobileScannerController? _controller;
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy || _done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _handleResult(raw);
      return;
    }
  }

  Future<void> _handleResult(String raw) async {
    final target = NativeAuth.parse(raw);
    if (target == null || target.token == null || target.token!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('未识别到有效链接，请扫描 DSH 启动二维码'),
          backgroundColor: IosTheme.iosRed,
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final cookie = await NativeAuth.exchangeCookie(target);
      if (!mounted) return;
      Navigator.of(context).pop(
        PairResult(host: target.host, port: target.port, cookie: cookie),
      );
    } on DshAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: IosTheme.iosRed,
        ),
      );
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('授权失败: $e'),
          backgroundColor: IosTheme.iosRed,
        ),
      );
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          '扫描授权',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller!,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                  color: Colors.white,
                );
              },
            ),
            onPressed: () => _controller?.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller!,
            onDetect: _onDetect,
          ),
          // 扫描框提示
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: IosTheme.iosBlue.withValues(alpha: 0.8),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // 底部提示
          Positioned(
            left: 0,
            right: 0,
            bottom: 80,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _busy ? '正在授权...' : '将 DSH 启动二维码放入框内',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 扫码授权结果
class PairResult {
  final String host;
  final int port;
  final String cookie;

  const PairResult({
    required this.host,
    required this.port,
    required this.cookie,
  });
}
