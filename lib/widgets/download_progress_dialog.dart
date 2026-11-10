import 'package:flutter/material.dart';
import '../services/update_service.dart';
import '../theme/ios_theme.dart';

/// 下载进度弹窗 —— iOS 风格
///
/// 从 update_dialog.dart 拆出来是为了守住 200 行上限。
/// 下载/安装的编排逻辑在 [DownloadProgressDialog._start]。
///
/// 状态行借鉴 dsh-go marketplace 详情页的 security 面板：
/// 发布指纹全程可见，校验通过前只显示指纹、通过后给「已校验」，
/// 兑现「声明 ≠ 已验证」。
class DownloadProgressDialog extends StatefulWidget {
  final UpdateInfo info;

  const DownloadProgressDialog({super.key, required this.info});

  @override
  State<DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<DownloadProgressDialog> {
  double _progress = 0;
  UpdateDlPhase _phase = UpdateDlPhase.downloading;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _progress = 0;
      _phase = UpdateDlPhase.downloading;
    });
    try {
      final file = await UpdateService.download(
        widget.info.url,
        (p) {
          if (mounted) setState(() => _progress = p);
        },
        sha256: widget.info.sha256,
        size: widget.info.size,
        onPhase: (p) {
          if (mounted) setState(() => _phase = p);
        },
      );
      if (!mounted) return;
      setState(() => _done = true);
      // 未允许"安装未知应用"：先跳系统开关页，回来再点安装
      final allowed = await UpdateService.canInstallUnknown();
      if (!mounted) return;
      if (!allowed) {
        await UpdateService.openUnknownAppSources();
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请允许"安装未知应用"后，重新检查更新完成安装（已校验的包会复用，不会重新下载）'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
      try {
        await UpdateService.installApk(file.path);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = '安装失败: $e');
      }
    } on UpdateVerifyException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '下载失败: $e');
    }
  }

  String get _title {
    if (_error != null) return '更新失败';
    if (_done) return '已校验，准备安装';
    if (_phase == UpdateDlPhase.verifying) return '正在校验完整性…';
    return '正在下载 ${(_progress * 100).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IosTheme.radiusM),
      ),
      title: Text(
        _title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: _error != null
          ? Text(_error!)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _done ? 1 : (_phase == UpdateDlPhase.verifying ? null : _progress),
                    backgroundColor: isDark
                        ? const Color(0xFF3A3A3C)
                        : const Color(0xFFF2F2F7),
                    color: IosTheme.iosBlue,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: IosTheme.spaceM),
                Text(
                  '${widget.info.versionName} · ${widget.info.sizeText}',
                  style: TextStyle(
                    fontSize: 14,
                    color: IosTheme.iosGray,
                  ),
                ),
                if (widget.info.sha256 != null) ...[
                  const SizedBox(height: IosTheme.spaceS),
                  Row(
                    children: [
                      Icon(
                        _done ? Icons.verified_outlined : Icons.fingerprint,
                        size: 16,
                        color: _done ? IosTheme.iosGreen : IosTheme.iosGray,
                      ),
                      const SizedBox(width: IosTheme.spaceS),
                      Expanded(
                        child: Text(
                          _done
                              ? 'SHA-256 已校验 · ${widget.info.fingerprintShort}'
                              : '发布指纹 ${widget.info.fingerprintShort} · 下载后逐字节校验',
                          style: TextStyle(
                            fontSize: 12,
                            color: _done ? IosTheme.iosGreen : IosTheme.iosGray,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: IosTheme.spaceXS),
                Text(
                  '下载完成后自动调起安装，可在后台继续聊天',
                  style: TextStyle(
                    fontSize: 12,
                    color: IosTheme.iosGray,
                  ),
                ),
              ],
            ),
      actions: [
        if (_error != null) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '取消',
              style: TextStyle(
                color: IosTheme.iosBlue,
                fontSize: 17,
              ),
            ),
          ),
          FilledButton(
            onPressed: _start,
            style: FilledButton.styleFrom(
              backgroundColor: IosTheme.iosBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(IosTheme.radiusButton),
              ),
            ),
            child: const Text('重试'),
          ),
        ],
      ],
    );
  }
}
