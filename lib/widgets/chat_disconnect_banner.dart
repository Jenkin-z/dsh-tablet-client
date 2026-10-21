import 'package:flutter/material.dart';

import '../theme/ios_theme.dart';

/// 断线横幅：连接中断时显示的提示条
class ChatDisconnectBanner extends StatelessWidget {
  const ChatDisconnectBanner({super.key, required this.retrying});

  final bool retrying;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IosTheme.iosOrange.withValues(alpha: 0.16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IosTheme.spaceL,
          vertical: IosTheme.spaceS,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: IosTheme.iosOrange,
            ),
            const SizedBox(width: IosTheme.spaceS),
            Expanded(
              child: Text(
                retrying ? '连接中断，正在重连…' : '已断开，自动重连已关闭',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
