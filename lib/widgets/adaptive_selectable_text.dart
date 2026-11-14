import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// 平台自适应文本：Android 保留长按选择复制；web 用普通 Text。
///
/// Flutter web 上 SelectableText 的语义子树不产出文本标签
/// （实测整个气泡区域对读屏/语义树变成空节点），会话流的
/// 可读性优先于浏览器内的选中复制，web 端降级为 Text。
class AdaptiveSelectableText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;

  const AdaptiveSelectableText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Text(data, style: style, textAlign: textAlign);
    }
    return SelectableText(data, style: style, textAlign: textAlign);
  }
}
