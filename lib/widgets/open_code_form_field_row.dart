import 'package:flutter/material.dart';

import '../theme/ios_theme.dart';
import 'form_field_input.dart';

/// opencode 表单里的单个字段行（标题 + 说明 + 字段渲染）
///
/// 从 open_code_form_sheet.dart 拆出来，让那个文件守住 200 行上限。
/// 字段渲染本体在 [FormFieldInput]。
class OpenCodeFormFieldRow extends StatelessWidget {
  final Map<String, dynamic> field;
  final dynamic value;
  final TextEditingController controller;
  final ValueChanged<dynamic> onChanged;

  const OpenCodeFormFieldRow({
    super.key,
    required this.field,
    required this.value,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final key = field['key'] as String? ?? '';
    final title = field['title'] as String? ?? key;
    final desc = field['description'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: IosTheme.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title + (field['required'] == true ? ' *' : ''),
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
            type: field['type'] as String? ?? 'string',
            field: field,
            value: value,
            controller: controller,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
