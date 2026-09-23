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

  Future<void> _openSession(String serverId, String sessionId) async {
    final settings = Provider.of<SettingsService>(context, listen: false);
    if (settings.activeServerId != serverId) {
      await settings.setActiveServer(serverId);
    }
    await settings.setSessionId(sessionId);
    if (!mounted) return;
    Provider.of<SessionRouter>(context, listen: false)
        .request(serverId, sessionId);
    setState(() => _currentIndex = 1);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ConsoleScreen(onOpenSession: _openSession),
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
