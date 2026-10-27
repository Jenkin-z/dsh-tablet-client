/// 与后端无关的断线重连退避（DSH mux 与 opencode SSE 共用同一组参数）
///
/// 借鉴 opencode-mobile 的工程实践，两条规则容易做错：
///
/// 1. **抖动**：固定间隔会让多客户端在网络抖动后同一瞬间一起重连，
///    把刚恢复的服务端再打垮一次。延迟在基准值上叠加 ±25% 随机抖动。
///
/// 2. **「稳定连接」才重置计数**：HTTP 握手成功 / WebSocket 对象建好
///    都不算稳定 —— 半开连接（服务端收了连接立刻挂）会让退避永远停在
///    最快档，变成 3 秒一次的锤子。只有真正**收到对端数据**（首帧）
///    才允许 [markStable]。调用方职责：
///    - 每次决定重试时调 [nextDelay]（内部自增 attempts）；
///    - 收到首帧业务数据时调 [markStable]；
///    - 主动断开/销毁时调 [reset]。
library;

import 'dart:math';

import '../utils/constants.dart';

class ReconnectBackoff {
  ReconnectBackoff({
    this.fastLimit = reconnectFastLimit,
    this.fastDelaySec = reconnectFastDelaySec,
    this.slowDelaySec = reconnectSlowDelaySec,
    this.maxDelaySec = reconnectMaxDelaySec,
    Random? rng,
  }) : _rng = rng;

  /// 前 N 次固定快速档；之后从慢速档起步翻倍，封顶 max
  final int fastLimit;
  final int fastDelaySec;
  final int slowDelaySec;
  final int maxDelaySec;
  final Random? _rng;

  int _attempts = 0;
  int get attempts => _attempts;

  /// 取下一次重试延迟（attempts 自增；含 ±25% 抖动）
  Duration nextDelay() {
    _attempts++;
    var secs = fastDelaySec;
    if (_attempts > fastLimit) {
      secs = slowDelaySec;
      for (var i = fastLimit + 1; i < _attempts; i++) {
        if (secs >= maxDelaySec) break;
        secs *= 2;
      }
    }
    if (secs > maxDelaySec) secs = maxDelaySec;
    return Duration(seconds: _jittered(secs));
  }

  /// 连接真正活了（收到首帧业务数据）才调用
  void markStable() => _attempts = 0;

  /// 主动断开 / 销毁：彻底归零
  void reset() => _attempts = 0;

  int _jittered(int secs) {
    final rng = _rng ?? Random();
    final jittered = secs * (0.75 + rng.nextDouble() * 0.5);
    return max(1, jittered.round());
  }
}
