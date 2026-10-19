# opencode 后端接入方案（通用 AgentBackend 兼容层）

- 日期：2026-10-19
- 状态：方案已评审，待实施
- 关联实测产物：`docs/opencode-openapi-v2.json`（本机 v2.0.32 全量 OpenAPI）、`docs/sse-capture*.txt`（真实事件流）、`tools/capture_opencode_sse.ps1`（抓流工具）

## 1. 背景与目标

app 目前只接 DSH（HTTP API + WebSocket mux）。本机安装了 opencode（v2.0.32），要求：

1. **并存**：opencode 作为与 DSH 同级的后端接入，像「多接了一台 PC」，设置里可添加、可切换；
2. **通用化**：DSH 和 opencode（以及将来的第三、四个 agent 客户端）都走同一套 `AgentBackend` 兼容层，页面逻辑不改，只按需改类型名/import；
3. **功能对齐**：核心聊天闭环（会话列表、发消息、流式回复、权限审批、中断）+ 模型切换 + 通知/声音，均与 DSH 现状保持一致；
4. **协议事实以真机实测为准**，不盲信文档（v2 与 v1 文档路径、接口均已实测差异修正）。

## 2. 已验证的 opencode 契约（全部真机实测）

### 2.1 服务与鉴权

| 项 | 实测结论 |
|---|---|
| 启动 | `opencode serve [--port 4096 --hostname 127.0.0.1]`；`opencode service start/status` 管理后台服务 |
| 监听 | 默认仅绑 `127.0.0.1`；局域网直连需 `--hostname 0.0.0.0` |
| API 前缀 | v2 全部在 `/api/*`（v1 文档的 `/global/*`、`/doc` 已废弃，返回 SPA 页面） |
| 鉴权 | HTTP Basic，用户名固定 `opencode`；密码 = 服务密码（`OPENCODE_SERVER_PASSWORD`）或配对令牌 |
| 远程访问 | `opencode pair [--remote]` 打印一次性授权链接 `https://<隧道域名>/auth/connect/<码>`（码 300s 有效）；app GET 该链接换 `{token}`，用 `opencode:<token>` 调全部 API（实测 200）。隧道为服务端主动出站连接，不依赖本地端口暴露 |
| 配对等价流 | `POST /api/pair` → `{code, expires_in:300}` → `GET /auth/connect/{code}` → `{token}` |
| OpenAPI | `GET /openapi.json`（带鉴权），已存 `docs/opencode-openapi-v2.json` |

### 2.2 REST 接口（核心闭环）

| 功能 | 端点 | 说明 |
|---|---|---|
| 会话列表 | `GET /api/session?limit=N&parentID=null` | `data[]` 为 `Session.Info`；`parentID=null` 只取根会话（子会话 = DSH subagent 的等价物） |
| 活跃会话 | `GET /api/session/active` | `data: {"ses_xxx": {...}}` 活跃集合，用于补 `running` 标记 |
| 创建会话 | `POST /api/session` | 体 `{}` 或含 `permissions` 规则；返回 `{data:{id,...}}` |
| 发消息 | `POST /api/session/{id}/prompt` | 体 `{text}`；返回收件箱消息（含 `delivery`） |
| 中断 | `POST /api/session/{id}/interrupt` | 对应 DSH cancel |
| 历史消息 | `GET /api/session/{id}/message` | `data[]`：`user{type,text}` / `assistant{type,content:[{type:text|reasoning|tool}]}` / `idle{outcome}` |
| 模型目录 | `GET /api/model` | `data[]` 每条含 `providerID/id/name/family/variants[]`；`variants` 即推理档位（`settings.reasoningEffort`） |
| 默认模型 | `GET /api/model/default` | |
| 切换模型 | `POST /api/session/{id}/model` | 体 `{model:{id, providerID, variant?}}`；语义 = 「对后续轮次生效」，与 DSH 投影 `next` 一致 |
| 待审批列表 | `GET /api/permission/request` | `data[]` 为 `Permission.Request{id, sessionID, action, resources[], source, message?}` |
| 审批应答 | `POST /api/session/{sid}/permission/{pid}/reply` | 体 `{decision: once\|always\|reject}`；实测 204 后会话恢复执行 |
| 会话信息 | `GET /api/session/{id}` | `Session.Info` 含 `model/time.updated/title/parentID/outcome` |
| 重命名 | `PATCH /api/session/{id}` | 体 `{title}` |

