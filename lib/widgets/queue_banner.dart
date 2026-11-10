import 'package:flutter/material.dart';
import '../models/queued_message.dart';
import '../theme/ios_theme.dart';

/// 排队横幅 —— 任务运行中继续输入的可见化（iOS 风格）
///
/// 借鉴 dsh-go marketplace「声明必须可见」的交互：
/// 运行中发出的消息进 Host 队列后不再石沉大海 —— 折叠态显示计数胶囊，
/// 点开看每条内容与放置类型（排队 / 插话）。
/// 当前会话无排队消息时不渲染。
class QueueBanner extends StatefulWidget {
  final List<QueuedMessage> queue;

  const QueueBanner({super.key, required this.queue});

  @override
  State<QueueBanner> createState() => _QueueBannerState();
}

class _QueueBannerState extends State<QueueBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // context 是上下文注入，不是用户的排队消息，不进横幅
    final items =
        widget.queue.where((m) => m.countsAsUserQueue).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final queued = items.where((m) => m.placement == QueuePlacement.queued).length;
    final steering = items.length - queued;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        IosTheme.spaceS,
        IosTheme.spaceL,
        0,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(IosTheme.radiusS),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(IosTheme.radiusS),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: IosTheme.spaceM,
                vertical: IosTheme.spaceS,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.low_priority,
                    size: 15,
                    color: IosTheme.iosBlue,
                  ),
                  const SizedBox(width: IosTheme.spaceS),
                  Expanded(
                    child: Text(
                      _summary(queued, steering),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: IosTheme.iosGray,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IosTheme.spaceM,
                0,
                IosTheme.spaceM,
                IosTheme.spaceS,
              ),
              child: Column(
                children: [
                  for (final m in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: IosTheme.spaceXS),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _placementBadge(m.placement, isDark),
                          const SizedBox(width: IosTheme.spaceS),
                          Expanded(
                            child: Text(
                              m.content.isEmpty ? '（空消息）' : m.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _summary(int queued, int steering) {
    final parts = <String>[
      if (queued > 0) '已排队 $queued 条',
      if (steering > 0) '插话 $steering 条',
    ];
    return '${parts.join(' · ')}，本轮结束后自动继续';
  }

  Widget _placementBadge(QueuePlacement placement, bool isDark) {
    final isSteering = placement == QueuePlacement.steering;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isSteering
            ? IosTheme.iosBlue.withValues(alpha: 0.15)
            : (isDark ? const Color(0xFF3A3A3C) : Colors.white),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isSteering ? '插话' : '排队',
        style: TextStyle(
          fontSize: 10,
          color: isSteering ? IosTheme.iosBlue : IosTheme.iosGray,
        ),
      ),
    );
  }
}
