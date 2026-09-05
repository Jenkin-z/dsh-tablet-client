import 'package:flutter/material.dart';
import '../utils/session_format.dart';
import 'console_animations.dart';

class ConsoleRunningCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> workspaces;
  final bool isCurrent;
  final VoidCallback onTap;

  const ConsoleRunningCard({
    super.key,
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
              const ConsolePulseDot(),
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
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
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
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.green),
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

class ConsoleUnviewedCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> workspaces;
  final VoidCallback onTap;

  const ConsoleUnviewedCard({
    super.key,
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sessionTitleOf(session),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
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
                      const ConsoleBreathBadge(text: 'NEW'),
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

class ConsoleRecentTile extends StatelessWidget {
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> workspaces;
  final bool isCurrent;
  final VoidCallback onTap;

  const ConsoleRecentTile({
    super.key,
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

class ConsoleQuietLine extends StatelessWidget {
  final String text;
  const ConsoleQuietLine({super.key, required this.text});

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
