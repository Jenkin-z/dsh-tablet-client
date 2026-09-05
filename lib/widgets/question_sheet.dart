import 'package:flutter/material.dart';

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

/// 问题表单弹窗：单选 chips / 多选 chips / 自定义文本；plan-review 意图给通过/否决按钮
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
    return AlertDialog(
      title: const Text('需要回答'),
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
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null && header.isNotEmpty)
            Text(header,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          Text(question, style: const TextStyle(fontSize: 15)),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (intent != null && intent['kind'] == 'plan-review') ...[
            const SizedBox(height: 8),
            Text('计划评审：${intent['approve'] ?? ''}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (options.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
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
                          );
                  }),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _controllerFor(qid),
            decoration: const InputDecoration(
              hintText: '补充说明（可选）',
              border: OutlineInputBorder(),
              isDense: true,
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