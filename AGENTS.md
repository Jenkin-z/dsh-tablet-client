# AGENTS.md — DSH Tablet Client

Flutter 原生 Android 应用，将旧 Android 平板变为 DSH 监控台。直连 DSH HTTP API + WebSocket mux。

## 构建

```bash
# 开发环境需要 Flutter SDK（本机路径）
$env:PATH = "D:\software\flutter_windows_3.44.8\bin;$env:PATH"

# 分析
flutter analyze

# 构建 Release APK
flutter build apk --release
# 输出：build/app/outputs/flutter-apk/app-release.apk

# 本地 HTTP 分发（Python）
cd build/app/outputs/flutter-apk
python -m http.server 8099 --bind 0.0.0.0
# 平板访问 http://<PC-IP>:8099/app-release.apk

# 更新检查机制
# 8099 同目录下需要 version.json：
# { "versionCode": 29, "versionName": "1.5.2", "size": 52500000, "changelog": "..." }
# App 启动时 GET http://<host>:8099/version.json，remoteCode > localCode 则提示更新
```

## 文件结构

```
lib/
├── main.dart              # 入口 + 主题 + Provider
├── models/                # 数据模型（纯 Dart，无 UI）
├── screens/               # 页面（一个文件一个 StatefulWidget）
├── services/              # 业务逻辑 + API（不 import package:flutter）
├── theme/                 # ios_theme.dart 设计系统
├── utils/                 # 纯函数工具
└── widgets/               # 可复用组件（一个文件一个组件）
```

## 代码规范

### 行数限制

| 类型 | 上限 | 超限处理 |
|------|------|----------|
| Screen 文件 | 400 行 | 拆到 service/controller + widgets/ |
| Widget 文件 | 200 行 | 拆子组件 |
| Service 文件 | 250 行 | 按职责拆分 |
| 单个方法 | 60 行 | 提取子方法 |
| build 方法 | 80 行 | 提取 `_buildXxx()` |

### 命名

| 类型 | 规则 | 示例 |
|------|------|------|
| 类 | UpperCamelCase | `ChatScreen` |
| 私有 | `_` 前缀 | `_onDelta` |
| 变量 | lowerCamelCase | `sessionId` |
| 常量 | lowerCamelCase | `const _key = 'x'` |
| 文件 | snake_case | `chat_screen.dart` |

### Widget

- `build()` 只做布局，不写业务逻辑
- 子组件提取到 `widgets/` 或 `_buildXxx()`
- 动画控制器 `initState` 创建，`dispose` 销毁
- `Consumer` / `Provider.of` 最小化作用域

### 服务层

- Service 不 import `package:flutter`
- API 封装只做 HTTP/RPC
- 状态通过 `ChangeNotifier` + `Provider`
- 异步操作检查 `mounted`

### 错误处理

- 网络请求必须 try-catch
- 后台操作（轮询、mux）失败静默重试

## 提交规范

```
<type>(<scope>): <中文描述，≤50字>

type: feat | fix | refactor | docs | chore | perf | style
scope: chat | console | settings | service | widget | build | theme
```

## 设计系统

主题定义在 `lib/theme/ios_theme.dart`，低饱和度极简风格：

- 主色：`#7C6FE0`（柔和紫蓝）
- 成功：`#6BBF8A` / 错误：`#E87070` / 警告：`#E8A95B`
- 背景：`#F7F8FA` / 卡片：`#FFFFFF`
- 圆角：卡片 14px / 按钮 10px / 输入 10px
- 阴影：3% 透明度，极淡

UI 组件：`IosCard`、`IosButton`、`IosSwitch`、`IosBadge`、`IosGroupedList`、`IosSectionHeader`
