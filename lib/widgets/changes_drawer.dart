import 'package:flutter/material.dart';
import '../services/changes_tracker.dart';
import '../theme/ios_theme.dart';
import 'changes_drawer_parts.dart';

/// 右侧变更栏 —— iOS 风格
///
/// 本会话的文件变更列表 + 行级 diff。
/// 文件行与 diff 区块拆到 changes_drawer_parts.dart，
/// 让本文件守住 200 行上限。
class ChangesDrawer extends StatefulWidget {
  final ChangesTracker tracker;

  const ChangesDrawer({super.key, required this.tracker});

  @override
  State<ChangesDrawer> createState() => _ChangesDrawerState();
}

class _ChangesDrawerState extends State<ChangesDrawer> {
  final Set<String> _open = {};

  @override
  Widget build(BuildContext context) {
    final items = widget.tracker.items;
    final p = IosPalette.of(context);
    return Drawer(
      backgroundColor: p.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IosTheme.spaceXL,
                IosTheme.spaceL,
                IosTheme.spaceL,
                IosTheme.spaceXS,
              ),
              child: Text(
                '变更',
                style: TextStyle(
                  fontSize: IosType.title2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: p.label,
                ),
              ),
            ),
            // 统计信息
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IosTheme.spaceXL,
                0,
                IosTheme.spaceL,
                IosTheme.spaceM,
              ),
              child: Text(
                items.isEmpty
                    ? '本会话暂无文件变更'
                    : '${items.length} 个文件${widget.tracker.pendingCount > 0 ? '（${widget.tracker.pendingCount} 待执行）' : ''}',
                style: TextStyle(
                  fontSize: IosType.footnotePlus,
                  color: p.label2,
                ),
              ),
            ),
            // 分隔线
            Container(height: 0.5, color: p.separator),
            // 变更列表
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: p.ok.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: IosTheme.spaceM),
                          Text(
                            '没有变更',
                            style: TextStyle(
                              fontSize: IosType.callout,
                              color: p.label3,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        vertical: IosTheme.spaceS,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _fileRow(items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileRow(FileChange e) {
    final key = '${e.turn ?? 0}:${e.path}';
    final open = _open.contains(key);
    return ChangesFileRow(
      change: e,
      isOpen: open,
      onToggle: () => setState(() {
        if (open) {
          _open.remove(key);
        } else {
          _open.add(key);
        }
      }),
    );
  }
}
