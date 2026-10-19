import 'dsh_api.dart';
import '../model_catalog.dart';

/// DSH 模型目录 + 切换（ModelCatalogService 的 DSH 实现）
///
/// 端点（依据 packages/api/session-controller/src/index.ts）：
/// - `session/modelCatalog` 零业务参数 → `{}`
/// - `session/selectModel` 形参 `request` → `{request:{sessionId,provider,model,reasoningEffort?}}`
///
/// 复用 [DshApi.rpc]，信封与错误解包只有一份实现。
class ModelService implements ModelCatalogService {
  final DshApi _api;
  ModelService(this._api);

  /// 拉取可路由的模型目录
  @override
  Future<ModelCatalog> fetchCatalog() async {
    // modelCatalog() 零业务参数 → args 必须是 {}
    final value = await _api.rpc('session/modelCatalog', {});

    final groups = <ProviderGroup>[];
    final rawGroups = value['groups'];
    if (rawGroups is List) {
      for (final g in rawGroups) {
        if (g is! Map) continue;
        final models = <CatalogModel>[];
        final rawModels = g['models'];
        if (rawModels is List) {
          for (final m in rawModels) {
            if (m is Map<String, dynamic>) {
              models.add(CatalogModel.fromJson(m));
            }
          }
        }
        groups.add(ProviderGroup(
          id: g['id'] as String? ?? '',
          name: g['name'] as String? ?? (g['id'] as String? ?? '未知'),
          models: models,
        ));
      }
    }

    final failures = <CatalogFailure>[];
    final rawFailures = value['failures'];
    if (rawFailures is List) {
      for (final f in rawFailures) {
        if (f is! Map) continue;
        failures.add(CatalogFailure(
          id: f['id'] as String? ?? '',
          name: f['name'] as String? ?? (f['id'] as String? ?? '未知'),
          message: f['message'] as String? ?? '目录加载失败',
        ));
      }
    }

    return ModelCatalog(groups: groups, failures: failures);
  }

  /// 切换会话模型
  @override
  Future<ModelSelection> select(
    String sessionId,
    ModelSelection selection,
  ) async {
    final value = await _api.rpc('session/selectModel', {
      'request': {
        'sessionId': sessionId,
        ...selection.toJson(),
      },
    });
    final selected = value['selected'];
    if (selected is Map<String, dynamic>) {
      return ModelSelection.fromJson(selected);
    }
    return selection;
  }
}
