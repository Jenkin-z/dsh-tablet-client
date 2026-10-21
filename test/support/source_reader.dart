/// 源码守卫测试的读取辅助
///
/// 为什么需要它：项目把超限文件按职责拆成了「主文件 + 同库 part 文件」，
/// 而契约测试的断言对象是**语义**（比如 `session/list` 的 args 必须是
/// `{_request:{}}`），不是某一行代码的物理位置。拆分后语义代码搬到 part
/// 文件里，若测试只读主文件，断言就会假阴性。
///
/// 这里按「主文件 + 其 part 声明里引用的所有文件」聚合成一份源码，
/// 让契约测试继续锁住语义，而不是锁住文件布局。
library;

import 'dart:io';

/// 读取主文件源码，并把它在 `part 'xxx.dart';` 里声明的 part 文件
/// 依次追加进来（按声明顺序）。
String readSourceWithParts(String mainPath) {
  final buffer = StringBuffer();
  buffer.writeln(File(mainPath).readAsStringSync());
  for (final part in _partPathsOf(mainPath)) {
    buffer.writeln();
    buffer.writeln('// ===== part: $part =====');
    buffer.writeln(File(part).readAsStringSync());
  }
  return buffer.toString();
}

/// 解析主文件里的 `part 'xxx.dart';` 声明，返回同目录下的绝对相对路径
List<String> _partPathsOf(String mainPath) {
  final source = File(mainPath).readAsStringSync();
  final dir = mainPath.substring(0, mainPath.lastIndexOf('/'));
  final parts = <String>[];
  final re = RegExp(r"""part\s+['"]([^'"]+)['"]\s*;""");
  for (final m in re.allMatches(source)) {
    final p = m.group(1)!;
    parts.add(dir.isEmpty ? p : '$dir/$p');
  }
  return parts;
}
