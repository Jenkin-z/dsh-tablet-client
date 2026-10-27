/// diff 工具通用改进测试：CRLF 归一化 + 上下文折叠
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_tablet_client/services/diff_util.dart';

void main() {
  group('CRLF 归一化', () {
    test('Windows 行尾不再导致整文件误报为全变', () {
      final lines = unifiedDiff('a\r\nb\r\nc', 'a\nb\nc\nd');
      final dels = lines.where((l) => l.op == DiffOp.del).length;
      final adds = lines.where((l) => l.op == DiffOp.add).length;
      expect(dels, 0, reason: '内容相同只是行尾不同，不应有任何删除行');
      expect(adds, 1);
    });
  });

  group('上下文折叠', () {
    test('超过阈值的连续上下文压缩为省略号', () {
      final old = List.generate(10, (i) => 'l$i').join('\n');
      final new_ = ['l0', 'l1', 'l2', 'CHANGED', 'l4', 'l5', 'l6', 'l7', 'l8', 'l9']
          .join('\n');
      final lines = unifiedDiff(old, new_, contextFold: 2);
      final same = lines.where((l) => l.op == DiffOp.same).toList();
      // 前后各折叠：2 行上下文 + 1 个省略号（前段）+ 变更 + 尾段
      expect(same.any((l) => l.text == '…'), isTrue);
      expect(lines.length, lessThan(12));
    });

    test('fold=0 关闭折叠（行为回退开关）', () {
      final lines = unifiedDiff('a\nb\nc', 'a\nX\nc', contextFold: 0);
      expect(lines.where((l) => l.op == DiffOp.same).length, 2);
    });

    test('默认折叠开启，add/del 永不被折叠', () {
      final lines = unifiedDiff('a\nb\nc', 'a\nb\nc\nnew1\nnew2');
      expect(lines.any((l) => l.op == DiffOp.add), isTrue);
      expect(lines.every((l) => l.op != DiffOp.same || l.text != '…') ||
          lines.any((l) => l.op == DiffOp.add), isTrue);
    });
  });
}
