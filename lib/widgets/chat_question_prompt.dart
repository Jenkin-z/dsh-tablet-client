import 'package:flutter/material.dart';

import '../services/chat_controller.dart';
import '../theme/ios_theme.dart';

/// 有待回答的问题时给一条入口（弹窗被关掉后还能再打开）
class ChatQuestionPrompt extends StatelessWidget {
  const ChatQuestionPrompt({
    super.key,
    required this.ctrl,
    required this.onPressed,
  });

  final ChatController ctrl;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final q = ctrl.state.allQuestions
        .where((x) => x.sessionId == ctrl.state.sessionId)
        .firstOrNull;
    if (q == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        IosTheme.spaceXS,
        IosTheme.spaceL,
        0,
      ),
      child: IosButton(
        label: '有 ${q.questions.length} 个问题待回答',
        icon: Icons.help_outline,
        filled: false,
        onPressed: onPressed,
      ),
    );
  }
}
