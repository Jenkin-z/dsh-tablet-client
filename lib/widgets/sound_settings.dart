import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/settings_service.dart';
import '../services/sound_service.dart';
import '../theme/ios_theme.dart';

/// 声音设置区块 —— iOS 风格
///
/// 提示音开关 + 试听 + 自定义铃声。
class SoundSettingsSection extends StatelessWidget {
  final SettingsService settings;

  const SoundSettingsSection({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IosSectionHeader(title: '提示音'),
        IosCard(
          child: Column(
            children: [
              SwitchListTile(
                secondary: Icon(
                  Icons.volume_up_outlined,
                  color: IosTheme.iosBlue,
                  size: 22,
                ),
                title: const Text('提示音'),
                subtitle: const Text(
                  '需确认与完成时播放',
                  style: TextStyle(fontSize: 13),
                ),
                value: settings.soundEnabled,
                onChanged: (v) => settings.setSoundEnabled(v),
                activeColor: IosTheme.iosGreen,
              ),
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 56),
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              SwitchListTile(
                secondary: Icon(
                  Icons.notification_important_outlined,
                  color: IosTheme.iosOrange,
                  size: 22,
                ),
                title: const Text('需确认提示音'),
                subtitle: const Text(
                  '审批 / 问题请求到达时',
                  style: TextStyle(fontSize: 13),
                ),
                value: settings.approvalSound,
                onChanged: settings.soundEnabled
                    ? (v) => settings.setApprovalSound(v)
                    : null,
                activeColor: IosTheme.iosGreen,
              ),
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 56),
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              SwitchListTile(
                secondary: Icon(
                  Icons.task_alt_outlined,
                  color: IosTheme.iosGreen,
                  size: 22,
                ),
                title: const Text('完成提示音'),
                subtitle: const Text(
                  'Agent 一轮回答结束时',
                  style: TextStyle(fontSize: 13),
                ),
                value: settings.completionSound,
                onChanged: settings.soundEnabled
                    ? (v) => settings.setCompletionSound(v)
                    : null,
                activeColor: IosTheme.iosGreen,
              ),
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 56),
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              ListTile(
                leading: Icon(
                  Icons.play_circle_outline,
                  color: IosTheme.iosPurple,
                  size: 22,
                ),
                title: const Text('试听'),
                subtitle: const Text(
                  '逐个播放，确认平板有声',
                  style: TextStyle(fontSize: 13),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _soundButton(context, '确认', 'approval'),
                    _soundButton(context, '提问', 'question'),
                    _soundButton(context, '完成', 'done'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: IosTheme.spaceL),
        const IosSectionHeader(title: '自定义铃声'),
        IosCard(
          child: Column(
            children: [
              _customSoundTile(context, 'approval', '确认音',
                  '审批 / 问题请求到达'),
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 56),
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              _customSoundTile(
                  context, 'question', '提问音', 'Agent 提问到达'),
              Container(
                height: 0.5,
                margin: const EdgeInsets.only(left: 56),
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              _customSoundTile(
                  context, 'done', '完成音', 'Agent 一轮回答结束'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _soundButton(BuildContext context, String label, String soundName) {
    return TextButton(
      onPressed: () => _previewSound(soundName),
      style: TextButton.styleFrom(
        foregroundColor: IosTheme.iosBlue,
        padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceS),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _customSoundTile(
      BuildContext context, String name, String label, String desc) {
    final custom = settings.customSoundPath(name);
    final fileName =
        custom == null ? null : custom.split('/').last.split('\\').last;
    return ListTile(
      leading: Icon(
        Icons.music_note_outlined,
        color: IosTheme.iosPink,
        size: 22,
      ),
      title: Text(label),
      subtitle: Text(
        custom == null
            ? '$desc · 内置默认'
            : '$desc · 自定义：$fileName',
        style: const TextStyle(fontSize: 13),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => _pickCustomSound(context, name),
            style: TextButton.styleFrom(
              foregroundColor: IosTheme.iosBlue,
              padding: const EdgeInsets.symmetric(horizontal: IosTheme.spaceS),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('选择'),
          ),
          if (custom != null)
            IconButton(
              icon: const Icon(Icons.restore, size: 18),
              color: IosTheme.iosGray,
              tooltip: '恢复内置',
              onPressed: () => _resetCustomSound(name),
            ),
        ],
      ),
    );
  }

  Future<void> _previewSound(String name) async {
    await SoundService.play(name, customPath: settings.customSoundPath(name));
  }

  Future<void> _pickCustomSound(
      BuildContext context, String name) async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.audio);
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
        await dest.writeAsBytes(await picked.readAsBytes());
      }
      await settings.setCustomSound(name, dest.path);
      await SoundService.play(name, customPath: dest.path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择铃声失败: $e')),
        );
      }
    }
  }

  Future<void> _resetCustomSound(String name) async {
    await settings.setCustomSound(name, null);
  }
}
