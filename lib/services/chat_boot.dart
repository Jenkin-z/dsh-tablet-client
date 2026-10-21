part of 'chat_controller.dart';

// 初始化 / 会话操作 / 会话列表（ChatController 的 part 文件）
//
// 方法用 `mixin ChatBoot on ChatController` 挂载：mixin 与宿主类在同一
// library（part 机制），mixin 方法可访问宿主的私有字段。

mixin ChatBoot on _ChatControllerCore {
  // ── 初始化 / 重连 ───────────────────────────────

  Future<void> boot() async {
    // 状态中枢是全局共享的：换 PC 会重建 ChatController，
    // 必须先清掉上一台的残留，否则控制台会读到过期状态。
    dispatcher.reset();
    state.reset();

    state.setConnecting(true);
    state.setConnectionError(null);

    final srv = settings.active;
    if (srv == null) {
      state.setConnecting(false);
      state.setConnected(false);
      state.setConnectionError('还没有 PC，去设置里添加。');
      return;
    }
    if (!srv.isPaired) {
      state.setConnecting(false);
      state.setConnected(false);
      state.setConnectionError(switch (srv.kind) {
        AgentKind.dsh => '需要配对：请先在 PC 上启动 dsh web，然后用启动令牌完成配对。',
        AgentKind.opencode => '需要授权：请在设置里重新添加 opencode（粘贴授权链接或填密码）。',
      });
      return;
    }
    // 无会话不算死局：backend 必须先建出来，否则侧栏「新建会话」会静默
    // 无效（曾经授权成功却永远连不上就是这个坑）。建好后刷新列表，
    // 有会话就自动打开最近一条；真没有再提示（此时侧栏新建也可用了）。
    var sessionId = settings.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      await _backend?.dispose();
      _backend = _createBackend(srv);
      await _refreshSessions();
      final candidates = state.sessions.toList();
      final latest = candidates.isEmpty
          ? null
          : candidates.reduce((a, b) =>
              ((a['updatedAt'] as int? ?? 0) >= (b['updatedAt'] as int? ?? 0))
                  ? a
                  : b);
      sessionId = latest?['sessionId'] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        state.setConnecting(false);
        state.setConnected(false);
        state.setConnectionError('这台后端还没有会话：打开侧栏「新建会话」开始第一段对话。');
        return;
      }
      await settings.setSessionId(sessionId);
      state.setSessionId(sessionId);
      state.setSessionTitle(_titleFor(sessionId));
      await _markCurrentSeen(srv.id, sessionId);
      await _backend!.open(sessionId);
      return;
    }

    state.setSessionId(sessionId);
    state.setSessionTitle(_titleFor(sessionId));

    await _markCurrentSeen(srv.id, sessionId);

    final needsNewBackend =
        _backend == null || _backend is! DshBackend && _backend is! OpenCodeBackend;
    if (needsNewBackend) {
      await _backend?.dispose();
      _backend = _createBackend(srv);
    }

    // 列表与「连接+历史」互不依赖，并行跑，切机器进对话页少等一段串行往返
    await Future.wait([_refreshSessions(), _backend!.open(sessionId)]);
  }

  AgentBackend _createBackend(AgentServer srv) {
    final ctx = BackendContext(
      settings: settings,
      manager: manager,
      state: state,
      dispatcher: dispatcher,
      server: srv,
      onRefreshSessions: _refreshSessions,
    );
    return switch (srv.kind) {
      AgentKind.dsh => DshBackend(ctx),
      AgentKind.opencode => OpenCodeBackend(ctx),
    };
  }

  /// 打开一个会话 = 读过它。
  ///
  /// 这是未读功能的**唯一出口**。此前 `settings.markSeen()` 只在
  /// settings_service 里定义、**从未被任何界面调用**，于是未读只能靠
  /// 「全部已读」清空；而那个按钮又只清 3 小时窗口内的，超窗的永远清不掉
  /// —— 这就是用户看到的「一直有未读、数字涨到 103」。
  ///
  /// 写未读水位属于「旁路 bookkeeping」：它失败绝不能连带把
  /// boot / switchSession 打断（那会让用户连对话页都进不去）。
  /// 所以这里吞掉异常，只留一条调试日志。
  Future<void> _markCurrentSeen(String serverId, String? sessionId) async {
    if (sessionId == null || sessionId.isEmpty) return;
    try {
      await settings.markSeen(settings.seenKey(serverId, sessionId));
    } catch (e) {
      debugPrint('markSeen 失败（不影响进入对话）: $e');
    }
  }

  Future<void> _refreshSessions() async {
    final backend = _backend;
    if (backend == null) return;
    state.setLoadingSessions(true);
    try {
      final items = await backend.listSessions();
      // 与 SessionMonitor 用同一个判定：子 Agent 会话和多余的空会话
      // 都不进任何列表（Web 端 sessionVisible() 的等价规则）
      state.setSessions(items
          .where((s) => isUserFacingSession(s,
              currentSessionId: settings.sessionId))
          .toList());
      state.setSessionTitle(_titleFor(settings.sessionId));
      // 拉到了才算数据侧健康 —— 状态点据此变绿
      state.setSessionsHealth(ok: true);
    } catch (e) {
      // 不再静默：列表失败就是降级，状态点会变橙并可点开看原因
      state.setSessionsHealth(ok: false, error: '会话列表读取失败：$e');
    } finally {
      state.setLoadingSessions(false);
    }
  }

  String _titleFor(String? sessionId) {
    final srv = settings.active;
    final fallback = srv == null ? 'DSH Agent' : _defaultTitle(srv);
    if (sessionId == null) return fallback;
    for (final s in state.sessions) {
      if (s['sessionId'] == sessionId) {
        return sessionTitleOf(s);
      }
    }
    return fallback;
  }

  String _defaultTitle(AgentServer srv) => switch (srv.kind) {
        AgentKind.dsh => 'DSH Agent',
        AgentKind.opencode => 'opencode Agent',
      };

  // ── 会话操作 ────────────────────────────────────

  Future<void> switchSession(String sessionId) async {
    if (sessionId == _backend?.activeSessionId && state.connected) return;
    await settings.setSessionId(sessionId);
    state.setSessionId(sessionId);
    state.setSessionTitle(_titleFor(sessionId));
    // 打开即已读：切换会话也要清掉它的未读标记
    await _markCurrentSeen(settings.activeServerId ?? '', sessionId);
    dispatcher.reset();
    await _backend?.open(sessionId);
  }

  Future<void> createNewSession({String? cwd}) async {
    final backend = _backend;
    // 不再要求 state.connected：两种后端的 API 客户端都是构造即就绪的
    // 纯 REST 能力，「授权成功但还没会话」时必须能从这里起步；
    // 失败（连不上 / 后端拒绝）由下面统一显示。
    if (backend == null) {
      state.setConnectionError('后端未就绪：请先在设置里添加并选择一台 PC。');
      return;
    }
    try {
      final id = await backend.createSession(cwd: cwd);
      await settings.setSessionId(id);
      await _refreshSessions();
      await switchSession(id);
    } catch (e) {
      state.setConnectionError('新建会话失败：$e');
    }
  }
}
