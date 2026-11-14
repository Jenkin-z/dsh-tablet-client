import 'package:flutter/material.dart';

import '../services/agent_mode.dart';
import '../services/model_catalog.dart';
import '../theme/ios_theme.dart';
import 'model_sheet_modes.dart';
import 'model_sheet_view.dart';

/// 模型切换面板（底部弹出）
///
/// 打开时拉模型目录，点选后调后端切换（DSH / opencode 同一条路）。
/// 选中结果通过 `Navigator.pop` 返回给调用方，由调用方决定是否回写状态
/// —— 面板本身不碰全局状态，权威值仍以 Host 推来的投影为准。
/// 顶部「模式」分区走 [AgentModeService]（后端不支持时整个分区不渲染）。
/// 主体视图拆到 model_sheet_view.dart（纯布局），
/// 展示组件在 model_sheet_parts.dart，让本文件守住 200 行上限。
class ModelSheet extends StatefulWidget {
  final ModelCatalogService service;

  /// 模式目录/切换；null = 后端无模式概念（DSH），不渲染模式分区
  final AgentModeService? modeService;
  final String sessionId;
  final ModelSelection? current;

  const ModelSheet({
    super.key,
    required this.service,
    required this.sessionId,
    this.modeService,
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

  List<AgentMode> _modes = const [];
  String _currentMode = '';
  String? _modeError;
  bool _modeBusy = false;

  @override
  void initState() {
    super.initState();
    _current = widget.current;
    _load();
    _loadModes();
  }

  /// 模式区独立加载：失败只降级模式分区，不挡模型目录
  Future<void> _loadModes() async {
    final service = widget.modeService;
    if (service == null) return;
    try {
      final modes = await service.fetchModes();
      final current = await service.currentMode(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _modes = modes;
        _currentMode = current;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _modeError = '模式读取失败：$e');
    }
  }

  Future<void> _selectMode(AgentMode mode) async {
    final service = widget.modeService;
    if (service == null || _modeBusy) return;
    setState(() {
      _modeBusy = true;
      _modeError = null;
    });
    try {
      await service.select(widget.sessionId, mode.id);
      if (!mounted) return;
      setState(() {
        _currentMode = mode.id;
        _modeBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modeBusy = false;
        _modeError = '切换失败：$e';
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final p = IosPalette.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(IosTheme.radiusCard),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_modes.isNotEmpty)
              ModeSection(
                modes: _modes,
                currentMode: _currentMode,
                error: _modeError,
                busy: _modeBusy,
                onSelect: _selectMode,
              ),
            Flexible(
              child: ModelSheetView(
                catalog: _catalog,
                current: _current,
                error: _error,
                loading: _loading,
                busy: _busy,
                onLoad: _load,
                onSelect: (group, model, {effort}) => _select(group, model,
                    effort: effort),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
