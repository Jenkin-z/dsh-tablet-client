import 'package:flutter/material.dart';

import '../services/chat_controller.dart';
import '../theme/ios_theme.dart';
import 'open_code_form_sheet.dart';

/// opencode 表单的 UI 宿主（DSH 提问在 chat_screen 内联装配，这里对称外包）
///
/// 自挂 dispatcher 的 onShowFormDialog / onPopFormDialog，
/// 并提供「有待填表单」的入口条（弹窗被关掉后还能再打开）。
/// 放在 build 里即可——首次 build 早于 ChatController.boot()（postFrame），
/// 回调一定先于任何事件就位。
class OpenCodeFormHost extends StatefulWidget {
  final ChatController ctrl;

  const OpenCodeFormHost({super.key, required this.ctrl});

  @override
  State<OpenCodeFormHost> createState() => _OpenCodeFormHostState();
}

class _OpenCodeFormHostState extends State<OpenCodeFormHost> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.dispatcher.onShowFormDialog = _maybeShow;
    widget.ctrl.dispatcher.onPopFormDialog = () {
      if (mounted) Navigator.of(context).maybePop();
    };
  }

  @override
  void dispose() {
    widget.ctrl.dispatcher.onShowFormDialog = null;
    widget.ctrl.dispatcher.onPopFormDialog = null;
    super.dispose();
  }

  void _maybeShow() {
    final ctrl = widget.ctrl;
    final form = ctrl.state.form;
    if (form == null || ctrl.state.formDialogOpen || !mounted) return;
    if (form.sessionId != ctrl.state.sessionId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('其他会话有表单待填写'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => ctrl.switchSession(form.sessionId),
          ),
        ),
      );
      return;
    }
    ctrl.state.setFormDialogOpen(true);
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OpenCodeFormSheet(
        form: form,
        onSubmit: _submit,
      ),
    ).then((submitted) {
      ctrl.state.setFormDialogOpen(false);
      // 未提交即关闭 → 显式取消，不让 Agent 一直挂等
      if (submitted != true) {
        ctrl.cancelForm(form.formId);
      }
    });
  }

  Future<bool> _submit(Map<String, dynamic> answer) async {
    final form = widget.ctrl.state.form;
    if (form == null) return false;
    // 400（答案不合法）会带 message 上抛，弹窗捕获后原地显示
    return widget.ctrl.submitForm(form.formId, answer);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final form = ctrl.state.allForms
        .where((f) => f.sessionId == ctrl.state.sessionId)
        .firstOrNull;
    if (form == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        IosTheme.spaceXS,
        IosTheme.spaceL,
        0,
      ),
      child: IosButton(
        label: '表单待填写：${form.title}',
        icon: Icons.assignment_outlined,
        filled: false,
        onPressed: _maybeShow,
      ),
    );
  }
}
