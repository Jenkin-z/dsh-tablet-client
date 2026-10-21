import '../models/pending.dart';

/// opencode 表单的取值 / 可见性 / 必填校验
///
/// 从 open_code_form_sheet.dart 拆出来，让那个文件守住 200 行上限。
/// 纯逻辑，无 UI 依赖。
class OpenCodeFormLogic {
  /// 字段当前值（key → 值）
  final Map<String, dynamic> values;

  /// 文本框里用户实际编辑过的内容（key → 文本）
  final Map<String, String> editedText;

  OpenCodeFormLogic({
    required this.values,
    required this.editedText,
  });

  /// 服务端 default 预填进 [values]
  ///
  /// 用户不改也能直接提交。
  static void applyDefaults(
    PendingForm form,
    Map<String, dynamic> values,
  ) {
    for (final f in form.fields) {
      final key = f['key'] as String? ?? '';
      final d = f['default'];
      if (key.isEmpty || d == null) continue;
      if (d is String || d is bool || d is num) {
        values[key] = d;
      } else if (d is List) {
        values[key] = d.whereType<String>().toList();
      }
    }
  }

  /// when 联动：字段仅在 `[{[key,op,value]}]` 全部命中时可见（AND）
  bool visible(Map<String, dynamic> field) {
    final when = field['when'];
    if (when is! List) return true;
    for (final w in when) {
      if (w is! Map) continue;
      final k = w['key'] as String? ?? '';
      final op = w['op'] as String? ?? 'eq';
      final v = w['value'];
      final cur = values[k];
      final hit = switch (op) {
        'neq' => cur != v,
        _ => cur == v,
      };
      if (!hit) return false;
    }
    return true;
  }

  /// 答案形状 {key: value}，与 reply API 1:1
  Map<String, dynamic> buildAnswer(PendingForm form) {
    final answer = <String, dynamic>{};
    for (final f in form.fields) {
      if (f['hidden'] == true || !visible(f)) continue;
      final key = f['key'] as String? ?? '';
      if (key.isEmpty) continue;
      final v = values[key];
      if (v == null) continue;
      // 文本类：用户在文本框编辑过以 controller 为准；否则用值本身
      // （chip 选项值 / default 不走 controller——见 FormFieldInput）
      if (v is String) {
        final edited = editedText[key] ?? '';
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

  /// 是否有必填项空缺（只有 required 空缺才拦截提交）
  bool missingRequired(PendingForm form) {
    for (final f in form.fields) {
      if (f['required'] != true) continue;
      if (f['hidden'] == true || !visible(f)) continue;
      final key = f['key'] as String? ?? '';
      final v = values[key];
      final empty = v == null ||
          (v is String && v.isEmpty) ||
          (v is List && v.isEmpty);
      if (empty) return true;
    }
    return false;
  }

  /// 当前可见（且非 hidden）的字段列表
  List<Map<String, dynamic>> visibleFields(PendingForm form) => form.fields
      .where((f) => f['hidden'] != true && visible(f))
      .toList();
}
