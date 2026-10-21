part of 'session_state.dart';

// 工具视图 + 会话列表（SessionState 的 part 文件）
//
// 方法用 `mixin X on _SessionStateCore` 挂载：mixin 进入宿主类的
// 方法分派（外部调用方才能解析到），而 part 机制保证 mixin 与宿主同一
// library，可访问宿主私有字段。

mixin SessionStateTools on _SessionStateCore {
  // ── 工具 ────────────────────────────────────────

  String? _activeTool;
  final ChangesTracker _changes = ChangesTracker();

  String? get activeTool => _activeTool;
  ChangesTracker get changes => _changes;

  void setActiveTool(String? value) {
    if (_activeTool == value) return;
    _activeTool = value;
    notifyListeners();
  }

  void applyToolView({
    required List<Map<String, String?>> diffs,
    required String title,
    required bool done,
    int? turn,
  }) {
    _changes.applyView(diffs: diffs, title: title, done: done, turn: turn);
    notifyListeners();
  }

  void clearChanges() {
    if (_changes.items.isEmpty) return;
    _changes.clear();
    notifyListeners();
  }

  // ── 会话列表 ────────────────────────────────────

  List<Map<String, dynamic>> _sessions = [];
  bool _loadingSessions = false;
  Set<String> _archivedIds = {};

  List<Map<String, dynamic>> get sessions => List.unmodifiable(_sessions);
  bool get loadingSessions => _loadingSessions;
  Set<String> get archivedIds => Set.unmodifiable(_archivedIds);

  void setSessions(List<Map<String, dynamic>> value) {
    _sessions = value;
    notifyListeners();
  }

  void setLoadingSessions(bool value) {
    if (_loadingSessions == value) return;
    _loadingSessions = value;
    notifyListeners();
  }

  void setArchivedIds(Set<String> value) {
    _archivedIds = value;
    notifyListeners();
  }

  /// 过滤归档会话后的可见列表
  List<Map<String, dynamic>> get visibleSessions {
    if (_archivedIds.isEmpty) return _sessions;
    return _sessions
        .where((s) => !_archivedIds.contains(s['sessionId']))
        .toList();
  }

  void updateSessionStatus(String sessionId, bool running) {
    for (var i = 0; i < _sessions.length; i++) {
      if (_sessions[i]['sessionId'] == sessionId) {
        if (_sessions[i]['running'] != running) {
          _sessions[i]['running'] = running;
          notifyListeners();
        }
        break;
      }
    }
  }
}
