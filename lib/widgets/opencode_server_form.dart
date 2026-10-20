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
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            if (linkMode) ..._linkFields(isDark) else ..._manualFields(isDark),
            const SizedBox(height: IosTheme.spaceM),
            _field(
              controller: name,
              hint: '留空则用地址',
              label: '名称（可选）',
              isDark: isDark,
            ),
            if (error != null) ...[
              const SizedBox(height: IosTheme.spaceM),
              Text(error!,
                  style: const TextStyle(fontSize: 13, color: IosTheme.iosRed)),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _linkFields(bool isDark) => [
        _field(
          controller: link,
          hint: 'https://xxxx.opencode.run/auth/connect/abc123',
          label: '授权链接',
          isDark: isDark,
        ),
        const SizedBox(height: IosTheme.spaceS),
        const Text(
          'PC 上运行 opencode pair --remote 生成，300 秒内有效',
          style: TextStyle(fontSize: 12, color: IosTheme.iosGray),
        ),
      ];

  List<Widget> _manualFields(bool isDark) => [
        _field(
          controller: url,
          hint: 'http://IP:4096，任意 IP 或主机名',
          label: '地址',
          isDark: isDark,
        ),
        const SizedBox(height: IosTheme.spaceM),
        _field(
          controller: password,
          hint: '服务密码',
          label: '密码',
          isDark: isDark,
          obscure: true,
        ),
        const SizedBox(height: IosTheme.spaceS),
        const Text(
          '局域网直连需 PC 端 opencode serve --hostname 0.0.0.0',
          style: TextStyle(fontSize: 12, color: IosTheme.iosGray),
        ),
      ];

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required String label,
    required bool isDark,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: !busy,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: IosTheme.iosGray),
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusInput),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
