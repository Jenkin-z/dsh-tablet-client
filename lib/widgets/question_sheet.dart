import 'package:flutter/material.dart';
import '../models/pending.dart';
import '../theme/ios_theme.dart';
import 'question_block.dart';

export '../models/pending.dart' show PendingQuestion;

/// 问题表单弹窗 —— iOS 风格
///
/// 单选 chips / 多选 chips / 自定义文本；
/// plan-review 意图给通过/否决按钮。
/// 题块布局拆到 question_block.dart（含 question_sheet_fields.dart）。
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
              for (final q in widget.question.questions)
                QuestionBlock(
                  q: q,
                  selected:
                      _selected.putIfAbsent(q['id'] as String? ?? '', () => {}),
                  controller: _controllerFor(q['id'] as String? ?? ''),
                  isDark: isDark,
                  onMultiSelect: (label, v) => setState(() {
                    final set = _selected
                        .putIfAbsent(q['id'] as String? ?? '', () => {});
                    if (v) {
                      set.add(label);
                    } else {
                      set.remove(label);
                    }
                  }),
                  onChoiceSelect: (label) => setState(() {
                    final qid = q['id'] as String? ?? '';
                    _selected.putIfAbsent(qid, () => {})
                      ..clear()
                      ..add(label);
                    // 单选：选选项即清空自定义文本
                    _custom[qid]?.clear();
                    _error = null;
                  }),
                ),
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
    final missing =
        widget.question.questions.where((q) => !_answered(q)).toList();
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
