/// 更新下载/安装的平台分派（Android IO / Web）
library;

export 'update_common.dart';
export 'update_platform_stub.dart'
    if (dart.library.io) 'update_platform_io.dart';
