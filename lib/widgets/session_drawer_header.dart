import 'package:flutter/material.dart';

import '../theme/ios_theme.dart';

/// 会话抽屉的标题栏（标题 + 刷新按钮 / 加载指示）
///
/// 从 session_drawer.dart 拆出来，让那个文件守住 200 行上限。
class SessionDrawerTitleBar extends StatelessWidget {
  final bool loading;
  final VoidCallback onRefresh;

  const SessionDrawerTitleBar({
    super.key,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosTheme.spaceXL,
        IosTheme.spaceL,
        IosTheme.spaceL,
        IosTheme.spaceS,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '会话',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: IosTheme.iosBlue,
              ),
            )
          else
            IconButton(
              icon: const Icon(
                Icons.refresh,
                size: 22,
                color: IosTheme.iosBlue,
              ),
              tooltip: '刷新',
              onPressed: onRefresh,
            ),
        ],
      ),
    );
  }
}

/// 「新建会话」按钮（未分组）
///
/// 从 session_drawer.dart 拆出来，让那个文件守住 200 行上限。
class SessionNewSessionButton extends StatelessWidget {
  final VoidCallback onTap;

  const SessionNewSessionButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IosTheme.spaceL,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: IosTheme.iosBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(IosTheme.radiusS),
        ),
        child: ListTile(
          leading: const Icon(
            Icons.add_circle_outline,
            color: IosTheme.iosBlue,
            size: 22,
          ),
          title: const Text(
            '新建会话',
            style: TextStyle(
              color: IosTheme.iosBlue,
              fontWeight: FontWeight.w500,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
