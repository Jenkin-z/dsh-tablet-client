import 'package:flutter/material.dart';

/// AppBar 右侧的聊天操作区：停止 / 变更入口 / 重连 / 切换模型
class ChatAppBarActions extends StatelessWidget {
  const ChatAppBarActions({
    super.key,
    required this.agentRunning,
    required this.stopping,
    required this.pendingCount,
    required this.connected,
    required this.onStop,
    required this.onOpenChanges,
    required this.onBoot,
    required this.onOpenModelSheet,
  });

  final bool agentRunning;
  final bool stopping;
  final int pendingCount;
  final bool connected;
  final VoidCallback onStop;
  final VoidCallback onOpenChanges;
  final VoidCallback onBoot;
  final VoidCallback onOpenModelSheet;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 停止：运行中或正在停止时才出现
        if (agentRunning || stopping)
          IconButton(
            icon: stopping
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.stop_circle_outlined, size: 22),
            tooltip: stopping ? '正在停止' : '停止',
            onPressed: stopping ? null : onStop,
          ),
        // 变更入口常驻：没待办时也要能翻历史 diff。
        // 之前写成 pendingCount > 0 才渲染，等于没变更就再也打不开。
        IconButton(
          icon: Badge(
            label: Text('$pendingCount'),
            isLabelVisible: pendingCount > 0,
            child: const Icon(Icons.difference_outlined, size: 22),
          ),
          tooltip: '变更',
          onPressed: connected ? onOpenChanges : null,
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 22),
          tooltip: '重连',
          onPressed: onBoot,
        ),
        IconButton(
          icon: const Icon(Icons.tune, size: 22),
          tooltip: '切换模型',
          onPressed: onOpenModelSheet,
        ),
      ],
    );
  }
}
