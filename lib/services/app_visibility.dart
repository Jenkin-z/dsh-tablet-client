/// 前后台可见性标记：由 UI 层（MainShell）通过 WidgetsBindingObserver 维护，
/// 服务层只读。用于区分「正在看屏幕」与「切到后台」，决定当前会话完成时
/// 是否也要弹通知。
class AppVisibility {
  static bool foreground = true;
}