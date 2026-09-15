/// 变更跟踪：本会话的文件变更（来自 mux view 槽 + 历史回填）
library;

import '../utils/constants.dart';

/// 单个文件的变更记录；result 帧会覆盖同 turn 同 path 的 call 记录
class FileChange {
  final String path;
  String title;
  String? oldText;
  String newText;
  bool done;
  final int? turn;

  FileChange({
    required this.path,
    required this.title,
    required this.oldText,
    required this.newText,
    required this.done,
    required this.turn,
  });
}

class ChangesTracker {
  final List<FileChange> _items = [];

  List<FileChange> get items => List.unmodifiable(_items);
  int get pendingCount => _items.where((e) => !e.done).length;

  void clear() => _items.clear();

  static String _cap(String s) =>
      s.length > changesMaxCharsPerFile
          ? s.substring(0, changesMaxCharsPerFile)
          : s;

  void applyView({
    required List<Map<String, String?>> diffs,
    required String title,
    required bool done,
    int? turn,
  }) {
    for (final d in diffs) {
      final path = d['path'] ?? '';
      if (path.isEmpty) continue;
      final idx =
          _items.indexWhere((e) => e.path == path && e.turn == turn);
      if (idx >= 0) {
        final e = _items[idx];
        e.title = title;
        e.oldText = d['oldText'];
        e.newText = _cap(d['newText'] ?? '');
        e.done = e.done || done;
      } else {
        if (_items.length >= changesMaxFiles) _items.removeAt(0);
        _items.add(FileChange(
          path: path,
          title: title,
          oldText: d['oldText'],
          newText: _cap(d['newText'] ?? ''),
          done: done,
          turn: turn,
        ));
      }
    }
  }
}