### 2.3 SSE 事件流

`GET /api/event`（Basic 鉴权，`Accept: text/event-stream`），帧格式 `data: {id, created?, type, location?, data, durable?}`，心跳行为 `: heartbeat`。

已实测事件词表（实抓 + 二进制字符串提取交叉验证）：

```
server.connected
session.created / project.updated / model.updated / provider.updated
session.inbox.enqueued / session.inbox.delivered
session.text.started / session.text.delta / session.text.ended
session.reasoning.started / session.reasoning.delta / session.reasoning.ended
session.step.started / session.step.streamed / session.step.ended / session.step.failed
session.tool.input.started / session.tool.input.ended / session.tool.called
session.tool.success / session.tool.failed / session.tool.progress
session.execution.started / session.execution.succeeded /
session.execution.failed / session.execution.interrupted
session.usage.updated
permission.asked / permission.replied / permission.rejected
session.compaction.* / session.shell.* / shell.created / shell.exited
```

### 2.4 权限模型

- 规则集 `Permission.Ruleset = [{action, resource, effect: allow|deny|ask}]`，可挂在会话上（`POST /api/session` 体 `permissions`）或全局配置；
- 工具 id 即 `action`（实测 `shell`、`write`、`browser`；注意不是 `bash`）；
- `permission.asked` 事件载荷与 `GET /api/permission/request` 元素同构；
- 端到端已验证：`asked` → 轮询列表 → `reply(once)` → 204 → 会话恢复 → 命令真实执行。

## 3. 架构设计

```
页面（chat_screen / session_drawer / approval_card / model_sheet —— 逻辑不改）
  └─ ChatController（门面：公开 API 不变，按 AgentServer.kind 选后端，对后端细节无感）
       │   open / listSessions / createSession / sendPrompt / cancel /
       │   replyApproval / listModels / switchModel / dispose
       ▼
     AgentBackend（抽象接口，后端同级）
       ├── DshBackend       = 现有 DshApi + MuxStream 装配（原样迁入，行为不变）
       └── OpenCodeBackend  = 新增 opencode REST + SSE 模块

两者产出的事件 → 同一个 EventDispatcher → 同一个 SessionState → 页面
```

- **DSH 不再是正房**：它只是 `AgentBackend` 的一份实现，连线、状态迁移、审批应答全部收在各自 backend 内部；
- 接第三个客户端 = `services/<name>/` 一个文件夹 + 一个 `AgentBackend` 实现 + `kind` 多一个枚举值。

### 3.1 AgentBackend 接口（草案）

```dart
abstract class AgentBackend {
  bool get connected;
  ModelCatalogService? get models;              // 模型目录/切换，未实现为 null

  Future<void> open(String? sessionId);         // 连接事件流并进入该会话
  Future<List<Map<String, dynamic>>> listSessions();   // 归一化会话 map
  Future<String> createSession({String? cwd});
  Future<void> sendPrompt({required String sessionId, required String text, required String requestId});
  Future<void> cancel(String sessionId);
  Future<bool> replyApproval({required String sessionId, required String approvalId, required bool allow});
  Future<void> dispose();
}
```

`requestId` 为本地乐观气泡的 rpcId，回执后由 `EventDispatcher` 对账（两后端同一套对账逻辑）。

### 3.2 事件映射（opencode SSE → 统一入口）

| opencode 事件 | EventDispatcher / 动作 |
|---|---|
| `session.text.delta` | `onTextDelta` 打字机 |
| `session.text.ended` | `onAssistantFinal(text, false)` 定稿 |
| `session.execution.started` | `onTurnStart` + `onSessionStatus(sid, true)` |
| `session.execution.succeeded/interrupted/failed` | `onTurnEnd` + `onSessionStatus(sid, false)` |
| `session.tool.input.started` / `session.tool.called` | `onToolCall(name, args)` |
| `session.tool.success` / `session.tool.failed` | `onToolResult()` |
| `permission.asked` | 拉 `GET /api/permission/request` 对账 → `onApproval` |
| `permission.replied/rejected` + **每次重连** | 全量对账 → `onApprovalResolved`（断线漏事件兜底） |
| `session.created` / 一轮结束 | 触发会话列表刷新 |
| 历史装载 `GET /api/session/{id}/message` | 新增 `onHistoryLoaded(List<ChatMessage>)` 统一入口 |

