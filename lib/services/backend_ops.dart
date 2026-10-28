import '../models/agent_server.dart';
import 'agent_backend.dart';
import 'backend_factory.dart';
import 'event_dispatcher.dart';
import 'session_state.dart';
import 'settings_service.dart';

/// 免连接后端操作（设置页等连接生命周期外的入口）
///
/// 「所有操作都走 AgentBackend」在这里同样成立：不直连任何具体 API 类，
/// 而是临时装配一个 backend——两种后端的 API 客户端都构造即就绪，
/// testConnection / createSession 是纯 REST（不碰 SSE/轮询/状态中枢），
/// 操作完即整体丢弃。页面只认本类 + 抽象，不知道 kind switch。
class BackendOps {
  final SettingsService settings;

  const BackendOps(this.settings);

  /// 当前选中后端的连接测试；无选中后端返回 false
  Future<bool> testConnection() async {
    final srv = settings.active;
    if (srv == null) return false;
    return _mount(srv, (b) => b.testConnection());
  }

  /// 当前选中后端新建会话，返回会话 id；无选中后端返回空串
  Future<String> createSession({String? cwd}) async {
    final srv = settings.active;
    if (srv == null) return '';
    return _mount(srv, (b) => b.createSession(cwd: cwd));
  }

  /// 临时装配 backend 执行一次性操作；状态中枢与 dispatcher 都是即弃件
  Future<T> _mount<T>(
    AgentServer srv,
    Future<T> Function(AgentBackend b) op,
  ) async {
    final state = SessionState();
    final dispatcher = EventDispatcher(
      state: state,
      serverIdProvider: () => srv.id,
    );
    try {
      return await op(createBackend(
        srv,
        BackendContext(
          settings: settings,
          state: state,
          dispatcher: dispatcher,
          server: srv,
          onRefreshSessions: () async {},
        ),
      ));
    } finally {
      dispatcher.dispose();
    }
  }
}
