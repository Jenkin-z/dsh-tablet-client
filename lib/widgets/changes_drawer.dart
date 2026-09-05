import 'package:flutter/material.dart';
import '../services/changes_tracker.dart';
import '../services/diff_util.dart';

/// 右侧变更栏：本会话的文件变更列表 + 行级 diff
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
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('变更',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                items.isEmpty
                    ? '本会话暂无文件变更'
                    : '${items.length} 个文件${widget.tracker.pendingCount > 0 ? '（${widget.tracker.pendingCount} 待执行）' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          leading: Icon(
            e.oldText == null ? Icons.note_add_outlined : Icons.edit_outlined,
            size: 20,
            color: e.done ? theme.colorScheme.primary : Colors.orange,
          ),
          title: Text(e.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          subtitle: Text(
            '${e.done ? '已应用' : '待执行'} · ${e.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(open ? Icons.expand_less : Icons.expand_more, size: 20),
          onTap: () => setState(() {
            if (open) {
              _open.remove(key);
            } else {
              _open.add(key);
            }
          }),
        ),
        if (open) _diffBlock(e),
      ],
    );
  }

  Widget _diffBlock(FileChange e) {
    final theme = Theme.of(context);
    final lines = unifiedDiff(e.oldText, e.newText);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in lines) _diffLine(l, theme),
        ],
      ),
    );
  }

  Widget _diffLine(DiffLine l, ThemeData theme) {
    Color? bg;
    String prefix = '  ';
    switch (l.op) {
      case DiffOp.add:
        bg = Colors.green.withValues(alpha: 0.15);
        prefix = '+ ';
        break;
      case DiffOp.del:
        bg = Colors.red.withValues(alpha: 0.15);
        prefix = '- ';
        break;
      case DiffOp.same:
        prefix = '  ';
        break;
    }
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: SelectableText(
        '$prefix${l.text}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
      ),
    );
  }
}