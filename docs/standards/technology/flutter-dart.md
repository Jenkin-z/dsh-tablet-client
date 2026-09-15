# Flutter / Dart Technology Profile

> **Status**: ✅ 适用（本项目主要技术栈）

## Runtime

- Flutter 3.47+ (stable channel)
- Dart SDK ≥3.0.0 <4.0.0
- Android minSdk 26 (Android 8.0+)
- Target: ARMv7 / ARM64 / x86_64

## Quality Gates

```bash
# 静态分析（零警告）
flutter analyze

# 构建验证
flutter build apk --release

# 格式化检查
dart format --output=none --set-exit-if-changed .
```

## Code Style

- 遵循 `dart format` 默认规则
- 字符串使用单引号 `'`
- 末尾逗号保留（利于格式化）
- 常量使用 `lowerCamelCase`（非 SCREAMING_CASE）
- 文件名 `snake_case`，类名 `UpperCamelCase`

## Architecture Patterns

### 状态管理

- `ChangeNotifier` + `Provider`（本项目选择）
- 避免整树重建：`Consumer`/`Provider.of` 最小化作用域
- `context.read<T>()` 在 `initState`/回调中（listen: false）

### Widget 职责

- `build()` 只做布局编排，不写业务逻辑
- 子组件提取到 `widgets/` 或 `_buildXxx()` 私有方法
- 动画控制器 `initState` 创建，`dispose` 销毁

### Service 层

- 无 Flutter UI 依赖（不 import `package:flutter`）
- API 封装只做 HTTP/RPC，不做 UI 状态管理
- 异步操作必须 `mounted` 检查（避免 setState on unmounted）

## Dependencies

| 包 | 用途 | 版本 |
|---|------|------|
| `http` | HTTP RPC | ^1.2.0 |
| `web_socket_channel` | WebSocket | ^2.4.0 |
| `provider` | 状态管理 | ^6.1.1 |
| `flutter_markdown` | Markdown 渲染 | ^0.7.7+1 |
| `audioplayers` | 提示音 | ^6.8.1 |
| `wakelock_plus` | 屏幕常亮 | ^1.2.5 |
| `flutter_foreground_task` | 前台保活 | ^8.9.1 |
| `shared_preferences` | 持久化 | ^2.2.2 |
| `package_info_plus` | 版本信息 | ^10.2.1 |
| `file_picker` | 文件选择 | ^12.2.0 |
| `path_provider` | 应用目录 | ^2.1.6 |

## Error Handling

- 网络请求必须 try-catch
- catch 后记录或用户提示，不吞异常
- 后台操作（轮询、mux）失败不崩溃，静默重试
- `DshAuthException` 特殊处理（授权过期 → 跳转配对）

## Performance Notes

- 流式消息：120ms 合并防卡顿（`StringBuffer` + `Timer`）
- 已读水位：500ms 防抖写入（避免高频磁盘 IO）
- 会话列表：缓存 + `notifyListeners()` 时清除
- Diff 算法：O(n*m) DP，400 万格上限保护
