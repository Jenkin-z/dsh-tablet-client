import 'package:flutter/material.dart';
import '../models/queued_message.dart';
import '../theme/ios_theme.dart';
import 'queue_edit_dialog.dart';

/// 排队横幅 —— 任务运行中继续输入的可见化（iOS 风格）
///
/// 折叠态显示计数胶囊，点开看每条内容与放置类型（排队 / 插话）；queued
/// 条目行内可转插话/编辑/删除（steering 已是插话且协议未明确可否操作，
/// 不提供）。成功不乐观改动，随 Host 推来的 queue 帧刷新；无队列不渲染。
class QueueBanner extends StatefulWidget {
  final List<QueuedMessage> queue;

  /// 队列操作回调（缺省 = 不显示该动作；失败提示由门面统一上报）
  final Future<void> Function(QueuedMessage item)? onSteer;
  final Future<void> Function(QueuedMessage item)? onRemove;
  final Future<void> Function(QueuedMessage item, String content)? onEdit;

  const QueueBanner({
    super.key,
    required this.queue,
    this.onSteer,
    this.onRemove,
    this.onEdit,
  });

  @override
  State<QueueBanner> createState() => _QueueBannerState();
}

class _QueueBannerState extends State<QueueBanner> {
  bool _expanded = false;

  /// 正在执行操作的条目 id：期间禁用全部条目动作（防重复点击）
  String? _busyId;

  bool get _hasActions =>
      widget.onSteer != null || widget.onRemove != null || widget.onEdit != null;

  @override
  Widget build(BuildContext context) {
    // context 是上下文注入，不是用户的排队消息，不进横幅
    final items = widget.queue.where((m) => m.countsAsUserQueue).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final queued =
        items.where((m) => m.placement == QueuePlacement.queued).length;
    final steering = items.length - queued;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(
          IosTheme.spaceL, IosTheme.spaceS, IosTheme.spaceL, 0),
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
                  horizontal: IosTheme.spaceM, vertical: IosTheme.spaceS),
              child: Row(
                children: [
                  Icon(Icons.low_priority, size: 15, color: IosTheme.iosBlue),
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
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
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
                  IosTheme.spaceM, 0, IosTheme.spaceM, IosTheme.spaceS),
              child: Column(
                children: [
                  for (final m in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: IosTheme.spaceXS),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
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
                                  color: isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          if (_hasActions) _itemActions(m),
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

  /// 行内操作（IconButton 默认 48pt 触控目标）；协议只对 queued 明确
  /// steer/edit/remove，steering 一律不提供。
  Widget _itemActions(QueuedMessage m) {
    if (m.placement != QueuePlacement.queued) return const SizedBox.shrink();
    final enabled = _busyId == null;
    Widget btn(IconData icon, Color color, String tip, VoidCallback? onTap) =>
        IconButton(
          icon: Icon(icon, size: 17),
          color: color,
          tooltip: tip,
          onPressed: onTap,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onSteer != null)
          btn(Icons.bolt, IosTheme.iosBlue, '转为插话',
              enabled ? () => _run(m, (i) => widget.onSteer!(i)) : null),
        if (widget.onEdit != null)
          btn(Icons.edit_outlined, IosTheme.iosGray, '编辑',
              enabled ? () => _edit(m) : null),
        if (widget.onRemove != null)
          btn(Icons.delete_outline, IosTheme.iosGray, '删除',
              enabled ? () => _run(m, (i) => widget.onRemove!(i)) : null),
      ],
    );
  }

  /// 执行一条队列操作：busy 置位防重复点击，结束（含失败）即释放。
  Future<void> _run(
      QueuedMessage m, Future<void> Function(QueuedMessage item) op) async {
    if (_busyId != null) return;
    setState(() => _busyId = m.id);
    try {
      await op(m);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// 编辑：弹窗预填原文，确认且内容有变才发起（内容未变不调 RPC）
  Future<void> _edit(QueuedMessage m) async {
    if (_busyId != null) return;
    final text = await showQueueEditDialog(context, m);
    if (text == null || text.isEmpty || text == m.content) return;
    await _run(m, (i) => widget.onEdit!(i, text));
  }
}
