import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/settings_service.dart';
import '../services/sound_service.dart';
import '../theme/ios_theme.dart';
import 'custom_sound_tile.dart';
import 'sound_settings_row.dart';

/// 声音设置区块 —— iOS 风格
///
/// 提示音开关 + 试听 + 自定义铃声。
/// 分隔线/试听按钮拆到 sound_settings_row.dart，自定义铃声行拆到
/// custom_sound_tile.dart，让本文件守住 200 行上限。
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
                activeThumbColor: IosTheme.iosGreen,
              ),
              const SoundSettingsDivider(),
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
                activeThumbColor: IosTheme.iosGreen,
              ),
              const SoundSettingsDivider(),
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
                activeThumbColor: IosTheme.iosGreen,
              ),
              const SoundSettingsDivider(),
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
                    SoundPreviewButton(
                      label: '确认',
                      onPressed: () => _previewSound('approval'),
                    ),
                    SoundPreviewButton(
                      label: '提问',
                      onPressed: () => _previewSound('question'),
                    ),
                    SoundPreviewButton(
                      label: '完成',
                      onPressed: () => _previewSound('done'),
                    ),
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
              const SoundSettingsDivider(),
              _customSoundTile(
                  context, 'question', '提问音', 'Agent 提问到达'),
              const SoundSettingsDivider(),
              _customSoundTile(
                  context, 'done', '完成音', 'Agent 一轮回答结束'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _customSoundTile(
      BuildContext context, String name, String label, String desc) {
    return CustomSoundTile(
      settings: settings,
      name: name,
      label: label,
      desc: desc,
      onPick: () => _pickCustomSound(context, name),
      onReset: () => _resetCustomSound(name),
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
