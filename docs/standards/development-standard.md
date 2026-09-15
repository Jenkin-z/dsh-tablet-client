# Development Standard

Flutter Android 应用开发规范。与 `AGENTS.md` 互补，此处为详细实现纪律。

## Before Changing Code

1. 确认范围、验收标准、风险、兼容性、回滚方案
2. 阅读 `AGENTS.md`、相关设计文档、源码
3. 区分必要变更、安全清理、无关发现（不扩展范围）
4. 有状态/跨模块行为：识别 owner、数据源、不变量、生命周期

## Change Discipline

- 最小一致变更修复根因，不用特例掩盖错误模型
- 保留用户已有变更和仓库约定，不做范围外的格式化/重命名
- 删除代码前搜索运行时、测试、文档、外部消费者
- 实现、契约、测试、文档在同一任务中同步

## Flutter 代码规范

### 文件组织

```
lib/
├── main.dart              # 入口 ≤100 行
├── models/                # 纯 Dart 数据类
├── screens/               # 页面级 StatefulWidget/StatelessWidget
├── services/              # 业务逻辑 + API（无 Flutter UI 依赖）
├── utils/                 # 纯函数工具
└── widgets/               # 可复用 UI 组件
```

### 文件行数上限

| 类型 | 上限 | 超限处理 |
|------|------|----------|
| Screen | 400 行 | 拆分：逻辑 → controller/service，子组件 → widgets/ |
| Widget | 200 行 | 拆分子组件到独立文件 |
| Service | 250 行 | 按职责拆分 |
| 工具 | 100 行 | 保持精简 |

### 类/方法上限

| 类型 | 上限 | 超限处理 |
|------|------|----------|
| State 方法数 | 15 个 | 提取 controller 或 mixin |
| 单方法行数 | 60 行 | 提取子方法 |
| build 方法 | 80 行 | 提取 `_buildXxx()` |
| 回调注册块 | 30 行 | 提取独立方法 |

### 命名

- 类：`UpperCamelCase`
- 私有：`_` 前缀 + `lowerCamelCase`
- 变量/参数：`lowerCamelCase`
- 常量：`lowerCamelCase`（非 SCREAMING）
- 文件：`snake_case`

### Widget 构建

- `build()` 只做布局编排，不写业务逻辑
- 动画控制器 `initState` 创建，`dispose` 销毁
- `Consumer`/`Provider.of` 最小化作用域

### 服务层

- Service 无 Flutter UI 依赖（不 import `package:flutter`）
- API 封装只做 HTTP/RPC
- 状态管理：`ChangeNotifier` + `Provider`
- 异步操作必须 `mounted` 检查

### 错误处理

- 网络请求必须 try-catch
- catch 后记录或提示，不吞异常
- 后台操作失败不崩溃，静默重试

## Quality Gates

```bash
flutter analyze              # 零警告
flutter build apk --release  # 构建成功
```

## Input Safety

- 用户输入、网络数据、持久化外部数据视为不可信
- 不将不可信文本插入 shell 命令、查询、路径、模板

## Compatibility

- 接口/数据变更时定义现有调用者行为
- 破坏性变更提供迁移、验证、回滚指导
- 交接前检查最终 diff，运行质量门禁

## Commit Convention

```
<type>(<scope>): <description>

type: feat | fix | refactor | docs | chore | perf | style
scope: chat | console | settings | service | widget | build
```