`onHistoryLoaded` 与 DSH 的 `onSnapshot` 共用同一段装载逻辑（抽公共方法，不复制）。

### 3.3 数据归一化（页面不感知来源）

会话 map（侧栏与控制台共用）：

```dart
{
  'sessionId': info.id,
  'projections': {'values': {'title': info.title}},
  'updatedAt': info.time.updated,     // ms
  'running': activeSet.contains(id),  // /api/session/active + SSE 实时更新
}
```

- 子会话（`parentID` 非空）在**数据入口**过滤，等价 DSH `origin == 'subagent'` 规则；
- 模型目录：`GET /api/model` 客户端按 `providerID` 分组，`variants → ReasoningEffort`；
- 历史：`user{text}` / `assistant{text 拼接（reasoning/tool 块跳过）}` → `ChatMessage`。

### 3.4 通知 / 声音对齐（与 DSH 走同一段代码）

| 通知 | DSH 现状 | 对齐方式 |
|---|---|---|
| 审批到达 | `SoundService.approval()` + 系统通知（现写在 ChatController 的 DSH 接线里） | 两行**上移为 `EventDispatcher` 审批到达钩子**（构造时挂一次），后端无关，两个后端行为天然一致 |
| 提问到达 | `SoundService.question()` + 通知 | 同样上移（opencode 表单 v1 不在范围，钩子后端无关，接表单时白拿） |
| 会话刚跑完 | `SessionMonitor` 边沿检测（`running` true→false）→ 通知 + done 音 + 未读标记 | **不改 SessionMonitor**：轮询侧用 `/api/session/active` 补 `running`；实时侧 SSE `session.execution.*` → `ServerManager.applySessionStatus`（与 DSH mux `onSessionStatus` 同一条线） |
| 通知权限 / 前台保活 | main.dart 统一初始化 | 共享，无需处理 |

## 4. 通用化改名清单

| 旧 | 新 | 说明 |
|---|---|---|
| `models/dsh_server.dart` → `DshServer` | `models/agent_server.dart` → `AgentServer` | 加 `kind`（`dsh`/`opencode`/…）、统一凭据字段；基址以 `url` 为权威（opencode 隧道为 https 完整 URL），`host/port` 仅作展示与旧数据迁移（旧 JSON 无 `url` 时由 host/port 派生 `http://host:port`） |
| `DshSessionState` | `SessionState` | 状态中枢与后端无关 |
| `MuxEventDispatcher` | `EventDispatcher` | 统一事件入口；mux 只是 DSH 的传输方式 |
| `DshMessage` | `ChatMessage` | 消息模型与后端无关 |
| `services/dsh/`（新文件夹） | `DshApi`、`DshAuth`、`mux_stream`、`mux_session_handler`、`mux_history`、`ModelService`(DSH 实现) 归入 | 与 `services/opencode/` 同级 |
| `ChatController` | 保留 | 门面，本来就不带 Dsh 字样 |

改名会触碰页面文件的 import 与类型名（逻辑不动）。持久化键 `serversJson` 及字段名保持不变，旧数据无缝迁移。

## 5. 文件改动清单

### 新增

| 文件 | 职责 | 预估行数 |
|---|---|---|
| `services/agent_backend.dart` | 统一后端接口 | ~70 |
| `services/dsh_backend.dart` | DSH 实现（从 ChatController 抽出 mux 装配、状态迁移、审批应答） | ~230 |
| `services/opencode/opencode_api.dart` | REST + Basic 鉴权，输出归一化 map | ~160 |
| `services/opencode/opencode_stream.dart` | SSE 订阅 + 指数退避重连 + 重连全量对账 | ~130 |
| `services/opencode/opencode_mapper.dart` | 纯函数：事件→回调、消息→ChatMessage、会话→统一 map（可单测） | ~130 |
| `services/opencode_backend.dart` | opencode 实现（与 DshBackend 同职责） | ~160 |
| `services/model_catalog.dart` | 模型目录抽象（fetchCatalog/select + 数据类） | ~80 |
| `widgets/add_opencode_dialog.dart` | 添加 opencode：粘贴授权链接 / 手动 URL+密码 | ~130 |

