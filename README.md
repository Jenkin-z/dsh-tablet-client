# DSH Tablet Client

> 把废旧 Android 平板变成 [DeepSeek Harness](https://github.com/deepseek-ai/dsh) 的专属监控台——常驻前台、永不熄屏、开机自启，随时瞥一眼 Agent 在干什么。

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter" />
  <img src="https://img.shields.io/badge/Android-8.0+-3DDC84?logo=android" />
  <img src="https://img.shields.io/badge/DSH-0.1.x-blue" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
</p>

---

## 为什么做这个

PC 上跑着 DSH Agent，你不在电脑前时想知道：

- Agent 现在在跑还是空闲？
- 后台完成了几个任务？
- 有没有审批/问题等着我处理？
- 刚才改了哪些文件？

**DSH Tablet Client** 就是干这个的——一台闲置 Android 平板，插电立在桌上，随时扫一眼。

## 功能一览

### 控制台

| 状态 | 说明 |
|------|------|
| 🟢 进行中 | Agent 正在运行的会话，实时显示 |
| 🟠 待查看 | 后台完成但你还没看的会话，带 NEW 标 |
| 📋 最近活跃 | 最近对话过的会话，快速切换 |

- 后台完成自动标未读 + 提示音
- 点卡片直达对应会话

### 对话

- 实时流式输出（Markdown 渲染）
- 左侧会话抽屉：按工作区分组，支持展开/收起
- 右侧变更栏：文件变更 diff 实时查看
- 审批/问题：直接在平板上允许/拒绝/回答
- 历史回填：最近 50 条消息

### 设置

- 服务器地址配置 + 连接测试
- 屏幕常亮 / 前台保活（开机自启）
- 提示音：内置 3 种 + 自定义铃声（mp3/wav/ogg）
- 主题：跟随系统 / 浅色 / 深色
- 应用内更新：启动自动检查 + 手动检查

## 兼容性

### Android 设备

| 条件 | 要求 |
|------|------|
| Android 版本 | **8.0+**（API 26+） |
| 架构 | ARMv7（armeabi-v7a）/ ARM64 / x86_64 |
| 内存 | ≥ 1GB（推荐 2GB+） |
| 存储 | ≥ 100MB 可用空间 |
| 网络 | 与 DSH 主机同一局域网 |

已验证设备：

- RK3288 平板（Android 9，PHH Treble GSI，armeabi-v7a）

**理论上**支持任何满足上述条件的 Android 设备，包括：
- 旧手机改造成监控屏
- 低配 Android TV 盒子 + 显示器
- 任何 2018 年后的 Android 平板

### DSH 主机端

| 条件 | 要求 |
|------|------|
| DSH 版本 | 0.1.x（使用内置 HTTP API + WebSocket mux） |
| 操作系统 | Windows / macOS / Linux 均可 |
| 网络 | 绑定 `0.0.0.0`（允许局域网访问） |

**不需要安装任何 DSH 插件**——平板端只用 DSH 原生接口。

## 前置条件

### 1. 启动 DSH 并开放局域网访问

确保 DSH 已绑定 `0.0.0.0`（默认行为），允许局域网设备连接。

验证方式（在 PC 上）：
```bash
# 检查 DSH 是否在运行
curl http://localhost:3080/api/host.describe
```

如果返回 JSON 且有 `result.ok: true`，说明 DSH 正常运行。

**注意**：DSH 默认绑定 `0.0.0.0` 时会自动将局域网 IP 加入信任列表，无需手动配置配对。浏览器配对流程（`/pair-accept`）是 Web GUI 专属的，平板 App 不需要。

### 2. 确认 PC 的局域网 IP

```bash
# Windows
ipconfig

# macOS / Linux
ifconfig
```

找到 WLAN 或以太网适配器的 IPv4 地址，例如 `192.168.10.171`。

### 3. 确保同一局域网

平板和 PC 必须在同一个 WiFi 网络下。

验证：平板浏览器打开 `http://<PC_IP>:3080`，应该能看到 DSH Web 界面或返回 JSON。

## 安装

### 方式一：下载 APK（推荐）

1. 平板浏览器打开 `http://<PC_IP>:8099/dsh-agent.apk`
2. 下载完成后点击安装
3. 首次安装需允许"安装未知应用"

### PC 端：下载服务与自动授权

平板能下载 APK 和自动授权，依赖 PC 上两个 PowerShell 脚本：

| 脚本 | 作用 | 何时运行 |
|------|------|------|
| `tool/release_apk.ps1` | 构建 release APK → 拷贝到 `flutter-apk/` → 生成 `version.json` | 每次发新版前 |
| `tool/publish_launch_token.ps1` | 从 `dsh-autostart.log` 提取最新启动令牌 → 生成 `launch-token.json` | DSH 每次重启后 |

> 两台 PC 分工：脚本可以都在 DSH 主机上跑；也可以 `release_apk.ps1` 在 DSH 主机，`publish_launch_token.ps1` 在跑 8099 下载服务的机器上——只要日志文件可达、且能写入对方机器上的 `flutter-apk/` 共享目录即可。

运行方式（必须用 **pwsh 7**，否则中文会乱码）：

```powershell
# 发布启动令牌（自动授权用）
pwsh -File .\tool\publish_launch_token.ps1

# 构建并发布 APK（更新用）
pwsh -File .\tool\release_apk.ps1 -Changelog "更新说明"
```

`release_apk.ps1` 会同时写 `version.json`，平板启动 App 会自动检查 `http://<PC_IP>:8099/version.json` 并提示更新。

`publish_launch_token.ps1` 参数：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-LogPath` | `D:\software\deepseek-harness\dsh-autostart.log` | DSH 启动日志路径，换机器必改 |
| `-LanHost` | `192.168.10.171` | 写入 `launch-token.json` 的 URL 主机名 |
| `-DshPort` | `3080` | DSH HTTP 端口 |

示例（日志在别的路径 / 主机时）：

```powershell
# 日志在远程共享目录
pwsh -File .\tool\publish_launch_token.ps1 -LogPath "\\server\share\dsh-autostart.log"

# 下载服务在别的机器
pwsh -File .\tool\publish_launch_token.ps1 -LanHost "192.168.10.100"
```

> 注意：`publish_launch_token.ps1` 会把 `launch-token.json` 写到仓库下的 `build/app/outputs/flutter-apk/`，因此**至少要先跑一次 `release_apk.ps1`**（或手动创建该目录），否则脚本会因目录不存在失败。
>
> 安全提示：启动令牌只在 DSH 进程生命周期内有效；授权换到的是 30 天 browser cookie。不用时删除 `flutter-apk/launch-token.json` 即可停止发布令牌。

### 方式二：自行构建

```bash
# 前置条件：Flutter 3.47+、Android SDK
git clone https://github.com/Jenkin-z/dsh-tablet-client.git
cd dsh-tablet-client

# 获取依赖
flutter pub get

# 构建 release APK
flutter build apk --release

# APK 位于 build/app/outputs/flutter-apk/app-release.apk
```

安装到平板：
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

## 使用

1. 打开 **DSH Agent** App
2. 进入 **设置** → 输入 PC 的局域网 IP（如 `192.168.10.171`），端口默认 `3080`
3. 点 **测试连接** → 显示"连接正常 ✓"
4. 切换到 **控制台** 或 **对话** tab 开始使用

### 推荐设置

- **屏幕常亮**：开启（默认）
- **前台保活**：开启（通知栏常驻，防系统杀掉）
- **开机自启**：开启（保活服务自带）
- **提示音**：开启（审批/完成时提醒）
- **省电白名单**：手动将 App 加入（防止电池优化杀后台）

## 项目结构

```
lib/
├── main.dart                    # 入口：初始化、三 tab 导航
├── models/
│   └── message.dart             # 消息数据模型
├── screens/
│   ├── chat_screen.dart         # 对话页：侧栏 + 流式 + Markdown
│   ├── console_screen.dart      # 控制台：进行中/待查看/最近活跃
│   └── settings_screen.dart     # 设置页：服务器/保活/提示音/主题/更新
├── services/
│   ├── dsh_api.dart             # DSH HTTP RPC 封装
│   ├── mux_stream.dart          # WebSocket 事件流（流式/审批/变更）
│   ├── session_monitor.dart     # 会话监控轮询（完成检测+未读）
│   ├── session_router.dart      # 跨 tab 会话切换
│   ├── settings_service.dart    # 持久化设置
│   ├── sound_service.dart       # 提示音
│   ├── update_service.dart      # 应用内更新
│   ├── changes_tracker.dart     # 文件变更跟踪
│   └── diff_util.dart           # 行级 diff 算法
├── utils/
│   └── session_format.dart      # 会话标题/时间格式化
└── widgets/
    ├── approval_card.dart       # 审批确认卡
    ├── changes_drawer.dart      # 右侧变更抽屉
    ├── message_bubble.dart      # 消息气泡（Markdown）
    ├── question_sheet.dart      # 问题回答表单
    └── update_dialog.dart       # 更新弹窗 + 下载进度
```

## 协议

平板与 DSH 的通信完全基于 DSH 内置接口，无需插件：

| 接口 | 用途 |
|------|------|
| `POST /api/host.describe` | 连接检测 |
| `POST /api/session.list` | 会话列表 |
| `POST /api/session.create` | 新建会话 |
| `POST /api/session.prompt` | 发送消息 |
| `POST /api/session.history` | 加载历史 |
| `POST /api/session.cancel` | 停止生成 |
| `POST /api/workspace.list` | 工作区分组 |
| `POST /api/respond` | 审批/问题回答 |
| `WS /api/events.mux` | 实时事件流 |

## 自定义提示音

设置页 → 自定义铃声 → 选择文件，支持 mp3/wav/ogg。音频拷贝到应用私有目录，删除源文件不影响。

## 开发

```bash
# 调试模式
flutter run

# 分析代码
flutter analyze

# 一键发布（需要 pwsh 7）
pwsh -File tool/release_apk.ps1 -Changelog "更新说明"
```

### 一键发布脚本

`tool/release_apk.ps1` 自动完成：分析 → 构建 → 拷贝 APK → 生成 `version.json`。

发布后平板启动 App 会自动检查更新（`http://<PC_IP>:8099/version.json`）。

## 依赖

| 包 | 用途 |
|---|------|
| `http` | HTTP RPC 通信 |
| `web_socket_channel` | WebSocket 事件流 |
| `provider` | 状态管理 |
| `flutter_markdown` | Markdown 渲染 |
| `audioplayers` | 提示音 + 自定义铃声 |
| `wakelock_plus` | 屏幕常亮 |
| `flutter_foreground_task` | 前台保活 + 开机自启 |
| `shared_preferences` | 设置持久化 |
| `package_info_plus` | 版本信息（更新用） |
| `file_picker` | 自定义铃声选文件 |
| `path_provider` | 应用私有目录 |

## 已知限制

- 历史消息只加载最近 50 条（长会话翻不到顶）
- 变更抽屉打开期间新变更需重进才刷新
- 审批/问题卡片在 `turn/end` 时自动清理（PC 端已处理的不会残留）
- 不支持语音输入/输出（DSH 端 dsh-voice 插件的音频需要 PC 端播放）

## License

MIT
