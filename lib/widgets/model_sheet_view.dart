import 'package:flutter/material.dart';

import '../services/model_catalog.dart';
import '../theme/ios_theme.dart';
import 'model_sheet_parts.dart';

/// 模型面板主体视图（header / 加载中 / 错误块 / 分组列表），纯展示。
/// 从 model_sheet.dart 拆出来守住 200 行上限；状态与网络仍在 [ModelSheet]。
class ModelSheetView extends StatelessWidget {
  final ModelCatalog? catalog;
  final ModelSelection? current;
  final String? error;
  final bool loading;
  final bool busy;

  final VoidCallback onLoad;
  final void Function(ProviderGroup group, CatalogModel model, {String? effort})
      onSelect;

  const ModelSheetView({
    super.key,
    required this.catalog,
    required this.current,
    required this.error,
    required this.loading,
    required this.busy,
    required this.onLoad,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(p),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        Flexible(child: _body(p)),
      ],
    );
  }

  Widget _header(IosPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        IosTheme.spaceL,
        IosTheme.spaceL,
        IosTheme.spaceS,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '切换模型',
              style: TextStyle(
                fontSize: IosType.title3,
                fontWeight: FontWeight.w600,
                color: p.label,
              ),
            ),
          ),
          if (catalog != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '重新加载',
              onPressed: busy ? null : onLoad,
            ),
        ],
      ),
    );
  }

  Widget _body(IosPalette p) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(IosTheme.spaceXXXL),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final c = catalog;
    if (c == null) {
      return _errorBlock(p, error ?? '加载失败');
    }
    if (c.isEmpty && c.failures.isEmpty) {
      return _errorBlock(p, '这个部署没有可路由的模型。');
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: IosTheme.spaceXL),
      children: [
        if (error != null) _inlineError(p, error!),
        ..._effortSection(),
        for (final g in c.groups)
          if (g.models.isNotEmpty) ..._group(g),
        if (c.failures.isNotEmpty) ...[
          const ModelSectionTitle('不可用'),
          for (final f in c.failures) CatalogFailureRow(f),
        ],
      ],
    );
  }

  /// 在当前目录里找到已选模型，用于展示推理档位
  ({CatalogModel model, ProviderGroup group})? get _currentEntry {
    final sel = current;
    final c = catalog;
    if (sel == null || c == null) return null;
    for (final g in c.groups) {
      if (g.id != sel.provider) continue;
      for (final m in g.models) {
        if (m.id == sel.model) return (model: m, group: g);
      }
    }
    return null;
  }

  /// 当前模型支持调档时，把档位做成可点的一行
  List<Widget> _effortSection() {
    final entry = _currentEntry;
    if (entry == null || !entry.model.hasEfforts) return const [];
    final model = entry.model;
    return [
      ModelSectionTitle('推理档位 · ${model.name}'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
        child: Wrap(
          spacing: IosTheme.spaceS,
          runSpacing: IosTheme.spaceS,
          children: [
            for (final e in model.efforts)
              ReasoningChip(
                effort: e,
                active: current?.reasoningEffort == e.id ||
                    (current?.reasoningEffort == null &&
                        model.defaultEffort == e.id),
                onTap: busy
                    ? null
                    : () => onSelect(entry.group, model, effort: e.id),
              ),
          ],
        ),
      ),
      const SizedBox(height: IosTheme.spaceL),
    ];
  }

  List<Widget> _group(ProviderGroup g) {
    return [
      ModelSectionTitle(g.name),
      for (final m in g.models)
        ModelTile(
          model: m,
          selected: current?.provider == g.id && current?.model == m.id,
          onTap: busy || (current?.provider == g.id && current?.model == m.id)
              ? null
              : () => onSelect(g, m),
        ),
    ];
  }

  Widget _inlineError(IosPalette p, String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        IosTheme.spaceS,
        IosTheme.spaceL,
        0,
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: IosType.footnotePlus,
          color: p.bad,
        ),
      ),
    );
  }

  Widget _errorBlock(IosPalette p, String message) {
    return Padding(
      padding: const EdgeInsets.all(IosTheme.spaceXXL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 32, color: p.label),
          const SizedBox(height: IosTheme.spaceM),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: p.label2,
            ),
          ),
          const SizedBox(height: IosTheme.spaceL),
          TextButton(onPressed: onLoad, child: const Text('重试')),
        ],
      ),
    );
  }
}
