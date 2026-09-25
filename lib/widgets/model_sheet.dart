import 'package:flutter/material.dart';

import '../services/model_service.dart';
import '../theme/ios_theme.dart';
import 'model_sheet_parts.dart';

/// 模型切换面板（底部弹出）
///
/// 打开时拉 `session/modelCatalog`，点选后调 `session/selectModel`。
/// 选中结果通过 `Navigator.pop` 返回给调用方，由调用方决定是否回写状态
/// —— 面板本身不碰全局状态，权威值仍以 Host 推来的投影为准。
class ModelSheet extends StatefulWidget {
  final ModelService service;
  final String sessionId;
  final ModelSelection? current;

  const ModelSheet({
    super.key,
    required this.service,
    required this.sessionId,
    this.current,
  });

  @override
  State<ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<ModelSheet> {
  ModelCatalog? _catalog;
  ModelSelection? _current;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _current = widget.current;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await widget.service.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _select(ProviderGroup group, CatalogModel model,
      {String? effort}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final applied = await widget.service.select(
        widget.sessionId,
        ModelSelection(
          provider: group.id,
          model: model.id,
          reasoningEffort: effort ?? model.defaultEffort,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(applied);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '切换失败：$e';
      });
    }
  }

  /// 在当前目录里找到已选模型，用于展示推理档位
  ({CatalogModel model, ProviderGroup group})? get _currentEntry {
    final c = _current;
    final catalog = _catalog;
    if (c == null || catalog == null) return null;
    for (final g in catalog.groups) {
      if (g.id != c.provider) continue;
      for (final m in g.models) {
        if (m.id == c.model) return (model: m, group: g);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(IosTheme.radiusCard),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(isDark),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Flexible(child: _body(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _header(bool isDark) {
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
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1C1C1E),
              ),
            ),
          ),
          if (_catalog != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '重新加载',
              onPressed: _busy ? null : _load,
            ),
        ],
      ),
    );
  }

  Widget _body(bool isDark) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(IosTheme.spaceXXXL),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final catalog = _catalog;
    if (catalog == null) {
      return _errorBlock(isDark, _error ?? '加载失败');
    }
    if (catalog.isEmpty && catalog.failures.isEmpty) {
      return _errorBlock(isDark, '这个部署没有可路由的模型。');
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: IosTheme.spaceXL),
      children: [
        if (_error != null) _inlineError(_error!),
        ..._effortSection(),
        for (final g in catalog.groups)
          if (g.models.isNotEmpty) ..._group(g),
        if (catalog.failures.isNotEmpty) ...[
          const ModelSectionTitle('不可用'),
          for (final f in catalog.failures) CatalogFailureRow(f),
        ],
      ],
    );
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
                active: _current?.reasoningEffort == e.id ||
                    (_current?.reasoningEffort == null &&
                        model.defaultEffort == e.id),
                onTap: _busy
                    ? null
                    : () => _select(entry.group, model, effort: e.id),
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
          selected: _current?.provider == g.id && _current?.model == m.id,
          onTap: _busy || (_current?.provider == g.id && _current?.model == m.id)
              ? null
              : () => _select(g, m),
        ),
    ];
  }

  Widget _inlineError(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosTheme.spaceL,
        IosTheme.spaceS,
        IosTheme.spaceL,
        0,
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, color: IosTheme.iosRed),
      ),
    );
  }

  Widget _errorBlock(bool isDark, String message) {
    return Padding(
      padding: const EdgeInsets.all(IosTheme.spaceXXL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 32, color: IosTheme.iosGray),
          const SizedBox(height: IosTheme.spaceM),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: IosTheme.spaceL),
          TextButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }
}
