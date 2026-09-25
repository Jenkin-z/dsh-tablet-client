import 'package:flutter/material.dart';

import '../services/model_service.dart';
import '../theme/ios_theme.dart';

/// 模型面板的纯展示组件
///
/// 状态与网络都在 [ModelSheet] 里，这里只负责画。
/// 拆出来是为了让 model_sheet.dart 守住 200 行上限。
class ModelSectionTitle extends StatelessWidget {
  final String text;
  const ModelSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        IosTheme.spaceL,
        IosTheme.spaceL,
        IosTheme.spaceXS,
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    );
  }
}

/// 单个模型条目
class ModelTile extends StatelessWidget {
  final CatalogModel model;
  final bool selected;
  final VoidCallback? onTap;

  const ModelTile({
    super.key,
    required this.model,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IosTheme.spaceL,
          vertical: IosTheme.spaceM,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    ),
                  ),
                  if (model.description != null &&
                      model.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      model.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 20, color: IosTheme.iosBlue),
          ],
        ),
      ),
    );
  }
}

/// 推理档位芯片
class ReasoningChip extends StatelessWidget {
  final ReasoningEffort effort;
  final bool active;
  final VoidCallback? onTap;

  const ReasoningChip({
    super.key,
    required this.effort,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: IosTheme.spaceM,
          vertical: IosTheme.spaceS,
        ),
        decoration: BoxDecoration(
          color: active
              ? IosTheme.iosBlue.withValues(alpha: 0.14)
              : (isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7)),
          borderRadius: BorderRadius.circular(IosTheme.radiusButton),
          border: Border.all(
            color: active ? IosTheme.iosBlue : Colors.transparent,
          ),
        ),
        child: Text(
          effort.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active
                ? IosTheme.iosBlue
                : (isDark ? Colors.white70 : const Color(0xFF1C1C1E)),
          ),
        ),
      ),
    );
  }
}

/// 加载失败的 provider 行
class CatalogFailureRow extends StatelessWidget {
  final CatalogFailure failure;
  const CatalogFailureRow(this.failure, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IosTheme.spaceL,
        vertical: IosTheme.spaceS,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: IosTheme.iosOrange),
          const SizedBox(width: IosTheme.spaceS),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                children: [
                  TextSpan(
                    text: '${failure.name} ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: failure.message),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
