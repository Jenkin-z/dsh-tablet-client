/// 一台被监控的 DSH 主机（一台 PC）
class DshServer {
  final String id;
  final String name;
  final String host;
  final int port;

  /// 原生 browser-session cookie（"dsh-auth-xxx=value"），约 30 天有效
  final String? cookie;
  final String? lastSessionId;
  final String? lastError;

  /// true = 授权失效，需要重新用启动令牌换取
  final bool unpaired;

  const DshServer({
    required this.id,
    required this.name,
    required this.host,
    this.port = 3080,
    this.cookie,
    this.lastSessionId,
    this.lastError,
    this.unpaired = false,
  });

  String get httpUrl => 'http://$host:$port';
  String get wsUrl => 'ws://$host:$port';
  bool get isPaired => cookie != null && cookie!.isNotEmpty && !unpaired;

  DshServer copyWith({
    String? name,
    String? host,
    int? port,
    String? cookie,
    String? lastSessionId,
    String? lastError,
    bool? unpaired,
    bool clearCookie = false,
    bool clearSessionId = false,
    bool clearError = false,
  }) {
    return DshServer(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      cookie: clearCookie ? null : (cookie ?? this.cookie),
      lastSessionId:
          clearSessionId ? null : (lastSessionId ?? this.lastSessionId),
      lastError: clearError ? null : (lastError ?? this.lastError),
      unpaired: unpaired ?? this.unpaired,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        if (cookie != null) 'cookie': cookie,
        if (lastSessionId != null) 'lastSessionId': lastSessionId,
      };

  factory DshServer.fromJson(Map<String, dynamic> json) {
    return DshServer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['host'] as String? ?? 'PC',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 3080,
      cookie: json['cookie'] as String?,
      lastSessionId: json['lastSessionId'] as String?,
    );
  }

  static String sessionKey(String serverId, String sessionId) =>
      '$serverId::$sessionId';
}
