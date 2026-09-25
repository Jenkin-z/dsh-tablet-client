/// 连接健康度的四态
///
/// 颜色必须诚实：绿色只代表「连上且数据可信」。
/// 只有 socket 通、但会话列表拉不到时，是 [degraded] 而不是 healthy
/// —— 这个区分不是洁癖，历史 bug 就是靠「列表空但显示绿色」骗过了肉眼。
enum ConnectionHealth {
  /// 正在建连（橙）
  connecting,

  /// 连上且最近一次数据拉取成功（绿）
  healthy,

  /// socket 通着，但数据侧失败：列表拉不到 / 接口报错（橙）
  degraded,

  /// 未连接（红）
  offline,
}
