import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session_state.dart';
import '../theme/ios_theme.dart';

/// 断线横幅：连接中断时显示的提示条
///
/// connectionError 有具体错误文本（流错误 / 解析失败 / 连接超时等）时
/// 在主文案下补一行，让用户知道「为什么断了」；无错时维持原两句文案。
class ChatDisconnectBanner extends StatelessWidget {
  const ChatDisconnectBanner({super.key, required this.retrying});

  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final error = context.watch<SessionState>().connectionError;
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    retrying ? '连接中断，正在重连…' : '已断开，自动重连已关闭',
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (error != null && error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        error,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: IosTheme.iosGray,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
