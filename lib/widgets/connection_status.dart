import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/connection_health.dart';
import '../services/dsh_session_state.dart';
import '../theme/ios_theme.dart';

/// 连接状态指示器：状态一律从 DshSessionState 读取
///
/// [showLabel] = false 时只显示圆点，用于 AppBar 标题等紧凑位置。
///
/// 判定依据是 [DshSessionState.health] 而不是 `connected`：
/// socket 通、但会话列表拉不到时显示「数据异常」（橙）。
/// 历史 bug 正是「列表空 + 显示绿色」让人以为一切正常。
class ConnectionStatus extends StatelessWidget {
  final bool showLabel;

  const ConnectionStatus({super.key, this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    return Consumer<DshSessionState>(
      builder: (context, state, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final health = state.health;

        final Color color;
        final String text;
        switch (health) {
          case ConnectionHealth.connecting:
            color = IosTheme.iosOrange;
            text = '连接中...';
          case ConnectionHealth.healthy:
            color = IosTheme.iosGreen;
            text = '已连接';
          case ConnectionHealth.degraded:
            color = IosTheme.iosOrange;
            text = '数据异常';
          case ConnectionHealth.offline:
            color = IosTheme.iosRed;
            text = '未连接';
        }

        // 降级/离线时点一下能看到具体原因，否则只有一个颜色让人无从下手。
        //
        // 正常时也给一句可点开的自述：这个点「一直是绿的」到底是因为真的连上了、
        // 还是某个写入方在盖状态，光看颜色分不出来。把四个原始字段亮出来，
        // 一眼就能判断它有没有在说谎。
        final detail = health == ConnectionHealth.degraded
            ? (state.sessionsError ?? '会话列表读取失败')
            : (health == ConnectionHealth.offline
                ? (state.connectionError ?? '连接尚未建立')
                : null);

        final diagnostic = StringBuffer()
          ..write(health == ConnectionHealth.healthy ? '已连接' : text)
          ..write('\n连接: ${state.connected ? "是" : "否"}')
          ..write(' · 建连中: ${state.connecting ? "是" : "否"}')
          ..write('\n数据: ${switch (state.sessionsOk) {
            null => '未校验',
            true => '已校验',
            false => '读取失败',
          }}');
        if (detail != null) diagnostic.write('\n$detail');

        final dot = Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: diagnostic.toString(),
              triggerMode: TooltipTriggerMode.tap,
              child: dot,
            ),
            if (showLabel) ...[
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
