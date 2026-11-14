import 'package:flutter/material.dart';
import '../models/poll_beat.dart';
import '../theme/ios_theme.dart';

/// 心跳刻度（DESIGN.md §2 签名动作）
///
/// 8 格刻度行——每格 = 一轮 8 秒轮询（绿=成功 / 橙=数据异常 / 红=missed）。
/// 最新一格滑入（620ms 指数缓出），不足 8 格补空格（0.38 透明度）。
/// 它把「每台机器自己的轮询通道、8 秒一轮」这个架构事实画在界面上。
class PollPulse extends StatelessWidget {
  final List<PollBeat> beats;

  /// 刻度格尺寸（横向短杠，对齐原型 .pulse .tick：10×5 圆角 3）
  static const double cellWidth = 10;
  static const double cellHeight = 5;

  /// 格间隙
  static const double gap = 3;

  /// 整行宽度（capacity 格 + capacity-1 个间隙）；
  /// 卡片上状态文案以它钳制宽度，与刻度行右缘对齐
  static const double rowWidth =
      PollBeat.capacity * cellWidth + (PollBeat.capacity - 1) * gap;

  const PollPulse({super.key, required this.beats});

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    final cells = <Widget>[];
    final pad = PollBeat.capacity - beats.length;
    for (var i = 0; i < PollBeat.capacity; i++) {
      if (i < pad) {
        cells.add(_cell(p.ok, 0.38));
        continue;
      }
      final beat = beats[i - pad];
      final color = switch (beat.status) {
        PollBeatStatus.ok => p.ok,
        PollBeatStatus.warn => p.warnTint,
        PollBeatStatus.missed => p.bad,
      };
      cells.add(_AnimatedCell(
        key: ValueKey(beat.at.millisecondsSinceEpoch),
        color: color,
        entering: i == PollBeat.capacity - 1,
      ));
    }
    return Semantics(
      label: '轮询心跳 ${beats.length} 格',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: PollPulse.gap),
            cells[i],
          ],
        ],
      ),
    );
  }

  Widget _cell(Color color, double alpha) => Opacity(
        opacity: alpha,
        child: Container(
          width: cellWidth,
          height: cellHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
}

/// 单格：新格滑入（620ms，原型 tickIn：scaleX .1→1 + 淡入）
class _AnimatedCell extends StatelessWidget {
  final Color color;
  final bool entering;

  const _AnimatedCell({
    required super.key,
    required this.color,
    required this.entering,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell = Container(
      width: PollPulse.cellWidth,
      height: PollPulse.cellHeight,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    if (!entering) return cell;
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(begin: 0, end: 1),
      duration: IosMotion.durationPulse,
      curve: IosMotion.curveSpring,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.scale(
          scaleX: 0.1 + 0.9 * t,
          child: child,
        ),
      ),
      child: cell,
    );
  }
}
