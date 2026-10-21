import 'package:flutter/material.dart';

import '../models/pending.dart';
import '../theme/ios_theme.dart';
import 'open_code_form_field_row.dart';
import 'open_code_form_logic.dart';

/// opencode 表单弹窗 —— iOS 风格
///
/// 与 DSH 的 QuestionSheet（chips+文本）不同：opencode form 是结构化字段，
/// 答案形状 `{key: value}` 与 reply API 1:1，不做形状转换。
/// required 空缺才拦截（optional 可空——DSH 没有 optional 概念）。
/// 字段级渲染在 [FormFieldInput]，字段行拆到 open_code_form_field_row.dart，
/// 取值/校验逻辑拆到 open_code_form_logic.dart。
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

  /// 取值/可见性/必填校验的纯逻辑
  OpenCodeFormLogic get _logic => OpenCodeFormLogic(
        values: _values,
        editedText: {
          for (final e in _text.entries) e.key: e.value.text,
        },
      );

  @override
  void initState() {
    super.initState();
    // 服务端 default 预填（用户不改也能直接提交）
    OpenCodeFormLogic.applyDefaults(widget.form, _values);
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

  Future<void> _submit() async {
    if (_logic.missingRequired(widget.form)) {
      setState(() => _error = '有必填项未填写');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final ok = await widget.onSubmit(_logic.buildAnswer(widget.form));
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
    final fields = _logic.visibleFields(widget.form);
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
    return OpenCodeFormFieldRow(
      field: f,
      value: _values[key],
      controller: _controllerFor(key, _values[key]),
      onChanged: (v) => setState(() {
        _values[key] = v;
        _error = null;
      }),
    );
  }
}
