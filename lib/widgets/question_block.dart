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
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: IosTheme.iosGray,
              ),
            ),
          const SizedBox(height: IosTheme.spaceXS),
          Text(
            question,
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white : const Color(0xFF1C1C1E),
            ),
          ),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: IosTheme.spaceXS),
            Text(
              detail,
              style: TextStyle(
                fontSize: 13,
                color: IosTheme.iosGray,
              ),
            ),
          ],
          if (intent != null && intent['kind'] == 'plan-review') ...[
            const SizedBox(height: IosTheme.spaceS),
            Container(
              padding: const EdgeInsets.all(IosTheme.spaceM),
              decoration: BoxDecoration(
                color: IosTheme.iosBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(IosTheme.radiusXS),
              ),
              child: Text(
                '计划评审：${intent['approve'] ?? ''}',
                style: const TextStyle(
                  fontSize: 13,
                  color: IosTheme.iosBlue,
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
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: '补充说明（可选）',
              hintStyle: TextStyle(color: IosTheme.iosGray),
              filled: true,
              fillColor: isDark
                  ? const Color(0xFF3A3A3C)
                  : const Color(0xFFF2F2F7),
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
