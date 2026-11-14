import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session_state.dart';
import '../theme/ios_theme.dart';
import 'connection_status.dart';

/// AppBar 标题（DESIGN.md §6：对话页顶栏只显示当前会话 + 状态点 + 模型 pill，
/// 不设设备切换）
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
            style: const TextStyle(
              fontSize: IosType.title3,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const _ModelPill(),
      ],
    );
  }
}

/// 当前模型 pill（展示用；切换入口在右侧 tune 按钮）
class _ModelPill extends StatelessWidget {
  const _ModelPill();

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return Selector<SessionState, String>(
      selector: (_, state) => state.modelSelection?.label ?? '',
      builder: (context, label, _) {
        if (label.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: p.accentSoft,
            borderRadius: BorderRadius.circular(IosTheme.radiusPill),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: IosType.caption,
              fontWeight: FontWeight.w500,
              color: p.accent,
              height: 1.2,
            ),
          ),
        );
      },
    );
  }
}
