import 'package:flutter/material.dart';
import '../services/update_service.dart';
import 'download_progress_dialog.dart';
import 'update_available_dialog.dart';

export 'download_progress_dialog.dart' show DownloadProgressDialog;
export 'update_available_dialog.dart' show UpdateAvailableDialog;

/// 更新弹窗（发现新版 / 下载进度）的对外入口 —— iOS 风格
///
/// 两个弹窗本体拆到 update_available_dialog.dart / download_progress_dialog.dart，
/// 让本文件守住 200 行上限。对外仍从 update_dialog.dart 导入即可。
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
