import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/dsh/dsh_auth.dart';
import '../services/opencode/opencode_target.dart';
import '../theme/ios_theme.dart';

/// 扫码页面向的链接类型（决定格式校验与提示文案）
enum QrScanExpect {
  /// DSH 启动链接（含 token）或 8899 配对页地址
  dshLink,

  /// opencode 授权链接（/auth/connect/<code>）
  opencodeLink,
}

/// 扫码授权页面：把二维码内容原样带回给调用方
///
/// 本页只做「扫码 + 格式校验」，授权的网络动作由调用方完成——
/// 这样 DSH 与 opencode 两套授权流程可以共用同一个扫码入口。
class QrScanScreen extends StatefulWidget {
  final QrScanExpect expect;

  const QrScanScreen({super.key, this.expect = QrScanExpect.dshLink});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  MobileScannerController? _controller;

  /// 无效码冷却：相机每帧都会重复识别同一张二维码，
  /// 不去重的话 SnackBar 会连环轰炸（曾经的线上体验问题）。
  String? _lastInvalidRaw;
  DateTime? _lastInvalidAt;
  static const _invalidCooldown = Duration(seconds: 3);

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

  bool _isValid(String raw) => switch (widget.expect) {
        QrScanExpect.dshLink => () {
            final t = NativeAuth.parse(raw);
            return t != null &&
                (t.isPairServer ||
                    (t.token != null && t.token!.isNotEmpty));
          }(),
        // 授权链接（含 /auth/connect/<code>）或局域网地址二维码都收，
        // 由调用方按内容决定填哪个模式
        QrScanExpect.opencodeLink => parseOpenCodeTarget(raw) != null,
      };

  String get _invalidHint => switch (widget.expect) {
        QrScanExpect.dshLink => '未识别到有效链接，请扫描 DSH 启动二维码',
        QrScanExpect.opencodeLink => '未识别到有效地址，请扫描 opencode 授权二维码或地址二维码',
      };

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _handleResult(raw);
      return;
    }
  }

  void _handleResult(String raw) {
    if (_isValid(raw)) {
      Navigator.of(context).pop(raw);
      return;
    }
    // 无效码冷却：同一条内容 3 秒内只提示一次，换内容立即提示
    final now = DateTime.now();
    final last = _lastInvalidAt;
    final same = _lastInvalidRaw == raw;
    if (same && last != null && now.difference(last) < _invalidCooldown) {
      return;
    }
    _lastInvalidRaw = raw;
    _lastInvalidAt = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(_invalidHint),
        backgroundColor: IosTheme.iosRed,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final hint = switch (widget.expect) {
      QrScanExpect.dshLink => '将 DSH 启动二维码放入框内',
      QrScanExpect.opencodeLink => '将 opencode 授权二维码放入框内',
    };
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          '扫码连接',
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
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
