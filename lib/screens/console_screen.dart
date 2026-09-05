import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_monitor.dart';
import '../services/settings_service.dart';
import '../utils/session_format.dart';

/// 控制台：进行中的对话 + 完成后未查看的对话 + 最近活跃
/// 点卡片直接跳到对话页对应会话。
class ConsoleScreen extends StatefulWidget {
  final void Function(String sessionId) onOpenSession;

  const ConsoleScreen({super.key, required this.onOpenSession});

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<SessionMonitor, SettingsService>(
      builder: (context, monitor, settings, _) {
        final running = monitor.runningSessions;
        final unviewed = monitor.unviewedSessions;
        final recent = monitor.recentSessions;
        return Scaffold(
          appBar: AppBar(
            title: const Text('控制台'),
            actions: [
              if (monitor.lastRefresh != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '更新于 ${_clock(monitor.lastRefresh!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: monitor.refresh,
              ),
            ],
          ),
          body: _buildBody(monitor, settings, running, unviewed, recent),
        );
      },
    );
  }

  String _clock(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

  Widget _buildBody(
    SessionMonitor monitor,
    SettingsService settings,
    List<Map<String, dynamic>> running,
    List<Map<String, dynamic>> unviewed,
    List<Map<String, dynamic>> recent,
  ) {
    if (monitor.loading && monitor.sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (monitor.error != null && monitor.sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text('加载失败：${monitor.error}'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: monitor.refresh,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final allQuiet = running.isEmpty && unviewed.isEmpty;
    return RefreshIndicator(
      onRefresh: monitor.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _StatStrip(
            running: running.length,
            unviewed: unviewed.length,
            total: monitor.sessions.length,
          ),
          const SizedBox(height: 8),
          _SectionHeader(
            icon: Icons.sync,
            iconColor: Colors.green,
            title: '进行中',
            count: running.length,
          ),
          if (running.isEmpty)
            const _QuietLine(text: '暂无运行中的会话')
          else
            for (var i = 0; i < running.length; i++)
              _Entrance(
                key: ValueKey('run:${running[i]['sessionId']}'),
                index: i,
                child: _RunningCard(
                  session: running[i],
                  workspaces: monitor.workspaces,
                  isCurrent:
                      running[i]['sessionId'] == settings.sessionId,
                  onTap: () => widget.onOpenSession(
                      running[i]['sessionId'] as String),
                ),
              ),
          const SizedBox(height: 8),
          _SectionHeader(
            icon: Icons.mark_as_unread_outlined,
            iconColor: Colors.orange,
            title: '待查看',
            count: unviewed.length,
            badge: unviewed.isNotEmpty,
            action: unviewed.isEmpty
                ? null
                : TextButton(
                    onPressed: () => settings.markAllSeen(
                      unviewed.map((s) =>
                          s['sessionId'] as String? ?? ''),
                    ),
                    child: const Text('全部已读'),
                  ),
          ),
          if (unviewed.isEmpty)
            const _QuietLine(text: '没有未查看的完成会话')
          else
            for (var i = 0; i < unviewed.length; i++)
              _Entrance(
                key: ValueKey('unv:${unviewed[i]['sessionId']}'),
                index: i,
                child: _UnviewedCard(
                  session: unviewed[i],
                  workspaces: monitor.workspaces,
                  onTap: () => widget.onOpenSession(
                      unviewed[i]['sessionId'] as String),
                ),
              ),
          const SizedBox(height: 8),
          _SectionHeader(
            icon: Icons.history,
            iconColor: Colors.blueGrey,
            title: '最近活跃',
            count: recent.length,
          ),
          if (recent.isEmpty && allQuiet)
            const _EmptyState()
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < recent.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _RecentTile(
                      session: recent[i],
                      workspaces: monitor.workspaces,
                      isCurrent:
                          recent[i]['sessionId'] == settings.sessionId,
                      onTap: () => widget.onOpenSession(
                          recent[i]['sessionId'] as String),
                    ),
                  ],
                  if (recent.isEmpty)
                    const ListTile(
                      dense: true,
                      title: Text('暂无',
                          textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 顶部统计条：运行中 / 待查看 / 全部（数字滚动切换动画）
class _StatStrip extends StatelessWidget {
  final int running;
  final int unviewed;
  final int total;

  const _StatStrip({
    required this.running,
    required this.unviewed,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: _StatChip(
                icon: Icons.sync, label: '运行中', value: running,
                color: Colors.green)),
        const SizedBox(width: 8),
        Expanded(
            child: _StatChip(
                icon: Icons.mark_as_unread_outlined, label: '待查看',
                value: unviewed, color: Colors.orange)),
        const SizedBox(width: 8),
        Expanded(
            child: _StatChip(
                icon: Icons.forum_outlined, label: '全部会话',
                value: total, color: Colors.blueGrey)),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: child,
              ),
              child: Text(
                '$value',
                key: ValueKey(value),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// 分区标题行
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final int count;
  final bool badge;
  final Widget? action;

  const _SectionHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.count,
    this.badge = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 6),
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey(count),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badge
                    ? Colors.orange
                    : Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  color: badge ? Colors.white : null,
                  fontWeight: badge ? FontWeight.bold : null,
                ),
              ),
            ),
          ),
          if (badge) ...[
            const SizedBox(width: 6),
            const _BreathBadge(),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// 进行中卡片：呼吸边框 + 脉冲圆点
class _RunningCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> workspaces;
  final bool isCurrent;
  final VoidCallback onTap;

  const _RunningCard({
    required this.session,
    required this.workspaces,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ws = workspaceOf(session, workspaces);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.green, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const _PulseDot(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sessionTitleOf(session),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('当前',
                                style: TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ws ?? '未分组'} · Agent 运行中',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// 待查看卡片：左侧橙条 + NEW 呼吸徽标
class _UnviewedCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> workspaces;
  final VoidCallback onTap;

  const _UnviewedCard({
    required this.session,
    required this.workspaces,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ws = workspaceOf(session, workspaces);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: Colors.orange),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              sessionTitleOf(session),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${ws ?? '未分组'} · ${timeAgoOf(session['updatedAt'] as int?)}完成',
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const _BreathBadge(text: 'NEW'),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> workspaces;
  final bool isCurrent;
  final VoidCallback onTap;

  const _RecentTile({
    required this.session,
    required this.workspaces,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ws = workspaceOf(session, workspaces);
    return ListTile(
      dense: true,
      leading: const Icon(Icons.chat_bubble_outline, size: 20),
      title: Text(
        sessionTitleOf(session),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${ws ?? '未分组'} · ${timeAgoOf(session['updatedAt'] as int?)}${isCurrent ? ' · 当前' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

class _QuietLine extends StatelessWidget {
  final String text;
  const _QuietLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(fontStyle: FontStyle.italic),
      ),
    );
  }
}

/// 全空状态：悬浮动画图标
class _EmptyState extends StatefulWidget {
  const _EmptyState();

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.08),
              end: const Offset(0, 0.08),
            ).animate(
                CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
            child: const Icon(
              Icons.radar,
              size: 56,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '一切安静',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '运行中的会话和待查看的完成会话\n会出现在这里',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ---------- 动画小件 ----------

/// 入场：淡入 + 上滑（按 key 只播一次，轮询刷新不重播）
class _Entrance extends StatefulWidget {
  final int index;
  final Widget child;

  const _Entrance({super.key, required this.index, required this.child});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.index * 70), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 350),
      opacity: _shown ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        offset: _shown ? Offset.zero : const Offset(0, 0.25),
        child: widget.child,
      ),
    );
  }
}

/// 运行脉冲圆点：缩放 + 渐隐循环
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.6, end: 1.6).animate(
                CurvedAnimation(parent: _c, curve: Curves.easeOut)),
            child: FadeTransition(
              opacity: Tween(begin: 0.7, end: 0.0).animate(_c),
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

/// 呼吸徽标：透明度循环
class _BreathBadge extends StatefulWidget {
  final String text;
  const _BreathBadge({this.text = '!'});

  @override
  State<_BreathBadge> createState() => _BreathBadgeState();
}

class _BreathBadgeState extends State<_BreathBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35).animate(
          CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          widget.text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
