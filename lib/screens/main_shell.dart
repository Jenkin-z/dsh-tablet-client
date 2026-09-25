import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/server_manager.dart';
import '../services/session_router.dart';
import '../services/settings_service.dart';
import '../widgets/update_dialog.dart';
import 'chat_screen.dart';
import 'console_screen.dart';
import 'settings_screen.dart';

/// 主框架：底部导航 + IndexedStack 三页
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _updateChecked = false;
  ServerManager? _manager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_updateChecked || !mounted) return;
      _updateChecked = true;
      final s = Provider.of<SettingsService>(context, listen: false);
      if (s.updateAutoCheck) {
        UpdateFlow.checkAndPrompt(
          context,
          s.servers.map((e) => e.host).followedBy([s.serverHost]),
          auto: true,
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_manager == null) {
      _manager = Provider.of<ServerManager>(context, listen: false);
      _manager!.start();
    }
  }

  @override
  void dispose() {
    _manager?.stop();
    super.dispose();
  }

  /// 打开会话：切机器 + 指定会话 + 跳到对话页。
  ///
  /// 两条路径由**机器是否变了**决定，与「那台机器有没有在跑会话」无关
  /// —— 后者是曾经的错误依据，导致同一个手势有时跳转有时不跳。
  ///
  /// · 跨机器：改 activeServerId 会让 ChatScreen 的 key 变化 → 重建 → boot()
  ///   自动读取目标会话，**不需要也不允许**再发一次路由请求。
  /// · 同机器：widget 不重建，走 SessionRouter 就地切会话。
  Future<void> _openSession(String serverId, String sessionId) async {
    final settings = Provider.of<SettingsService>(context, listen: false);
    final machineChanged = settings.activeServerId != serverId;

    if (machineChanged) {
      await settings.setActiveServer(serverId);
    }
    await settings.setSessionId(sessionId);
    if (!mounted) return;

    setState(() => _currentIndex = 1);

    if (!machineChanged) {
      Provider.of<SessionRouter>(context, listen: false)
          .request(serverId, sessionId);
    }
  }

  /// 只切当前机器，留在控制台。
  ///
  /// 这是「点设备卡」的唯一语义。不跳转、不碰会话：
  /// 目标机器会用它自己上次的会话（sessionId 是每台机器各存各的）。
  Future<void> _switchServer(String serverId) async {
    final settings = Provider.of<SettingsService>(context, listen: false);
    if (settings.activeServerId == serverId) return;
    await settings.setActiveServer(serverId);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ConsoleScreen(
            onOpenSession: _openSession,
            onSwitchServer: _switchServer,
          ),
          ChatScreen(key: ValueKey(settings.activeServerId)),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerTheme.color ??
                  const Color(0xFFC6C6C8),
              width: 0.5,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          animationDuration: const Duration(milliseconds: 300),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined, size: 22),
              selectedIcon: Icon(Icons.dashboard, size: 22),
              label: '控制台',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline, size: 22),
              selectedIcon: Icon(Icons.chat_bubble, size: 22),
              label: '对话',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, size: 22),
              selectedIcon: Icon(Icons.settings, size: 22),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}
