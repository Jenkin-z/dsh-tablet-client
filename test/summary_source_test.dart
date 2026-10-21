/// 完成通知摘要数据源回归测试
///
/// opencode 的 `order=asc&limit=20` 取到的是会话开头，不是最新结果。
/// 这个错误不会报错，只会让通知摘要变成很久以前的内容，必须用源码
/// 断言把「取最新一页」锁住。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/services/session_source.dart').readAsStringSync();
  });

  test('opencode 摘要取最新 20 条，再翻回 asc 交给 mapper', () {
    final classStart = source.indexOf('class OpenCodeSessionSource');
    expect(classStart >= 0, isTrue);
    final methodStart =
        source.indexOf('Future<String?> fetchSummary', classStart);
    expect(methodStart >= 0, isTrue);
    final body = source.substring(
      methodStart,
      (methodStart + 900).clamp(0, source.length),
    );

    expect(body.contains("order: 'desc'"), isTrue, reason: '必须显式取最新一页');
    expect(body.contains('limit: 20'), isTrue);
    expect(body.contains('reversed'), isTrue,
        reason: 'messagesToChat 约定 asc 序');
  });

  test('DSH 摘要走 session/page 的最近一页', () {
    final classStart = source.indexOf('class DshSessionSource');
    expect(classStart >= 0, isTrue);
    final methodStart =
        source.indexOf('Future<String?> fetchSummary', classStart);
    expect(methodStart >= 0, isTrue);
    final body = source.substring(
      methodStart,
      (methodStart + 500).clamp(0, source.length),
    );

    expect(body.contains('getHistory'), isTrue);
    expect(body.contains('maxMessages: 20'), isTrue);
  });
}
