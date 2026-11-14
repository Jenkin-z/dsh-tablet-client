/// 轮询心跳（DESIGN.md §2 签名动作：心跳刻度）
///
/// 每格 = 一轮 8 秒轮询的结果；绿=成功 / 橙=数据异常 / 红=missed。
/// 纯 Dart 模型，服务层与 UI 共用。
enum PollBeatStatus { ok, warn, missed }

class PollBeat {
  /// 刻度行容量（8 格 = 8 轮 × 8s）
  static const int capacity = 8;

  final PollBeatStatus status;
  final DateTime at;

  const PollBeat(this.status, this.at);
}
