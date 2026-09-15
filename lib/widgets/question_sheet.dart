import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 待回答的问题请求（一 ask 多问一批答）
class PendingQuestion {
  final String rpcId;
  final String sessionId;
  final List<Map<String, dynamic>> questions;

  PendingQuestion({
    required this.rpcId,
    required this.sessionId,
    required this.questions,
  });
}

/// 问题表单弹窗 —— iOS 风格
///
/// 单选 chips / 多选 chips / 自定义文本；
/// plan-review 意图给通过/否决按钮。
class QuestionSheet extends StatefulWidget {
  final PendingQuestion question;
  final Future<void> Function(List<Map<String, dynamic>> answers) onSubmit;

  const QuestionSheet(
      {super.key, required this.question, required this.onSubmit});

  @override
  State<QuestionSheet> createState() => _QuestionSheetState();
}

class _QuestionSheetState extends State<QuestionSheet> {
  // questionId -> 选中的 option label
  final Map<String, Set<String>> _selected = {};
  final Map<String, TextEditingController> _custom = {};
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in _custom.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String qid) =>
      _custom.putIfAbsent(qid, () => TextEditingController());

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IosTheme.radiusM),
      ),
      title: const Text(
        '需要回答',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final q in widget.question.questions) _questionBlock(q),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(
            '稍后',
            style: TextStyle(
              color: IosTheme.iosBlue,
              fontSize: 17,
            ),
          ),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: IosTheme.iosBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(IosTheme.radiusButton),
            ),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('提交'),
        ),
      ],
    );
  }

  Widget _questionBlock(Map<String, dynamic> q) {
    final qid = q['id'] as String? ?? '';
    final header = q['header'] as String?;
    final question = q['question'] as String? ?? '';
    final detail = q['detail'] as String?;
    final options = (q['options'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final multi = q['multiSelect'] == true;
    final intent = q['intent'] as Map<String, dynamic>?;
    final selected = _selected.putIfAbsent(qid, () => <String>{});
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            Wrap(
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
                            onSelected: (v) => setState(() {
                              if (v) {
                                selected.add(label);
                              } else {
                                selected.remove(label);
                              }
                            }),
                            tooltip: desc,
                            selectedColor:
                                IosTheme.iosBlue.withValues(alpha: 0.15),
                            checkmarkColor: IosTheme.iosBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(IosTheme.radiusChip),
                            ),
                          )
                        : ChoiceChip(
                            label: Text(label),
                            selected: isSel,
                            onSelected: (_) => setState(() {
                              selected
                                ..clear()
                                ..add(label);
                            }),
                            tooltip: desc,
                            selectedColor:
                                IosTheme.iosBlue.withValues(alpha: 0.15),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(IosTheme.radiusChip),
                            ),
                          );
                  }),
              ],
            ),
          ],
          const SizedBox(height: IosTheme.spaceM),
          TextField(
            controller: _controllerFor(qid),
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

  Future<void> _submit() async {
    final answers = <Map<String, dynamic>>[];
    for (final q in widget.question.questions) {
      final qid = q['id'] as String? ?? '';
      final custom = _custom[qid]?.text.trim() ?? '';
      answers.add({
        'id': qid,
        'selected': _selected[qid]?.toList() ?? <String>[],
        if (custom.isNotEmpty) 'custom': custom,
      });
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(answers);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
