import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 问题选项 chips 行（单选 ChoiceChip / 多选 FilterChip）
///
/// 从 question_sheet.dart 拆出来是为了守住 200 行上限。
/// 选中集合仍归 [QuestionSheet] 所有，这里引用后读写并通过回调让状态层 setState。
class QuestionChipsRow extends StatelessWidget {
  final List<Map<String, dynamic>> options;
  final bool multi;
  final Set<String> selected; // 引用 QuestionSheet 的选中集合
  final void Function(String label, bool value) onMultiSelect;
  final void Function(String label) onChoiceSelect;

  const QuestionChipsRow({
    super.key,
    required this.options,
    required this.multi,
    required this.selected,
    required this.onMultiSelect,
    required this.onChoiceSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: IosTheme.spaceS,
      runSpacing: IosTheme.spaceS,
      children: [
        for (final o in options)
          Builder(builder: (context) {
            final label = o['label'] as String? ?? '';
            final desc = o['description'] as String?;
            final isSel = selected.contains(label);
            return multi
                ? FilterChip(
                    label: Text(label),
                    selected: isSel,
                    onSelected: (v) => onMultiSelect(label, v),
                    tooltip: desc,
                    selectedColor: IosTheme.iosBlue.withValues(alpha: 0.15),
                    checkmarkColor: IosTheme.iosBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(IosTheme.radiusChip),
                    ),
                  )
                : ChoiceChip(
                    label: Text(label),
                    selected: isSel,
                    onSelected: (_) => onChoiceSelect(label),
                    tooltip: desc,
                    selectedColor: IosTheme.iosBlue.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(IosTheme.radiusChip),
                    ),
                  );
          }),
      ],
    );
  }
}
