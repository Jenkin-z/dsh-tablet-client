import 'package:flutter/material.dart';
import '../services/update_service.dart';

/// 发现新版弹窗：更新日志 + 立即更新 / 稍后
class UpdateAvailableDialog extends StatelessWidget {
  final UpdateInfo info;

  const UpdateAvailableDialog({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('发现新版本 ${info.versionName}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('大小：${info.sizeText}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(info.changelog),
            ],
          ),
        ),
      ),
      actions: [
        if (!info.force)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍后'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('立即更新'),
        ),
      ],
    );
  }
}

/// 下载进度弹窗：进度条 + 百分比，完成后自动调安装器
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
      // 未允许“安装未知应用”：先跳系统开关页，回来再点安装
      final allowed = await UpdateService.canInstallUnknown();
      if (!mounted) return;
      if (!allowed) {
        await UpdateService.openUnknownAppSources();
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请允许“安装未知应用”后，重新检查更新完成安装'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
      Navigator.of(context).pop();
      await UpdateService.installApk(file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '下载失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).toStringAsFixed(0);
    return AlertDialog(
      title: Text(_error != null
          ? '更新失败'
          : _done
              ? '下载完成'
              : '正在下载 $pct%'),
      content: _error != null
          ? Text(_error!)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text('${widget.info.versionName} · ${widget.info.sizeText}'),
                const SizedBox(height: 4),
                const Text('下载完成后自动调起安装，可在后台继续聊天',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
      actions: [
        if (_error != null) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _start,
            child: const Text('重试'),
          ),
        ],
      ],
    );
  }
}

/// 更新流程编排：检查 → 弹新版 → 下载 → 安装
class UpdateFlow {
  /// auto=true 时：无更新/网络失败静默；有更新才弹窗
  /// auto=false（手动点）：无更新给 Toast
  static Future<void> checkAndPrompt(
    BuildContext context,
    String serverHost, {
    bool auto = false,
  }) async {
    final info = await UpdateService.check(serverHost);
    if (!context.mounted) return;
    if (info == null) {
      if (!auto) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已是最新版本')),
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
