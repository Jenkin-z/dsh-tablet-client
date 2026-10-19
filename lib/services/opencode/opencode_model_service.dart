import '../model_catalog.dart';
import 'opencode_api.dart';

/// opencode 模型目录（ModelCatalogService 实现）
///
/// `GET /api/model` 的 data[] 每条含 `providerID/id/name/variants[]`；
/// - 按 providerID 分组（与 DSH 的 groups 同形，model_sheet 无感）；
/// - `variants` 即推理档位：variant.id 进 Model.Ref.variant，
///   settings.reasoningEffort 作展示名（实测 low/medium/high/xhigh/max）；
/// - 不设 defaultEffort：用户没选档位时不传 variant，用服务端默认。
class OpenCodeModelService implements ModelCatalogService {
  final OpenCodeApi _api;

  const OpenCodeModelService(this._api);

  @override
  Future<ModelCatalog> fetchCatalog() async {
    final items = await _api.modelCatalog();
    final byProvider = <String, List<CatalogModel>>{};
    final order = <String>[];

    for (final m in items) {
      final providerID = m['providerID'] as String? ?? '';
      final id = m['id'] as String? ?? '';
      if (id.isEmpty) continue;
      final efforts = <ReasoningEffort>[];
      final variants = m['variants'];
      if (variants is List) {
        for (final v in variants) {
          if (v is! Map) continue;
          final vid = v['id'] as String?;
          if (vid == null || vid.isEmpty) continue;
          final settings = v['settings'];
          final effort =
              settings is Map ? settings['reasoningEffort'] as String? : null;
          efforts.add(ReasoningEffort(id: vid, name: effort ?? vid));
        }
      }
      if (!byProvider.containsKey(providerID)) {
        byProvider[providerID] = <CatalogModel>[];
        order.add(providerID);
      }
      byProvider[providerID]!.add(
        CatalogModel(
          id: id,
          name: m['name'] as String? ?? id,
          description: m['family'] as String?,
          efforts: efforts,
        ),
      );
    }

    final groups = order
        .map((id) => ProviderGroup(
              id: id,
              name: id,
              models: byProvider[id] ?? const [],
            ))
        .toList();
    return ModelCatalog(groups: groups, failures: const []);
  }

  @override
  Future<ModelSelection> select(
    String sessionId,
    ModelSelection selection,
  ) async {
    await _api.selectModel(
      sessionId,
      id: selection.model,
      providerID: selection.provider,
      variant: selection.reasoningEffort,
    );
    return selection;
  }
}