### 修改

| 文件 | 改动 |
|---|---|
| `models/dsh_server.dart` → `agent_server.dart` | 改名 + `kind`/凭据/`url` 字段 + JSON 兼容 |
| `services/chat_controller.dart` | 瘦身成门面（377 → ~230 行），按 kind 选后端；通知钩子上移 |
| `services/mux_event_dispatcher.dart` → `event_dispatcher.dart` | 改名；新增 `onHistoryLoaded`（与 onSnapshot 共用装载）；审批/提问到达钩子 |
| `services/dsh_session_state.dart` → `session_state.dart` | 改名 |
| `models/message.dart` | `DshMessage` → `ChatMessage` |
| `services/settings_service` / `server_manager` / `session_monitor` | kind 感知：opencode 条目走 `OpenCodeApi` 轮询（含 `/api/session/active` 补 running），否则控制台会误报离线 |
| `services/model_service.dart` | 拆：数据类与抽象进 `model_catalog.dart`，DSH 实现移入 `services/dsh/` |
| `widgets/model_sheet.dart` | 依赖抽象 `ModelCatalogService`（数据类不变） |
| `widgets/server_list_card.dart` | 增「添加 opencode」行；opencode 条目不显示 DSH 授权钥匙按钮 |
| 全部引用改名文件的 screens/widgets | 仅改 import 与类型名 |

## 6. 连接与配对

设置页「添加 opencode」对话框，两种接入方式：

1. **粘贴授权链接**（对齐 DSH 启动令牌体验）：`opencode pair --remote` 生成 → 贴入 → app 自动 `GET /auth/connect/{code}` 换 token → 存为凭据；
2. **手动 URL + 密码**：局域网直连 `http://<IP>:4096` + 服务密码（PC 端需 `opencode serve --hostname 0.0.0.0`）。

**PC 端进程常驻**：已决策选 C（不配自启）——用户平时开着 opencode 即可，隧道方式不依赖本地监听；后续需要无人值守再仿 `serve-updates.ps1` 模式补自启守护。

## 7. v1 范围外（已知降级行为）

| 项 | v1 表现 | 后续 |
|---|---|---|
| 提问/表单（opencode forms） | 不显示提问卡片（到达钩子已后端无关预留） | 表单数据结构确认后接入，通知自动生效 |
| diff 变更面板 | opencode 下变更抽屉为空 | 可用 `session.tool.*` 的输入输出构造 diff 视图 |
| 会话列表 running 的控制台边沿 | 依赖 `/api/session/active` 轮询 + SSE，双通道已备 | — |
| 「不可用 provider」分组 | opencode 目录无部分失败概念，该区恒不显示（UI 本来就只在有失败时渲染，无感） | — |

## 8. 验证方案

1. `flutter analyze` 零告警；
2. DSH 回归：抽 `DshBackend` 后原行为不变（连接、消息、审批、通知、模型切换）；
3. opencode 实测：本机 `opencode serve`（已跑通）→ 模拟器/平板连 `192.168.x.x:4096` 或隧道链接，走查——列表、发消息、流式、审批（用 `permissions: [{action:'shell',resource:'*',effect:'ask'}]` 会话强制触发）、中断、完成通知+声音、模型切换；
4. 双后端切换：设置里 DSH ↔ opencode 来回切，状态中枢无残留（`reset()` 路径）。

## 9. 决策记录

| 决策 | 结论 | 提出/确认 |
|---|---|---|
| 接入形态 | 并存，统一兼容层，页面逻辑不改、通用化改造照做 | 老大 |
| DSH 是否走兼容层 | 走，DSH 与 opencode 同级实现 | 老大 |
| 通知 | opencode 与 DSH 完全对齐，走同一段代码 | 老大 |
| 通用化改名 | 按第 4 节清单执行 | 老大 |
| 添加入口 | 设置页新增「添加 opencode」 | 老大 |
| 模型切换 | 纳入，功能与 DSH 逐项一致（已对照确认） | 老大 |
| PC 端常驻 | 选 C 不配自启；opencode 自带远程（OpenTunnel 授权链接） | 老大 |
| 远程鉴权 | 粘贴 `auth/connect` 链接换 token，Basic `opencode:<token>` | 实测确定 |
