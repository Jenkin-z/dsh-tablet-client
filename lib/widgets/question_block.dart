import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';
import 'question_sheet_fields.dart';

/// 问题块：题干 / 补充说明（detail）/ plan-review 提示 / 选项 chips / 自定义文本框
///
/// 从 question_sheet.dart 拆出来是为了守住 200 行上限。
/// 纯布局：chips 由 [QuestionChipsRow] 画，TextField 控制器由调用方提供并持有。
class QuestionBlock extends StatelessWidget {
  final Map<String, dynamic> q;
  final Set<String> selected;
  final TextEditingController controller;
  final bool isDark;
  final void Function(String label, bool value) onMultiSelect;
  final void Function(String label) onChoiceSelect;

  const QuestionBlock({
    super.key,
    required this.q,
    required this.selected,
    required this.controller,
    required this.isDark,
    required this.onMultiSelect,
    required this.onChoiceSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    final header = q['header'] as String?;
    final question = q['question'] as String? ?? '';
    final detail = q['detail'] as String?;
    final options = (q['options'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final multi = q['multiSelect'] == true;
    final intent = q['intent'] as Map<String, dynamic>?;

    return Padding(
      padding: const EdgeInsets.only(bottom: IosTheme.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null && header.isNotEmpty)
            Text(
              header,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: IosType.footnotePlus,
                color: p.label,
              ),
            ),
          const SizedBox(height: IosTheme.spaceXS),
          Text(
            question,
            style: TextStyle(
              fontSize: IosType.body,
              color: p.label,
            ),
          ),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: IosTheme.spaceXS),
            Text(
              detail,
              style: TextStyle(
                fontSize: IosType.footnotePlus,
                color: p.label,
              ),
            ),
          ],
          if (intent != null && intent['kind'] == 'plan-review') ...[
            const SizedBox(height: IosTheme.spaceS),
            Container(
              padding: const EdgeInsets.all(IosTheme.spaceM),
              decoration: BoxDecoration(
                color: p.accentSoft,
                borderRadius: BorderRadius.circular(IosTheme.radiusXS),
              ),
              child: Text(
                '计划评审：${intent['approve'] ?? ''}',
                style: TextStyle(
                  fontSize: IosType.footnotePlus,
                  color: p.accent,
                ),
              ),
            ),
          ],
          if (options.isNotEmpty) ...[
            const SizedBox(height: IosTheme.spaceM),
            QuestionChipsRow(
              options: options,
              multi: multi,
              selected: selected,
              onMultiSelect: onMultiSelect,
              onChoiceSelect: onChoiceSelect,
            ),
          ],
          const SizedBox(height: IosTheme.spaceM),
          TextField(
            controller: controller,
            style: const TextStyle(fontSize: IosType.body),
            decoration: InputDecoration(
              hintText: '补充说明（可选）',
              hintStyle: TextStyle(color: p.label3),
              filled: true,
              fillColor: p.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(IosTheme.radiusInput),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: IosTheme.spaceL,
                vertical: IosTheme.spaceM,
              ),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
