# AGENTS.md — DSH Tablet Client 代码规范

## 项目概览

Flutter 原生 Android 应用，将旧 Android 平板变为 DeepSeek Harness (DSH) 的监控台。
直连 DSH HTTP API + WebSocket mux，零插件依赖。

## 文件与结构规范

### 单文件上限

| 类型 | 上限 | 超限处理 |
|------|------|----------|
| Screen 文件 | **400 行** | 拆分：业务逻辑 → service/controller，子组件 → widgets/ |
| Widget 文件 | **200 行** | 拆分子组件到独立文件 |
| Service 文件 | **250 行** | 按职责拆分（如 API 封装 vs 业务逻辑） |
| 通用/工具 | **100 行** | 保持精简，复杂度高时拆模块 |

### 单类/单方法上限

| 类型 | 上限 | 超限处理 |
|------|------|----------|
| State 类方法数 | **15 个** | 提取到独立 controller 或 mixin |
| 单个方法行数 | **60 行** | 提取子方法或子组件 |
| build 方法 | **80 行** | 提取子组件 `_buildXxx()` 放 widgets/ |
| 回调注册块 | **30 行** | 提取为独立方法或用 Map 批量注册 |

### 文件组织

```
lib/
├── main.dart              # 入口 + 路由（≤150 行）
├── models/                # 数据模型（纯 Dart 类，无 UI 依赖）
├── screens/               # 页面级组件（每个文件一个 StatefulWidget/StatelessWidget）
├── services/              # 业务逻辑 + API 封装（无 Flutter UI 依赖）
├── utils/                 # 纯函数工具（格式化、算法等）
└── widgets/               # 可复用 UI 组件（每个文件一个组件）
```

- **一个文件一个公开类**（私有辅助类可在同一文件，但不超过 3 个）
- 文件名使用 `snake_case`，与类名对应
- `screens/` 只放页面，动画/卡片等子组件放 `widgets/`

## 代码风格

### 基础

- 遵循 `dart format` 默认规则
- 使用 `flutter analyze` 零警告
- 字符串使用单引号 `'`
- 末尾逗号保留（利于格式化）

### 命名

| 类型 | 规则 | 示例 |
|------|------|------|
| 类 | UpperCamelCase | `ChatScreen`, `DshApi` |
| 私有类/方法 | `_` 前缀 + lowerCamelCase | `_ChatScreenState`, `_onDelta` |
| 变量/参数 | lowerCamelCase | `sessionId`, `isStreaming` |
| 常量 | lowerCamelCase（非 SCREAMING） | `const _ungroupedKey = '_ungrouped'` |
| 文件 | snake_case | `chat_screen.dart`, `session_format.dart` |

### Widget 构建

- `build()` 方法内不写业务逻辑，只做布局编排
- 子组件提取到 `widgets/` 或作为 `_buildXxx()` 私有方法
- 动画控制器在 `initState` 创建，`dispose` 销毁
- `Consumer` / `Provider.of` 最小化作用域，避免整树重建

### 服务层

- Service 类无 Flutter UI 依赖（不 import `package:flutter`）
- API 封装只做 HTTP/RPC，不做 UI 状态管理
- 状态管理通过 `ChangeNotifier` + `Provider` 传递
- 异步操作必须处理 `mounted` 检查（避免 setState on unmounted）

### 错误处理

- 所有网络请求必须 try-catch
- catch 后记录日志或用户提示，不吞异常
- 后台操作（轮询、mux）失败不崩溃，静默重试

## 提交规范

```
<type>(<scope>): <description>

type: feat | fix | refactor | docs | chore | perf | style
scope: chat | console | settings | service | widget | build
description: 简明中文，≤50 字
```

示例：
- `feat(console): 控制台 tab + 会话监控轮询`
- `fix(chat): 修复审批卡 PC 端确认后平板不消失`
- `refactor(chat): 提取会话抽屉为独立组件`
- `perf(chat): 流式增量 120ms 合并防卡顿`

## 质量门禁

每次变更前必须通过：

```bash
flutter analyze          # 零警告
flutter build apk --release  # 构建成功
```

## 当前技术债务（v1.2.3）

| 文件 | 状态 |
|------|------|
| `chat_screen.dart` | 已抽出会话抽屉 / 输入栏 / 工具条；业务回调仍偏多 |
| `console_screen.dart` | 已抽出卡片与动画 |
| `mux_stream.dart` | 解析已抽出 `mux_history.dart` |
| `settings_screen.dart` | 仍超 400 行，下次拆区块 |

已修：任务中断后「正在调用工具」卡住（`tool/result`、本地取消、session.list running 跃迁三路清条）。
