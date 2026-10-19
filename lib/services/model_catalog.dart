/// 模型目录抽象：数据类 + 后端无关的目录/切换接口
///
/// DSH 与 opencode 各自实现 [ModelCatalogService]：
/// - DSH：`session/modelCatalog` + `session/selectModel` RPC（services/dsh/model_service.dart）
/// - opencode：`GET /api/model` + `POST /api/session/{id}/model`（services/opencode/opencode_model_service.dart）
library;

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

  /// 从控制流投影里读当前模型选择
  ///
  /// `modelSelection` 投影 = `{lastUsed, next}`；`next` 优先。
  /// DSH 专属格式，但解析是纯数据变换，放这里供 EventDispatcher 共用。
  static ModelSelection? fromProjection(dynamic projectionValue) {
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

/// 模型目录 + 切换（后端无关抽象）
///
/// 页面（model_sheet）只依赖这个接口；未实现模型切换的后端返回 null，
/// 界面据此隐藏切换入口。
abstract class ModelCatalogService {
  /// 拉取可路由的模型目录
  Future<ModelCatalog> fetchCatalog();

  /// 切换会话模型；返回生效后的选择
  Future<ModelSelection> select(String sessionId, ModelSelection selection);
}
