import 'package:flutter/material.dart';

import '../theme/ios_theme.dart';

/// 添加/重新授权 opencode 的表单区（两种接入模式的输入 + 名称 + 错误）
///
/// 纯展示 + 回调，不碰状态与网络：由 AddOpenCodeDialog 持有控制器，
/// 保存动作走对话框自己的 _save。
class OpenCodeServerForm extends StatelessWidget {
  final TextEditingController link;
  final TextEditingController url;
  final TextEditingController password;
  final TextEditingController name;
  final bool linkMode;
  final bool busy;
  final String? error;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback? onScan;

  const OpenCodeServerForm({
    super.key,
    required this.link,
    required this.url,
    required this.password,
    required this.name,
    required this.linkMode,
    required this.busy,
    required this.onModeChanged,
    this.error,
    this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('授权链接'),
                  icon: Icon(Icons.link, size: 16),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('手动连接'),
                  icon: Icon(Icons.wifi, size: 16),
                ),
              ],
              selected: {linkMode},
              onSelectionChanged:
                  busy ? null : (v) => onModeChanged(v.first),
            ),
            const SizedBox(height: IosTheme.spaceL),
            if (linkMode) ..._linkFields(p) else ..._manualFields(p),
            const SizedBox(height: IosTheme.spaceM),
            _field(
              controller: name,
              hint: '留空则用地址',
              label: '名称（可选）',
              p: p,
            ),
            if (error != null) ...[
              const SizedBox(height: IosTheme.spaceM),
              Text(
                error!,
                style: TextStyle(
                  fontSize: IosType.footnotePlus,
                  color: p.bad,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _linkFields(IosPalette p) => [
        _field(
          controller: link,
          hint: 'https://xxxx.opencode.run/auth/connect/abc123',
          label: '授权链接',
          p: p,
          scan: true,
        ),
        const SizedBox(height: IosTheme.spaceS),
        Text(
          'PC 上运行 opencode pair --remote 生成，300 秒内有效；也可直接扫授权二维码',
          style: TextStyle(
            fontSize: IosType.footnote,
            color: p.label2,
          ),
        ),
      ];

  List<Widget> _manualFields(IosPalette p) => [
        _field(
          controller: url,
          hint: 'http://IP:4096，任意 IP 或主机名',
          label: '地址',
          p: p,
          scan: true,
        ),
        const SizedBox(height: IosTheme.spaceM),
        _field(
          controller: password,
          hint: '服务密码',
          label: '密码',
          p: p,
          obscure: true,
        ),
        const SizedBox(height: IosTheme.spaceS),
        Text(
          '局域网直连需 PC 端 opencode serve --hostname 0.0.0.0',
          style: TextStyle(
            fontSize: IosType.footnote,
            color: p.label2,
          ),
        ),
      ];

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required String label,
    required IosPalette p,
    bool obscure = false,
    bool scan = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: !busy,
      style: const TextStyle(fontSize: IosType.body),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: IosType.footnotePlus,
          color: p.label3,
        ),
        filled: true,
        fillColor: p.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusInput),
          borderSide: BorderSide.none,
        ),
        suffixIcon: scan && onScan != null
            ? IconButton(
                icon: const Icon(Icons.qr_code_scanner, size: 22),
                color: p.accent,
                tooltip: '扫码填入',
                onPressed: busy ? null : onScan,
              )
            : null,
      ),
    );
  }
}
