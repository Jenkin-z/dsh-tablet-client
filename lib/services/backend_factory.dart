import '../models/agent_server.dart';
import 'agent_backend.dart';
import 'dsh_backend.dart';
import 'opencode_backend.dart';

/// 后端工厂：按 [AgentServer.kind] 装配 [AgentBackend]（唯一的 kind switch）
///
/// 全仓库只有这里知道 DSH / opencode 是两个实现类；接第三个后端 =
/// 一个实现类 + [AgentKind] 多一个枚举值 + 本文件一行。
/// 两类使用方：
/// - ChatBoot（连接生命周期内，正常 open()）；
/// - BackendOps（免连接操作：临时装配、操作完即弃）。
AgentBackend createBackend(AgentServer srv, BackendContext ctx) =>
    switch (srv.kind) {
      AgentKind.dsh => DshBackend(ctx),
      AgentKind.opencode => OpenCodeBackend(ctx),
    };
