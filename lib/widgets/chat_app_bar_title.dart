import 'package:flutter/material.dart';

import '../theme/ios_theme.dart';
import 'connection_status.dart';

/// AppBar 标题（DESIGN.md §6：连接状态点 + 当前会话标题）
///
/// 只显示会话标题，单行省略——标题过长时截断，绝不侵占右侧动作按钮。
/// 模型不在顶栏展示，切换入口在右侧 tune 按钮。
class ChatAppBarTitle extends StatelessWidget {
  const ChatAppBarTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ConnectionStatus(showLabel: false),
        const SizedBox(width: IosTheme.spaceS),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: IosType.title3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
