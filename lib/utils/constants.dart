/// 全局常量：超时、阈值、上限
library;

// ── 网络 ──────────────────────────────────────────
const Duration httpTimeout = Duration(seconds: 30);
const Duration cancelTimeout = Duration(seconds: 5);
const Duration eventResultTimeout = Duration(seconds: 15);
const Duration pollInterval = Duration(seconds: 8);
const Duration updateCheckTimeout = Duration(seconds: 8);

// ── 重连 ──────────────────────────────────────────
const int reconnectFastLimit = 5;
const int reconnectFastDelaySec = 3;
const int reconnectSlowDelaySec = 30;

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
