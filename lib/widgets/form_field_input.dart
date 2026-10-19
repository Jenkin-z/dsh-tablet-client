import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ios_theme.dart';

/// opencode 表单字段渲染（无状态：值由壳管理，变更经 [onChanged] 上抛）
///
/// 覆盖实测字段类型：string（可带 options/custom 自填）/ integer / number /
/// boolean / multiselect / external（无 url_launcher，给可复制文本）。
class FormFieldInput extends StatelessWidget {
  final String fieldKey;
  final String type;
  final Map<String, dynamic> field;
  final dynamic value;
  final TextEditingController controller;
  final ValueChanged<dynamic> onChanged;

  const FormFieldInput({
    super.key,
    required this.fieldKey,
    required this.type,
    required this.field,
    required this.value,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = (field['options'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    switch (type) {
      case 'boolean':
        return Switch(
          value: value == true,
          onChanged: (v) => onChanged(v),
        );
      case 'integer':
      case 'number':
        return _numberInput(type == 'integer');
      case 'multiselect':
        return _chips(options, multi: true);
      case 'external':
        return SelectableText(
          field['url'] as String? ?? '',
          style: const TextStyle(fontSize: 13, color: IosTheme.iosBlue),
        );
      case 'string':
      default:
        if (options.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _chips(options, multi: false),
              // custom=true：选项之外允许自填
              if (field['custom'] == true) ...[
                const SizedBox(height: IosTheme.spaceS),
                _textInput(TextInputType.text),
              ],
            ],
          );
        }
        return _textInput(TextInputType.text);
    }
  }

  Widget _textInput(TextInputType keyboard) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      decoration: _deco(),
      onChanged: onChanged,
    );
  }

  Widget _numberInput(bool isInt) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]'))],
      decoration: _deco(),
      onChanged: (v) {
        final n = isInt ? int.tryParse(v) : double.tryParse(v);
        if (n != null) onChanged(n);
      },
    );
  }

  InputDecoration _deco() {
    return InputDecoration(
      hintText: field['placeholder'] as String? ?? '',
      filled: true,
      fillColor: const Color(0xFFF2F2F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IosTheme.radiusInput),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: IosTheme.spaceL,
        vertical: IosTheme.spaceM,
      ),
    );
  }

  Widget _chips(List<Map<String, dynamic>> options, {required bool multi}) {
    return Wrap(
      spacing: IosTheme.spaceS,
      runSpacing: IosTheme.spaceS,
      children: [
        for (final o in options)
          Builder(builder: (context) {
            final v = o['value'] as String? ?? '';
            final label = o['label'] as String? ?? v;
            final desc = o['description'] as String?;
            final isSel = multi
                ? (value is List && (value as List).contains(v))
                : value == v;
            return multi
                ? FilterChip(
                    label: Text(label),
                    selected: isSel,
                    tooltip: desc,
                    onSelected: (sel) {
                      final cur = value is List
                          ? List<String>.from(value as List)
                          : <String>[];
                      if (sel) {
                        cur.add(v);
                      } else {
                        cur.remove(v);
                      }
                      onChanged(cur);
                    },
                  )
                : ChoiceChip(
                    label: Text(label),
                    selected: isSel,
                    tooltip: desc,
                    onSelected: (_) => onChanged(v),
                  );
          }),
      ],
    );
  }
}
