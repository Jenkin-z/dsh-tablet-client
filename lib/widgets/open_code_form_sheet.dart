import 'package:flutter/material.dart';

import '../models/pending.dart';
import '../theme/ios_theme.dart';
import 'form_field_input.dart';

/// opencode 表单弹窗 —— iOS 风格
///
/// 与 DSH 的 QuestionSheet（chips+文本）不同：opencode form 是结构化字段，
/// 答案形状 `{key: value}` 与 reply API 1:1，不做形状转换。
/// required 空缺才拦截（optional 可空——DSH 没有 optional 概念）。
/// 字段级渲染在 [FormFieldInput]。
class OpenCodeFormSheet extends StatefulWidget {
  final PendingForm form;

  /// 返回 true = 已提交或已被解决；抛出 = 服务端不接受（message 直显）
  final Future<bool> Function(Map<String, dynamic> answer) onSubmit;

  const OpenCodeFormSheet({
    super.key,
    required this.form,
    required this.onSubmit,
  });

  @override
  State<OpenCodeFormSheet> createState() => _OpenCodeFormSheetState();
}

class _OpenCodeFormSheetState extends State<OpenCodeFormSheet> {
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _text = {};
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 服务端 default 预填（用户不改也能直接提交）
    for (final f in widget.form.fields) {
      final key = f['key'] as String? ?? '';
      final d = f['default'];
      if (key.isEmpty || d == null) continue;
      if (d is String || d is bool || d is num) {
        _values[key] = d;
      } else if (d is List) {
        _values[key] = d.whereType<String>().toList();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key, dynamic value) =>
      _text.putIfAbsent(
        key,
        () => TextEditingController(text: value is String ? value : ''),
      );

  /// when 联动：字段仅在 `[{[key,op,value]}]` 全部命中时可见（AND）
  bool _visible(Map<String, dynamic> field) {
    final when = field['when'];
    if (when is! List) return true;
    for (final w in when) {
      if (w is! Map) continue;
      final k = w['key'] as String? ?? '';
      final op = w['op'] as String? ?? 'eq';
      final v = w['value'];
      final cur = _values[k];
      final hit = switch (op) {
        'neq' => cur != v,
        _ => cur == v,
      };
      if (!hit) return false;
    }
    return true;
  }

  Map<String, dynamic> _buildAnswer() {
    final answer = <String, dynamic>{};
    for (final f in widget.form.fields) {
      if (f['hidden'] == true || !_visible(f)) continue;
      final key = f['key'] as String? ?? '';
      if (key.isEmpty) continue;
      final v = _values[key];
      if (v == null) continue;
      // 文本类：用户在文本框编辑过以 controller 为准；否则用值本身
      // （chip 选项值 / default 不走 controller——见 FormFieldInput）
      if (v is String) {
        final edited = _text[key]?.text ?? '';
        if (edited.isNotEmpty) {
          answer[key] = edited;
        } else if (v.isNotEmpty) {
          answer[key] = v;
        }
      } else if (v is List) {
        if (v.isNotEmpty) answer[key] = v;
      } else {
        answer[key] = v;
      }
    }
    return answer;
  }

  bool _missingRequired() {
    for (final f in widget.form.fields) {
      if (f['required'] != true) continue;
      if (f['hidden'] == true || !_visible(f)) continue;
      final key = f['key'] as String? ?? '';
      final v = _values[key];
      final empty = v == null ||
          (v is String && v.isEmpty) ||
          (v is List && v.isEmpty);
      if (empty) return true;
    }
    return false;
  }

  Future<void> _submit() async {
    if (_missingRequired()) {
      setState(() => _error = '有必填项未填写');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final ok = await widget.onSubmit(_buildAnswer());
      if (mounted && ok) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _cancel() {
    // 未提交即关闭 → 调用方显式取消（通知 Agent，不让它一直挂等）
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fields = widget.form.fields
        .where((f) => f['hidden'] != true && _visible(f))
        .toList();
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IosTheme.radiusM),
      ),
      title: Text(
        widget.form.title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final f in fields) _fieldRow(f),
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
            style: TextStyle(color: IosTheme.iosRed, fontSize: 17),
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

  Widget _fieldRow(Map<String, dynamic> f) {
    final key = f['key'] as String? ?? '';
    final title = f['title'] as String? ?? key;
    final desc = f['description'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: IosTheme.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title + (f['required'] == true ? ' *' : ''),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: IosTheme.spaceXS),
            Text(
              desc,
              style: const TextStyle(fontSize: 13, color: IosTheme.iosGray),
            ),
          ],
          const SizedBox(height: IosTheme.spaceS),
          FormFieldInput(
            key: ValueKey(key),
            fieldKey: key,
            type: f['type'] as String? ?? 'string',
            field: f,
            value: _values[key],
            controller: _controllerFor(key, _values[key]),
            onChanged: (v) => setState(() {
              _values[key] = v;
              _error = null;
            }),
          ),
        ],
      ),
    );
  }
}
