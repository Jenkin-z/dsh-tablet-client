/// 行级 unified diff（LCS），为 RK3288 做了上限保护
library;

import '../utils/constants.dart';

enum DiffOp { same, add, del }

class DiffLine {
  final DiffOp op;
  final String text;
  const DiffLine(this.op, this.text);
}

/// oldText == null 表示新建文件：全部标绿
/// 超限时降级为「全删+全加」，并在末尾注记
/// [contextFold]：变更之间最多保留多少行上下文，更长的连续段折叠为
/// 省略号（null = 用 [diffContextFold]；传 0 关闭折叠）。移动端/平板上
/// 长上下文会把 diff 卡片撑到不可读，折叠是大文件可读性的关键。
List<DiffLine> unifiedDiff(String? oldText, String newText,
    {int maxLines = diffMaxLines, int? contextFold}) {
  final fold = contextFold ?? diffContextFold;
  // CRLF 归一化：否则 Windows 文件的每一行都带着 \r，和 Unix 侧
  // 对比时整文件误报为「全变」。
  List<String> newLines = newText.split(RegExp(r'\r?\n'));
  if (oldText == null) {
    final out = newLines.take(maxLines).map((l) => DiffLine(DiffOp.add, l)).toList();
    if (newLines.length > maxLines) {
      out.add(DiffLine(DiffOp.same, '… 以下 ${newLines.length - maxLines} 行已截断'));
    }
    return out;
  }
  List<String> oldLines = oldText.split(RegExp(r'\r?\n'));

  // 规模保护：DP 表上限约 400 万格
  if (oldLines.length * newLines.length > diffDpCellLimit) {
    final out = <DiffLine>[];
    for (final l in oldLines.take(maxLines ~/ 2)) {
      out.add(DiffLine(DiffOp.del, l));
    }
    for (final l in newLines.take(maxLines ~/ 2)) {
      out.add(DiffLine(DiffOp.add, l));
    }
    out.add(const DiffLine(DiffOp.same, '… 文件过大，仅显示前后片段'));
    return out;
  }

  final n = oldLines.length;
  final m = newLines.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = oldLines[i] == newLines[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final raw = <DiffLine>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (oldLines[i] == newLines[j]) {
      raw.add(DiffLine(DiffOp.same, oldLines[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      raw.add(DiffLine(DiffOp.del, oldLines[i]));
      i++;
    } else {
      raw.add(DiffLine(DiffOp.add, newLines[j]));
      j++;
    }
  }
  while (i < n) {
    raw.add(DiffLine(DiffOp.del, oldLines[i++]));
  }
  while (j < m) {
    raw.add(DiffLine(DiffOp.add, newLines[j++]));
  }
  final out = _foldContext(raw, fold);
  if (out.length > maxLines) {
    out.removeRange(maxLines, out.length);
    out.add(const DiffLine(DiffOp.same, '… 以下内容已截断'));
  }
  return out;
}

/// 折叠连续的上下文行：每段保留前 [fold] 行，超出部分压缩成一行省略号。
/// fold <= 0 时原样返回。变更块本身（add/del）永不被折叠。
List<DiffLine> _foldContext(List<DiffLine> lines, int fold) {
  if (fold <= 0) return lines;
  final out = <DiffLine>[];
  var run = 0;
  for (final l in lines) {
    if (l.op != DiffOp.same) {
      run = 0;
      out.add(l);
      continue;
    }
    run++;
    if (run <= fold) {
      out.add(l);
    } else if (run == fold + 1) {
      out.add(const DiffLine(DiffOp.same, '…'));
    }
    // run > fold+1：继续吞掉
  }
  return out;
}