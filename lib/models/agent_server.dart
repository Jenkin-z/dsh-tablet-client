/// 后端类型：DSH 与 opencode 是同级的两份 AgentBackend 实现
enum AgentKind {
  /// DSH 原生 Host（HTTP RPC + WebSocket mux + cookie 鉴权）
  dsh,

  /// opencode（REST + SSE + Basic 鉴权）
  opencode,
}

/// 一台被监控的 Agent 后端（一台 PC / 一个 opencode 服务）
///
/// 通用化改造后 DSH 只是其中一种 [kind]：
/// - 基址以 [url] 为权威（opencode 隧道是 https 完整 URL）；
///   [host]/[port] 仅作展示与旧数据迁移（旧 JSON 无 url 时由此派生）；
/// - 凭据按 kind 分治：DSH 用 [cookie]，opencode 用 [token]
///   （配对令牌或服务密码，Basic 用户名固定 `opencode`）。
class AgentServer {
  final String id;
  final String name;
  final AgentKind kind;
  final String host;
  final int port;

  /// 权威基址；为空时按 `http://host:port` 派生（旧数据无缝迁移）
  final String? url;

  /// DSH：原生 browser-session cookie（"dsh-auth-xxx=value"），约 30 天有效
  final String? cookie;

  /// opencode：Basic 鉴权密码（配对令牌或 OPENCODE_SERVER_PASSWORD）
  final String? token;

  final String? lastSessionId;
  final String? lastError;

  /// true = 授权失效，需要重新添加/授权
  final bool unpaired;

  const AgentServer({
    required this.id,
    required this.name,
    this.kind = AgentKind.dsh,
    this.host = '',
    this.port = 3080,
    this.url,
    this.cookie,
    this.token,
    this.lastSessionId,
    this.lastError,
    this.unpaired = false,
  });

  String get httpUrl {
    final u = url;
    if (u != null && u.isNotEmpty) return u;
    return 'http://$host:$port';
  }

  String get wsUrl {
    final u = url;
    if (u != null && u.isNotEmpty) {
      return u.startsWith('https')
          ? 'wss${u.substring(5)}'
          : 'ws${u.substring(4)}';
    }
    return 'ws://$host:$port';
  }

  bool get isPaired {
    if (unpaired) return false;
    return switch (kind) {
      AgentKind.dsh => cookie != null && cookie!.isNotEmpty,
      AgentKind.opencode => token != null && token!.isNotEmpty,
    };
  }

  /// 连接配置指纹：只随「后端地址 / 凭据 / 类型」变化。
  ///
  /// UI 用它做 ChatScreen 的 key：同一台 PC 重新配对时 id 不变，
  /// 但 cookie/token 已换，必须重建后端，不能继续用旧连接。
  /// 刻意不含 name/lastSessionId —— 改名、切会话不该触发重连。
  int get connectionRevision => Object.hash(kind, httpUrl, cookie, token);

  /// 列表/控制台展示用地址（去掉 scheme，隧道域名也不换行）
  String get displayAddress {
    final u = url;
    if (u != null && u.isNotEmpty) {
      return u
          .replaceFirst('https://', '')
          .replaceFirst('http://', '')
          .replaceFirst(RegExp(r'/$'), '');
    }
    return '$host:$port';
  }

  AgentServer copyWith({
    String? name,
    String? host,
    int? port,
    String? url,
    String? cookie,
    String? token,
    String? lastSessionId,
    String? lastError,
    bool? unpaired,
    bool clearCookie = false,
    bool clearToken = false,
    bool clearSessionId = false,
    bool clearError = false,
  }) {
    return AgentServer(
      id: id,
      name: name ?? this.name,
      kind: kind,
      host: host ?? this.host,
      port: port ?? this.port,
      url: url ?? this.url,
      cookie: clearCookie ? null : (cookie ?? this.cookie),
      token: clearToken ? null : (token ?? this.token),
      lastSessionId:
          clearSessionId ? null : (lastSessionId ?? this.lastSessionId),
      lastError: clearError ? null : (lastError ?? this.lastError),
      unpaired: unpaired ?? this.unpaired,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'host': host,
        'port': port,
        if (url != null) 'url': url,
        if (cookie != null) 'cookie': cookie,
        if (token != null) 'token': token,
        if (lastSessionId != null) 'lastSessionId': lastSessionId,
      };

  factory AgentServer.fromJson(Map<String, dynamic> json) {
    return AgentServer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['host'] as String? ?? 'PC',
      // 旧数据没有 kind 字段 → 一律按 DSH 解释，无缝迁移
      kind: json['kind'] == 'opencode' ? AgentKind.opencode : AgentKind.dsh,
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 3080,
      url: json['url'] as String?,
      cookie: json['cookie'] as String?,
      token: json['token'] as String?,
      lastSessionId: json['lastSessionId'] as String?,
    );
  }

  static String sessionKey(String serverId, String sessionId) =>
      '$serverId::$sessionId';
}
