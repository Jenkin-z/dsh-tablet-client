import 'package:flutter/material.dart';
import '../theme/ios_theme.dart';

/// 配对页底部的「说明」卡片：各条授权方式怎么用
class PairInfoCard extends StatelessWidget {
  const PairInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(IosTheme.radiusCard),
        boxShadow: IosTheme.shadowS,
      ),
      padding: const EdgeInsets.all(IosTheme.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '说明',
            style: TextStyle(
              fontSize: IosType.body,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: IosTheme.spaceS),
          _infoRow(
            p: p,
            icon: Icons.pin,
            text: '配对码方式（dsh-lan-pair，默认19387）：PC 打开管理页 '
                'http://127.0.0.1:<DSH端口>/__gate/admin 或 DSH 侧边栏面板拿配对码，'
                '这里填 PC 局域网 IP 再输配对码授权；一码一机、300 秒内有效，'
                '设备配对一次可保存一年',
          ),
          const SizedBox(height: IosTheme.spaceS),
          _infoRow(
            p: p,
            icon: Icons.link,
            text: '启动令牌在 PC 上 dsh web 启动输出的网址里（?token=r_...），每个 DSH 进程一份，重启后会变',
          ),
          const SizedBox(height: IosTheme.spaceS),
          _infoRow(
            p: p,
            icon: Icons.schedule,
            text: '换到的授权默认 30 天有效，DSH 重启不用重新授权',
          ),
          const SizedBox(height: IosTheme.spaceS),
          _infoRow(
            p: p,
            icon: Icons.auto_fix_high,
            text: '自动方式：在 PC 上运行 tool\\publish_launch_token.ps1，令牌会发到 8099 下载服务，平板一键拉取',
          ),
          const SizedBox(height: IosTheme.spaceS),
          _infoRow(
            p: p,
            icon: Icons.phonelink_lock,
            text: '配对页方式（桌面端 19387）：PC 双击「手机授权.bat」，这里填 PC 局域网 IP 后点「配对页授权」，授权完即可关掉 PC 上的窗口；换网段需重新授权',
          ),
        ],
      ),
    );
  }

  Widget _infoRow({required IconData icon, required String text, required IosPalette p}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: p.label2),
        const SizedBox(width: IosTheme.spaceS),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: p.label2,
            ),
          ),
        ),
      ],
    );
  }
}
