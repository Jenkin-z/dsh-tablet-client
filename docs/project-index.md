# dsh-tablet-client - Project Index

Flutter 原生 Android 应用，将旧 Android 平板变为 DSH 的监控台。

## Module Map

| Module | Responsibility | Data tables | Source directory | APIs/其他 |
|--------|---------------|-------------|-----------------|----------|
| **ChatController** | 聊天业务逻辑：连接、消息流、审批、会话切换 | - | `lib/services/chat_controller.dart` | - |
| **DshApi** | DSH HTTP RPC 封装 | - | `lib/services/dsh_api.dart` | `POST /api/*` |
| **MuxStream** | WebSocket 事件流：流式输出、审批、变更 | - | `lib/services/mux_stream.dart`, `mux_history.dart` | `WS /api/remote.mux` |
| **SettingsService** | 持久化设置：服务器、主题、声音、未读水位 | SharedPreferences | `lib/services/settings_service.dart`, `seen_store.dart` | - |
| **ServerManager** | 多台 PC 聚合轮询 | - | `lib/services/server_manager.dart`, `session_monitor.dart` | - |
| **SessionRouter** | 跨 tab 会话切换 | - | `lib/services/session_router.dart` | - |
| **SoundService** | 提示音播放 | - | `lib/services/sound_service.dart` | - |
| **UpdateService** | 应用内更新：检查、下载、安装 | - | `lib/services/update_service.dart` | `GET :8099/version.json` |
| **ChangesTracker** | 文件变更跟踪 | - | `lib/services/changes_tracker.dart`, `diff_util.dart` | - |

## Repository Map

| Area | Directory/file | Purpose | Notes |
|------|---------------|---------|-------|
| Entry | `lib/main.dart` | App 初始化 + Provider 注册 | ≤100 行 |
| 主框架 | `lib/screens/main_shell.dart` | 底部导航 + IndexedStack | - |
| 页面 | `lib/screens/` | chat / console / settings 三页 | 每文件一个页面 |
| 业务逻辑 | `lib/services/` | API、流、状态管理 | 无 Flutter UI 依赖 |
| 数据模型 | `lib/models/` | DshMessage、DshServer | 纯 Dart 类 |
| UI 组件 | `lib/widgets/` | 可复用组件 | 每文件一个组件 |
| 工具 | `lib/utils/` | 格式化、常量、diff | 纯函数 |
| 资源 | `assets/sounds/` | 内置提示音 wav | - |
| 构建工具 | `tool/` | release_apk.ps1, publish_launch_token.ps1 | PowerShell 7 |
| 文档 | `docs/` | 设计、标准、报告 | 本文档所在 |

## 前端架构

```
lib/
├── main.dart                    # 入口 + App（≤100 行）
├── models/
│   ├── message.dart             # 消息模型
│   └── dsh_server.dart          # 服务器模型
├── screens/
│   ├── main_shell.dart          # 主框架
│   ├── chat_screen.dart         # 对话页 UI
│   ├── console_screen.dart      # 控制台
│   ├── settings_screen.dart     # 设置页
│   └── pair_screen.dart         # 配对页
├── services/
│   ├── chat_controller.dart     # 聊天控制器（核心）
│   ├── dsh_api.dart             # HTTP RPC
│   ├── mux_stream.dart          # WebSocket 流
│   ├── mux_history.dart         # 历史解析
│   ├── settings_service.dart    # 持久化
│   ├── seen_store.dart          # 已读水位
│   ├── server_manager.dart      # 多 PC 管理
│   ├── session_monitor.dart     # 单 PC 轮询
│   ├── session_router.dart      # 跨 tab 路由
│   ├── sound_service.dart       # 提示音
│   ├── update_service.dart      # 更新
│   ├── changes_tracker.dart     # 变更跟踪
│   └── diff_util.dart           # diff 算法
├── utils/
│   ├── constants.dart           # 全局常量
│   └── session_format.dart      # 格式化
└── widgets/
    ├── approval_card.dart       # 审批卡
    ├── chat_input_bar.dart      # 输入栏
    ├── changes_drawer.dart      # 变更抽屉
    ├── console_animations.dart  # 控制台动画
    ├── console_devices.dart     # 设备卡片
    ├── console_widgets.dart     # 控制台组件
    ├── message_bubble.dart      # 消息气泡
    ├── question_sheet.dart      # 问题表单
    ├── server_list_card.dart    # 服务器列表
    ├── session_drawer.dart      # 会话抽屉
    ├── session_tile.dart        # 会话条目
    ├── sound_settings.dart      # 声音设置
    ├── tool_status_bar.dart     # 工具状态条
    └── update_dialog.dart       # 更新弹窗
```

## Maintenance Rules

- 模块边界、目录、API 变更时更新此文件
- 每个模块一行，详细设计链接到 `docs/design/`
- 不要从文件名推断职责，验证实际代码
