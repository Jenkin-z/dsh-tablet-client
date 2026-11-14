import 'package:flutter/material.dart';

import '../services/agent_mode.dart';
import '../services/model_catalog.dart';
import '../theme/ios_theme.dart';
import 'model_sheet_parts.dart';

/// 模型面板顶部的「模式」分区（opencode 的 agent：build/plan…）
///
/// 纯展示：列表、当前高亮、切换中与失败提示都由入参给；
/// 状态与网络在 [ModelSheet] 里。DSH 等无模式的后端不渲染本分区。
class ModeSection extends StatelessWidget {
  final List<AgentMode> modes;
  final String currentMode;
  final String? error;
  final bool busy;

  final void Function(AgentMode mode) onSelect;

  const ModeSection({
    super.key,
    required this.modes,
    required this.currentMode,
    required this.error,
    required this.busy,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ModelSectionTitle('模式'),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              IosTheme.spaceL,
              IosTheme.spaceS,
              IosTheme.spaceL,
              0,
            ),
            child: Text(
              error!,
              style: TextStyle(
                fontSize: IosType.footnotePlus,
                color: p.bad,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
            child: Wrap(
              spacing: IosTheme.spaceS,
              runSpacing: IosTheme.spaceS,
              children: [
                for (final m in modes)
                  ReasoningChip(
                    effort: ReasoningEffort(id: m.id, name: m.name),
                    active: currentMode == m.id,
                    onTap: busy || currentMode == m.id
                        ? null
                        : () => onSelect(m),
                  ),
              ],
            ),
          ),
        const SizedBox(height: IosTheme.spaceL),
      ],
    );
  }
}
