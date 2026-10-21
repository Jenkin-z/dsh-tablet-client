/// 通知 id 分配回归测试
///
/// 审批/提问/表单/会话完成可能同时到达；固定 id 会让后一条通知
/// 直接覆盖前一条。统一分配器必须保证进程内递增且不重复。
library;

import 'package:dsh_tablet_client/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nextId 进程内递增，连续分配不会重复', () {
    final first = NotificationService.nextId();
    final second = NotificationService.nextId();
    final third = NotificationService.nextId();

    expect(second, greaterThan(first));
    expect(third, greaterThan(second));
    expect({first, second, third}, hasLength(3));
  });
}
