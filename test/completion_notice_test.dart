/// 完成通知文案测试
///
/// 通知必须带任务名和概要，不能只剩「会话已完成」。
library;

import 'package:dsh_tablet_client/utils/session_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('summarizeConversation', () {
    test('优先最后一条 assistant，并压缩换行/多余空白', () {
      final summary = summarizeConversation([
        (role: 'user', text: '帮我修登录页'),
        (role: 'assistant', text: '已修复\n\n登录页  样式'),
      ]);

      expect(summary, '已修复 登录页 样式');
    });

    test('没有 assistant 时回退最后一条 user', () {
      expect(
        summarizeConversation([
          (role: 'user', text: '跑一下测试'),
        ]),
        '跑一下测试',
      );
    });

    test('最后一条 user 比旧 assistant 新时用 user', () {
      expect(
        summarizeConversation([
          (role: 'assistant', text: '上一轮结果'),
          (role: 'user', text: '刚发的新任务'),
        ]),
        '刚发的新任务',
      );
    });

    test('超长摘要截断并带省略号', () {
      final text = List.filled(30, 'a').join();
      final summary = summarizeConversation(
        [(role: 'assistant', text: text)],
        maxChars: 10,
      );

      expect(summary, 'aaaaaaaaaa…');
    });

    test('空白消息返回 null', () {
      expect(
        summarizeConversation([
          (role: 'assistant', text: '   '),
        ]),
        isNull,
      );
    });
  });

  group('completionNotice', () {
    Map<String, dynamic> session(String title) => {
          'sessionId': 'sess-123456789',
          'projections': {
            'values': {'title': title},
          },
        };

    test('标题是任务名，正文带机器与摘要', () {
      final notice = completionNotice(
        session: session('修复登录页'),
        serverName: '工作台',
        summary: '已修复样式问题',
      );

      expect(notice.title, '修复登录页');
      expect(notice.body, '工作台 · 已修复样式问题');
    });

    test('没有摘要时给出可点击的兜底文案', () {
      final notice = completionNotice(
        session: session('修复登录页'),
        serverName: '工作台',
      );

      expect(notice.title, '修复登录页');
      expect(notice.body, '在工作台上完成，点击查看结果');
    });

    test('摘要与标题相同时不重复', () {
      final notice = completionNotice(
        session: session('修复登录页'),
        serverName: '工作台',
        summary: '修复登录页',
      );

      expect(notice.body, '在工作台上完成，点击查看结果');
    });
  });
}
