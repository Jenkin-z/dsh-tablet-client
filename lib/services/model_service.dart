import 'dsh_api.dart';

/// 一个可用模型
class CatalogModel {
  final String id;
  final String name;
  final String? description;

  /// 推理档位（可选）。为空表示该模型不支持调档。
  final List<ReasoningEffort> efforts;
  final String? defaultEffort;

  const CatalogModel({
    required this.id,
    required this.name,
    this.description,
    this.efforts = const [],
    this.defaultEffort,
  });

  bool get hasEfforts => efforts.isNotEmpty;

  factory CatalogModel.fromJson(Map<String, dynamic> j) {
    final reasoning = j['reasoning'];
    final efforts = <ReasoningEffort>[];
    String? defaultEffort;
    if (reasoning is Map) {
      defaultEffort = reasoning['defaultEffort'] as String?;
      final raw = reasoning['efforts'];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map && e['id'] is String) {
            efforts.add(ReasoningEffort(
              id: e['id'] as String,
              name: e['name'] as String? ?? e['id'] as String,
              description: e['description'] as String?,
            ));
          }
        }
      }
    }
    return CatalogModel(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? (j['id'] as String? ?? '未知模型'),
      description: j['description'] as String?,
      efforts: efforts,
      defaultEffort: defaultEffort,
    );
  }
}

/// 一个推理档位
class ReasoningEffort {
  final String id;
  final String name;
  final String? description;
  const ReasoningEffort({
    required this.id,
    required this.name,
    this.description,
  });
}

/// 一个 provider 及其模型
class ProviderGroup {
  final String id;
  final String name;
  final List<CatalogModel> models;
  const ProviderGroup({
    required this.id,
    required this.name,
    required this.models,
  });
}

/// 目录加载失败的 provider
///
/// Host 会逐组返回失败原因，所以某个 provider 挂掉不该让整页报错。
class CatalogFailure {
  final String id;
  final String name;
  final String message;
  const CatalogFailure({
    required this.id,
    required this.name,
    required this.message,
  });
}

/// 模型目录全貌
class ModelCatalog {
  final List<ProviderGroup> groups;
  final List<CatalogFailure> failures;

  const ModelCatalog({required this.groups, required this.failures});

  bool get isEmpty => groups.every((g) => g.models.isEmpty);
}

/// 当前选中的模型
class ModelSelection {
  final String provider;
  final String model;
  final String? reasoningEffort;

  const ModelSelection({
    required this.provider,
    required this.model,
    this.reasoningEffort,
  });

  factory ModelSelection.fromJson(Map<String, dynamic> j) => ModelSelection(
        provider: j['provider'] as String? ?? '',
        model: j['model'] as String? ?? '',
        reasoningEffort: j['reasoningEffort'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'model': model,
        if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
      };

  /// 显示串
  String get label => model.isEmpty ? provider : model;

  bool sameAs(ModelSelection? other) =>
      other != null &&
      other.provider == provider &&
      other.model == model &&
      other.reasoningEffort == reasoningEffort;

  ModelSelection copyWith({String? reasoningEffort}) => ModelSelection(
        provider: provider,
        model: model,
        reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      );
}

/// 模型目录 + 切换。
///
/// 端点（依据 packages/api/session-controller/src/index.ts）：
/// - `session/modelCatalog` 零业务参数 → `{}`
/// - `session/selectModel` 形参 `request` → `{request:{sessionId,provider,model,reasoningEffort?}}`
///
/// 复用 [DshApi.rpc]，信封与错误解包只有一份实现。
class ModelService {
  final DshApi _api;
  ModelService(this._api);

  /// 拉取可路由的模型目录
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

  /// 从控制流投影里读当前模型选择
  ///
  /// `modelSelection` 投影 = `{lastUsed, next}`；`next` 优先。
  static ModelSelection? selectionFromProjection(dynamic projectionValue) {
    if (projectionValue is! Map) return null;
    final next = projectionValue['next'];
    if (next is Map<String, dynamic>) return ModelSelection.fromJson(next);
    final lastUsed = projectionValue['lastUsed'];
    if (lastUsed is Map<String, dynamic>) {
      return ModelSelection.fromJson(lastUsed);
    }
    return null;
  }
}
