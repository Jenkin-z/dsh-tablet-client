import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/dsh_api.dart';
import '../services/settings_service.dart';
import '../services/sound_service.dart';
import '../services/update_service.dart';
import '../widgets/server_list_card.dart';
import '../widgets/update_dialog.dart';

/// 设置界面：服务器地址、常亮、前台保活、会话管理
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _testing = false;
  String? _testResult;

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final s = Provider.of<SettingsService>(context, listen: false);
      final api = DshApi(baseUrl: s.serverUrl, cookie: s.active?.cookie);
      final ok = await api.testConnection();
      if (!mounted) return;
      setState(() => _testResult = ok ? '连接正常 ✓' : '连接失败 ✗');
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = '连接失败: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _previewSound(String name) async {
    final s = Provider.of<SettingsService>(context, listen: false);
    await SoundService.play(name, customPath: s.customSoundPath(name));
  }

  /// 选择自定义铃声：拷入应用私有目录后生效，并试播
  Future<void> _pickCustomSound(String name) async {
    try {
      final picked =
          await FilePicker.pickFile(type: FileType.audio);
      if (picked == null) return;
      final appDir = await getApplicationDocumentsDirectory();
      final soundsDir = Directory('${appDir.path}/sounds');
      await soundsDir.create(recursive: true);
      final origName = picked.name;
      final ext = origName.contains('.')
          ? origName.substring(origName.lastIndexOf('.'))
          : '.mp3';
      final dest = File('${soundsDir.path}/custom_$name$ext');
      final srcPath = picked.path;
      if (srcPath != null) {
        await File(srcPath).copy(dest.path);
      } else {
        // SAF 等无路径情况：读字节流写入
        await dest.writeAsBytes(await picked.readAsBytes());
      }
      if (!mounted) return;
      final s = Provider.of<SettingsService>(context, listen: false);
      await s.setCustomSound(name, dest.path);
      await SoundService.play(name, customPath: dest.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择铃声失败: $e')),
      );
    }
  }

  Future<void> _resetCustomSound(String name) async {
    final s = Provider.of<SettingsService>(context, listen: false);
    await s.setCustomSound(name, null);
  }

  Future<void> _newSession() async {    try {
      final s = Provider.of<SettingsService>(context, listen: false);
      final api = DshApi(baseUrl: s.serverUrl, cookie: s.active?.cookie);
      final id = await api.createSession();
      await s.setSessionId(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已创建新会话，返回对话页重连生效')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, s, _) => Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('PC'),
            const ServerListCard(),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '当前: ${s.serverUrl}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _testing ? null : _testConnection,
                      child: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('测试当前连接'),
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 8),
                      Text(_testResult!,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('平板常驻'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('屏幕常亮'),
                    subtitle: const Text('防止平板自动锁屏熄屏'),
                    secondary: const Icon(Icons.lightbulb_outline),
                    value: s.keepScreenOn,
                    onChanged: (v) async {
                      await s.setKeepScreenOn(v);
                      await WakelockPlus.toggle(enable: v);
                    },
                  ),
                  const Divider(height: 1),
                  const _ForegroundServiceTile(),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('断线自动重连'),
                    subtitle: const Text('网络恢复后自动连回 DSH'),
                    secondary: const Icon(Icons.autorenew),
                    value: s.autoReconnect,
                    onChanged: (v) => s.setAutoReconnect(v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('外观'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('主题'),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'system',
                          label: Text('跟随系统'),
                          icon: Icon(Icons.settings_suggest_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: 'light',
                          label: Text('浅色'),
                          icon: Icon(Icons.light_mode_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: 'dark',
                          label: Text('深色'),
                          icon: Icon(Icons.dark_mode_outlined, size: 18),
                        ),
                      ],
                      selected: {s.themeModeKey},
                      onSelectionChanged: (v) =>
                          s.setThemeMode(v.first),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('提示音'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('提示音'),
                    subtitle: const Text('需确认与完成时播放（后期可换自定义铃声）'),
                    secondary: const Icon(Icons.volume_up_outlined),
                    value: s.soundEnabled,
                    onChanged: (v) => s.setSoundEnabled(v),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('需确认提示音'),
                    subtitle: const Text('审批 / 问题请求到达时'),
                    secondary: const Icon(Icons.notification_important_outlined),
                    value: s.approvalSound,
                    onChanged:
                        s.soundEnabled ? (v) => s.setApprovalSound(v) : null,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('完成提示音'),
                    subtitle: const Text('Agent 一轮回答结束时'),
                    secondary: const Icon(Icons.task_alt_outlined),
                    value: s.completionSound,
                    onChanged: s.soundEnabled
                        ? (v) => s.setCompletionSound(v)
                        : null,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.play_circle_outline),
                    title: const Text('试听'),
                    subtitle: const Text('逐个播放，确认平板有声（走媒体音量）'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _previewSound('approval'),
                          child: const Text('确认'),
                        ),
                        TextButton(
                          onPressed: () => _previewSound('question'),
                          child: const Text('提问'),
                        ),
                        TextButton(
                          onPressed: () => _previewSound('done'),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('自定义铃声'),
            Card(
              child: Column(
                children: [
                  _customSoundTile(s, 'approval', '确认音', '审批 / 问题请求到达'),
                  const Divider(height: 1),
                  _customSoundTile(s, 'question', '提问音', 'Agent 提问到达'),
                  const Divider(height: 1),
                  _customSoundTile(s, 'done', '完成音', 'Agent 一轮回答结束'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('应用更新'),
            Card(
              child: Column(
                children: [
                  FutureBuilder<String>(
                    future: UpdateService.currentVersion(),
                    builder: (context, snap) => ListTile(
                      leading: const Icon(Icons.smartphone_outlined),
                      title: const Text('当前版本'),
                      subtitle:
                          Text(snap.data ?? '…', style: const TextStyle(fontSize: 12)),
                      trailing: OutlinedButton(
                        onPressed: () => UpdateFlow.checkAndPrompt(
                          context,
                          s.servers.map((e) => e.host).followedBy([s.serverHost]),
                        ),
                        child: const Text('检查更新'),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('启动时自动检查'),
                    subtitle: const Text('局域网小文件请求，无更新不打扰'),
                    secondary: const Icon(Icons.system_update_outlined),
                    value: s.updateAutoCheck,
                    onChanged: (v) => s.setUpdateAutoCheck(v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('会话'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.tag),
                    title: const Text('当前会话'),
                    subtitle: Text(
                      s.sessionId ?? '无',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新建会话'),
                    subtitle: const Text('另起一段对话，旧记录保留在 PC 端'),
                    onTap: _newSession,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customSoundTile(
      SettingsService s, String name, String label, String desc) {
    final custom = s.customSoundPath(name);
    final fileName =
        custom == null ? null : custom.split('/').last.split('\\').last;
    return ListTile(
      leading: const Icon(Icons.music_note_outlined),
      title: Text(label),
      subtitle: Text(custom == null ? '$desc · 内置默认' : '$desc · 自定义：$fileName'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => _pickCustomSound(name),
            child: const Text('选择文件'),
          ),
          if (custom != null)
            IconButton(
              icon: const Icon(Icons.restore, size: 20),
              tooltip: '恢复内置',
              onPressed: () => _resetCustomSound(name),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

/// 前台服务开关（保活）：开启后在通知栏常驻通知，系统不会杀进程
class _ForegroundServiceTile extends StatefulWidget {
  const _ForegroundServiceTile();

  @override
  State<_ForegroundServiceTile> createState() => _ForegroundServiceTileState();
}

class _ForegroundServiceTileState extends State<_ForegroundServiceTile> {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.isRunningService.then((v) {
      if (mounted) setState(() => _running = v);
    });
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      await FlutterForegroundTask.startService(
        notificationTitle: 'DSH Agent 运行中',
        notificationText: '与 PC 端保持连接',
        callback: _foregroundCallback,
      );
    } else {
      await FlutterForegroundTask.stopService();
    }
    if (mounted) setState(() => _running = value);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('前台保活服务'),
      subtitle: const Text('通知栏常驻，防止系统杀掉应用'),
      secondary: const Icon(Icons.shield_outlined),
      value: _running,
      onChanged: _toggle,
    );
  }
}

/// 前台服务入口（必须为顶层函数）
@pragma('vm:entry-point')
void _foregroundCallback() {
  FlutterForegroundTask.setTaskHandler(_DshTaskHandler());
}

class _DshTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 心跳：更新通知时间，证明存活
    FlutterForegroundTask.updateService(
      notificationText: '与 PC 端保持连接',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}