import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/settings_service.dart';
import '../services/sound_service.dart';
import '../theme/ios_theme.dart';
import 'custom_sound_tile.dart';
import 'sound_settings_row.dart';

/// 提示音开关区（只出「行」，卡片与标题由页面负责）
///
/// 提示音总开关 + 需确认/完成提示音 + 试听。
class SoundTogglesSection extends StatelessWidget {
  final SettingsService settings;

  const SoundTogglesSection({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
                onPressed: () => SoundActions.preview(settings, 'approval'),
              ),
              SoundPreviewButton(
                label: '提问',
                onPressed: () => SoundActions.preview(settings, 'question'),
              ),
              SoundPreviewButton(
                label: '完成',
                onPressed: () => SoundActions.preview(settings, 'done'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 自定义铃声区（只出「行」，卡片与标题由页面负责）
class CustomSoundsSection extends StatelessWidget {
  final SettingsService settings;

  const CustomSoundsSection({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tile(context, 'approval', '确认音', '审批 / 问题请求到达'),
        const SoundSettingsDivider(),
        _tile(context, 'question', '提问音', 'Agent 提问到达'),
        const SoundSettingsDivider(),
        _tile(context, 'done', '完成音', 'Agent 一轮回答结束'),
      ],
    );
  }

  Widget _tile(
      BuildContext context, String name, String label, String desc) {
    return CustomSoundTile(
      settings: settings,
      name: name,
      label: label,
      desc: desc,
      onPick: () => SoundActions.pick(context, settings, name),
      onReset: () => SoundActions.reset(settings, name),
    );
  }
}

/// 铃声的试听/选取/重置动作
class SoundActions {
  const SoundActions._();

  static Future<void> preview(SettingsService settings, String name) async {
    await SoundService.play(name, customPath: settings.customSoundPath(name));
  }

  static Future<void> reset(SettingsService settings, String name) async {
    await settings.setCustomSound(name, null);
  }

  static Future<void> pick(
      BuildContext context, SettingsService settings, String name) async {
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
}
