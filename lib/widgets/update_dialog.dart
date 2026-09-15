import 'package:flutter/material.dart';
import '../services/update_service.dart';
import '../theme/ios_theme.dart';

/// 发现新版弹窗 —— iOS 风格
class UpdateAvailableDialog extends StatelessWidget {
  final UpdateInfo info;

  const UpdateAvailableDialog({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IosTheme.radiusM),
      ),
      title: Text(
        '发现新版本 ${info.versionName}',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(IosTheme.spaceM),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A3A3C)
                      : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(IosTheme.radiusXS),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 18,
                      color: IosTheme.iosGray,
                    ),
                    const SizedBox(width: IosTheme.spaceS),
                    Text(
                      '大小：${info.sizeText}',
                      style: TextStyle(
                        fontSize: 14,
                        color: IosTheme.iosGray,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: IosTheme.spaceM),
              Text(
                info.changelog,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!info.force)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '稍后',
              style: TextStyle(
                color: IosTheme.iosBlue,
                fontSize: 17,
              ),
            ),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: IosTheme.iosBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(IosTheme.radiusButton),
            ),
          ),
          child: const Text('立即更新'),
        ),
      ],
    );
  }
}

/// 下载进度弹窗 —— iOS 风格
class DownloadProgressDialog extends StatefulWidget {
  final UpdateInfo info;

  const DownloadProgressDialog({super.key, required this.info});

  @override
  State<DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<DownloadProgressDialog> {
  double _progress = 0;
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
    });
    try {
      final file = await UpdateService.download(
        widget.info.url,
        (p) {
          if (mounted) setState(() => _progress = p);
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
            content: Text('请允许"安装未知应用"后，重新检查更新完成安装'),
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '下载失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).toStringAsFixed(0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IosTheme.radiusM),
      ),
      title: Text(
        _error != null
            ? '更新失败'
            : _done
                ? '下载完成'
                : '正在下载 $pct%',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: _error != null
          ? Text(_error!)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress,
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

/// 更新流程编排：检查 → 弹新版 → 下载 → 安装
class UpdateFlow {
  /// auto=true：有更新才弹；连不上更新服静默
  /// auto=false：无更新 / 失败都给 Toast
  static Future<void> checkAndPrompt(
    BuildContext context,
    Iterable<String> hosts, {
    bool auto = false,
  }) async {
    final result = await UpdateService.checkHosts(hosts);
    if (!context.mounted) return;
    final info = result.info;
    if (info == null) {
      if (!auto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error == null
                ? '已是最新版本'
                : '检查更新失败：${result.error}'),
          ),
        );
      }
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: !info.force,
      builder: (_) => UpdateAvailableDialog(info: info),
    );
    if (go != true || !context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DownloadProgressDialog(info: info),
    );
  }
}
