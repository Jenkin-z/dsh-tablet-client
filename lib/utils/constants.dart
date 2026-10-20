/// 全局常量：超时、阈值、上限
library;

// ── 网络 ──────────────────────────────────────────
const Duration httpTimeout = Duration(seconds: 30);
const Duration cancelTimeout = Duration(seconds: 5);
const Duration eventResultTimeout = Duration(seconds: 15);
const Duration pollInterval = Duration(seconds: 8);
const Duration updateCheckTimeout = Duration(seconds: 8);

// ── 重连（借鉴 DSH 官方 RemoteStreamMuxClient）────
const int reconnectFastLimit = 5;
const int reconnectFastDelaySec = 3;
const int reconnectSlowDelaySec = 30;
/// 物理连接重连最大延迟（指数退避上限）
const int reconnectMaxDelaySec = 60;

/// SSE 建连超时：TCP 能通但对端不响应（如 stale 的 adb reverse / 半开
/// 连接）时 send 会永远挂起，超时掐断并继续重试，否则重试链会卡死——
/// 表现就是「正在重连」永远转下去。
const Duration sseConnectTimeout = Duration(seconds: 15);

// ── 流式消息 ──────────────────────────────────────
const Duration deltaFlushInterval = Duration(milliseconds: 120);
const Duration approvalPollInterval = Duration(seconds: 5);
const Duration echoDedupWindow = Duration(seconds: 60);

// ── 滚动 ──────────────────────────────────────────
const double scrollIdleThreshold = 200;
const int jumpToLatestFrames = 8;

// ── 控制台 ────────────────────────────────────────
const Duration consoleRecentWindow = Duration(hours: 3);
const int consoleRecentLimit = 8;

// ── 变更跟踪 ──────────────────────────────────────
const int changesMaxFiles = 100;
const int changesMaxCharsPerFile = 100000;

// ── Diff ──────────────────────────────────────────
const int diffMaxLines = 400;
const int diffDpCellLimit = 4000000;

// ── 更新下载 ──────────────────────────────────────
const Duration downloadConnectTimeout = Duration(seconds: 10);
const Duration downloadRequestTimeout = Duration(seconds: 20);
const Duration downloadChunkTimeout = Duration(seconds: 30);

// ── SeenStore ─────────────────────────────────────
const int seenStoreMaxEntries = 300;
const Duration seenStoreDebounce = Duration(milliseconds: 500);

// ── Mux 就绪 ──────────────────────────────────────
/// 发出 open 后等待 `$events` ready 帧的上限，超过则提示重试
const Duration connectReadyTimeout = Duration(seconds: 12);

// ── opencode ──────────────────────────────────────
/// opencode /api/session/active 轮询间隔：补 running 标记 + 断线兜底
/// （实时侧 SSE session.execution.* 已覆盖，这是双通道里的轮询侧）
const Duration opencodeActivePollInterval = Duration(seconds: 5);
