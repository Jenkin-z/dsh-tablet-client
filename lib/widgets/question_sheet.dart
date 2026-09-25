import 'package:flutter/material.dart';
import '../models/pending.dart';
import '../theme/ios_theme.dart';

export '../models/pending.dart' show PendingQuestion;

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
  String? _error;

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
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: IosTheme.spaceM),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: IosTheme.iosRed, fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : _cancel,
          child: Text(
            '放弃回答',
            style: TextStyle(
              color: IosTheme.iosRed,
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
                              // 单选：选选项即清空自定义文本
                              _custom[qid]?.clear();
                              _error = null;
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

  /// 按 Web 端规则编码答案（QuestionComposer.tsx:205-232）
  ///
  /// - 单选 + 自定义文本 → `selected` **强制清空**（自定义即替代选项）
  /// - 多选 → `selected` 保留，且与 `custom` **共存**
  /// - `custom` 为空时**整个键省略**（不能是空串）
  /// - 跳过 → `{id, selected:[]}`
  List<Map<String, dynamic>> _buildAnswers() {
    final answers = <Map<String, dynamic>>[];
    for (final q in widget.question.questions) {
      final qid = q['id'] as String? ?? '';
      final multi = q['multiSelect'] == true;
      final custom = _custom[qid]?.text.trim() ?? '';
      final selected = _selected[qid]?.toList() ?? <String>[];

      // 自定义答案与选项互斥（多选除外）
      final keepSelected = custom.isEmpty || multi ? selected : <String>[];
      answers.add({
        'id': qid,
        'selected': keepSelected,
        if (custom.isNotEmpty) 'custom': custom,
      });
    }
    return answers;
  }

  /// 该题是否已回答：有选项被选中，或填了自定义文本
  bool _answered(Map<String, dynamic> q) {
    final qid = q['id'] as String? ?? '';
    final custom = _custom[qid]?.text.trim() ?? '';
    return (_selected[qid]?.isNotEmpty ?? false) || custom.isNotEmpty;
  }

  Future<void> _cancel() async {
    // 返回 false 表示「未提交」→ 调用方据此取消 Host 侧的待答请求
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _submit() async {
    // Web 端要求全部作答才可提交，未答则跳到第一处缺失
    final missing = widget.question.questions.where((q) => !_answered(q)).toList();
    if (missing.isNotEmpty) {
      setState(() => _error = '请先完成这道问题：请选择一个选项或填写自定义答案。');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_buildAnswers());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '回答未被接受，可能已过期，可再试一次');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
