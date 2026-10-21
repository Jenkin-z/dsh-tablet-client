import 'package:flutter/material.dart';

import '../theme/ios_theme.dart';

/// 控制台统计卡片
///
/// 从 console_animations.dart 拆出来，让那个文件守住 200 行上限。
class ConsoleStatsCard extends StatelessWidget {
  final int runningCount;
  final int unviewedCount;
  final int totalCount;

  const ConsoleStatsCard({
    super.key,
    required this.runningCount,
    required this.unviewedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: IosTheme.spaceM,
        vertical: IosTheme.spaceS,
      ),
      padding: const EdgeInsets.all(IosTheme.spaceM),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(IosTheme.radiusM),
        border: Border.all(
          color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('运行中', runningCount, IosTheme.iosGreen),
          _buildStatItem('待查看', unviewedCount, IosTheme.iosOrange),
          _buildStatItem('总会话', totalCount, IosTheme.iosGray),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: IosTheme.iosGray,
          ),
        ),
      ],
    );
  }
}

/// 空状态
///
/// 从 console_animations.dart 拆出来，让那个文件守住 200 行上限。
class ConsoleEmptyState extends StatelessWidget {
  const ConsoleEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.computer_outlined,
            size: 64,
            color: IosTheme.iosGray,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无会话',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: IosTheme.iosGray,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '运行中的会话和待查看的完成会话\n会出现在这里',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: IosTheme.iosGray,
            ),
          ),
        ],
      ),
    );
  }
}
